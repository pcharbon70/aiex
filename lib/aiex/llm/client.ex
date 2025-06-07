defmodule Aiex.LLM.Client do
  @moduledoc """
  Main LLM client that manages adapters and provides a unified interface.

  This module handles adapter selection, rate limiting, retries, and response
  processing for all LLM interactions.
  """

  use GenServer
  require Logger

  alias Aiex.LLM.{Adapter, RateLimiter, Config}

  @default_timeout 30_000
  @default_retries 3
  @default_backoff_base 1000

  # Client API

  @doc """
  Starts the LLM client.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generate a completion using the configured adapter.
  """
  @spec complete(Adapter.completion_request(), keyword()) :: Adapter.adapter_result()
  def complete(request, opts \\ []) do
    GenServer.call(__MODULE__, {:complete, request, opts}, get_timeout(opts))
  end

  @doc """
  Generate a completion with automatic retries.
  """
  @spec complete_with_retry(Adapter.completion_request(), keyword()) :: Adapter.adapter_result()
  def complete_with_retry(request, opts \\ []) do
    retries = Keyword.get(opts, :retries, @default_retries)
    attempt_completion(request, opts, retries)
  end

  @doc """
  Stream a completion from the LLM.
  """
  @spec stream_complete(Adapter.completion_request(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, any()}
  def stream_complete(request, opts \\ []) do
    stream_request = Map.put(request, :stream, true)
    GenServer.call(__MODULE__, {:complete, stream_request, opts}, get_timeout(opts))
  end

  @doc """
  Get the current adapter configuration.
  """
  @spec get_config() :: map()
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  @doc """
  Update the adapter configuration.
  """
  @spec update_config(keyword()) :: :ok | {:error, any()}
  def update_config(updates) do
    GenServer.call(__MODULE__, {:update_config, updates})
  end

  @doc """
  Get adapter usage statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    config = Config.load(opts)

    case validate_config(config) do
      :ok ->
        state = %{
          config: config,
          adapter_module: load_adapter(config.provider),
          stats: %{
            total_requests: 0,
            successful_requests: 0,
            failed_requests: 0,
            total_tokens: 0,
            total_cost: 0.0
          }
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:config_error, reason}}
    end
  end

  @impl true
  def handle_call({:complete, request, opts}, _from, state) do
    case process_completion(request, opts, state) do
      {:ok, response, new_state} ->
        {:reply, {:ok, response}, new_state}

      {:error, error, new_state} ->
        {:reply, {:error, error}, new_state}

      {:stream, stream, new_state} ->
        {:reply, {:stream, stream}, new_state}
    end
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call({:update_config, updates}, _from, state) do
    case Config.update(state.config, updates) do
      {:ok, new_config} ->
        new_state = %{
          state
          | config: new_config,
            adapter_module: load_adapter(new_config.provider)
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  # Private functions

  defp process_completion(request, opts, state) do
    # Use distributed coordinator for provider selection if available
    start_time = :os.system_time(:millisecond)

    with {:ok, {provider, adapter}} <- select_provider(request, opts, state),
         :ok <- RateLimiter.check_rate_limit(provider),
         {:ok, validated_request} <- validate_request(request, state),
         {:ok, response} <- call_distributed_adapter(adapter, validated_request, opts, state) do
      # Report success to coordinator
      response_time = :os.system_time(:millisecond) - start_time
      report_request_result(provider, :success, %{response_time: response_time})

      new_stats = update_stats(state.stats, response)
      new_state = %{state | stats: new_stats}

      case response do
        %{content: _} = completion ->
          {:ok, completion, new_state}

        {:stream, stream} ->
          {:stream, stream, new_state}
      end
    else
      {:error, :rate_limited} = _error ->
        Logger.warning("Rate limit exceeded")
        new_stats = Map.update!(state.stats, :failed_requests, &(&1 + 1))

        {:error, %{type: :rate_limit, message: "Rate limit exceeded"},
         %{state | stats: new_stats}}

      {:error, reason} = _error ->
        Logger.error("LLM completion failed: #{inspect(reason)}")

        # Report failure to coordinator if we had a provider
        case select_provider(request, opts, state) do
          {:ok, {provider, _}} -> report_request_result(provider, :error, %{error: reason})
          _ -> :ok
        end

        new_stats = Map.update!(state.stats, :failed_requests, &(&1 + 1))
        {:error, reason, %{state | stats: new_stats}}
    end
  end

  defp select_provider(request, opts, state) do
    # Try to use distributed coordinator first, fall back to configured provider
    case Process.whereis(Aiex.LLM.ModelCoordinator) do
      nil ->
        # No coordinator available, use configured provider
        {:ok, {state.config.provider, state.adapter_module}}

      _pid ->
        # Use distributed coordinator
        case Aiex.LLM.ModelCoordinator.select_provider(request, opts) do
          {:ok, result} ->
            {:ok, result}

          {:error, _} ->
            # Fall back to configured provider
            {:ok, {state.config.provider, state.adapter_module}}
        end
    end
  end

  defp call_distributed_adapter(adapter, request, opts, state) do
    adapter.complete(request, merge_config_opts(opts, state.config))
  end

  defp report_request_result(provider, result, metadata) do
    case Process.whereis(Aiex.LLM.ModelCoordinator) do
      # No coordinator available
      nil -> :ok
      _pid -> Aiex.LLM.ModelCoordinator.report_request_result(provider, result, metadata)
    end
  end

  defp merge_config_opts(opts, config) do
    Keyword.merge(
      [
        api_key: config.api_key,
        base_url: config.base_url,
        timeout: config.timeout
      ],
      opts
    )
  end

  defp validate_request(request, state) do
    cond do
      not is_map(request) ->
        {:error, "Request must be a map"}

      not Map.has_key?(request, :messages) ->
        {:error, "Request must include messages"}

      not is_list(request.messages) ->
        {:error, "Messages must be a list"}

      Enum.empty?(request.messages) ->
        {:error, "Messages cannot be empty"}

      not valid_model?(request.model, state) ->
        {:error, "Unsupported model: #{request.model}"}

      true ->
        {:ok, normalize_request(request, state)}
    end
  end

  # Will use default
  defp valid_model?(nil, _state), do: true

  defp valid_model?(model, state) do
    supported = state.adapter_module.supported_models()
    model in supported
  end

  defp normalize_request(request, state) do
    request
    |> Map.put_new(:model, state.config.default_model)
    |> Map.put_new(:max_tokens, state.config.max_tokens)
    |> Map.put_new(:temperature, state.config.temperature)
    |> Map.put_new(:stream, false)
    |> Map.put_new(:metadata, %{})
  end

  defp update_stats(stats, response) do
    stats
    |> Map.update!(:total_requests, &(&1 + 1))
    |> Map.update!(:successful_requests, &(&1 + 1))
    |> update_token_stats(response)
    |> update_cost_stats(response)
  end

  defp update_token_stats(stats, %{usage: usage}) do
    Map.update!(stats, :total_tokens, &(&1 + usage.total_tokens))
  end

  defp update_token_stats(stats, _), do: stats

  defp update_cost_stats(stats, %{metadata: %{cost: cost}}) do
    Map.update!(stats, :total_cost, &(&1 + cost))
  end

  defp update_cost_stats(stats, _), do: stats

  defp validate_config(config) do
    cond do
      is_nil(config.provider) ->
        {:error, "Provider must be specified"}

      config.provider in [:ollama, :lm_studio] ->
        # Local providers don't require API keys
        :ok

      is_nil(config.api_key) ->
        {:error, "API key must be specified for cloud providers"}

      true ->
        :ok
    end
  end

  defp load_adapter(:openai), do: Aiex.LLM.Adapters.OpenAI
  defp load_adapter(:anthropic), do: Aiex.LLM.Adapters.Anthropic
  defp load_adapter(:ollama), do: Aiex.LLM.Adapters.Ollama
  defp load_adapter(:lm_studio), do: Aiex.LLM.Adapters.LMStudio
  defp load_adapter(provider), do: raise("Unsupported provider: #{provider}")

  defp get_timeout(opts) do
    Keyword.get(opts, :timeout, @default_timeout)
  end

  defp attempt_completion(request, opts, retries) when retries > 0 do
    case complete(request, opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, %{type: :rate_limit, retry_after: retry_after}} when retry_after != nil ->
        Logger.info("Rate limited, retrying after #{retry_after}ms")
        Process.sleep(retry_after)
        attempt_completion(request, opts, retries - 1)

      {:error, %{type: type}} when type in [:server_error, :unknown] ->
        backoff = calculate_backoff(retries)
        Logger.info("Retrying after #{backoff}ms due to #{type}")
        Process.sleep(backoff)
        attempt_completion(request, opts, retries - 1)

      {:error, _} = error ->
        error
    end
  end

  defp attempt_completion(_request, _opts, 0) do
    {:error, %{type: :max_retries_exceeded, message: "Maximum retries exceeded"}}
  end

  defp calculate_backoff(retries_left) do
    # Exponential backoff with jitter
    base_delay = @default_backoff_base * :math.pow(2, @default_retries - retries_left)
    jitter = :rand.uniform(1000)
    round(base_delay + jitter)
  end
end
