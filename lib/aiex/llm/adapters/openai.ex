defmodule Aiex.LLM.Adapters.OpenAI do
  @moduledoc """
  OpenAI API adapter for chat completions.
  
  Implements the LLM.Adapter behaviour for OpenAI's chat completion API,
  including support for streaming responses and proper error handling.
  """
  
  @behaviour Aiex.LLM.Adapter
  
  require Logger
  
  @base_url "https://api.openai.com/v1"
  @chat_endpoint "/chat/completions"
  @timeout 30_000
  
  @supported_models [
    "gpt-4",
    "gpt-4-0613",
    "gpt-4-32k",
    "gpt-4-32k-0613",
    "gpt-4-turbo-preview",
    "gpt-3.5-turbo",
    "gpt-3.5-turbo-0613",
    "gpt-3.5-turbo-16k",
    "gpt-3.5-turbo-16k-0613"
  ]
  
  @rate_limits %{
    requests_per_minute: 60,
    tokens_per_minute: 90_000
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
        {:error, "OpenAI API key is required"}
      
      not String.starts_with?(api_key, "sk-") ->
        {:error, "Invalid OpenAI API key format"}
      
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
    model = request.model || "gpt-3.5-turbo"
    input_tokens = estimate_tokens(request.messages)
    output_tokens = request.max_tokens || 1000
    
    pricing = get_model_pricing(model)
    
    %{
      input_cost: input_tokens * pricing.input_cost_per_token,
      estimated_output_cost: output_tokens * pricing.output_cost_per_token,
      currency: "USD"
    }
  end
  
  # Private functions
  
  defp build_payload(request) do
    payload = %{
      model: request.model || "gpt-3.5-turbo",
      messages: format_messages(request.messages)
    }
    |> put_optional(:max_tokens, request.max_tokens)
    |> put_optional(:temperature, request.temperature)
    |> put_optional(:stream, request.stream)
    
    {:ok, payload}
  end
  
  defp format_messages(messages) do
    Enum.map(messages, fn message ->
      %{
        role: to_string(message.role),
        content: message.content
      }
    end)
  end
  
  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
  
  defp make_request(payload, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    base_url = Keyword.get(opts, :base_url, @base_url)
    timeout = Keyword.get(opts, :timeout, @timeout)
    
    url = base_url <> @chat_endpoint
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
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"},
      {"user-agent", "Aiex/#{Application.spec(:aiex, :vsn)}"}
    ]
  end
  
  defp parse_completion_response(response) do
    case response do
      %{"choices" => [choice | _], "usage" => usage} ->
        {:ok, %{
          content: get_in(choice, ["message", "content"]) || "",
          model: response["model"],
          usage: %{
            prompt_tokens: usage["prompt_tokens"],
            completion_tokens: usage["completion_tokens"],
            total_tokens: usage["total_tokens"]
          },
          finish_reason: parse_finish_reason(choice["finish_reason"]),
          metadata: %{
            id: response["id"],
            created: response["created"],
            cost: calculate_cost(response["model"], usage)
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
      %{
        content: get_in(chunk, ["choices", Access.at(0), "delta", "content"]) || "",
        delta: get_in(chunk, ["choices", Access.at(0), "delta", "content"]) || "",
        finish_reason: parse_finish_reason(get_in(chunk, ["choices", Access.at(0), "finish_reason"])),
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
    type = case error["type"] do
      "insufficient_quota" -> :rate_limit
      "invalid_request_error" -> :invalid_request
      "authentication_error" -> :authentication
      "server_error" -> :server_error
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
    retry_after * 1000  # Convert to milliseconds
  end
  defp parse_retry_after(_), do: nil
  
  defp parse_finish_reason("stop"), do: :stop
  defp parse_finish_reason("length"), do: :length
  defp parse_finish_reason("content_filter"), do: :content_filter
  defp parse_finish_reason("function_call"), do: :function_call
  defp parse_finish_reason(_), do: nil
  
  defp estimate_tokens(messages) do
    # Rough estimation: ~4 characters per token
    # In production, you'd use a proper tokenizer
    total_chars = messages
    |> Enum.map(&String.length(&1.content))
    |> Enum.sum()
    
    div(total_chars, 4) + length(messages) * 4  # Add overhead for message structure
  end
  
  defp get_model_pricing("gpt-4") do
    %{input_cost_per_token: 0.00003, output_cost_per_token: 0.00006}
  end
  defp get_model_pricing("gpt-4-32k") do
    %{input_cost_per_token: 0.00006, output_cost_per_token: 0.00012}
  end
  defp get_model_pricing("gpt-3.5-turbo") do
    %{input_cost_per_token: 0.0000015, output_cost_per_token: 0.000002}
  end
  defp get_model_pricing("gpt-3.5-turbo-16k") do
    %{input_cost_per_token: 0.000003, output_cost_per_token: 0.000004}
  end
  defp get_model_pricing(_model) do
    # Default to GPT-3.5-turbo pricing
    %{input_cost_per_token: 0.0000015, output_cost_per_token: 0.000002}
  end
  
  defp calculate_cost(model, usage) do
    pricing = get_model_pricing(model)
    input_cost = usage["prompt_tokens"] * pricing.input_cost_per_token
    output_cost = usage["completion_tokens"] * pricing.output_cost_per_token
    input_cost + output_cost
  end
end