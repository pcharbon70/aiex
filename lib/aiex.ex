defmodule Aiex do
  @moduledoc """
  Aiex - Distributed AI-powered Elixir coding assistant.

  Aiex is a sophisticated coding assistant built with pure OTP primitives, designed for
  horizontal scaling and fault tolerance. It provides intelligent code analysis, module
  generation, and multi-provider LLM integration across distributed Elixir clusters.

  ## Features

  - **Distributed Architecture**: Built with pure OTP clustering, Horde, and Mnesia
  - **Multi-LLM Support**: OpenAI, Anthropic, Ollama, and LM Studio adapters
  - **Secure Operations**: Sandboxed file operations with audit logging
  - **Multi-Interface**: CLI, Phoenix LiveView, and VS Code LSP support
  - **Production Ready**: Kubernetes-native deployment with optional libcluster

  ## Architecture Overview

  The application follows a distributed supervision tree design with five main subsystems:

  1. **CLI Interface** - Rich terminal UI with verb-noun command structure
  2. **Context Management Engine** - Distributed context with Mnesia persistence
  3. **LLM Integration Layer** - Multi-provider coordination with intelligent routing
  4. **File Operation Sandbox** - Security-focused operations with path validation
  5. **Interface Gateway** - Unified access point for all interface types

  ## Getting Started

  ### Using the CLI

      # Generate a new module
      mix ai.gen.module Calculator "basic arithmetic operations"

      # Explain existing code
      mix ai.explain lib/my_module.ex

      # Get help
      mix ai

  ### Using Programmatically

      # Start the application
      Application.ensure_all_started(:aiex)

      # Register an interface
      config = %{
        type: :api,
        session_id: "my_session",
        user_id: nil,
        capabilities: [:text_output],
        settings: %{}
      }
      {:ok, interface_id} = Aiex.InterfaceGateway.register_interface(MyInterface, config)

      # Submit a request
      request = %{
        id: "req_1",
        type: :completion,
        content: "Explain this code",
        context: %{},
        options: []
      }
      {:ok, request_id} = Aiex.InterfaceGateway.submit_request(interface_id, request)

  ## Configuration

  Configure providers in `config/config.exs`:

      config :aiex,
        llm: [
          default_provider: :ollama,
          distributed_coordination: true,
          provider_affinity: :local_preferred
        ],
        cluster: [
          discovery_strategy: :kubernetes_dns,
          heartbeat_interval: 5_000
        ]

  ## Distributed Deployment

  Clustering is optional and disabled by default for development.

  For single-node development (default):

      config :aiex, cluster_enabled: false

  For Kubernetes distributed deployment:

      config :aiex, cluster_enabled: true
      
      config :libcluster,
        topologies: [
          aiex_cluster: [
            strategy: Cluster.Strategy.Kubernetes.DNS,
            config: [
              service: "aiex-headless",
              application_name: "aiex"
            ]
          ]
        ]

  See the [Implementation Plan](planning/detailed_implementation_plan.md) for detailed
  architecture documentation and the [Architecture Overview](research/coding_agent_overview.md)
  for design principles.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # pg is started automatically by OTP, no need to start it manually

    children =
      [
        # Core infrastructure
        {Registry, keys: :unique, name: Aiex.Registry},
        {Horde.Registry, name: Aiex.HordeRegistry, keys: :unique},
        {Horde.DynamicSupervisor, name: Aiex.HordeSupervisor, strategy: :one_for_one},

        # Distributed event bus
        Aiex.Events.EventBus,

        # Distributed configuration management
        Aiex.Config.DistributedConfig,

        # HTTP Client for LLM requests
        {Finch, name: AiexFinch},

        # Distributed context management
        Aiex.Context.DistributedEngine,
        {Horde.Registry, name: Aiex.Context.SessionRegistry, keys: :unique},
        Aiex.Context.Manager,
        Aiex.Context.SessionSupervisor,

        # Context compression
        Aiex.Context.Compressor,

        # Sandbox Configuration
        Aiex.Sandbox.Config,

        # Audit Logger
        Aiex.Sandbox.AuditLogger,

        # LLM Rate Limiter
        Aiex.LLM.RateLimiter,

        # Distributed LLM Model Coordinator
        {Aiex.LLM.ModelCoordinator, []},

        # Template system for AI prompts (integrated but supervisor pending)
        # Aiex.LLM.Templates.TemplateRegistry,

        # Semantic Analysis
        Aiex.Semantic.Chunker,

        # Template system for AI prompts
        Aiex.LLM.Templates.Supervisor,

        # Interface Gateway for unified access
        {Aiex.InterfaceGateway, []},

        # AI Engines (must start before coordinators that depend on them)
        Aiex.AI.Engines.CodeAnalyzer,
        Aiex.AI.Engines.GenerationEngine,
        Aiex.AI.Engines.ExplanationEngine,
        Aiex.AI.Engines.RefactoringEngine,
        Aiex.AI.Engines.TestGenerator,

        # AI Coordinators
        Aiex.AI.Coordinators.CodingAssistant,
        Aiex.AI.Coordinators.ConversationManager,

        # Phoenix PubSub
        {Phoenix.PubSub, name: Aiex.PubSub},

        # Phoenix Endpoint for web interface
        AiexWeb.Endpoint,
        
        # Terminal User Interface (Zig/Libvaxis)
        # Started in isolated supervision for fault tolerance
        tui_supervisor(),

        # LLM Client (optional - only start if configured)
        llm_client_spec(),

        # Cluster coordination (if libcluster is configured)
        cluster_supervisor()
      ]
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Aiex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Private functions

  defp cluster_supervisor do
    # Only start cluster supervisor if:
    # 1. Clustering is explicitly enabled in config
    # 2. libcluster dependency is available
    # 3. Topologies are configured
    with true <- Application.get_env(:aiex, :cluster_enabled, false),
         {:ok, _} <- Application.ensure_loaded(:libcluster),
         topologies when not is_nil(topologies) and topologies != [] <-
           Application.get_env(:libcluster, :topologies) do
      require Logger
      Logger.info("Starting distributed clustering with #{length(topologies)} topology(ies)")
      {Cluster.Supervisor, [topologies, [name: Aiex.ClusterSupervisor]]}
    else
      false ->
        require Logger
        Logger.debug("Clustering disabled in configuration - running in single-node mode")
        nil

      {:error, :nofile} ->
        require Logger
        Logger.info("libcluster not available - running in single-node mode")
        nil

      _ ->
        require Logger
        Logger.debug("No cluster topologies configured - running in single-node mode")
        nil
    end
  end

  defp llm_client_spec do
    # Only start LLM client if properly configured
    # For now, we'll skip it to allow basic CLI functionality
    # In a full implementation, this would check for API keys
    nil
  end
  
  defp tui_supervisor do
    # Only start TUI if explicitly enabled
    if Application.get_env(:aiex, :tui_enabled, false) do
      require Logger
      Logger.info("Starting Zig/Libvaxis Terminal User Interface")
      Aiex.Tui.Supervisor
    else
      nil
    end
  end
end
