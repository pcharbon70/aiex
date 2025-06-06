defmodule Aiex.CLI.Pipeline do
  @moduledoc """
  Core CLI pipeline that processes commands using Optimus for parsing
  and Owl for rich terminal output.
  
  Pipeline stages: parse -> validate -> route -> execute -> present
  """

  alias Aiex.CLI.{Commands, Presenter}

  @doc """
  Main entry point for processing CLI commands.
  """
  def process(argv) do
    argv
    |> parse()
    |> validate()
    |> route()
    |> execute()
    |> present()
  end

  @doc """
  Parse stage: Uses Optimus to parse command line arguments
  """
  def parse(argv) do
    try do
      result = Optimus.parse!(Commands.optimus_spec(), argv)
      {:ok, result}
    rescue
      e ->
        {:error, :parse_error, Exception.message(e)}
    catch
      :exit, value ->
        {:error, :parse_error, "Command parsing failed: #{inspect(value)}"}
    end
  end

  @doc """
  Validate stage: Ensures the parsed command is valid
  """
  def validate({:ok, result}) do
    validate_parsed_result(result)
    {:ok, result}
  end
  
  def validate({:error, stage, reason}), do: {:error, stage, reason}

  @doc """
  Route stage: Determines which command handler should process the request
  """
  def route({:ok, result}) do
    case Commands.route(result) do
      {:ok, handler} -> {:ok, {handler, result}}
      {:error, reason} -> {:error, :routing_error, reason}
    end
  end
  
  def route({:error, stage, reason}), do: {:error, stage, reason}

  @doc """
  Execute stage: Runs the command through its handler
  """
  def execute({:ok, {handler, result}}) do
    case handler.execute(result) do
      {:ok, exec_result} -> {:ok, exec_result}
      {:error, reason} -> {:error, :execution_error, reason}
    end
  end
  
  def execute({:error, stage, reason}), do: {:error, stage, reason}

  @doc """
  Present stage: Uses Owl to display results with rich formatting
  """
  def present({:ok, result}) do
    Presenter.present_success(result)
    :ok
  end
  
  def present({:error, stage, reason}) do
    Presenter.present_error(stage, reason)
    {:error, stage, reason}
  end

  # Private helper functions

  defp validate_parsed_result(_result) do
    # All parsed results are considered valid - let routing handle command logic
    :ok
  end
end