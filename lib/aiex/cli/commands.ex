defmodule Aiex.CLI.Commands do
  @moduledoc """
  Optimus command definitions for Aiex CLI.

  Implements verb-noun command structure:
  - aiex create project --name foo --template basic
  - aiex analyze code --path ./src --depth 3
  - aiex help [command]
  - aiex version
  """

  alias Aiex.CLI.Commands.{Create, Analyze, Help, Version}

  @doc """
  Returns the main Optimus specification with all commands and subcommands.
  """
  def optimus_spec do
    Optimus.new!(
      name: "aiex",
      description: "AI-powered Elixir coding assistant",
      version: "0.1.0",
      author: "Aiex Team",
      about: "Intelligent coding assistant leveraging AI for Elixir development",
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: [
        create: create_command_spec(),
        analyze: analyze_command_spec(),
        help: help_command_spec(),
        version: version_command_spec()
      ]
    )
  end

  @doc """
  Routes parsed commands to their appropriate handlers.
  """
  def route(result) do
    case result do
      {[:create], %Optimus.ParseResult{}} -> {:ok, Create}
      {[:analyze], %Optimus.ParseResult{}} -> {:ok, Analyze}
      {[:help], %Optimus.ParseResult{}} -> {:ok, Help}
      {[:version], %Optimus.ParseResult{}} -> {:ok, Version}
      # Default to help when no args
      {[], %Optimus.ParseResult{}} -> {:ok, Help}
      # Default to help for empty parse result
      %Optimus.ParseResult{} -> {:ok, Help}
      _ -> {:error, "Unknown command. Use 'aiex --help' for available commands."}
    end
  end

  # Private command specifications

  defp create_command_spec do
    [
      name: "create",
      about: "Create new projects, modules, or code structures",
      subcommands: [
        project: [
          name: "project",
          about: "Create a new Elixir project with AI assistance",
          options: [
            name: [
              value_name: "PROJECT_NAME",
              short: "-n",
              long: "--name",
              help: "Name of the project to create",
              parser: :string,
              required: true
            ],
            template: [
              value_name: "TEMPLATE",
              short: "-t",
              long: "--template",
              help: "Project template (basic, web, umbrella, etc.)",
              parser: :string,
              default: "basic"
            ],
            path: [
              value_name: "PATH",
              short: "-p",
              long: "--path",
              help: "Directory to create the project in",
              parser: :string,
              default: "."
            ]
          ]
        ],
        module: [
          name: "module",
          about: "Create a new Elixir module with AI-generated structure",
          options: [
            name: [
              value_name: "MODULE_NAME",
              short: "-n",
              long: "--name",
              help: "Name of the module to create",
              parser: :string,
              required: true
            ],
            type: [
              value_name: "MODULE_TYPE",
              short: "-t",
              long: "--type",
              help: "Type of module (genserver, supervisor, behaviour, etc.)",
              parser: :string,
              default: "basic"
            ]
          ]
        ]
      ]
    ]
  end

  defp analyze_command_spec do
    [
      name: "analyze",
      about: "Analyze code for improvements, patterns, and issues",
      subcommands: [
        code: [
          name: "code",
          about: "Analyze code quality and suggest improvements",
          options: [
            path: [
              value_name: "PATH",
              short: "-p",
              long: "--path",
              help: "Path to analyze (file or directory)",
              parser: :string,
              required: true
            ],
            depth: [
              value_name: "DEPTH",
              short: "-d",
              long: "--depth",
              help: "Maximum directory depth to analyze",
              parser: :integer,
              default: 3
            ],
            format: [
              value_name: "FORMAT",
              short: "-f",
              long: "--format",
              help: "Output format (text, json, markdown)",
              parser: :string,
              default: "text"
            ]
          ]
        ],
        deps: [
          name: "deps",
          about: "Analyze project dependencies",
          options: [
            outdated: [
              short: "-o",
              long: "--outdated",
              help: "Check for outdated dependencies",
              multiple: false
            ],
            security: [
              short: "-s",
              long: "--security",
              help: "Check for security vulnerabilities",
              multiple: false
            ]
          ]
        ]
      ]
    ]
  end

  defp help_command_spec do
    [
      name: "help",
      about: "Show help information for commands",
      args: [
        command: [
          value_name: "COMMAND",
          help: "Command to show help for",
          required: false,
          parser: :string
        ]
      ]
    ]
  end

  defp version_command_spec do
    [
      name: "version",
      about: "Show version information"
    ]
  end
end
