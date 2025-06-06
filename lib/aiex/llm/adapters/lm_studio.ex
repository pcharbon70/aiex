defmodule Aiex.LLM.Adapters.LMStudio do
  @moduledoc """
  LM Studio adapter for HuggingFace models.

  Implements the LLM.Adapter behaviour for LM Studio's OpenAI-compatible API,
  including support for model management and HuggingFace ecosystem integration.
  """

  @behaviour Aiex.LLM.Adapter

  require Logger

  @default_base_url "http://localhost:1234/v1"
  @chat_endpoint "/chat/completions"
  @models_endpoint "/models"
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
        {:error,
         "LM Studio service unreachable at #{base_url}. Is LM Studio running with server enabled?"}

      {:error, reason} ->
        {:error, "LM Studio validation failed: #{reason}"}
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
  Check if LM Studio service is running and accessible.
  """
  def health_check(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    timeout = Keyword.get(opts, :timeout, 5_000)

    url = base_url <> @models_endpoint

    case Finch.build(:get, url)
         |> Finch.request(AiexFinch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: 200}} ->
        {:ok, :healthy}

      {:ok, %Finch.Response{status: status}} ->
        {:error, "LM Studio returned status #{status}"}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :unreachable}

      {:error, %Mint.TransportError{reason: reason}} ->
        {:error, "Connection error: #{reason}"}

      {:error, reason} ->
        {:error, "Health check failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Discover available models from LM Studio.
  """
  def discover_models(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    timeout = Keyword.get(opts, :timeout, 10_000)

    url = base_url <> @models_endpoint

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
  Get model information including HuggingFace metadata.
  """
  def model_info(model_id, opts \\ []) do
    case discover_models(opts) do
      {:ok, models} ->
        case Enum.find(models, &(&1["id"] == model_id)) do
          nil -> {:error, "Model not found: #{model_id}"}
          model -> {:ok, model}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp build_payload(request) do
    # LM Studio uses OpenAI-compatible format
    payload =
      %{
        model: request.model || determine_default_model(request),
        messages: format_messages(request.messages)
      }
      |> put_optional(:max_tokens, request.max_tokens)
      |> put_optional(:temperature, request.temperature)
      |> put_optional(:stream, request.stream)

    {:ok, payload}
  end

  defp determine_default_model(request) do
    # Try to infer appropriate model based on message content
    content_length =
      request.messages
      |> Enum.map(&String.length(&1.content))
      |> Enum.sum()

    cond do
      String.contains?(inspect(request.messages), ["code", "function", "def ", "class "]) ->
        # Prefer code-specific models
        "code-model"

      content_length > 2000 ->
        # Prefer models with larger context windows
        "long-context-model"

      true ->
        # Default general-purpose model
        "general-model"
    end
  end

  defp format_messages(messages) do
    Enum.map(messages, fn message ->
      %{
        role: format_role(message.role),
        content: message.content
      }
    end)
  end

  defp format_role(:user), do: "user"
  defp format_role(:assistant), do: "assistant"
  defp format_role(:system), do: "system"
  defp format_role(role), do: to_string(role)

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp make_request(payload, opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    timeout = Keyword.get(opts, :timeout, @timeout)

    url = base_url <> @chat_endpoint
    headers = build_headers()
    body = Jason.encode!(payload)

    case Finch.build(:post, url, headers, body)
         |> Finch.request(AiexFinch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %Finch.Response{status: status, body: error_body}} ->
        {:error, parse_error_response(status, error_body)}

      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:error,
         %{type: :timeout, message: "Request timed out - HuggingFace models can be slow to load"}}

      {:error, %Mint.TransportError{reason: reason}} ->
        {:error, %{type: :network_error, message: "Network error: #{reason}"}}

      {:error, reason} ->
        {:error, %{type: :unknown, message: "Unknown error: #{inspect(reason)}"}}
    end
  end

  defp build_headers do
    [
      {"content-type", "application/json"},
      {"user-agent", "Aiex/#{Application.spec(:aiex, :vsn)}"}
    ]
  end

  defp parse_completion_response(response) do
    case response do
      %{"choices" => [choice | _], "usage" => usage} = resp ->
        {:ok,
         %{
           content: get_in(choice, ["message", "content"]) || "",
           model: resp["model"],
           usage: %{
             prompt_tokens: usage["prompt_tokens"] || 0,
             completion_tokens: usage["completion_tokens"] || 0,
             total_tokens: usage["total_tokens"] || 0
           },
           finish_reason: parse_finish_reason(choice["finish_reason"]),
           metadata: %{
             id: resp["id"],
             created: resp["created"],
             system_fingerprint: resp["system_fingerprint"],
             # Local models are free
             cost: 0.0,
             model_info: extract_model_info(resp["model"])
           }
         }}

      %{"error" => error} ->
        {:error, parse_api_error(error)}

      _ ->
        {:error, %{type: :invalid_response, message: "Unexpected response format"}}
    end
  end

  defp parse_stream_response(response) do
    # LM Studio uses OpenAI-compatible Server-Sent Events
    Stream.map([response], fn chunk ->
      content =
        case chunk do
          %{"choices" => [%{"delta" => %{"content" => content}} | _]} -> content
          _ -> ""
        end

      %{
        content: content,
        delta: content,
        finish_reason: parse_stream_finish_reason(chunk),
        metadata: %{
          id: chunk["id"],
          model: chunk["model"]
        }
      }
    end)
  end

  defp parse_models_response(body) do
    try do
      %{"data" => models} = Jason.decode!(body)

      model_list =
        Enum.map(models, fn model ->
          %{
            "id" => model["id"],
            "object" => model["object"],
            "created" => model["created"],
            "owned_by" => model["owned_by"],
            "permission" => model["permission"],
            "root" => model["root"],
            "parent" => model["parent"],
            # LM Studio specific metadata
            "huggingface_repo" => extract_huggingface_repo(model["id"]),
            "model_type" => infer_model_type(model["id"]),
            "quantization" => detect_quantization(model["id"])
          }
        end)

      {:ok, model_list}
    rescue
      _ ->
        {:error, "Failed to parse models response"}
    end
  end

  defp extract_huggingface_repo(model_id) do
    # Many LM Studio models follow HuggingFace naming convention
    case String.split(model_id, "/", parts: 2) do
      [org, model] -> "#{org}/#{model}"
      _ -> nil
    end
  end

  defp infer_model_type(model_id) do
    model_lower = String.downcase(model_id)

    cond do
      String.contains?(model_lower, ["code", "codellama", "starcoder", "deepseek-coder"]) ->
        "code"

      String.contains?(model_lower, ["instruct", "chat", "assistant"]) ->
        "chat"

      String.contains?(model_lower, ["embed", "sentence"]) ->
        "embedding"

      String.contains?(model_lower, ["base", "foundation"]) ->
        "base"

      true ->
        "general"
    end
  end

  defp detect_quantization(model_id) do
    model_lower = String.downcase(model_id)

    cond do
      String.contains?(model_lower, ["q4_0", "q4_1", "q5_0", "q5_1", "q8_0"]) ->
        "ggml"

      String.contains?(model_lower, ["gguf"]) ->
        "gguf"

      String.contains?(model_lower, ["awq"]) ->
        "awq"

      String.contains?(model_lower, ["gptq"]) ->
        "gptq"

      String.contains?(model_lower, ["int4", "int8"]) ->
        "quantized"

      true ->
        # Assume full precision if no quantization detected
        "fp16"
    end
  end

  defp extract_model_info(model_id) do
    %{
      huggingface_repo: extract_huggingface_repo(model_id),
      model_type: infer_model_type(model_id),
      quantization: detect_quantization(model_id)
    }
  end

  defp parse_error_response(status, body) do
    try do
      error_data = Jason.decode!(body)
      parse_api_error(error_data["error"])
    rescue
      _ ->
        %{
          type: :http_error,
          message: "HTTP #{status}: #{body}",
          code: to_string(status)
        }
    end
  end

  defp parse_api_error(error) when is_map(error) do
    type =
      case error["type"] do
        "invalid_request_error" -> :invalid_request
        "authentication_error" -> :authentication
        "permission_error" -> :authentication
        "not_found_error" -> :invalid_request
        "rate_limit_error" -> :rate_limit
        "api_error" -> :server_error
        "overloaded_error" -> :server_error
        _ -> :unknown
      end

    %{
      type: type,
      message: error["message"] || "Unknown error",
      code: error["code"]
    }
  end

  defp parse_api_error(_), do: %{type: :unknown, message: "Unknown error"}

  defp parse_finish_reason("stop"), do: :stop
  defp parse_finish_reason("length"), do: :length
  defp parse_finish_reason("content_filter"), do: :content_filter
  defp parse_finish_reason("function_call"), do: :function_call
  defp parse_finish_reason("tool_calls"), do: :function_call
  defp parse_finish_reason(_), do: nil

  defp parse_stream_finish_reason(chunk) do
    case get_in(chunk, ["choices", Access.at(0), "finish_reason"]) do
      nil -> nil
      reason -> parse_finish_reason(reason)
    end
  end
end
