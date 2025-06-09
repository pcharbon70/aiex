defmodule Aiex.CLI.InteractiveShell do
  @moduledoc """
  Enhanced interactive AI shell with advanced features.
  
  Provides a sophisticated command-line interface for AI-powered development
  with persistent context, conversation history, and enhanced capabilities.
  """

  use GenServer
  
  alias Aiex.AI.Coordinators.{CodingAssistant, ConversationManager}
  alias Aiex.AI.WorkflowOrchestrator
  alias Aiex.CLI.Commands.AI.{ProgressReporter, OutputFormatter}
  alias Aiex.IEx.Helpers
  alias Aiex.Context.DistributedEngine

  require Logger

  @shell_prompt "🤖 aiex> "
  @continuation_prompt "     > "
  @help_commands [
    {:help, "Show this help message"},
    {:quit, "Exit the AI shell"},
    {:clear, "Clear conversation history"},
    {:context, "Show current context information"},
    {:workflow, "List available AI workflows"},
    {:explain, "Explain code or concepts"},
    {:generate, "Generate code based on requirements"},
    {:refactor, "Get refactoring suggestions"},
    {:analyze, "Analyze code quality and patterns"},
    {:chat, "Switch to conversational AI mode"},
    {:history, "Show command history"},
    {:save, "Save current session"},
    {:load, "Load a previous session"},
    {:status, "Show system and cluster status"}
  ]

  defstruct [
    :session_id,
    :conversation_id,
    :context,
    :history,
    :mode,
    :settings,
    :last_command,
    :project_dir,
    :multiline_buffer,
    :auto_save
  ]

  # Client API

  @doc """
  Start the interactive AI shell.
  """
  def start(opts \\ []) do
    project_dir = Keyword.get(opts, :project_dir, System.cwd!())
    settings = Keyword.get(opts, :settings, %{})
    
    IO.puts(welcome_message())
    
    case GenServer.start_link(__MODULE__, {project_dir, settings}, name: __MODULE__) do
      {:ok, pid} -> 
        run_shell_loop()
        GenServer.stop(pid)
        
      {:error, {:already_started, _}} ->
        IO.puts("⚠️  AI shell is already running. Use 'quit' to exit first.")
        {:error, :already_running}
        
      {:error, reason} ->
        IO.puts("❌ Failed to start AI shell: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Stop the interactive AI shell.
  """
  def stop do
    GenServer.cast(__MODULE__, :stop)
  end

  # Server Implementation

  @impl true
  def init({project_dir, settings}) do
    session_id = generate_session_id()
    
    # Initialize conversation with ConversationManager
    conversation_context = %{
      interface: :cli_shell,
      project_directory: project_dir,
      session_id: session_id
    }
    
    {:ok, conversation_id} = ConversationManager.start_conversation(
      session_id, 
      :development_conversation, 
      conversation_context
    )
    
    state = %__MODULE__{
      session_id: session_id,
      conversation_id: conversation_id,
      context: %{project_dir: project_dir, files: [], modules: []},
      history: [],
      mode: :command,
      settings: Map.merge(default_settings(), settings),
      project_dir: project_dir,
      multiline_buffer: [],
      auto_save: true
    }
    
    # Load project context
    {:ok, load_project_context(state)}
  end

  @impl true
  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:execute_command, command}, state) do
    new_state = process_command(command, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:timeout, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.auto_save do
      save_session(state)
    end
    
    ConversationManager.end_conversation(state.session_id)
    IO.puts("\n👋 AI shell session ended. Goodbye!")
    :ok
  end

  # Shell Loop

  defp run_shell_loop do
    case get_user_input() do
      :quit -> 
        :ok
        
      {:multiline, line} ->
        GenServer.cast(__MODULE__, {:add_to_multiline, line})
        run_shell_loop()
        
      {:command, command} ->
        GenServer.cast(__MODULE__, {:execute_command, command})
        run_shell_loop()
        
      :error ->
        IO.puts("❌ Input error occurred")
        run_shell_loop()
    end
  end

  defp get_user_input do
    case IO.gets(@shell_prompt) do
      :eof -> :quit
      {:error, _} -> :error
      input ->
        line = String.trim(input)
        
        cond do
          line in ["quit", "exit", ":q"] -> :quit
          line == "" -> run_shell_loop()
          String.ends_with?(line, "\\") -> 
            {:multiline, String.slice(line, 0..-2//-1)}
          true -> 
            {:command, line}
        end
    end
  end

  defp process_command(command, state) do
    # Add to history
    new_history = [command | state.history] |> Enum.take(100)
    
    # Parse and execute command
    result = case parse_command(command) do
      {:builtin, cmd, args} -> 
        execute_builtin_command(cmd, args, state)
        
      {:ai_command, type, content} -> 
        execute_ai_command(type, content, state)
        
      {:chat_message, message} when state.mode == :chat -> 
        execute_chat_message(message, state)
        
      {:elixir_code, code} -> 
        execute_elixir_code(code, state)
        
      {:help} -> 
        show_help()
        state
        
      {:error, reason} -> 
        IO.puts("❌ #{reason}")
        state
    end
    
    %{result | history: new_history, last_command: command}
  end

  defp parse_command(command) do
    case String.trim(command) do
      # Built-in commands
      "help" -> {:help}
      "clear" -> {:builtin, :clear, []}
      "quit" -> {:builtin, :quit, []}
      "context" -> {:builtin, :context, []}
      "workflow" -> {:builtin, :workflow, []}
      "history" -> {:builtin, :history, []}
      "status" -> {:builtin, :status, []}
      "save" <> rest -> {:builtin, :save, String.trim(rest)}
      "load" <> rest -> {:builtin, :load, String.trim(rest)}
      
      # AI commands with structured syntax
      "/explain " <> content -> {:ai_command, :explain, content}
      "/generate " <> content -> {:ai_command, :generate, content}
      "/refactor " <> content -> {:ai_command, :refactor, content}
      "/analyze " <> content -> {:ai_command, :analyze, content}
      "/workflow " <> content -> {:ai_command, :workflow, content}
      
      # Chat mode toggle
      "/chat" -> {:builtin, :chat_mode, []}
      
      # If in chat mode, treat as chat message
      content when byte_size(content) > 0 ->
        if looks_like_elixir_code?(content) do
          {:elixir_code, content}
        else
          {:chat_message, content}
        end
        
      _ -> 
        {:error, "Unknown command. Type 'help' for available commands."}
    end
  end

  defp execute_builtin_command(:clear, _, state) do
    IO.write("\e[2J\e[H")  # Clear screen
    IO.puts(welcome_message())
    %{state | history: []}
  end

  defp execute_builtin_command(:quit, _, state) do
    GenServer.cast(__MODULE__, :stop)
    state
  end

  defp execute_builtin_command(:context, _, state) do
    show_context_info(state)
    state
  end

  defp execute_builtin_command(:workflow, _, state) do
    show_available_workflows()
    state
  end

  defp execute_builtin_command(:history, _, state) do
    show_command_history(state)
    state
  end

  defp execute_builtin_command(:status, _, state) do
    show_system_status()
    state
  end

  defp execute_builtin_command(:save, filename, state) do
    save_result = save_session(state, filename)
    IO.puts(save_result)
    state
  end

  defp execute_builtin_command(:load, filename, state) do
    case load_session(state, filename) do
      {:ok, new_state} -> 
        IO.puts("✅ Session loaded successfully")
        new_state
      {:error, reason} -> 
        IO.puts("❌ Failed to load session: #{reason}")
        state
    end
  end

  defp execute_builtin_command(:chat_mode, _, state) do
    new_mode = if state.mode == :chat, do: :command, else: :chat
    IO.puts("🔄 Switched to #{new_mode} mode")
    %{state | mode: new_mode}
  end

  defp execute_ai_command(type, content, state) do
    ProgressReporter.start("Processing AI #{type} request...")
    
    result = case type do
      :explain -> handle_explain_command(content, state)
      :generate -> handle_generate_command(content, state)
      :refactor -> handle_refactor_command(content, state)
      :analyze -> handle_analyze_command(content, state)
      :workflow -> handle_workflow_command(content, state)
    end
    
    case result do
      {:ok, response} -> 
        ProgressReporter.complete("#{String.capitalize(to_string(type))} completed!")
        display_ai_response(type, response)
        
      {:error, reason} -> 
        ProgressReporter.error("#{String.capitalize(to_string(type))} failed: #{reason}")
    end
    
    state
  end

  defp execute_chat_message(message, state) do
    case ConversationManager.continue_conversation(state.session_id, message) do
      {:ok, response} ->
        IO.puts("\n🤖 AI: #{response.response}")
        
        if Map.has_key?(response, :actions_taken) and length(response.actions_taken) > 0 do
          IO.puts("🔧 Actions: #{format_actions(response.actions_taken)}")
        end
        
      {:error, reason} ->
        IO.puts("❌ Chat error: #{reason}")
    end
    
    state
  end

  defp execute_elixir_code(code, state) do
    case evaluate_elixir_code(code, state) do
      {:ok, result} -> 
        IO.puts("📊 Result: #{inspect(result)}")
        
      {:error, reason} -> 
        IO.puts("❌ Evaluation error: #{reason}")
    end
    
    state
  end

  # AI Command Handlers

  defp handle_explain_command(content, state) do
    context = build_enhanced_context(content, state)
    
    request = %{
      intent: :explain_codebase,
      description: "Explain: #{content}",
      code: content,
      context: context
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_generate_command(content, state) do
    context = build_enhanced_context(content, state)
    
    request = %{
      intent: :implement_feature,
      description: content,
      context: context,
      project_info: %{
        directory: state.project_dir,
        language: :elixir
      }
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_refactor_command(content, state) do
    # Try to read the file if content looks like a file path
    code_content = if File.exists?(content) do
      case File.read(content) do
        {:ok, file_content} -> file_content
        {:error, _} -> content
      end
    else
      content
    end
    
    context = build_enhanced_context(code_content, state)
    
    request = %{
      intent: :refactor_code,
      description: "Refactor code for better quality",
      code: code_content,
      context: context
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_analyze_command(content, state) do
    # Handle file path or direct code
    {code_content, file_path} = if File.exists?(content) do
      case File.read(content) do
        {:ok, file_content} -> {file_content, content}
        {:error, _} -> {content, nil}
      end
    else
      {content, nil}
    end
    
    context = build_enhanced_context(code_content, state)
    if file_path, do: Map.put(context, :file_path, file_path), else: context
    
    request = %{
      intent: :code_review,
      description: "Analyze code quality and patterns",
      code: code_content,
      context: context
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_workflow_command(workflow_spec, state) do
    # Parse workflow specification
    {template_name, context_data} = parse_workflow_spec(workflow_spec, state)
    
    case WorkflowOrchestrator.execute_template(template_name, context_data) do
      {:ok, workflow_id, workflow_state} ->
        monitor_workflow_in_shell(workflow_id)
        {:ok, workflow_state}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper Functions

  defp build_enhanced_context(content, state) do
    base_context = %{
      project_directory: state.project_dir,
      session_id: state.session_id,
      interface: :interactive_shell,
      user_context: state.context
    }
    
    # Add distributed context if available
    case DistributedEngine.get_related_context(content) do
      {:ok, distributed_context} ->
        Map.merge(base_context, %{distributed: distributed_context})
      {:error, _} ->
        base_context
    end
  end

  defp parse_workflow_spec(spec, state) do
    case String.split(spec, " ", parts: 2) do
      [template_name] -> 
        {template_name, %{project_directory: state.project_dir}}
        
      [template_name, context_spec] ->
        context = parse_context_spec(context_spec, state)
        {template_name, context}
    end
  end

  defp parse_context_spec(spec, state) do
    base_context = %{project_directory: state.project_dir}
    
    # Simple parsing - could be enhanced with more sophisticated syntax
    cond do
      String.starts_with?(spec, "file:") ->
        file_path = String.slice(spec, 5..-1//-1)
        Map.put(base_context, :file_path, file_path)
        
      String.starts_with?(spec, "module:") ->
        module_name = String.slice(spec, 7..-1//-1)
        Map.put(base_context, :module, module_name)
        
      true ->
        Map.put(base_context, :description, spec)
    end
  end

  defp monitor_workflow_in_shell(workflow_id) do
    spawn(fn ->
      monitor_loop(workflow_id, 0)
    end)
  end

  defp monitor_loop(workflow_id, checks) do
    case WorkflowOrchestrator.get_workflow_status(workflow_id) do
      {:ok, workflow_state} ->
        case workflow_state.status do
          :completed -> :ok
          :failed -> IO.puts("❌ Workflow failed")
          status when status in [:running, :pending] ->
            if rem(checks, 3) == 0 do
              ProgressReporter.update("Workflow #{status}... (#{checks * 2}s)")
            end
            Process.sleep(2000)
            monitor_loop(workflow_id, checks + 1)
          _ -> :ok
        end
      {:error, _} -> :ok
    end
  end

  defp evaluate_elixir_code(code, _state) do
    try do
      {result, _binding} = Code.eval_string(code, [])
      {:ok, result}
    rescue
      error -> {:error, Exception.message(error)}
    catch
      :error, reason -> {:error, inspect(reason)}
    end
  end

  defp looks_like_elixir_code?(content) do
    elixir_patterns = [
      ~r/^def\s+/,
      ~r/^defmodule\s+/,
      ~r/^defp\s+/,
      ~r/^\s*\|>/,
      ~r/^\s*case\s+/,
      ~r/^\s*with\s+/,
      ~r/^\s*%\{/,
      ~r/^\s*\[/,
      ~r/Enum\./,
      ~r/GenServer\./
    ]
    
    Enum.any?(elixir_patterns, &Regex.match?(&1, content))
  end

  defp load_project_context(state) do
    # Scan project directory for Elixir files
    elixir_files = find_elixir_files(state.project_dir)
    modules = extract_modules_from_files(elixir_files)
    
    context = %{
      project_dir: state.project_dir,
      files: elixir_files,
      modules: modules,
      last_scan: DateTime.utc_now()
    }
    
    %{state | context: context}
  end

  defp find_elixir_files(dir) do
    Path.wildcard(Path.join([dir, "**", "*.{ex,exs}"]))
    |> Enum.take(100)  # Limit for performance
  end

  defp extract_modules_from_files(files) do
    files
    |> Enum.map(&extract_module_from_file/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(50)
  end

  defp extract_module_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Regex.run(~r/defmodule\s+([A-Za-z_][A-Za-z0-9_.]*)/m, content) do
          [_, module_name] -> %{name: module_name, file: file_path}
          nil -> nil
        end
      {:error, _} -> nil
    end
  end

  # Display Functions

  defp welcome_message do
    """
    
    🤖 Aiex Interactive AI Shell v#{Application.spec(:aiex, :vsn)}
    #{String.duplicate("=", 60)}
    
    Enhanced AI-powered development assistant ready!
    
    Quick Start:
    • Type 'help' for command reference
    • Use /explain <code> to get AI explanations
    • Use /generate <description> to create code
    • Use /analyze <file> to analyze code quality
    • Type '/chat' to enter conversational mode
    
    Project: #{Path.basename(System.cwd!())}
    #{String.duplicate("=", 60)}
    """
  end

  defp show_help do
    IO.puts("\n📚 AI Shell Commands\n")
    
    IO.puts("🛠️  Built-in Commands:")
    Enum.each(@help_commands, fn {cmd, desc} ->
      IO.puts("   #{String.pad_trailing(to_string(cmd), 12)} #{desc}")
    end)
    
    IO.puts("\n🤖 AI Commands:")
    IO.puts("   /explain <code>       Get AI explanation of code")
    IO.puts("   /generate <desc>      Generate code from description")
    IO.puts("   /analyze <file>       Analyze code quality")
    IO.puts("   /refactor <code>      Get refactoring suggestions")
    IO.puts("   /workflow <template>  Execute AI workflow")
    
    IO.puts("\n💬 Chat Mode:")
    IO.puts("   /chat                 Toggle conversational AI mode")
    IO.puts("   In chat mode, type naturally to converse with AI")
    
    IO.puts("\n⚡ Elixir Code:")
    IO.puts("   Type Elixir code directly to evaluate it")
    IO.puts("   Example: Enum.map([1,2,3], &(&1 * 2))")
    
    IO.puts("\n💡 Tips:")
    IO.puts("   • Use \\ at end of line for multi-line input")
    IO.puts("   • Commands are context-aware of your project")
    IO.puts("   • History is automatically saved")
    IO.puts("")
  end

  defp show_context_info(state) do
    IO.puts("\n📊 Current Context Information\n")
    
    IO.puts("🏗️  Project:")
    IO.puts("   Directory: #{state.context.project_dir}")
    IO.puts("   Files Found: #{length(state.context.files)}")
    IO.puts("   Modules: #{length(state.context.modules)}")
    
    IO.puts("\n🧠 Session:")
    IO.puts("   Session ID: #{state.session_id}")
    IO.puts("   Mode: #{state.mode}")
    IO.puts("   Commands in History: #{length(state.history)}")
    
    if length(state.context.modules) > 0 do
      IO.puts("\n📦 Recent Modules:")
      state.context.modules
      |> Enum.take(5)
      |> Enum.each(fn mod ->
        IO.puts("   • #{mod.name} (#{Path.basename(mod.file)})")
      end)
    end
    
    cluster_status = Helpers.cluster_status()
    IO.puts("\n🌐 Cluster Status:")
    IO.puts("   Connected Nodes: #{cluster_status.total_nodes}")
    IO.puts("   Health: #{cluster_status.cluster_health}")
    IO.puts("")
  end

  defp show_available_workflows do
    IO.puts("\n🔧 Available AI Workflows\n")
    
    # This would query WorkflowOrchestrator for available templates
    workflows = [
      %{name: "code_review", description: "Comprehensive code review with suggestions"},
      %{name: "test_generation", description: "Generate comprehensive test suites"},
      %{name: "documentation", description: "Generate module and function documentation"},
      %{name: "refactoring", description: "Multi-step code refactoring workflow"},
      %{name: "performance_analysis", description: "Analyze and optimize performance"},
      %{name: "security_audit", description: "Security-focused code analysis"}
    ]
    
    Enum.each(workflows, fn workflow ->
      IO.puts("   📋 #{String.pad_trailing(workflow.name, 20)} #{workflow.description}")
    end)
    
    IO.puts("\n💡 Usage: /workflow <template_name> [context]")
    IO.puts("   Example: /workflow code_review file:lib/my_module.ex")
    IO.puts("")
  end

  defp show_command_history(state) do
    IO.puts("\n📜 Command History (Last 10)\n")
    
    state.history
    |> Enum.take(10)
    |> Enum.with_index(1)
    |> Enum.each(fn {cmd, index} ->
      IO.puts("   #{String.pad_leading(to_string(index), 2)}. #{cmd}")
    end)
    
    IO.puts("")
  end

  defp show_system_status do
    IO.puts("\n⚡ System Status\n")
    
    cluster_status = Helpers.cluster_status()
    
    IO.puts("🌐 Cluster:")
    IO.puts("   Local Node: #{cluster_status.local_node}")
    IO.puts("   Connected Nodes: #{length(cluster_status.connected_nodes)}")
    IO.puts("   Health: #{cluster_status.cluster_health}")
    
    IO.puts("\n🤖 AI Services:")
    IO.puts("   Active Providers: #{cluster_status.ai_providers.active}")
    IO.puts("   Healthy Providers: #{cluster_status.ai_providers.healthy}")
    
    IO.puts("\n🧠 Context Engines:")
    IO.puts("   Active: #{cluster_status.context_engines.active}")
    IO.puts("   Synced: #{cluster_status.context_engines.synced}")
    
    IO.puts("\n🔌 Interfaces:")
    IO.puts("   CLI: #{cluster_status.interfaces.cli}")
    IO.puts("   LiveView: #{cluster_status.interfaces.liveview}")
    IO.puts("   LSP: #{cluster_status.interfaces.lsp}")
    
    IO.puts("")
  end

  defp display_ai_response(type, response) do
    formatted = case type do
      :explain -> OutputFormatter.format_explanation(response)
      :analyze -> OutputFormatter.format_analysis(response)
      :refactor -> OutputFormatter.format_refactoring_suggestions(response)
      :generate -> format_generation_response(response)
      :workflow -> OutputFormatter.format_workflow_results(response)
    end
    
    IO.puts("\n#{formatted}\n")
  end

  defp format_generation_response(response) do
    case Map.get(response, :artifacts) do
      %{code: code} when is_binary(code) ->
        """
        🎯 Generated Code:
        #{String.duplicate("=", 50)}
        
        #{code}
        
        #{String.duplicate("=", 50)}
        💡 Copy the code above to use in your project.
        """
      _ ->
        "Generated response: #{inspect(response)}"
    end
  end

  defp format_actions(actions) do
    actions
    |> Enum.map(fn action -> action.action end)
    |> Enum.join(", ")
  end

  # Session Management

  defp save_session(state, filename \\ nil) do
    session_file = filename || "#{state.session_id}.aiex_session"
    session_path = Path.join(System.tmp_dir!(), session_file)
    
    session_data = %{
      session_id: state.session_id,
      conversation_id: state.conversation_id,
      context: state.context,
      history: state.history,
      mode: state.mode,
      settings: state.settings,
      saved_at: DateTime.utc_now()
    }
    
    case File.write(session_path, :erlang.term_to_binary(session_data)) do
      :ok -> 
        "✅ Session saved to #{session_path}"
      {:error, reason} -> 
        "❌ Failed to save session: #{reason}"
    end
  end

  defp load_session(state, filename) do
    session_path = if String.contains?(filename, "/") do
      filename
    else
      Path.join(System.tmp_dir!(), filename)
    end
    
    case File.read(session_path) do
      {:ok, binary_data} ->
        try do
          session_data = :erlang.binary_to_term(binary_data)
          
          # Restore state while keeping current GenServer specifics
          restored_state = %{state |
            context: session_data.context,
            history: session_data.history,
            mode: session_data.mode,
            settings: session_data.settings
          }
          
          {:ok, restored_state}
        rescue
          _ -> {:error, "Invalid session file format"}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_session_id do
    "shell_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp default_settings do
    %{
      auto_save: true,
      show_context: true,
      max_history: 100,
      ai_model: "gpt-4",
      output_format: "enhanced"
    }
  end
end