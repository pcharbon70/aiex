defmodule Aiex.CLI.Commands.Help do
  @moduledoc """
  Help command handler providing usage information and examples.
  """

  @behaviour Aiex.CLI.Commands.CommandBehaviour

  @impl true
  def execute({[:help], %Optimus.ParseResult{args: %{command: command}}}) when command != nil do
    show_command_help(command)
  end

  @impl true
  def execute({[:help], %Optimus.ParseResult{}}) do
    show_general_help()
  end

  @impl true
  def execute({[], %Optimus.ParseResult{}}) do
    show_general_help()
  end

  @impl true
  def execute(%Optimus.ParseResult{}) do
    show_general_help()
  end

  defp show_general_help do
    {:ok,
     {:info, "Aiex - AI-powered Elixir coding assistant",
      %{
        "Usage" => "aiex <command> [options]",
        "Version" => "0.1.0",
        "Commands" => """

          create project    Create a new Elixir project with AI assistance
          create module     Create a new Elixir module with AI-generated structure
          analyze code      Analyze code quality and suggest improvements  
          analyze deps      Analyze project dependencies
          help [command]    Show help information
          version           Show version information

        Examples:
          aiex create project --name my_app --template web
          aiex analyze code --path ./lib --depth 2
          aiex help create
        """
      }}}
  end

  defp show_command_help(command) do
    case command do
      "create" ->
        {:ok,
         {:info, "Create Command",
          %{
            "Usage" => "aiex create <subcommand> [options]",
            "Subcommands" => """

              project    Create a new Elixir project
                         Options: --name (required), --template, --path
              
              module     Create a new Elixir module  
                         Options: --name (required), --type

            Examples:
              aiex create project --name my_app --template web --path ./projects
              aiex create module --name MyWorker --type genserver
            """
          }}}

      "analyze" ->
        {:ok,
         {:info, "Analyze Command",
          %{
            "Usage" => "aiex analyze <subcommand> [options]",
            "Subcommands" => """

              code       Analyze code quality and patterns
                         Options: --path (required), --depth, --format
              
              deps       Analyze project dependencies
                         Options: --outdated, --security

            Examples:
              aiex analyze code --path ./lib --depth 3 --format json
              aiex analyze deps --outdated --security
            """
          }}}

      _ ->
        {:error, "Unknown command: #{command}. Use 'aiex help' for available commands."}
    end
  end
end
