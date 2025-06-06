defmodule Aiex.CLI do
  @moduledoc """
  Main CLI entry point for Aiex.
  
  This module provides the primary interface for the Aiex coding assistant,
  handling command parsing, routing, and execution through a structured pipeline.
  """

  alias Aiex.CLI.Pipeline

  @doc """
  Main entry point called by escript.
  """
  def main(argv) do
    argv
    |> Pipeline.process()
    |> handle_result()
  end

  defp handle_result(:ok), do: System.halt(0)
  defp handle_result({:error, _stage, _reason}), do: System.halt(1)
end