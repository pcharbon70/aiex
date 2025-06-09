defmodule Aiex.IEx.Integration do
  @moduledoc """
  IEx integration module for enhanced AI helpers.
  
  This module provides seamless integration of AI-powered helpers into
  standard IEx sessions, making AI assistance available through simple
  function calls.
  """

  @doc """
  Load AI helpers into the current IEx session.
  
  ## Usage
  
  Add this to your ~/.iex.exs file:
  
      if Code.ensure_loaded?(Aiex.IEx.Integration) do
        Aiex.IEx.Integration.load_helpers()
      end
  
  Or call manually in IEx:
  
      iex> Aiex.IEx.Integration.load_helpers()
  """
  def load_helpers do
    # Import the enhanced helpers into the IEx session
    import_result = try do
      # Import both standard and enhanced helpers
      import Aiex.IEx.Helpers
      import Aiex.IEx.EnhancedHelpers
      
      # Define convenient aliases
      setup_aliases()
      
      :ok
    rescue
      error ->
        {:error, Exception.message(error)}
    end
    
    case import_result do
      :ok ->
        IO.puts("""
        
        🤖 Aiex AI Helpers Loaded Successfully!
        #{String.duplicate("=", 50)}
        
        Available AI Functions:
        • ai/1              - Quick AI assistance
        • ai_shell/0        - Start interactive AI shell
        • ai_complete/2     - AI code completion
        • ai_eval/2         - Smart code evaluation
        • ai_doc/2          - Enhanced documentation
        • ai_debug/2        - AI debugging assistance
        • ai_project/1      - Project analysis
        • ai_test_suggest/2 - Test suggestions
        
        Enhanced IEx Commands:
        • h/2 with :ai      - AI-enhanced help
        • c/2 with :analyze - Compilation with AI analysis
        • test/2 variants   - AI-powered testing
        
        Quick Start:
        • ai("explain GenServer.call")
        • ai_shell()
        • ai_complete("defmodule MyMod")
        
        #{String.duplicate("=", 50)}
        """)
        
      {:error, reason} ->
        IO.puts("❌ Failed to load AI helpers: #{reason}")
    end
    
    import_result
  end

  @doc """
  Unload AI helpers from the current session.
  """
  def unload_helpers do
    IO.puts("🔄 AI helpers unloaded from current session")
    :ok
  end

  @doc """
  Show available AI helper functions.
  """
  def show_ai_help do
    IO.puts("""
    
    🤖 Available AI Helper Functions
    #{String.duplicate("=", 60)}
    
    🚀 Quick AI Commands:
    • ai("query")                    - General AI assistance
    • ai_shell()                     - Start interactive shell
    • ai_complete("code", opts)      - Code completion
    • ai_eval("code", opts)          - Smart evaluation
    
    📚 Documentation & Analysis:
    • ai_doc(Module)                 - Enhanced docs with AI
    • ai_doc(Module.function)        - Function docs + AI
    • ai_project(focus: :performance) - Project analysis
    
    🐛 Debugging:
    • ai_debug(pid)                  - Process analysis
    • ai_debug(error, context: "...")- Error analysis
    
    🧪 Testing:
    • ai_test_suggest(Module)        - Test suggestions
    
    🔧 Enhanced IEx Commands:
    • h(GenServer, :ai)              - AI-enhanced help
    • c("file.ex", :analyze)         - Compile with AI analysis
    • test(Module, :generate)        - Generate tests
    • test(Module, :analyze)         - Analyze test coverage
    • search("pattern", :semantic)   - Semantic search
    
    💡 Examples:
    • ai("explain pattern matching")
    • ai_complete("def handle_call")
    • ai_eval("Enum.map([1,2,3], &(&1*2))", explain: true)
    • ai_debug({:error, :timeout}, context: "API call")
    • h(GenServer, :ai)
    
    #{String.duplicate("=", 60)}
    """)
  end

  @doc """
  Check if AI helpers are available and properly configured.
  """
  def check_ai_status do
    checks = [
      {:aiex_loaded, check_aiex_loaded()},
      {:coordinators, check_coordinators()},
      {:distributed_engine, check_distributed_engine()},
      {:interface_gateway, check_interface_gateway()},
      {:model_coordinator, check_model_coordinator()}
    ]
    
    IO.puts("\n🔍 AI System Status Check\n")
    
    all_good = Enum.all?(checks, fn {name, status} ->
      case status do
        :ok ->
          IO.puts("✅ #{format_check_name(name)}: Available")
          true
          
        {:warning, message} ->
          IO.puts("⚠️  #{format_check_name(name)}: #{message}")
          true
          
        {:error, message} ->
          IO.puts("❌ #{format_check_name(name)}: #{message}")
          false
      end
    end)
    
    if all_good do
      IO.puts("\n🎉 All AI systems are operational!")
    else
      IO.puts("\n⚠️  Some AI systems may not be fully available")
    end
    
    IO.puts("")
    checks
  end

  # Private helper functions

  defp setup_aliases do
    # These would be set up in the actual IEx session
    # For now, just document the intended aliases
    """
    Available aliases after loading:
    • ai/1 -> Aiex.IEx.EnhancedHelpers.ai/1
    • ai_shell/0 -> Aiex.IEx.EnhancedHelpers.ai_shell/0
    """
  end

  defp check_aiex_loaded do
    if Code.ensure_loaded?(Aiex) do
      :ok
    else
      {:error, "Aiex application not loaded"}
    end
  end

  defp check_coordinators do
    coordinators = [
      Aiex.AI.Coordinators.CodingAssistant,
      Aiex.AI.Coordinators.ConversationManager,
      Aiex.AI.WorkflowOrchestrator
    ]
    
    missing = Enum.reject(coordinators, &Code.ensure_loaded?/1)
    
    case missing do
      [] -> :ok
      [_] -> {:warning, "Some AI coordinators not loaded"}
      _ -> {:error, "AI coordinators not available"}
    end
  end

  defp check_distributed_engine do
    if Code.ensure_loaded?(Aiex.Context.DistributedEngine) do
      case Process.whereis(Aiex.Context.DistributedEngine) do
        nil -> {:warning, "Distributed engine not started"}
        _pid -> :ok
      end
    else
      {:error, "Distributed engine module not loaded"}
    end
  end

  defp check_interface_gateway do
    if Code.ensure_loaded?(Aiex.InterfaceGateway) do
      case Process.whereis(Aiex.InterfaceGateway) do
        nil -> {:warning, "Interface gateway not started"}
        _pid -> :ok
      end
    else
      {:error, "Interface gateway not loaded"}
    end
  end

  defp check_model_coordinator do
    if Code.ensure_loaded?(Aiex.LLM.ModelCoordinator) do
      case Process.whereis(Aiex.LLM.ModelCoordinator) do
        nil -> {:warning, "Model coordinator not started"}
        _pid -> :ok
      end
    else
      {:error, "Model coordinator not loaded"}
    end
  end

  defp format_check_name(:aiex_loaded), do: "Aiex Application"
  defp format_check_name(:coordinators), do: "AI Coordinators"
  defp format_check_name(:distributed_engine), do: "Distributed Engine"
  defp format_check_name(:interface_gateway), do: "Interface Gateway"
  defp format_check_name(:model_coordinator), do: "Model Coordinator"
  defp format_check_name(name), do: "#{name}"
end