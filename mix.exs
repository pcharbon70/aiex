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
      releases: releases(),

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
      {:tidewave, "~> 0.1", only: [:dev]},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      # CLI and HTTP
      {:owl, "~> 0.12.0"},
      {:optimus, "~> 0.3.0"},
      {:finch, "~> 0.18.0"},
      {:hammer, "~> 6.1"},
      {:jason, "~> 1.4"},

      # Phoenix LiveView Web Interface
      {:phoenix, "~> 1.7.14"},
      {:phoenix_live_view, "~> 0.20.17"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:plug_cowboy, "~> 2.7"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},
      {:gettext, "~> 0.24"},
      {:floki, ">= 0.30.0", only: :test},

      # Assets
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},

      # Distributed OTP
      {:horde, "~> 0.9.0"},
      {:libcluster, "~> 3.3", optional: true},
      {:syn, "~> 3.3"},

      # Performance Monitoring & Optimization
      {:recon, "~> 2.5"},
      {:benchee, "~> 1.3"},
      {:observer_cli, "~> 1.7"},
      
      # HTTP server for health probes
      {:ranch, "~> 2.1"},

      # NATS messaging
      {:gnat, "~> 1.8"},
      {:msgpax, "~> 2.4"},

      # Terminal UI (temporarily disabled due to Python 3.14 compatibility issue)
      # {:ratatouille, "~> 0.5.1"},

      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp escript do
    [
      main_module: Aiex.CLI
    ]
  end

  defp releases do
    [
      aiex: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, &copy_tui_binary/1, &copy_launcher/1],
        strip_beams: Mix.env() == :prod,
        include_erts: true,
        cookie: "aiex_release_cookie",
        quiet: true
      ]
    ]
  end

  # Copy the Rust TUI binary into the release
  defp copy_tui_binary(release) do
    tui_binary = Path.join(["tui", "target", "release", "aiex-tui"])

    if File.exists?(tui_binary) do
      File.cp!(tui_binary, Path.join([release.path, "bin", "aiex-tui"]))
      File.chmod!(Path.join([release.path, "bin", "aiex-tui"]), 0o755)
    end

    release
  end

  # Copy the launcher script into the release
  defp copy_launcher(release) do
    launcher_script = "scripts/aiex-launcher.sh"

    if File.exists?(launcher_script) do
      File.cp!(launcher_script, Path.join([release.path, "bin", "aiex"]))
      File.chmod!(Path.join([release.path, "bin", "aiex"]), 0o755)
    end

    release
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
        Configuration: [
          Aiex.Config.DistributedConfig
        ],
        "Events & Communication": [
          Aiex.Events.EventBus
        ],
        Interfaces: [
          Aiex.Interfaces.CLIInterface
        ],
        "Mix Tasks": [
          Mix.Tasks.Ai,
          Mix.Tasks.Ai.Explain,
          Mix.Tasks.Ai.Gen.Module
        ],
        Templates: [
          Aiex.LLM.Templates.PromptTemplate
        ]
      ],
      groups_for_docs: [
        "Client API": &(&1[:type] == :client),
        "Server Callbacks": &(&1[:type] == :callback),
        Configuration: &(&1[:type] == :config)
      ]
    ]
  end
end
