defmodule Aiex.NATS.MessageHandler do
  @moduledoc """
  Behaviour for NATS message handlers.
  
  Message handlers receive decoded NATS messages and process them according
  to their specific domain (file operations, LLM requests, etc.).
  """
  
  @doc """
  Handles a decoded NATS message with context information.
  
  ## Parameters
  
  - `data` - The decoded message data (typically a map)
  - `context` - Message context containing:
    - `:topic` - The NATS subject the message was received on
    - `:reply_to` - Optional reply subject for responses
    - `:gnat_conn` - The NATS connection PID
    - `:timestamp` - When the message was received
  
  ## Returns
  
  The handler should process the message and optionally send a response
  using the provided context information.
  """
  @callback handle_message(data :: map(), context :: map()) :: :ok | {:error, term()}
end