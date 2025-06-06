defmodule Aiex.LLM.Adapters.Ollama do
  @moduledoc """
  Ollama local model adapter for chat completions.

  Implements the LLM.Adapter behaviour for Ollama's local API,
  including support for model discovery and health checking.
  """

  @behaviour Aiex.LLM.Adapter

  require Logger

  @default_base_url "http://localhost:11434"
  @generate_endpoint "/api/generate"
  @chat_endpoint "/api/chat"
  @tags_endpoint "/api/tags"
  @show_endpoint "/api/show"
  # Longer timeout for local inference
  @timeout 120_000

  @rate_limits %{
    # No rate limits for local models
    requests_per_minute: nil,
    tokens_per_minute: nil
  }

  @impl true
  def complete(request, opts \\ []) do
    with {:ok, :healthy} <- health_check(opts),
         {:ok, payload} <- build_payload(request),
         {:ok, response} <- make_request(payload, opts) do
      if request.stream do
        {:stream, parse_stream_response(response)}
      else
        parse_completion_response(response)
      end
    end
  end

  @impl true
  def validate_config(opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)

    case health_check(opts) do
      {:ok, :healthy} ->
        :ok

      {:error, :unreachable} ->
        {:error, "Ollama service unreachable at #{base_url}. Is Ollama running?"}

      {:error, reason} ->
        {:error, "Ollama validation failed: #{reason}"}
    end
  end

  @impl true
  def supported_models(opts \\ []) do
    case discover_models(opts) do
      {:ok, models} -> models
      # Return empty list if discovery fails
      {:error, _reason} -> []
    end
  end

  @impl true
  def rate_limits, do: @rate_limits

  @impl true
  def estimate_cost(_request) do
    # Local models are free to run
    %{
      input_cost: 0.0,
      estimated_output_cost: 0.0,
      currency: "USD"
    }
  end

  @doc """
  Check if Ollama service is running and accessible.
  """
  def health_check(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    timeout = Keyword.get(opts, :timeout, 5_000)

    url = base_url <> @tags_endpoint

    case Finch.build(:get, url)
         |> Finch.request(AiexFinch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: 200}} ->
        {:ok, :healthy}

      {:ok, %Finch.Response{status: status}} ->
        {:error, "Ollama returned status #{status}"}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :unreachable}

      {:error, %Mint.TransportError{reason: reason}} ->
        {:error, "Connection error: #{reason}"}

      {:error, reason} ->
        {:error, "Health check failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Discover available models from Ollama.
  """
  def discover_models(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    timeout = Keyword.get(opts, :timeout, 10_000)

    url = base_url <> @tags_endpoint

    case Finch.build(:get, url)
         |> Finch.request(AiexFinch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        parse_models_response(body)

      {:ok, %Finch.Response{status: status, body: error_body}} ->
        {:error, "Failed to discover models: HTTP #{status} - #{error_body}"}

      {:error, reason} ->
        {:error, "Model discovery failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Get detailed information about a specific model.
  """
  def model_info(model_name, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    timeout = Keyword.get(opts, :timeout, 10_000)

    url = base_url <> @show_endpoint
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(%{name: model_name})

    case Finch.build(:post, url, headers, body)
         |> Finch.request(AiexFinch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %Finch.Response{status: status, body: error_body}} ->
        {:error, "Failed to get model info: HTTP #{status} - #{error_body}"}

      {:error, reason} ->
        {:error, "Model info request failed: #{inspect(reason)}"}
    end
  end

  # Private functions

  defp build_payload(request) do
    # Use chat endpoint if we have conversation, otherwise generate
    if has_conversation?(request.messages) do
      build_chat_payload(request)
    else
      build_generate_payload(request)
    end
  end

  defp has_conversation?(messages) do
    length(messages) > 1 or Enum.any?(messages, &(&1.role != :user))
  end

  defp build_chat_payload(request) do
    payload =
      %{
        model: request.model || "llama2",
        messages: format_messages(request.messages)
      }
      |> put_optional(:stream, request.stream)
      |> put_optional(:options, build_options(request))

    {:ok, {payload, @chat_endpoint}}
  end

  defp build_generate_payload(request) do
    # For single prompt generation
    prompt =
      case request.messages do
        [%{content: content}] -> content
        messages -> format_messages_as_prompt(messages)
      end

    payload =
      %{
        model: request.model || "llama2",
        prompt: prompt
      }
      |> put_optional(:stream, request.stream)
      |> put_optional(:options, build_options(request))

    {:ok, {payload, @generate_endpoint}}
  end

  defp format_messages(messages) do
    Enum.map(messages, fn message ->
      %{
        role: format_role(message.role),
        content: message.content
      }
    end)
  end

  defp format_messages_as_prompt(messages) do
    messages
    |> Enum.map(fn message ->
      role = format_role(message.role)
      "#{String.capitalize(role)}: #{message.content}"
    end)
    |> Enum.join("\n\n")
  end

  defp format_role(:user), do: "user"
  defp format_role(:assistant), do: "assistant"
  defp format_role(:system), do: "system"
  defp format_role(role), do: to_string(role)

  defp build_options(request) do
    options =
      %{}
      |> put_optional(:temperature, request.temperature)
      |> put_optional(:num_predict, request.max_tokens)

    if map_size(options) > 0, do: options, else: nil
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp make_request({payload, endpoint}, opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    timeout = Keyword.get(opts, :timeout, @timeout)

    url = base_url <> endpoint
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(payload)

    case Finch.build(:post, url, headers, body)
         |> Finch.request(AiexFinch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %Finch.Response{status: status, body: error_body}} ->
        {:error, parse_error_response(status, error_body)}

      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:error, %{type: :timeout, message: "Request timed out - local models can be slow"}}

      {:error, %Mint.TransportError{reason: reason}} ->
        {:error, %{type: :network_error, message: "Network error: #{reason}"}}

      {:error, reason} ->
        {:error, %{type: :unknown, message: "Unknown error: #{inspect(reason)}"}}
    end
  end

  defp parse_completion_response(response) do
    case response do
      # Chat endpoint response format
      %{"message" => %{"content" => content}} = resp ->
        {:ok,
         %{
           content: content,
           model: resp["model"],
           usage: parse_usage(resp),
           finish_reason: parse_finish_reason(resp["done_reason"]),
           metadata: %{
             created_at: resp["created_at"],
             total_duration: resp["total_duration"],
             load_duration: resp["load_duration"],
             prompt_eval_duration: resp["prompt_eval_duration"],
             eval_duration: resp["eval_duration"],
             # Local models are free
             cost: 0.0
           }
         }}

      # Generate endpoint response format
      %{"response" => content} = resp ->
        {:ok,
         %{
           content: content,
           model: resp["model"],
           usage: parse_usage(resp),
           finish_reason: parse_finish_reason(resp["done_reason"]),
           metadata: %{
             created_at: resp["created_at"],
             total_duration: resp["total_duration"],
             load_duration: resp["load_duration"],
             prompt_eval_duration: resp["prompt_eval_duration"],
             eval_duration: resp["eval_duration"],
             cost: 0.0
           }
         }}

      %{"error" => error} ->
        {:error, %{type: :api_error, message: error}}

      _ ->
        {:error, %{type: :invalid_response, message: "Unexpected response format"}}
    end
  end

  defp parse_stream_response(response) do
    # Ollama returns JSONL for streaming
    Stream.map([response], fn chunk ->
      content =
        case chunk do
          %{"message" => %{"content" => content}} -> content
          %{"response" => content} -> content
          _ -> ""
        end

      %{
        content: content,
        delta: content,
        finish_reason: if(chunk["done"], do: :stop, else: nil),
        metadata: %{
          model: chunk["model"],
          created_at: chunk["created_at"]
        }
      }
    end)
  end

  defp parse_models_response(body) do
    try do
      %{"models" => models} = Jason.decode!(body)

      model_names =
        Enum.map(models, fn model ->
          model["name"]
        end)

      {:ok, model_names}
    rescue
      _ ->
        {:error, "Failed to parse models response"}
    end
  end

  defp parse_usage(response) do
    %{
      prompt_tokens: response["prompt_eval_count"] || 0,
      completion_tokens: response["eval_count"] || 0,
      total_tokens: (response["prompt_eval_count"] || 0) + (response["eval_count"] || 0)
    }
  end

  defp parse_error_response(status, body) do
    try do
      error_data = Jason.decode!(body)

      %{
        type: :api_error,
        message: error_data["error"] || "HTTP #{status}",
        code: to_string(status)
      }
    rescue
      _ ->
        %{
          type: :http_error,
          message: "HTTP #{status}: #{body}",
          code: to_string(status)
        }
    end
  end

  defp parse_finish_reason("stop"), do: :stop
  defp parse_finish_reason("length"), do: :length
  # Assume stop if not specified
  defp parse_finish_reason(nil), do: :stop
  defp parse_finish_reason(_), do: nil
end
