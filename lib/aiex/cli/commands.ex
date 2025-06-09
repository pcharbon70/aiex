defmodule Aiex.CLI.Commands do
  @moduledoc """
  Optimus command definitions for Aiex CLI.

  Implements verb-noun command structure:
  - aiex create project --name foo --template basic
  - aiex analyze code --path ./src --depth 3
  - aiex help [command]
  - aiex version
  """

  alias Aiex.CLI.Commands.{Create, Analyze, Help, Version, AI}

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
        ai: ai_command_spec(),
        help: help_command_spec(),
        version: version_command_spec()
      ]
    )
  end

  @doc """
  Routes parsed commands to their appropriate handlers.
  """
  def route(result) do
    # Debug logging
    require Logger
    Logger.info("Routing result: #{inspect(result)}")
    
    case result do
      {[:create], %Optimus.ParseResult{}} -> {:ok, Create}
      {[:analyze], %Optimus.ParseResult{}} -> {:ok, Analyze}
      {[:ai], %Optimus.ParseResult{}} -> {:ok, AI}
      {[:ai, _subcommand], %Optimus.ParseResult{}} -> {:ok, AI}

      {[:help], %Optimus.ParseResult{}} -> {:ok, Help}
      {[:version], %Optimus.ParseResult{}} -> {:ok, Version}
      # Default to help when no args
      {[], %Optimus.ParseResult{}} -> {:ok, Help}
      # Default to help for empty parse result
      %Optimus.ParseResult{} -> {:ok, Help}
      _ -> {:error, "Unknown command. Use 'aiex --help' for available commands.

Available commands:
  • create - Create new projects or modules
  • analyze - Analyze code and dependencies
  • ai - AI-powered coding assistance commands
  • help - Show help information
  • version - Show version information"}
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

  defp shell_command_spec do
    [
      name: "shell",
      about: "Start interactive AI shell with enhanced features",
      args: [],
      options: [
        project_dir: [
          value_name: "DIR",
          short: "-d",
          long: "--project-dir",
          help: "Project directory for context",
          required: false,
          parser: :string
        ],
        mode: [
          value_name: "MODE",
          short: "-m",
          long: "--mode",
          help: "Shell mode (interactive, command, chat)",
          required: false,
          parser: :string,
          default: "interactive"
        ],
        save_session: [
          value_name: "FILE",
          short: "-s",
          long: "--save-session",
          help: "Auto-save session to file",
          required: false,
          parser: :string
        ]
      ],
      flags: [
        no_auto_save: [
          long: "--no-auto-save",
          help: "Disable automatic session saving"
        ],
        verbose: [
          short: "-v",
          long: "--verbose",
          help: "Enable verbose output"
        ]
      ]
    ]
  end

  defp pipeline_command_spec do
    [
      name: "pipeline",
      about: "Chain AI operations together for complex workflows",
      subcommands: [
        validate: [
          name: "validate",
          about: "Validate a pipeline specification",
          args: [
            spec: [
              value_name: "PIPELINE_SPEC",
              help: "Pipeline specification string",
              required: true,
              parser: :string
            ]
          ]
        ],
        list: [
          name: "list",
          about: "List available pipeline operations"
        ],
        examples: [
          name: "examples",
          about: "Show pipeline usage examples"
        ]
      ],
      options: [
        spec: [
          value_name: "PIPELINE_SPEC",
          short: "-s",
          long: "--spec",
          help: "Pipeline specification string (e.g., 'analyze | refactor | test_generate')",
          parser: :string,
          required: false
        ],
        input: [
          value_name: "FILE",
          short: "-i",
          long: "--input",
          help: "Input file for pipeline",
          parser: :string,
          required: false
        ],
        output: [
          value_name: "FILE",
          short: "-o",
          long: "--output",
          help: "Output file for results",
          parser: :string,
          required: false
        ],
        mode: [
          value_name: "MODE",
          short: "-m",
          long: "--mode",
          help: "Execution mode (sequential, parallel, conditional, streaming)",
          parser: :string,
          default: "sequential"
        ]
      ],
      flags: [
        validate: [
          short: "-v",
          long: "--validate",
          help: "Validate pipeline only, don't execute"
        ],
        continue_on_error: [
          short: "-c",
          long: "--continue-on-error",
          help: "Continue pipeline execution even if a step fails"
        ],
        verbose: [
          long: "--verbose",
          help: "Enable verbose output"
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

  defp ai_command_spec do
    [
      name: "ai",
      about: "AI-powered coding assistance commands",
      subcommands: [
        analyze: [
          name: "analyze",
          about: "Analyze code with AI for quality insights",
          options: [
            file: [
              value_name: "FILE",
              short: "-f",
              long: "--file",
              help: "File to analyze",
              required: true,
              parser: :string
            ],
            type: [
              value_name: "TYPE",
              short: "-t",
              long: "--type",
              help: "Analysis type (quality, performance, security)",
              required: false,
              parser: :string,
              default: "quality"
            ],
            output: [
              value_name: "FORMAT",
              short: "-o",
              long: "--output",
              help: "Output format (text, json, markdown)",
              required: false,
              parser: :string,
              default: "text"
            ]
          ]
        ],
        generate: [
          name: "generate",
          about: "Generate code using AI",
          options: [
            type: [
              value_name: "TYPE",
              short: "-t",
              long: "--type",
              help: "Generation type (module, function, test)",
              required: true,
              parser: :string
            ],
            requirements: [
              value_name: "TEXT",
              short: "-r",
              long: "--requirements",
              help: "Requirements description",
              required: true,
              parser: :string
            ],
            context: [
              value_name: "FILE",
              short: "-c",
              long: "--context",
              help: "Context file for generation",
              required: false,
              parser: :string
            ],
            output: [
              value_name: "FILE",
              short: "-o",
              long: "--output",
              help: "Output file (default: stdout)",
              required: false,
              parser: :string
            ]
          ]
        ],
        explain: [
          name: "explain",
          about: "Get AI explanations of code",
          options: [
            file: [
              value_name: "FILE",
              short: "-f",
              long: "--file",
              help: "File to explain",
              required: true,
              parser: :string
            ],
            level: [
              value_name: "LEVEL",
              short: "-l",
              long: "--level",
              help: "Detail level (basic, intermediate, advanced)",
              required: false,
              parser: :string,
              default: "intermediate"
            ],
            focus: [
              value_name: "FOCUS",
              long: "--focus",
              help: "Focus area (comprehensive, patterns, architecture)",
              required: false,
              parser: :string,
              default: "comprehensive"
            ]
          ]
        ],
        refactor: [
          name: "refactor",
          about: "Get AI refactoring suggestions",
          options: [
            file: [
              value_name: "FILE",
              short: "-f",
              long: "--file",
              help: "File to refactor",
              required: true,
              parser: :string
            ],
            type: [
              value_name: "TYPE",
              short: "-t",
              long: "--type",
              help: "Refactoring type (all, performance, readability)",
              required: false,
              parser: :string,
              default: "all"
            ]
          ],
          flags: [
            apply: [
              short: "-a",
              long: "--apply",
              help: "Apply refactoring changes to file"
            ],
            preview: [
              short: "-p",
              long: "--preview",
              help: "Show refactoring preview"
            ]
          ]
        ],
        workflow: [
          name: "workflow",
          about: "Execute AI workflow templates",
          options: [
            template: [
              value_name: "TEMPLATE",
              short: "-t",
              long: "--template",
              help: "Workflow template name",
              required: true,
              parser: :string
            ],
            context: [
              value_name: "FILE",
              short: "-c",
              long: "--context",
              help: "Context file for workflow",
              required: false,
              parser: :string
            ],
            description: [
              value_name: "TEXT",
              short: "-d",
              long: "--description",
              help: "Workflow description",
              required: false,
              parser: :string
            ],
            mode: [
              value_name: "MODE",
              short: "-m",
              long: "--mode",
              help: "Execution mode (sequential, parallel)",
              required: false,
              parser: :string,
              default: "sequential"
            ]
          ]
        ],
        chat: [
          name: "chat",
          about: "Start interactive AI chat session",
          options: [
            conversation_type: [
              value_name: "TYPE",
              short: "-t",
              long: "--type",
              help: "Conversation type (coding, general, debug)",
              required: false,
              parser: :string,
              default: "coding"
            ],
            context: [
              value_name: "DIR",
              short: "-c",
              long: "--context",
              help: "Project context directory",
              required: false,
              parser: :string,
              default: "."
            ]
          ]
        ]
      ]
    ]
  end

end
