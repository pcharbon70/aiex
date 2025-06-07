defmodule Aiex.LLM.Adapter do
  @moduledoc """
  Behaviour defining the interface for LLM adapters.

  This module defines the contract that all LLM adapters must implement,
  providing a consistent interface for different AI model providers.
  """

  @type message :: %{
          role: :system | :user | :assistant,
          content: String.t()
        }

  @type completion_request :: %{
          messages: [message()],
          model: String.t(),
          max_tokens: pos_integer() | nil,
          temperature: float() | nil,
          stream: boolean(),
          metadata: map()
        }

  @type completion_response :: %{
          content: String.t(),
          model: String.t(),
          usage: %{
            prompt_tokens: pos_integer(),
            completion_tokens: pos_integer(),
            total_tokens: pos_integer()
          },
          finish_reason: :stop | :length | :content_filter | :function_call | nil,
          metadata: map()
        }

  @type stream_chunk :: %{
          content: String.t(),
          delta: String.t(),
          finish_reason: atom() | nil,
          metadata: map()
        }

  @type error_response :: %{
          type: :rate_limit | :invalid_request | :authentication | :server_error | :unknown,
          message: String.t(),
          code: String.t() | nil,
          retry_after: pos_integer() | nil
        }

  @type adapter_result ::
          {:ok, completion_response()}
          | {:error, error_response()}
          | {:stream, Enumerable.t(stream_chunk())}

  @doc """
  Generate a completion from the LLM.
  """
  @callback complete(completion_request(), keyword()) :: adapter_result()

  @doc """
  Validate the adapter configuration.
  """
  @callback validate_config(keyword()) :: :ok | {:error, String.t()}

  @doc """
  Get the adapter's supported models.
  """
  @callback supported_models() :: [String.t()]

  @doc """
  Get the adapter's rate limits.
  """
  @callback rate_limits() :: %{
              requests_per_minute: pos_integer() | nil,
              tokens_per_minute: pos_integer() | nil
            }

  @doc """
  Check the health of the adapter/provider.
  """
  @callback health_check(map()) :: :ok | {:error, term()}

  @doc """
  Estimate the cost of a completion request.
  """
  @callback estimate_cost(completion_request()) :: %{
              input_cost: float(),
              estimated_output_cost: float(),
              currency: String.t()
            }

  @optional_callbacks [estimate_cost: 1]
end
