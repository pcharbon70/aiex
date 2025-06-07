defmodule Aiex.LLM.Adapters.Anthropic do
  @moduledoc """
  Anthropic Claude API adapter for chat completions.

  Implements the LLM.Adapter behaviour for Anthropic's Messages API,
  including support for Claude-3 models and streaming responses.
  """

  @behaviour Aiex.LLM.Adapter

  require Logger

  @base_url "https://api.anthropic.com/v1"
  @messages_endpoint "/messages"
  @timeout 60_000

  @supported_models [
    "claude-3-opus-20240229",
    "claude-3-sonnet-20240229",
    "claude-3-haiku-20240307",
    "claude-2.1",
    "claude-2.0",
    "claude-instant-1.2"
  ]

  @rate_limits %{
    requests_per_minute: 50,
    tokens_per_minute: 100_000
  }

  @impl true
  def complete(request, opts \\ []) do
    with {:ok, payload} <- build_payload(request),
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
    api_key = Keyword.get(opts, :api_key)

    cond do
      is_nil(api_key) or api_key == "" ->
        {:error, "Anthropic API key is required"}

      not String.starts_with?(api_key, "sk-ant-") ->
        {:error, "Invalid Anthropic API key format"}

      true ->
        :ok
    end
  end

  @impl true
  def supported_models, do: @supported_models

  @impl true
  def rate_limits, do: @rate_limits

  @impl true
  def estimate_cost(request) do
    model = Map.get(request, :model, "claude-3-haiku-20240307")
    input_tokens = estimate_tokens(request.messages)
    output_tokens = Map.get(request, :max_tokens, 1000)

    pricing = get_model_pricing(model)

    %{
      input_cost: input_tokens * pricing.input_cost_per_token,
      estimated_output_cost: output_tokens * pricing.output_cost_per_token,
      currency: "USD"
    }
  end

  # Private functions

  defp build_payload(request) do
    # Separate system message from user messages (Anthropic format)
    {system_message, messages} = extract_system_message(request.messages)

    payload =
      %{
        model: request.model || "claude-3-haiku-20240307",
        messages: format_messages(messages)
      }
      |> put_optional(:system, system_message)
      # Required for Anthropic
      |> put_optional(:max_tokens, request.max_tokens || 1000)
      |> put_optional(:temperature, request.temperature)
      |> put_optional(:stream, request.stream)

    {:ok, payload}
  end

  defp extract_system_message(messages) do
    case Enum.find(messages, &(&1.role == :system)) do
      %{content: content} = system_msg ->
        remaining_messages = Enum.reject(messages, &(&1 == system_msg))
        {content, remaining_messages}

      nil ->
        {nil, messages}
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
  # System messages are handled separately
  defp format_role(:system), do: "user"
  defp format_role(role), do: to_string(role)

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp make_request(payload, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    base_url = Keyword.get(opts, :base_url, @base_url)
    timeout = Keyword.get(opts, :timeout, @timeout)

    url = base_url <> @messages_endpoint
    headers = build_headers(api_key)
    body = Jason.encode!(payload)

    case Finch.build(:post, url, headers, body)
         |> Finch.request(AiexFinch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %Finch.Response{status: status, body: error_body}} ->
        {:error, parse_error_response(status, error_body)}

      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:error, %{type: :timeout, message: "Request timed out"}}

      {:error, %Mint.TransportError{reason: reason}} ->
        {:error, %{type: :network_error, message: "Network error: #{reason}"}}

      {:error, reason} ->
        {:error, %{type: :unknown, message: "Unknown error: #{inspect(reason)}"}}
    end
  end

  defp build_headers(api_key) do
    [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"},
      {"user-agent", "Aiex/#{Application.spec(:aiex, :vsn)}"}
    ]
  end

  defp parse_completion_response(response) do
    case response do
      %{"content" => [%{"text" => content} | _], "usage" => usage} = resp ->
        {:ok,
         %{
           content: content,
           model: resp["model"],
           usage: %{
             prompt_tokens: usage["input_tokens"],
             completion_tokens: usage["output_tokens"],
             total_tokens: usage["input_tokens"] + usage["output_tokens"]
           },
           finish_reason: parse_finish_reason(resp["stop_reason"]),
           metadata: %{
             id: resp["id"],
             cost: calculate_cost(resp["model"], usage)
           }
         }}

      %{"error" => error} ->
        {:error, parse_api_error(error)}

      _ ->
        {:error, %{type: :invalid_response, message: "Unexpected response format"}}
    end
  end

  defp parse_stream_response(response) do
    # For streaming, we'd need to implement Server-Sent Events parsing
    # This is a simplified version
    Stream.map([response], fn chunk ->
      content =
        case chunk do
          %{"content" => [%{"text" => text} | _]} -> text
          %{"delta" => %{"text" => text}} -> text
          _ -> ""
        end

      %{
        content: content,
        delta: content,
        finish_reason: parse_finish_reason(chunk["stop_reason"]),
        metadata: %{id: chunk["id"]}
      }
    end)
  end

  defp parse_error_response(status, body) do
    try do
      error_data = Jason.decode!(body)
      parse_api_error(error_data["error"])
    rescue
      _ ->
        %{
          type: :http_error,
          message: "HTTP #{status}",
          code: to_string(status)
        }
    end
  end

  defp parse_api_error(error) when is_map(error) do
    type =
      case error["type"] do
        "rate_limit_error" -> :rate_limit
        "invalid_request_error" -> :invalid_request
        "authentication_error" -> :authentication
        "permission_error" -> :authentication
        "not_found_error" -> :invalid_request
        "overloaded_error" -> :server_error
        "api_error" -> :server_error
        _ -> :unknown
      end

    %{
      type: type,
      message: error["message"] || "Unknown error",
      code: error["code"],
      retry_after: parse_retry_after(error)
    }
  end

  defp parse_api_error(_), do: %{type: :unknown, message: "Unknown error"}

  defp parse_retry_after(%{"retry_after" => retry_after}) when is_integer(retry_after) do
    # Convert to milliseconds
    retry_after * 1000
  end

  defp parse_retry_after(_), do: nil

  defp parse_finish_reason("end_turn"), do: :stop
  defp parse_finish_reason("max_tokens"), do: :length
  defp parse_finish_reason("stop_sequence"), do: :stop
  defp parse_finish_reason(_), do: nil

  defp estimate_tokens(messages) do
    # Rough estimation: ~4 characters per token for Claude
    # Claude models have better token efficiency than GPT
    total_chars =
      messages
      |> Enum.map(&String.length(&1.content))
      |> Enum.sum()

    # Less overhead than OpenAI
    div(total_chars, 4) + length(messages) * 3
  end

  defp get_model_pricing("claude-3-opus-20240229") do
    %{input_cost_per_token: 0.000015, output_cost_per_token: 0.000075}
  end

  defp get_model_pricing("claude-3-sonnet-20240229") do
    %{input_cost_per_token: 0.000003, output_cost_per_token: 0.000015}
  end

  defp get_model_pricing("claude-3-haiku-20240307") do
    %{input_cost_per_token: 0.00000025, output_cost_per_token: 0.00000125}
  end

  defp get_model_pricing("claude-2.1") do
    %{input_cost_per_token: 0.000008, output_cost_per_token: 0.000024}
  end

  defp get_model_pricing("claude-2.0") do
    %{input_cost_per_token: 0.000008, output_cost_per_token: 0.000024}
  end

  defp get_model_pricing("claude-instant-1.2") do
    %{input_cost_per_token: 0.0000008, output_cost_per_token: 0.0000024}
  end

  defp get_model_pricing(_model) do
    # Default to Haiku pricing
    %{input_cost_per_token: 0.00000025, output_cost_per_token: 0.00000125}
  end

  defp calculate_cost(model, usage) do
    pricing = get_model_pricing(model)
    input_cost = usage["input_tokens"] * pricing.input_cost_per_token
    output_cost = usage["output_tokens"] * pricing.output_cost_per_token
    input_cost + output_cost
  end

  @doc """
  Performs a health check on the Anthropic API.
  """
  def health_check(opts \\ []) do
    api_key = Keyword.get(opts, :api_key) || Application.get_env(:aiex, :anthropic_api_key)
    
    if api_key do
      # Try a minimal completion request to check API health
      headers = build_headers(api_key)
      
      # Minimal test request
      test_request = %{
        model: "claude-3-haiku-20240307",
        max_tokens: 1,
        messages: [%{role: "user", content: "Hi"}]
      }
      
      case Finch.build(:post, @base_url <> @messages_endpoint, headers, Jason.encode!(test_request))
           |> Finch.request(AiexFinch, receive_timeout: 5_000) do
        {:ok, %Finch.Response{status: 200}} ->
          :ok
        
        {:ok, %Finch.Response{status: status}} ->
          {:error, "Anthropic API returned status #{status}"}
        
        {:error, %Mint.TransportError{reason: :econnrefused}} ->
          {:error, "Connection refused - Anthropic API unreachable"}
        
        {:error, reason} ->
          {:error, "Health check failed: #{inspect(reason)}"}
      end
    else
      {:error, "No API key configured"}
    end
  end
end
