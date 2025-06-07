defmodule Aiex.MixProject do
  use Mix.Project

  def project do
    [
      app: :aiex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      
      # Hex package configuration
      description: description(),
      package: package(),
      
      # Documentation configuration
      name: "Aiex",
      source_url: "https://github.com/your-org/aiex",
      homepage_url: "https://github.com/your-org/aiex",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {Aiex, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # CLI and HTTP
      {:owl, "~> 0.12.0"},
      {:optimus, "~> 0.3.0"},
      {:finch, "~> 0.18.0"},
      {:hammer, "~> 6.1"},
      {:jason, "~> 1.4"},
      
      # Distributed OTP
      {:horde, "~> 0.9.0"},
      {:libcluster, "~> 3.3"},
      {:syn, "~> 3.3"},
      
      # NATS messaging
      {:gnat, "~> 1.8"},
      {:msgpax, "~> 2.4"},
      
      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp escript do
    [
      main_module: Aiex.CLI
    ]
  end

  defp description do
    """
    Aiex is a distributed AI-powered Elixir coding assistant built with OTP primitives.
    
    Features include intelligent code analysis, module generation, distributed LLM coordination,
    secure sandboxed file operations, and multi-interface support (CLI, LiveView, LSP).
    Built for horizontal scaling and fault tolerance using pure Erlang/OTP clustering.
    """
  end

  defp package do
    [
      name: "aiex",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/your-org/aiex",
        "Documentation" => "https://hexdocs.pm/aiex"
      },
      maintainers: ["Your Name"],
      files: ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md": [title: "Changelog"],
        "planning/detailed_implementation_plan.md": [title: "Implementation Plan"],
        "research/coding_agent_overview.md": [title: "Architecture Overview"]
      ],
      groups_for_modules: [
        "Core Application": [
          Aiex,
          Aiex.InterfaceBehaviour,
          Aiex.InterfaceGateway
        ],
        "CLI Framework": [
          Aiex.CLI,
          Aiex.CLI.Commands,
          Aiex.CLI.Pipeline,
          Aiex.CLI.Presenter
        ],
        "Distributed Context": [
          Aiex.Context.DistributedEngine,
          Aiex.Context.Engine,
          Aiex.Context.Manager,
          Aiex.Context.Session,
          Aiex.Context.SessionSupervisor
        ],
        "LLM Integration": [
          Aiex.LLM.Adapter,
          Aiex.LLM.Client,
          Aiex.LLM.Config,
          Aiex.LLM.ModelCoordinator,
          Aiex.LLM.RateLimiter,
          Aiex.LLM.ResponseParser
        ],
        "LLM Adapters": [
          Aiex.LLM.Adapters.Anthropic,
          Aiex.LLM.Adapters.LMStudio,
          Aiex.LLM.Adapters.Ollama,
          Aiex.LLM.Adapters.OpenAI
        ],
        "Sandbox & Security": [
          Aiex.Sandbox,
          Aiex.Sandbox.AuditLogger,
          Aiex.Sandbox.Config,
          Aiex.Sandbox.PathValidator
        ],
        "Configuration": [
          Aiex.Config.DistributedConfig
        ],
        "Events & Communication": [
          Aiex.Events.EventBus
        ],
        "Interfaces": [
          Aiex.Interfaces.CLIInterface
        ],
        "Mix Tasks": [
          Mix.Tasks.Ai,
          Mix.Tasks.Ai.Explain,
          Mix.Tasks.Ai.Gen.Module
        ],
        "Templates": [
          Aiex.LLM.Templates.PromptTemplate
        ]
      ],
      groups_for_docs: [
        "Client API": &(&1[:type] == :client),
        "Server Callbacks": &(&1[:type] == :callback),
        "Configuration": &(&1[:type] == :config)
      ]
    ]
  end
end
