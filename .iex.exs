# IEx configuration for Aiex development

# Import AI helpers for convenient access
import Aiex.IEx.Helpers

# Useful aliases for development
alias Aiex.InterfaceGateway
alias Aiex.Context.DistributedEngine
alias Aiex.LLM.ModelCoordinator
alias Aiex.Events.EventBus
alias Aiex.Config.DistributedConfig

# Helper functions for development
defmodule IExHelpers do
  @moduledoc """
  Additional helper functions for IEx development sessions.
  """

  @doc "Start all Aiex services if not already running"
  def start_aiex do
    case Application.ensure_all_started(:aiex) do
      {:ok, _} -> 
        IO.puts("✅ Aiex services started successfully")
        cluster_info()
      
      {:error, reason} -> 
        IO.puts("❌ Failed to start Aiex: #{inspect(reason)}")
    end
  end

  @doc "Show cluster information"
  def cluster_info do
    status = cluster_status()
    
    IO.puts("\n🌐 Cluster Status:")
    IO.puts("  Local Node: #{status.local_node}")
    IO.puts("  Connected Nodes: #{length(status.connected_nodes)}")
    IO.puts("  Cluster Health: #{status.cluster_health}")
    IO.puts("  AI Providers: #{status.ai_providers.active}/#{status.ai_providers.healthy}")
    IO.puts("  Interfaces: CLI(#{status.interfaces.cli}) LiveView(#{status.interfaces.liveview}) LSP(#{status.interfaces.lsp})")
    
    status
  end

  @doc "Show available AI helper functions"
  def help do
    IO.puts("""
    
    🤖 Aiex AI Helper Functions:
    
    ai_complete(code)      - Get AI code completions
    ai_explain(code)       - Get AI explanations  
    ai_test(module)        - Generate AI tests
    ai_usage(function)     - Find usage patterns
    
    distributed_context(element) - Get distributed context
    cluster_status()             - Show cluster status
    select_optimal_node(type)    - Find best node for processing
    
    🛠️  Development Helpers:
    
    start_aiex()          - Start all Aiex services
    cluster_info()        - Show detailed cluster info
    help()                - Show this help
    
    📖 Examples:
    
    ai_complete("defmodule MyModule")
    ai_explain(GenServer.handle_call)
    ai_test(MyModule)
    distributed_context("MyModule.function")
    
    """)
  end

  @doc "Quick AI completion with smart defaults"
  def c(code_fragment), do: ai_complete(code_fragment)

  @doc "Quick AI explanation with smart defaults"  
  def e(code_or_function), do: ai_explain(code_or_function)

  @doc "Quick test generation"
  def t(target), do: ai_test(target)

  @doc "Quick usage analysis"
  def u(function_name), do: ai_usage(function_name)
end

# Import development helpers
import IExHelpers

# Welcome message
IO.puts("""

🤖 Welcome to Aiex Interactive Development Environment!

Type help() to see available AI helper functions.
Type start_aiex() to ensure all services are running.
Type cluster_info() to see current cluster status.

Quick commands: c(code), e(code), t(module), u(function)

""")

# Auto-start services in development
if Mix.env() == :dev do
  spawn(fn ->
    :timer.sleep(1000)  # Give IEx time to start
    IExHelpers.start_aiex()
  end)
end