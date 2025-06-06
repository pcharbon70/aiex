defmodule Aiex.LLM.RateLimiter do
  @moduledoc """
  Rate limiting for LLM API calls using Hammer.
  
  Implements per-provider rate limiting to prevent exceeding API quotas
  and getting throttled by LLM providers.
  """
  
  use GenServer
  require Logger
  
  @doc """
  Check if a request is allowed under current rate limits.
  """
  @spec check_rate_limit(atom()) :: :ok | {:error, :rate_limited}
  def check_rate_limit(provider) do
    GenServer.call(__MODULE__, {:check_rate_limit, provider})
  end
  
  @doc """
  Record a successful request for rate limit tracking.
  """
  @spec record_request(atom(), pos_integer()) :: :ok
  def record_request(provider, tokens \\ 1) do
    GenServer.cast(__MODULE__, {:record_request, provider, tokens})
  end
  
  @doc """
  Get current rate limit status for a provider.
  """
  @spec get_status(atom()) :: map()
  def get_status(provider) do
    GenServer.call(__MODULE__, {:get_status, provider})
  end
  
  @doc """
  Start the rate limiter.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    state = %{
      providers: %{},
      limits: load_rate_limits()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:check_rate_limit, provider}, _from, state) do
    limits = Map.get(state.limits, provider, default_limits())
    result = check_provider_limits(provider, limits)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:get_status, provider}, _from, state) do
    status = get_provider_status(provider, state)
    {:reply, status, state}
  end
  
  @impl true
  def handle_cast({:record_request, provider, tokens}, state) do
    record_provider_request(provider, tokens)
    {:noreply, state}
  end
  
  # Private functions
  
  defp check_provider_limits(provider, limits) do
    request_result = check_request_limit(provider, limits.requests_per_minute)
    token_result = check_token_limit(provider, limits.tokens_per_minute, 1)
    
    case {request_result, token_result} do
      {:allow, :allow} -> :ok
      _ -> {:error, :rate_limited}
    end
  end
  
  defp check_request_limit(provider, limit) when is_integer(limit) do
    bucket_id = "requests:#{provider}"
    scale_ms = 60_000  # 1 minute
    
    case Hammer.check_rate(bucket_id, scale_ms, limit) do
      {:allow, _count} -> :allow
      {:deny, _limit} -> :deny
    end
  end
  defp check_request_limit(_provider, nil), do: :allow
  
  defp check_token_limit(provider, limit, tokens) when is_integer(limit) do
    bucket_id = "tokens:#{provider}"
    scale_ms = 60_000  # 1 minute
    
    case Hammer.check_rate(bucket_id, scale_ms, limit, tokens) do
      {:allow, _count} -> :allow
      {:deny, _limit} -> :deny
    end
  end
  defp check_token_limit(_provider, nil, _tokens), do: :allow
  
  defp record_provider_request(provider, tokens) do
    # Record the request
    request_bucket = "requests:#{provider}"
    Hammer.check_rate(request_bucket, 60_000, 9999, 1)
    
    # Record the tokens
    if tokens > 0 do
      token_bucket = "tokens:#{provider}"
      Hammer.check_rate(token_bucket, 60_000, 999_999, tokens)
    end
    
    Logger.debug("Recorded request for #{provider}: #{tokens} tokens")
  end
  
  defp get_provider_status(provider, state) do
    limits = Map.get(state.limits, provider, default_limits())
    
    request_count = get_bucket_count("requests:#{provider}")
    token_count = get_bucket_count("tokens:#{provider}")
    
    %{
      provider: provider,
      requests: %{
        current: request_count,
        limit: limits.requests_per_minute,
        remaining: max(0, (limits.requests_per_minute || 999) - request_count)
      },
      tokens: %{
        current: token_count,
        limit: limits.tokens_per_minute,
        remaining: max(0, (limits.tokens_per_minute || 999_999) - token_count)
      },
      reset_time: get_reset_time()
    }
  end
  
  defp get_bucket_count(bucket_id) do
    case Hammer.inspect_bucket(bucket_id, 60_000, 1) do
      {:ok, {count, _, _, _, _}} -> count
      _ -> 0
    end
  end
  
  defp get_reset_time do
    # Calculate seconds until next minute boundary
    now = System.system_time(:second)
    60 - rem(now, 60)
  end
  
  defp load_rate_limits do
    %{
      openai: %{
        requests_per_minute: get_env_int("AIEX_OPENAI_RPM", 60),
        tokens_per_minute: get_env_int("AIEX_OPENAI_TPM", 90_000)
      },
      anthropic: %{
        requests_per_minute: get_env_int("AIEX_ANTHROPIC_RPM", 50),
        tokens_per_minute: get_env_int("AIEX_ANTHROPIC_TPM", 100_000)
      },
      google: %{
        requests_per_minute: get_env_int("AIEX_GOOGLE_RPM", 60),
        tokens_per_minute: get_env_int("AIEX_GOOGLE_TPM", 60_000)
      }
    }
  end
  
  defp default_limits do
    %{
      requests_per_minute: 60,
      tokens_per_minute: 60_000
    }
  end
  
  defp get_env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      value -> 
        case Integer.parse(value) do
          {int, _} -> int
          :error -> default
        end
    end
  end
end