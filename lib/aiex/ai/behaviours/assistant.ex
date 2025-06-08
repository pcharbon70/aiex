defmodule Aiex.AI.Behaviours.Assistant do
  @moduledoc """
  Behavior contract for AI assistants that coordinate multiple engines
  and manage complex workflows.
  
  Assistants orchestrate AI engines and maintain conversation context
  for multi-turn interactions.
  """

  @doc """
  Handles a user request by coordinating appropriate AI engines.
  
  ## Parameters
  
  - `request` - User request with intent and parameters
  - `conversation_context` - Previous conversation history and context
  - `project_context` - Current project state and context
  
  ## Returns
  
  - `{:ok, response, updated_context}` - Successful response with updated context
  - `{:error, reason}` - Request processing failed
  """
  @callback handle_request(
    request :: map(),
    conversation_context :: map(),
    project_context :: map()
  ) :: {:ok, map(), map()} | {:error, atom() | String.t()}

  @doc """
  Determines if this assistant can handle the given request type.
  
  ## Parameters
  
  - `request_type` - The type of request (e.g., :coding_task, :explanation, :conversation)
  
  ## Returns
  
  - `true` if the assistant can handle this request
  - `false` if the assistant cannot handle this request
  """
  @callback can_handle_request?(request_type :: atom()) :: boolean()

  @doc """
  Starts a new conversation session with the assistant.
  
  ## Parameters
  
  - `session_id` - Unique identifier for the conversation session
  - `initial_context` - Initial project and user context
  
  ## Returns
  
  - `{:ok, session_state}` - Session started successfully
  - `{:error, reason}` - Session creation failed
  """
  @callback start_session(session_id :: String.t(), initial_context :: map()) ::
    {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Ends a conversation session and cleans up resources.
  
  ## Parameters
  
  - `session_id` - Unique identifier for the conversation session
  
  ## Returns
  
  - `:ok` - Session ended successfully
  - `{:error, reason}` - Session cleanup failed
  """
  @callback end_session(session_id :: String.t()) ::
    :ok | {:error, atom() | String.t()}

  @doc """
  Returns metadata about the assistant's capabilities and supported workflows.
  
  ## Returns
  
  A map containing:
  - `:name` - Human-readable name of the assistant
  - `:description` - Brief description of capabilities
  - `:supported_workflows` - List of workflow types this assistant supports
  - `:required_engines` - List of AI engines this assistant depends on
  """
  @callback get_capabilities() :: map()

  @optional_callbacks [start_session: 2, end_session: 1]
end