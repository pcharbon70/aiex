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
    case result do
      {[:create], %Optimus.ParseResult{}} -> {:ok, Create}
      {[:analyze], %Optimus.ParseResult{}} -> {:ok, Analyze}
      {[:ai], %Optimus.ParseResult{}} -> {:ok, AI}
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

  defp ai_command_spec do
    [
      name: "ai",
      about: "AI-powered coding assistance and workflow orchestration",
      subcommands: [
        analyze: [
          name: "analyze",
          about: "Analyze code using AI engines for insights and improvements",
          options: [
            file: [
              value_name: "FILE_PATH",
              short: "-f",
              long: "--file",
              help: "Path to the file to analyze",
              parser: :string
            ],
            type: [
              value_name: "ANALYSIS_TYPE",
              short: "-t",
              long: "--type",
              help: "Type of analysis (structure, quality, performance, all)",
              parser: :string,
              default: "quality"
            ],
            output: [
              value_name: "OUTPUT_FORMAT",
              short: "-o",
              long: "--output",
              help: "Output format (text, json, markdown)",
              parser: :string,
              default: "text"
            ]
          ]
        ],
        generate: [
          name: "generate",
          about: "Generate code using AI with intelligent suggestions",
          options: [
            type: [
              value_name: "GENERATION_TYPE",
              short: "-t",
              long: "--type",
              help: "Type of generation (function, module, test, documentation)",
              parser: :string,
              required: true
            ],
            context: [
              value_name: "CONTEXT_FILE",
              short: "-c",
              long: "--context",
              help: "Context file to base generation on",
              parser: :string
            ],
            requirements: [
              value_name: "REQUIREMENTS",
              short: "-r",
              long: "--requirements",
              help: "Requirements or description for generation",
              parser: :string,
              required: true
            ],
            output: [
              value_name: "OUTPUT_FILE",
              short: "-o",
              long: "--output",
              help: "Output file path (default: stdout)",
              parser: :string
            ]
          ]
        ],
        explain: [
          name: "explain",
          about: "Get AI explanations of code functionality and patterns",
          options: [
            file: [
              value_name: "FILE_PATH",
              short: "-f",
              long: "--file",
              help: "Path to the file to explain",
              parser: :string,
              required: true
            ],
            level: [
              value_name: "DETAIL_LEVEL",
              short: "-l",
              long: "--level",
              help: "Explanation detail level (beginner, intermediate, advanced)",
              parser: :string,
              default: "intermediate"
            ],
            focus: [
              value_name: "FOCUS_AREA",
              short: "-F",
              long: "--focus",
              help: "Focus area (architecture, patterns, logic, performance)",
              parser: :string,
              default: "comprehensive"
            ]
          ]
        ],
        refactor: [
          name: "refactor",
          about: "AI-powered code refactoring with suggestions and automation",
          options: [
            file: [
              value_name: "FILE_PATH",
              short: "-f",
              long: "--file",
              help: "Path to the file to refactor",
              parser: :string,
              required: true
            ],
            type: [
              value_name: "REFACTOR_TYPE",
              short: "-t",
              long: "--type",
              help: "Refactoring type (extract_function, simplify_logic, optimize_performance, all)",
              parser: :string,
              default: "all"
            ],
            apply: [
              short: "-a",
              long: "--apply",
              help: "Apply refactoring suggestions automatically",
              multiple: false
            ],
            preview: [
              short: "-p",
              long: "--preview",
              help: "Show preview of changes without applying",
              multiple: false
            ]
          ]
        ],
        workflow: [
          name: "workflow",
          about: "Execute AI-orchestrated workflows for complex tasks",
          options: [
            template: [
              value_name: "TEMPLATE_NAME",
              short: "-t",
              long: "--template",
              help: "Workflow template (feature_implementation, bug_fix_workflow, code_review_workflow)",
              parser: :string,
              required: true
            ],
            context: [
              value_name: "CONTEXT_FILE",
              short: "-c",
              long: "--context",
              help: "Context file for workflow execution",
              parser: :string
            ],
            description: [
              value_name: "DESCRIPTION",
              short: "-d",
              long: "--description",
              help: "Description of the task or feature to implement",
              parser: :string,
              required: true
            ],
            mode: [
              value_name: "EXECUTION_MODE",
              short: "-m",
              long: "--mode",
              help: "Execution mode (sequential, parallel, pipeline)",
              parser: :string,
              default: "sequential"
            ]
          ]
        ],
        chat: [
          name: "chat",
          about: "Start an interactive AI chat session for coding assistance",
          options: [
            conversation_type: [
              value_name: "CONVERSATION_TYPE",
              short: "-t",
              long: "--type",
              help: "Conversation type (coding, general, project, debugging)",
              parser: :string,
              default: "coding"
            ],
            context: [
              value_name: "CONTEXT_DIR",
              short: "-c",
              long: "--context",
              help: "Project directory for context",
              parser: :string,
              default: "."
            ]
          ]
        ],
        template: [
          name: "template",
          about: "Manage and test AI prompt templates",
          subcommands: [
            list: [
              name: "list",
              about: "List available templates",
              options: [
                category: [
                  value_name: "CATEGORY",
                  short: "-c",
                  long: "--category",
                  help: "Filter by category (workflow, operation)",
                  parser: :string
                ]
              ]
            ],
            test: [
              name: "test",
              about: "Test a template with sample data",
              options: [
                name: [
                  value_name: "TEMPLATE_NAME",
                  short: "-n",
                  long: "--name",
                  help: "Name of template to test",
                  parser: :string,
                  required: true
                ],
                variables: [
                  value_name: "VARIABLES_JSON",
                  short: "-v",
                  long: "--variables",
                  help: "JSON string of template variables",
                  parser: :string
                ]
              ]
            ]
          ]
        ]
      ]
    ]
  end
end
