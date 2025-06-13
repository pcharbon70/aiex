defmodule Aiex.DevTools.DebuggingConsole do
  @moduledoc """
  Interactive debugging console for Aiex distributed systems.
  
  Provides a REPL-like interface for debugging cluster issues, inspecting state,
  and performing administrative operations across the distributed system.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.DevTools.ClusterInspector
  alias Aiex.Telemetry.{DistributedAggregator, DistributedTracer}
  alias Aiex.Performance.{DistributedAnalyzer, Dashboard}
  alias Aiex.Release.{DistributedRelease, HealthEndpoint}
  
  @command_timeout 30_000
  
  defstruct [
    :session_id,
    :command_history,
    :current_node,
    :context,
    interactive: false
  ]
  
  # Console commands
  @commands %{
    "help" => "Show available commands",
    "nodes" => "List connected nodes",
    "node <node>" => "Switch to a specific node context",
    "cluster" => "Show cluster overview",
    "inspect <node>" => "Inspect detailed node information",
    "processes [pattern]" => "List processes, optionally filtered by pattern",
    "hot [limit]" => "Show hot processes (default limit: 10)",
    "memory" => "Analyze memory usage across cluster",
    "ets" => "Show ETS table distribution",
    "mnesia" => "Show Mnesia status",
    "health" => "Generate cluster health report",
    "test" => "Test cluster coordination",
    "trace <operation>" => "Start distributed tracing for operation",
    "perf" => "Show performance dashboard",
    "metrics" => "Show telemetry metrics",
    "release" => "Show release information",
    "logs [node]" => "Show recent logs",
    "gc [node]" => "Force garbage collection",
    "observer" => "Start observer on target node",
    "exec <code>" => "Execute Elixir code",
    "reset" => "Reset console state",
    "quit" => "Exit console"
  }
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc "Start interactive console session"
  def start_interactive do
    GenServer.call(__MODULE__, :start_interactive)
  end
  
  @doc "Execute a console command"
  def execute_command(command) do
    GenServer.call(__MODULE__, {:execute_command, command}, @command_timeout)
  end
  
  @doc "Get command history"
  def get_history do
    GenServer.call(__MODULE__, :get_history)
  end
  
  @doc "Get available commands"
  def get_commands do
    @commands
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    session_id = generate_session_id()
    
    state = %__MODULE__{
      session_id: session_id,
      command_history: [],
      current_node: Node.self(),
      context: %{},
      interactive: Keyword.get(opts, :interactive, false)
    }
    
    Logger.info("Debugging console started - session #{session_id}")
    {:ok, state}
  end
  
  @impl true
  def handle_call(:start_interactive, _from, state) do
    if state.interactive do
      {:reply, {:error, :already_interactive}, state}
    else
      spawn(fn -> run_interactive_loop(state.session_id) end)
      {:reply, :ok, %{state | interactive: true}}
    end
  end
  
  def handle_call({:execute_command, command}, _from, state) do
    {result, updated_state} = process_command(command, state)
    
    # Add to history
    history_entry = %{
      timestamp: System.system_time(:millisecond),
      command: command,
      result: result,
      node: state.current_node
    }
    
    updated_history = [history_entry | state.command_history] |> Enum.take(100)  # Keep last 100
    final_state = %{updated_state | command_history: updated_history}
    
    {:reply, result, final_state}
  end
  
  def handle_call(:get_history, _from, state) do
    {:reply, Enum.reverse(state.command_history), state}
  end
  
  # Command processing
  
  defp process_command(command_str, state) do
    command_parts = String.split(String.trim(command_str))
    
    case command_parts do
      [] -> 
        {%{type: :empty}, state}
      
      ["help"] -> 
        {format_help(), state}
      
      ["nodes"] -> 
        {list_nodes(), state}
      
      ["node", node_str] -> 
        switch_node(node_str, state)
      
      ["cluster"] -> 
        {cluster_overview(), state}
      
      ["inspect"] -> 
        {inspect_node(state.current_node), state}
      
      ["inspect", node_str] -> 
        {inspect_node(parse_node(node_str)), state}
      
      ["processes"] -> 
        {list_processes(), state}
      
      ["processes", pattern] -> 
        {find_processes(pattern), state}
      
      ["hot"] -> 
        {hot_processes(10), state}
      
      ["hot", limit_str] -> 
        limit = String.to_integer(limit_str)
        {hot_processes(limit), state}
      
      ["memory"] -> 
        {memory_analysis(), state}
      
      ["ets"] -> 
        {ets_distribution(), state}
      
      ["mnesia"] -> 
        {mnesia_status(), state}
      
      ["health"] -> 
        {health_report(), state}
      
      ["test"] -> 
        {test_coordination(), state}
      
      ["trace", operation] -> 
        {start_tracing(operation), state}
      
      ["perf"] -> 
        {performance_dashboard(), state}
      
      ["metrics"] -> 
        {telemetry_metrics(), state}
      
      ["release"] -> 
        {release_info(), state}
      
      ["logs"] -> 
        {recent_logs(state.current_node), state}
      
      ["logs", node_str] -> 
        {recent_logs(parse_node(node_str)), state}
      
      ["gc"] -> 
        {force_gc(state.current_node), state}
      
      ["gc", node_str] -> 
        {force_gc(parse_node(node_str)), state}
      
      ["observer"] -> 
        {start_observer(state.current_node), state}
      
      ["exec" | code_parts] -> 
        code = Enum.join(code_parts, " ")
        {execute_code(code, state.current_node), state}
      
      ["reset"] -> 
        {%{type: :success, message: "Console state reset"}, %{state | context: %{}}}
      
      ["quit"] -> 
        {%{type: :quit, message: "Goodbye!"}, state}
      
      _ -> 
        {%{type: :error, message: "Unknown command: #{command_str}. Type 'help' for available commands."}, state}
    end
  end
  
  # Command implementations
  
  defp format_help do
    commands_list = Enum.map(@commands, fn {cmd, desc} ->
      "  #{String.pad_trailing(cmd, 20)} - #{desc}"
    end) |> Enum.join("\n")
    
    %{
      type: :help,
      content: """
      Aiex Debugging Console Commands:
      
      #{commands_list}
      
      Examples:
        cluster                    # Show cluster overview
        inspect node@host          # Inspect specific node
        processes GenServer        # Find GenServer processes
        hot 5                      # Show top 5 hot processes
        exec Process.list() |> length  # Execute Elixir code
      """
    }
  end
  
  defp list_nodes do
    nodes = [Node.self() | Node.list()]
    node_info = Enum.map(nodes, fn node ->
      status = if node == Node.self(), do: "local", else: "connected"
      ping_result = if node == Node.self(), do: :pong, else: Node.ping(node)
      
      %{
        node: node,
        status: status,
        ping: ping_result,
        processes: get_remote_process_count(node)
      }
    end)
    
    %{
      type: :nodes,
      total: length(nodes),
      nodes: node_info
    }
  end
  
  defp switch_node(node_str, state) do
    node = parse_node(node_str)
    
    if node == Node.self() or node in Node.list() do
      {%{type: :success, message: "Switched to node: #{node}"}, %{state | current_node: node}}
    else
      {%{type: :error, message: "Node not connected: #{node}"}, state}
    end
  end
  
  defp cluster_overview do
    case ClusterInspector.cluster_overview() do
      overview when is_map(overview) ->
        %{type: :cluster_overview, data: overview}
      error ->
        %{type: :error, message: "Failed to get cluster overview: #{inspect(error)}"}
    end
  end
  
  defp inspect_node(node) do
    case ClusterInspector.inspect_node(node) do
      inspection when is_map(inspection) ->
        %{type: :node_inspection, data: inspection}
      error ->
        %{type: :error, message: "Failed to inspect node: #{inspect(error)}"}
    end
  end
  
  defp list_processes do
    case ClusterInspector.process_distribution() do
      distribution when is_map(distribution) ->
        %{type: :process_distribution, data: distribution}
      error ->
        %{type: :error, message: "Failed to get process distribution: #{inspect(error)}"}
    end
  end
  
  defp find_processes(pattern) do
    case ClusterInspector.find_processes(pattern) do
      result when is_map(result) ->
        %{type: :process_search, data: result}
      error ->
        %{type: :error, message: "Failed to find processes: #{inspect(error)}"}
    end
  end
  
  defp hot_processes(limit) do
    case ClusterInspector.hot_processes(limit) do
      result when is_map(result) ->
        %{type: :hot_processes, data: result}
      error ->
        %{type: :error, message: "Failed to get hot processes: #{inspect(error)}"}
    end
  end
  
  defp memory_analysis do
    case ClusterInspector.memory_analysis() do
      analysis when is_map(analysis) ->
        %{type: :memory_analysis, data: analysis}
      error ->
        %{type: :error, message: "Failed to analyze memory: #{inspect(error)}"}
    end
  end
  
  defp ets_distribution do
    case ClusterInspector.ets_distribution() do
      distribution when is_map(distribution) ->
        %{type: :ets_distribution, data: distribution}
      error ->
        %{type: :error, message: "Failed to get ETS distribution: #{inspect(error)}"}
    end
  end
  
  defp mnesia_status do
    case ClusterInspector.mnesia_status() do
      status when is_map(status) ->
        %{type: :mnesia_status, data: status}
      error ->
        %{type: :error, message: "Failed to get Mnesia status: #{inspect(error)}"}
    end
  end
  
  defp health_report do
    case ClusterInspector.health_report() do
      report when is_map(report) ->
        %{type: :health_report, data: report}
      error ->
        %{type: :error, message: "Failed to generate health report: #{inspect(error)}"}
    end
  end
  
  defp test_coordination do
    case ClusterInspector.test_coordination() do
      results when is_map(results) ->
        %{type: :coordination_test, data: results}
      error ->
        %{type: :error, message: "Failed to test coordination: #{inspect(error)}"}
    end
  end
  
  defp start_tracing(operation) do
    try do
      {trace_id, span_id} = DistributedTracer.start_trace("console_trace_#{operation}")
      DistributedTracer.set_attributes(%{"operation" => operation, "initiated_by" => "console"})
      
      %{
        type: :success,
        message: "Started tracing for #{operation}",
        trace_id: trace_id,
        span_id: span_id
      }
    rescue
      error ->
        %{type: :error, message: "Failed to start tracing: #{Exception.message(error)}"}
    end
  end
  
  defp performance_dashboard do
    try do
      case DistributedAnalyzer.analyze_cluster() do
        {:ok, analysis} ->
          %{type: :performance_dashboard, data: analysis}
        error ->
          %{type: :error, message: "Failed to get performance data: #{inspect(error)}"}
      end
    rescue
      error ->
        %{type: :error, message: "Performance analysis failed: #{Exception.message(error)}"}
    end
  end
  
  defp telemetry_metrics do
    try do
      case DistributedAggregator.get_cluster_metrics() do
        {:ok, metrics} ->
          %{type: :telemetry_metrics, data: metrics}
        error ->
          %{type: :error, message: "Failed to get metrics: #{inspect(error)}"}
      end
    rescue
      error ->
        %{type: :error, message: "Telemetry access failed: #{Exception.message(error)}"}
    end
  end
  
  defp release_info do
    try do
      status = DistributedRelease.get_cluster_status()
      health = DistributedRelease.health_check()
      
      %{
        type: :release_info,
        data: %{
          cluster_status: status,
          health_check: health,
          version: DistributedRelease.get_version()
        }
      }
    rescue
      error ->
        %{type: :error, message: "Failed to get release info: #{Exception.message(error)}"}
    end
  end
  
  defp recent_logs(node) do
    # This would integrate with logging system to show recent logs
    # For now, return a placeholder
    %{
      type: :logs,
      node: node,
      message: "Log viewing not yet implemented. Check system logs or use external log aggregation."
    }
  end
  
  defp force_gc(node) do
    try do
      case call_remote_safely(node, :erlang, :garbage_collect, []) do
        {:ok, _} ->
          %{type: :success, message: "Forced garbage collection on #{node}"}
        {:error, reason} ->
          %{type: :error, message: "Failed to force GC: #{inspect(reason)}"}
      end
    rescue
      error ->
        %{type: :error, message: "GC command failed: #{Exception.message(error)}"}
    end
  end
  
  defp start_observer(node) do
    try do
      case call_remote_safely(node, :observer, :start, []) do
        {:ok, _} ->
          %{type: :success, message: "Started observer on #{node}"}
        {:error, reason} ->
          %{type: :error, message: "Failed to start observer: #{inspect(reason)}"}
      end
    rescue
      error ->
        %{type: :error, message: "Observer start failed: #{Exception.message(error)}"}
    end
  end
  
  defp execute_code(code, node) do
    try do
      {result, _binding} = case call_remote_safely(node, Code, :eval_string, [code]) do
        {:ok, eval_result} -> eval_result
        {:error, reason} -> {reason, []}
      end
      
      %{
        type: :code_result,
        code: code,
        result: inspect(result, limit: :infinity, pretty: true),
        node: node
      }
    rescue
      error ->
        %{
          type: :error,
          message: "Code execution failed: #{Exception.message(error)}",
          code: code
        }
    end
  end
  
  # Helper functions
  
  defp run_interactive_loop(session_id) do
    IO.puts("\n=== Aiex Debugging Console (Session: #{session_id}) ===")
    IO.puts("Type 'help' for available commands, 'quit' to exit\n")
    
    interactive_loop()
  end
  
  defp interactive_loop do
    case IO.gets("aiex> ") do
      :eof ->
        IO.puts("\nGoodbye!")
      
      command_input when is_binary(command_input) ->
        command = String.trim(command_input)
        
        unless command == "quit" do
          result = execute_command(command)
          print_result(result)
          interactive_loop()
        else
          IO.puts("Goodbye!")
        end
    end
  end
  
  defp print_result(%{type: :help, content: content}) do
    IO.puts(content)
  end
  
  defp print_result(%{type: :nodes, nodes: nodes}) do
    IO.puts("\nConnected Nodes:")
    Enum.each(nodes, fn node_info ->
      status_color = if node_info.ping == :pong, do: IO.ANSI.green(), else: IO.ANSI.red()
      IO.puts("  #{status_color}#{node_info.node}#{IO.ANSI.reset()} (#{node_info.status}) - #{node_info.processes} processes")
    end)
  end
  
  defp print_result(%{type: :cluster_overview, data: data}) do
    IO.puts("\n=== Cluster Overview ===")
    IO.puts("Health: #{format_health(data.cluster_health)}")
    IO.puts("Nodes: #{data.total_nodes}")
    IO.puts("Total Memory: #{data.system_overview.total_memory_mb}MB")
    IO.puts("Total Processes: #{data.system_overview.total_processes}")
    IO.puts("Coordination: #{data.coordination_status}")
  end
  
  defp print_result(%{type: :error, message: message}) do
    IO.puts("#{IO.ANSI.red()}Error: #{message}#{IO.ANSI.reset()}")
  end
  
  defp print_result(%{type: :success, message: message}) do
    IO.puts("#{IO.ANSI.green()}#{message}#{IO.ANSI.reset()}")
  end
  
  defp print_result(%{type: :code_result, result: result, node: node}) do
    IO.puts("#{IO.ANSI.cyan()}[#{node}]#{IO.ANSI.reset()} => #{result}")
  end
  
  defp print_result(result) do
    # Generic fallback for complex results
    IO.puts(inspect(result, pretty: true, limit: :infinity))
  end
  
  defp format_health(:healthy), do: "#{IO.ANSI.green()}HEALTHY#{IO.ANSI.reset()}"
  defp format_health(:degraded), do: "#{IO.ANSI.yellow()}DEGRADED#{IO.ANSI.reset()}"
  defp format_health(:critical), do: "#{IO.ANSI.red()}CRITICAL#{IO.ANSI.reset()}"
  defp format_health(status), do: to_string(status)
  
  defp parse_node(node_str) do
    case String.contains?(node_str, "@") do
      true -> String.to_atom(node_str)
      false -> String.to_atom("#{node_str}@#{get_hostname()}")
    end
  end
  
  defp get_hostname do
    case Node.self() |> to_string() |> String.split("@") do
      [_name, hostname] -> hostname
      _ -> "localhost"
    end
  end
  
  defp call_remote_safely(node, module, function, args) do
    if node == Node.self() do
      try do
        {:ok, apply(module, function, args)}
      rescue
        error -> {:error, error}
      end
    else
      case :rpc.call(node, module, function, args, 10_000) do
        {:badrpc, reason} -> {:error, reason}
        result -> {:ok, result}
      end
    end
  end
  
  defp get_remote_process_count(node) do
    case call_remote_safely(node, :erlang, :system_info, [:process_count]) do
      {:ok, count} -> count
      _ -> "unknown"
    end
  end
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end