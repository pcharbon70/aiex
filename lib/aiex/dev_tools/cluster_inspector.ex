defmodule Aiex.DevTools.ClusterInspector do
  @moduledoc """
  Interactive cluster inspection and debugging tools for Aiex distributed systems.
  
  Provides comprehensive utilities for examining cluster state, node health,
  process distribution, and system diagnostics across the distributed cluster.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Telemetry.DistributedAggregator
  alias Aiex.Release.DistributedRelease
  alias Aiex.Performance.DistributedAnalyzer
  
  @inspection_timeout 30_000
  @remote_call_timeout 10_000
  
  defstruct [
    :inspection_cache,
    :cache_ttl,
    last_inspection: nil,
    connected_nodes: []
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc "Get comprehensive cluster overview"
  def cluster_overview do
    GenServer.call(__MODULE__, :cluster_overview, @inspection_timeout)
  end
  
  @doc "Inspect a specific node in detail"
  def inspect_node(node \\ Node.self()) do
    GenServer.call(__MODULE__, {:inspect_node, node}, @inspection_timeout)
  end
  
  @doc "Get process distribution across the cluster"
  def process_distribution do
    GenServer.call(__MODULE__, :process_distribution, @inspection_timeout)
  end
  
  @doc "Analyze memory usage across nodes"
  def memory_analysis do
    GenServer.call(__MODULE__, :memory_analysis, @inspection_timeout)
  end
  
  @doc "Check ETS table distribution"
  def ets_distribution do
    GenServer.call(__MODULE__, :ets_distribution, @inspection_timeout)
  end
  
  @doc "Examine Mnesia table status"
  def mnesia_status do
    GenServer.call(__MODULE__, :mnesia_status, @inspection_timeout)
  end
  
  @doc "Get application supervision tree for a node"
  def supervision_tree(node \\ Node.self()) do
    GenServer.call(__MODULE__, {:supervision_tree, node}, @inspection_timeout)
  end
  
  @doc "Find processes by name pattern across cluster"
  def find_processes(pattern) do
    GenServer.call(__MODULE__, {:find_processes, pattern}, @inspection_timeout)
  end
  
  @doc "Get hot processes across the cluster"
  def hot_processes(limit \\ 10) do
    GenServer.call(__MODULE__, {:hot_processes, limit}, @inspection_timeout)
  end
  
  @doc "Examine message queues across cluster"
  def message_queues(threshold \\ 100) do
    GenServer.call(__MODULE__, {:message_queues, threshold}, @inspection_timeout)
  end
  
  @doc "Get network connectivity matrix"
  def network_matrix do
    GenServer.call(__MODULE__, :network_matrix, @inspection_timeout)
  end
  
  @doc "Test cluster coordination features"
  def test_coordination do
    GenServer.call(__MODULE__, :test_coordination, @inspection_timeout)
  end
  
  @doc "Generate cluster health report"
  def health_report do
    GenServer.call(__MODULE__, :health_report, @inspection_timeout)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    cache_ttl = Keyword.get(opts, :cache_ttl, 30_000)  # 30 seconds
    inspection_cache = :ets.new(:cluster_inspection_cache, [:set, :private])
    
    # Schedule periodic node discovery
    Process.send_after(self(), :update_node_list, 1000)
    
    state = %__MODULE__{
      inspection_cache: inspection_cache,
      cache_ttl: cache_ttl,
      connected_nodes: Node.list()
    }
    
    Logger.info("Cluster inspector started")
    {:ok, state}
  end
  
  @impl true
  def handle_call(:cluster_overview, _from, state) do
    overview = build_cluster_overview(state)
    {:reply, overview, state}
  end
  
  def handle_call({:inspect_node, node}, _from, state) do
    inspection = inspect_node_detailed(node)
    {:reply, inspection, state}
  end
  
  def handle_call(:process_distribution, _from, state) do
    distribution = analyze_process_distribution(state)
    {:reply, distribution, state}
  end
  
  def handle_call(:memory_analysis, _from, state) do
    analysis = analyze_memory_usage(state)
    {:reply, analysis, state}
  end
  
  def handle_call(:ets_distribution, _from, state) do
    distribution = analyze_ets_distribution(state)
    {:reply, distribution, state}
  end
  
  def handle_call(:mnesia_status, _from, state) do
    status = analyze_mnesia_status(state)
    {:reply, status, state}
  end
  
  def handle_call({:supervision_tree, node}, _from, state) do
    tree = get_supervision_tree(node)
    {:reply, tree, state}
  end
  
  def handle_call({:find_processes, pattern}, _from, state) do
    processes = find_processes_by_pattern(pattern, state)
    {:reply, processes, state}
  end
  
  def handle_call({:hot_processes, limit}, _from, state) do
    hot_procs = get_hot_processes(limit, state)
    {:reply, hot_procs, state}
  end
  
  def handle_call({:message_queues, threshold}, _from, state) do
    queues = analyze_message_queues(threshold, state)
    {:reply, queues, state}
  end
  
  def handle_call(:network_matrix, _from, state) do
    matrix = build_network_matrix(state)
    {:reply, matrix, state}
  end
  
  def handle_call(:test_coordination, _from, state) do
    results = test_cluster_coordination(state)
    {:reply, results, state}
  end
  
  def handle_call(:health_report, _from, state) do
    report = generate_health_report(state)
    {:reply, report, state}
  end
  
  @impl true
  def handle_info(:update_node_list, state) do
    connected_nodes = Node.list()
    
    # Schedule next update
    Process.send_after(self(), :update_node_list, 5000)
    
    {:noreply, %{state | connected_nodes: connected_nodes}}
  end
  
  @impl true
  def terminate(_reason, state) do
    :ets.delete(state.inspection_cache)
    :ok
  end
  
  # Private functions
  
  defp build_cluster_overview(state) do
    all_nodes = [Node.self() | state.connected_nodes]
    
    %{
      timestamp: System.system_time(:millisecond),
      local_node: Node.self(),
      connected_nodes: state.connected_nodes,
      total_nodes: length(all_nodes),
      cluster_health: assess_cluster_health(all_nodes),
      node_summary: build_node_summaries(all_nodes),
      system_overview: %{
        total_processes: sum_across_nodes(all_nodes, &get_process_count/1),
        total_memory_mb: sum_across_nodes(all_nodes, &get_memory_mb/1),
        total_ets_tables: sum_across_nodes(all_nodes, &get_ets_count/1),
        aiex_version: get_aiex_version()
      },
      coordination_status: check_coordination_status(all_nodes)
    }
  end
  
  defp inspect_node_detailed(node) do
    node_info = case node == Node.self() do
      true -> get_local_node_info()
      false -> get_remote_node_info(node)
    end
    
    %{
      node: node,
      timestamp: System.system_time(:millisecond),
      status: if(node in Node.list() or node == Node.self(), do: :connected, else: :disconnected),
      system_info: node_info,
      processes: get_node_processes(node),
      memory_breakdown: get_node_memory(node),
      ets_tables: get_node_ets_tables(node),
      applications: get_node_applications(node),
      supervision_tree: get_supervision_tree(node),
      aiex_components: get_aiex_components(node)
    }
  end
  
  defp analyze_process_distribution(state) do
    all_nodes = [Node.self() | state.connected_nodes]
    
    node_data = Enum.map(all_nodes, fn node ->
      process_count = get_process_count(node)
      aiex_processes = count_aiex_processes(node)
      
      %{
        node: node,
        total_processes: process_count,
        aiex_processes: aiex_processes,
        system_processes: process_count - aiex_processes,
        load_percentage: calculate_load_percentage(process_count)
      }
    end)
    
    %{
      timestamp: System.system_time(:millisecond),
      nodes: node_data,
      total_processes: Enum.sum(Enum.map(node_data, & &1.total_processes)),
      total_aiex_processes: Enum.sum(Enum.map(node_data, & &1.aiex_processes)),
      distribution_balance: calculate_distribution_balance(node_data)
    }
  end
  
  defp analyze_memory_usage(state) do
    all_nodes = [Node.self() | state.connected_nodes]
    
    node_data = Enum.map(all_nodes, fn node ->
      memory = get_node_memory(node)
      
      %{
        node: node,
        total_mb: div(memory.total || 0, 1024 * 1024),
        processes_mb: div(memory.processes || 0, 1024 * 1024),
        system_mb: div(memory.system || 0, 1024 * 1024),
        atom_mb: div(memory.atom || 0, 1024 * 1024),
        binary_mb: div(memory.binary || 0, 1024 * 1024),
        ets_mb: div(memory.ets || 0, 1024 * 1024)
      }
    end)
    
    %{
      timestamp: System.system_time(:millisecond),
      nodes: node_data,
      cluster_total_mb: Enum.sum(Enum.map(node_data, & &1.total_mb)),
      memory_distribution: calculate_memory_distribution(node_data)
    }
  end
  
  defp analyze_ets_distribution(state) do
    all_nodes = [Node.self() | state.connected_nodes]
    
    node_data = Enum.map(all_nodes, fn node ->
      ets_info = get_node_ets_info(node)
      
      %{
        node: node,
        table_count: length(ets_info),
        total_objects: Enum.sum(Enum.map(ets_info, &(&1.size || 0))),
        total_memory_words: Enum.sum(Enum.map(ets_info, &(&1.memory || 0))),
        aiex_tables: Enum.filter(ets_info, &is_aiex_table?/1)
      }
    end)
    
    %{
      timestamp: System.system_time(:millisecond),
      nodes: node_data,
      cluster_totals: %{
        tables: Enum.sum(Enum.map(node_data, & &1.table_count)),
        objects: Enum.sum(Enum.map(node_data, & &1.total_objects)),
        memory_words: Enum.sum(Enum.map(node_data, & &1.total_memory_words))
      }
    }
  end
  
  defp analyze_mnesia_status(_state) do
    try do
      running_nodes = :mnesia.system_info(:running_db_nodes)
      stopped_nodes = :mnesia.system_info(:db_nodes) -- running_nodes
      
      tables_info = :mnesia.system_info(:tables)
      |> Enum.map(fn table ->
        %{
          name: table,
          size: :mnesia.table_info(table, :size),
          memory: :mnesia.table_info(table, :memory),
          type: :mnesia.table_info(table, :type),
          storage_type: :mnesia.table_info(table, :storage_type),
          disc_copies: :mnesia.table_info(table, :disc_copies),
          ram_copies: :mnesia.table_info(table, :ram_copies)
        }
      end)
      
      %{
        status: :running,
        running_nodes: running_nodes,
        stopped_nodes: stopped_nodes,
        master_node: :mnesia.system_info(:master_node),
        tables: tables_info,
        directory: :mnesia.system_info(:directory),
        schema_location: :mnesia.system_info(:schema_location)
      }
    rescue
      _ ->
        %{status: :not_running, error: "Mnesia is not running or not available"}
    end
  end
  
  defp get_supervision_tree(node) do
    case call_node_safely(node, :application, :get_application, [Process.whereis(Aiex.Supervisor)]) do
      {:ok, :aiex} ->
        build_supervision_tree(node, Aiex.Supervisor)
      _ ->
        %{error: "Could not access Aiex supervision tree on #{node}"}
    end
  end
  
  defp find_processes_by_pattern(pattern, state) do
    all_nodes = [Node.self() | state.connected_nodes]
    
    results = Enum.flat_map(all_nodes, fn node ->
      processes = get_node_process_list(node)
      
      matched = Enum.filter(processes, fn {pid, info} ->
        name = info[:registered_name] || info[:initial_call] || "unknown"
        String.contains?(to_string(name), pattern)
      end)
      
      Enum.map(matched, fn {pid, info} ->
        %{
          node: node,
          pid: pid,
          name: info[:registered_name],
          initial_call: info[:initial_call],
          current_function: info[:current_function],
          message_queue_len: info[:message_queue_len] || 0,
          memory: info[:memory] || 0,
          reductions: info[:reductions] || 0
        }
      end)
    end)
    
    %{
      pattern: pattern,
      matches: length(results),
      processes: results
    }
  end
  
  defp get_hot_processes(limit, state) do
    all_nodes = [Node.self() | state.connected_nodes]
    
    all_processes = Enum.flat_map(all_nodes, fn node ->
      case call_node_safely(node, :recon, :proc_count, [:reductions, limit]) do
        {:ok, processes} ->
          Enum.map(processes, fn {pid, reductions, [memory | _]} ->
            %{
              node: node,
              pid: pid,
              reductions: reductions,
              memory: memory,
              score: reductions + memory  # Simple scoring
            }
          end)
        _ ->
          []
      end
    end)
    
    hot_processes = all_processes
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(limit)
    
    %{
      limit: limit,
      total_found: length(all_processes),
      hot_processes: hot_processes
    }
  end
  
  defp analyze_message_queues(threshold, state) do
    all_nodes = [Node.self() | state.connected_nodes]
    
    queued_processes = Enum.flat_map(all_nodes, fn node ->
      processes = get_node_process_list(node)
      
      Enum.filter(processes, fn {_pid, info} ->
        (info[:message_queue_len] || 0) >= threshold
      end)
      |> Enum.map(fn {pid, info} ->
        %{
          node: node,
          pid: pid,
          queue_length: info[:message_queue_len],
          name: info[:registered_name],
          memory: info[:memory] || 0
        }
      end)
    end)
    |> Enum.sort_by(& &1.queue_length, :desc)
    
    %{
      threshold: threshold,
      processes_with_queues: length(queued_processes),
      processes: queued_processes
    }
  end
  
  defp build_network_matrix(state) do
    all_nodes = [Node.self() | state.connected_nodes]
    
    connectivity = Enum.map(all_nodes, fn source_node ->
      targets = Enum.map(all_nodes, fn target_node ->
        if source_node == target_node do
          :self
        else
          case call_node_safely(source_node, Node, :ping, [target_node]) do
            {:ok, :pong} -> :connected
            _ -> :disconnected
          end
        end
      end)
      
      %{
        source: source_node,
        targets: Enum.zip(all_nodes, targets) |> Enum.into(%{})
      }
    end)
    
    %{
      nodes: all_nodes,
      connectivity_matrix: connectivity,
      fully_connected: all_connected?(connectivity)
    }
  end
  
  defp test_cluster_coordination(state) do
    all_nodes = [Node.self() | state.connected_nodes]
    
    tests = [
      {"pg groups", test_pg_groups(all_nodes)},
      {"distributed calls", test_distributed_calls(all_nodes)},
      {"event bus", test_event_bus(all_nodes)},
      {"telemetry aggregation", test_telemetry_aggregation(all_nodes)}
    ]
    
    %{
      timestamp: System.system_time(:millisecond),
      nodes_tested: all_nodes,
      tests: tests,
      overall_status: if(Enum.all?(tests, fn {_, result} -> result.status == :ok end), do: :ok, else: :error)
    }
  end
  
  defp generate_health_report(state) do
    overview = build_cluster_overview(state)
    memory = analyze_memory_usage(state)
    processes = analyze_process_distribution(state)
    
    issues = []
    
    # Check for issues
    issues = if overview.total_nodes < 2 and Application.get_env(:aiex, :cluster_enabled, false) do
      ["Cluster enabled but only #{overview.total_nodes} node(s) connected" | issues]
    else
      issues
    end
    
    issues = if overview.system_overview.total_memory_mb > 2048 do
      ["High cluster memory usage: #{overview.system_overview.total_memory_mb}MB" | issues]
    else
      issues
    end
    
    issues = if processes.distribution_balance < 0.7 do
      ["Unbalanced process distribution across nodes" | issues]
    else
      issues
    end
    
    %{
      timestamp: System.system_time(:millisecond),
      cluster_health: overview.cluster_health,
      nodes: overview.total_nodes,
      issues: issues,
      recommendations: generate_recommendations(overview, memory, processes),
      summary: %{
        memory_mb: overview.system_overview.total_memory_mb,
        processes: overview.system_overview.total_processes,
        coordination: overview.coordination_status
      }
    }
  end
  
  # Helper functions
  
  defp call_node_safely(node, module, function, args) do
    if node == Node.self() do
      try do
        {:ok, apply(module, function, args)}
      rescue
        error -> {:error, error}
      end
    else
      try do
        case :rpc.call(node, module, function, args, @remote_call_timeout) do
          {:badrpc, reason} -> {:error, reason}
          result -> {:ok, result}
        end
      rescue
        error -> {:error, error}
      end
    end
  end
  
  defp get_process_count(node) do
    case call_node_safely(node, :erlang, :system_info, [:process_count]) do
      {:ok, count} -> count
      _ -> 0
    end
  end
  
  defp get_memory_mb(node) do
    case call_node_safely(node, :erlang, :memory, [:total]) do
      {:ok, bytes} -> div(bytes, 1024 * 1024)
      _ -> 0
    end
  end
  
  defp get_ets_count(node) do
    case call_node_safely(node, :ets, :all, []) do
      {:ok, tables} -> length(tables)
      _ -> 0
    end
  end
  
  defp get_local_node_info do
    %{
      system_info: %{
        otp_release: :erlang.system_info(:otp_release),
        erts_version: :erlang.system_info(:version),
        system_architecture: :erlang.system_info(:system_architecture),
        schedulers: :erlang.system_info(:schedulers),
        process_limit: :erlang.system_info(:process_limit),
        port_limit: :erlang.system_info(:port_limit)
      },
      uptime: :erlang.statistics(:wall_clock) |> elem(0),
      reductions: :erlang.statistics(:reductions) |> elem(0)
    }
  end
  
  defp get_remote_node_info(node) do
    case call_node_safely(node, __MODULE__, :get_local_node_info, []) do
      {:ok, info} -> info
      _ -> %{error: "Could not retrieve node info"}
    end
  end
  
  defp get_node_memory(node) do
    case call_node_safely(node, :erlang, :memory, []) do
      {:ok, memory} -> Enum.into(memory, %{})
      _ -> %{}
    end
  end
  
  defp get_node_processes(node) do
    case call_node_safely(node, Process, :list, []) do
      {:ok, pids} -> length(pids)
      _ -> 0
    end
  end
  
  defp get_node_ets_tables(node) do
    case call_node_safely(node, :ets, :all, []) do
      {:ok, tables} -> length(tables)
      _ -> 0
    end
  end
  
  defp get_node_applications(node) do
    case call_node_safely(node, Application, :loaded_applications, []) do
      {:ok, apps} -> Enum.map(apps, &elem(&1, 0))
      _ -> []
    end
  end
  
  defp get_aiex_components(node) do
    aiex_processes = [
      Aiex.Supervisor,
      Aiex.Context.Manager,
      Aiex.LLM.ModelCoordinator,
      Aiex.Events.EventBus,
      Aiex.Performance.Supervisor,
      Aiex.Telemetry.Supervisor,
      Aiex.Release.Supervisor
    ]
    
    Enum.map(aiex_processes, fn process ->
      case call_node_safely(node, Process, :whereis, [process]) do
        {:ok, pid} when is_pid(pid) -> {process, :running, pid}
        _ -> {process, :not_running, nil}
      end
    end)
  end
  
  defp build_node_summaries(nodes) do
    Enum.map(nodes, fn node ->
      %{
        node: node,
        processes: get_process_count(node),
        memory_mb: get_memory_mb(node),
        ets_tables: get_ets_count(node),
        status: if(node == Node.self() or node in Node.list(), do: :connected, else: :disconnected)
      }
    end)
  end
  
  defp sum_across_nodes(nodes, fun) do
    Enum.map(nodes, fun) |> Enum.sum()
  end
  
  defp assess_cluster_health(nodes) do
    connected_count = length(Enum.filter(nodes, &(&1 == Node.self() or &1 in Node.list())))
    total_count = length(nodes)
    
    cond do
      connected_count == total_count -> :healthy
      connected_count >= div(total_count, 2) -> :degraded
      true -> :critical
    end
  end
  
  defp check_coordination_status(nodes) do
    # Simple coordination check - can we reach all nodes?
    reachable = Enum.count(nodes, fn node ->
      node == Node.self() or Node.ping(node) == :pong
    end)
    
    if reachable == length(nodes) do
      :fully_coordinated
    else
      :partially_coordinated
    end
  end
  
  defp count_aiex_processes(node) do
    case call_node_safely(node, Process, :list, []) do
      {:ok, pids} ->
        Enum.count(pids, fn pid ->
          case call_node_safely(node, Process, :info, [pid, :registered_name]) do
            {:ok, {:registered_name, name}} -> is_aiex_process?(name)
            _ -> false
          end
        end)
      _ -> 0
    end
  end
  
  defp is_aiex_process?(name) when is_atom(name) do
    name_str = to_string(name)
    String.starts_with?(name_str, "Elixir.Aiex") or String.contains?(name_str, "aiex")
  end
  
  defp is_aiex_process?(_), do: false
  
  defp calculate_load_percentage(process_count) do
    # Simple heuristic - consider 1000+ processes as high load
    min(100, div(process_count * 100, 1000))
  end
  
  defp calculate_distribution_balance(node_data) do
    if length(node_data) < 2 do
      1.0
    else
      process_counts = Enum.map(node_data, & &1.total_processes)
      avg = Enum.sum(process_counts) / length(process_counts)
      variance = (Enum.map(process_counts, &(:math.pow(&1 - avg, 2))) |> Enum.sum()) / length(process_counts)
      coefficient_of_variation = :math.sqrt(variance) / avg
      max(0.0, 1.0 - coefficient_of_variation)
    end
  end
  
  defp calculate_memory_distribution(node_data) do
    total_memory = Enum.sum(Enum.map(node_data, & &1.total_mb))
    
    Enum.map(node_data, fn node ->
      %{
        node: node.node,
        percentage: if(total_memory > 0, do: node.total_mb * 100 / total_memory, else: 0)
      }
    end)
  end
  
  defp get_node_ets_info(node) do
    case call_node_safely(node, :ets, :all, []) do
      {:ok, tables} ->
        Enum.map(tables, fn table ->
          try do
            %{
              name: table,
              size: :ets.info(table, :size),
              memory: :ets.info(table, :memory),
              type: :ets.info(table, :type),
              owner: :ets.info(table, :owner)
            }
          rescue
            _ -> %{name: table, error: "Could not get table info"}
          end
        end)
      _ -> []
    end
  end
  
  defp is_aiex_table?(table_info) do
    name_str = to_string(table_info.name || "")
    String.contains?(name_str, "aiex") or String.contains?(name_str, "Aiex")
  end
  
  defp build_supervision_tree(node, supervisor) do
    case call_node_safely(node, Supervisor, :which_children, [supervisor]) do
      {:ok, children} ->
        %{
          supervisor: supervisor,
          children: Enum.map(children, &format_child_spec/1)
        }
      _ ->
        %{error: "Could not get supervision tree"}
    end
  end
  
  defp format_child_spec({id, pid, type, modules}) do
    %{
      id: id,
      pid: pid,
      type: type,
      modules: modules,
      status: if(is_pid(pid), do: :running, else: :not_running)
    }
  end
  
  defp get_node_process_list(node) do
    case call_node_safely(node, Process, :list, []) do
      {:ok, pids} ->
        Enum.map(pids, fn pid ->
          case call_node_safely(node, Process, :info, [pid]) do
            {:ok, info} -> {pid, Enum.into(info, %{})}
            _ -> {pid, %{}}
          end
        end)
      _ -> []
    end
  end
  
  defp all_connected?(connectivity) do
    Enum.all?(connectivity, fn %{targets: targets} ->
      Enum.all?(targets, fn {_node, status} ->
        status in [:self, :connected]
      end)
    end)
  end
  
  defp test_pg_groups(nodes) do
    try do
      # Test if pg groups are working
      test_group = :aiex_test_group
      :pg.join(test_group, self())
      
      members = :pg.get_members(test_group)
      :pg.leave(test_group, self())
      
      %{status: :ok, members: length(members), nodes: length(nodes)}
    rescue
      error -> %{status: :error, error: Exception.message(error)}
    end
  end
  
  defp test_distributed_calls(nodes) do
    successful_calls = Enum.count(nodes, fn node ->
      case call_node_safely(node, Node, :self, []) do
        {:ok, ^node} -> true
        _ -> false
      end
    end)
    
    %{
      status: if(successful_calls == length(nodes), do: :ok, else: :partial),
      successful_calls: successful_calls,
      total_nodes: length(nodes)
    }
  end
  
  defp test_event_bus(_nodes) do
    try do
      # Test if event bus is accessible
      case Process.whereis(Aiex.Events.EventBus) do
        pid when is_pid(pid) -> %{status: :ok, event_bus_pid: pid}
        nil -> %{status: :error, error: "EventBus not running"}
      end
    rescue
      error -> %{status: :error, error: Exception.message(error)}
    end
  end
  
  defp test_telemetry_aggregation(_nodes) do
    try do
      case Process.whereis(DistributedAggregator) do
        pid when is_pid(pid) ->
          # Try to get cluster metrics
          case DistributedAggregator.get_cluster_metrics() do
            {:ok, _metrics} -> %{status: :ok, aggregator_pid: pid}
            _ -> %{status: :error, error: "Could not get cluster metrics"}
          end
        nil -> %{status: :error, error: "DistributedAggregator not running"}
      end
    rescue
      error -> %{status: :error, error: Exception.message(error)}
    end
  end
  
  defp generate_recommendations(overview, memory, processes) do
    recommendations = []
    
    recommendations = if overview.cluster_health != :healthy do
      ["Consider investigating node connectivity issues" | recommendations]
    else
      recommendations
    end
    
    recommendations = if memory.cluster_total_mb > 4096 do
      ["Monitor memory usage - cluster using #{memory.cluster_total_mb}MB" | recommendations]
    else
      recommendations
    end
    
    recommendations = if processes.distribution_balance < 0.8 do
      ["Consider rebalancing processes across nodes" | recommendations]
    else
      recommendations
    end
    
    recommendations = if overview.coordination_status != :fully_coordinated do
      ["Check cluster coordination and network connectivity" | recommendations]
    else
      recommendations
    end
    
    if Enum.empty?(recommendations) do
      ["Cluster appears to be operating normally"]
    else
      recommendations
    end
  end
  
  defp get_aiex_version do
    Application.spec(:aiex, :vsn) || "unknown"
  end
end