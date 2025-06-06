defmodule Aiex.CLI.Commands.CommandBehaviour do
  @moduledoc """
  Behaviour for command handlers in the Aiex CLI system.
  
  All command handlers must implement this behaviour to ensure
  consistent interfaces and error handling.
  """

  @doc """
  Execute a command with the parsed arguments from Optimus.
  
  Returns:
  - `{:ok, result}` - Command executed successfully
  - `{:error, reason}` - Command failed with error message
  """
  @callback execute({list(), Optimus.ParseResult.t()}) :: 
    {:ok, term()} | {:error, String.t()}
end