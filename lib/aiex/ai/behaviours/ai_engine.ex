defmodule Aiex.AI.Behaviours.AIEngine do
  @moduledoc """
  Behavior contract for AI engines that provide coding assistance capabilities.
  
  All AI engines should implement this behavior to ensure consistent interface
  and integration with the existing distributed infrastructure.
  """

  @doc """
  Processes a request using the AI engine's specific capabilities.
  
  ## Parameters
  
  - `request` - A map containing the request data and options
  - `context` - Project context and session information
  
  ## Returns
  
  - `{:ok, result}` - Successful processing with result
  - `{:error, reason}` - Processing failed with reason
  """
  @callback process(request :: map(), context :: map()) :: 
    {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Validates that the engine can process the given request type.
  
  ## Parameters
  
  - `request_type` - The type of request (e.g., :analyze, :generate, :explain)
  
  ## Returns
  
  - `true` if the engine can handle this request type
  - `false` if the engine cannot handle this request type
  """
  @callback can_handle?(request_type :: atom()) :: boolean()

  @doc """
  Returns metadata about the AI engine's capabilities.
  
  ## Returns
  
  A map containing:
  - `:name` - Human-readable name of the engine
  - `:description` - Brief description of capabilities
  - `:supported_types` - List of request types this engine supports
  - `:version` - Engine version
  """
  @callback get_metadata() :: map()

  @doc """
  Prepares the engine for processing (initialization, warming up, etc.).
  
  ## Parameters
  
  - `options` - Optional configuration for engine preparation
  
  ## Returns
  
  - `:ok` - Engine is ready
  - `{:error, reason}` - Preparation failed
  """
  @callback prepare(options :: keyword()) :: :ok | {:error, atom() | String.t()}

  @doc """
  Cleans up resources and shuts down the engine gracefully.
  
  ## Returns
  
  - `:ok` - Cleanup completed successfully
  """
  @callback cleanup() :: :ok

  @optional_callbacks [prepare: 1, cleanup: 0]
end