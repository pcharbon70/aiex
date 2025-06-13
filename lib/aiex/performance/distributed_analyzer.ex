defmodule Aiex.Performance.DistributedAnalyzer do
  @moduledoc """
  Distributed performance analyzer using :recon for cluster-wide analysis.
  
  Provides coordinated performance monitoring across all nodes in the cluster,
  implementing patterns from Discord and WhatsApp deployments for production-grade
  performance optimization.
  """

  use GenServer
  require Logger

  alias Aiex.Events.EventBus

  @analysis_interval 60_000  # 1 minute
  @memory_threshold 100_000_000  # 100MB
  @message_queue_threshold 1000

  defmodule State do
    @moduledoc false
    defstruct [
      :node_metrics,
      :analysis_tasks,
      :hot_processes,
      :memory_snapshots,
      :gc_stats,
      :analysis_timer
    ]
  end

  # Client API

  @doc """
  Starts the distributed performance analyzer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Performs immediate cluster-wide performance analysis.
  """
  def analyze_cluster do
    GenServer.call(__MODULE__, :analyze_cluster, 30_000)
  end

  @doc """
  Gets current performance metrics for all nodes.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Analyzes memory usage across the cluster.
  """
  def analyze_memory do
    GenServer.call(__MODULE__, :analyze_memory, 30_000)
  end

  @doc """
  Identifies hot processes consuming excessive resources.
  """
  def find_hot_processes(limit \\ 10) do
    GenServer.call(__MODULE__, {:find_hot_processes, limit})
  end

  @doc """
  Performs garbage collection analysis across nodes.
  """
  def analyze_gc do
    GenServer.call(__MODULE__, :analyze_gc, 30_000)
  end

  @doc """
  Gets process info for a specific PID across any node.
  """
  def process_info(pid) when is_pid(pid) do
    GenServer.call(__MODULE__, {:process_info, pid})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Ensure pg is started
    case Process.whereis(:pg) do
      nil ->
        # pg is not started, which is fine for tests
        :ok
      _pid ->
        # Join performance monitoring process group
        :pg.join(:aiex_performance, self())
    end
    
    # Schedule periodic analysis
    timer = Process.send_after(self(), :periodic_analysis, @analysis_interval)
    
    state = %State{
      node_metrics: %{},
      analysis_tasks: %{},
      hot_processes: [],
      memory_snapshots: [],
      gc_stats: %{},
      analysis_timer: timer
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call(:analyze_cluster, _from, state) do
    metrics = perform_cluster_analysis()
    new_state = %{state | node_metrics: metrics}
    {:reply, {:ok, metrics}, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, {:ok, state.node_metrics}, state}
  end

  @impl true
  def handle_call(:analyze_memory, _from, state) do
    memory_analysis = perform_memory_analysis()
    new_state = %{state | memory_snapshots: [memory_analysis | Enum.take(state.memory_snapshots, 9)]}
    {:reply, {:ok, memory_analysis}, new_state}
  end

  @impl true
  def handle_call({:find_hot_processes, limit}, _from, state) do
    hot_procs = find_hot_processes_cluster(limit)
    new_state = %{state | hot_processes: hot_procs}
    {:reply, {:ok, hot_procs}, new_state}
  end

  @impl true
  def handle_call(:analyze_gc, _from, state) do
    gc_analysis = perform_gc_analysis()
    new_state = %{state | gc_stats: gc_analysis}
    {:reply, {:ok, gc_analysis}, new_state}
  end

  @impl true
  def handle_call({:process_info, pid}, _from, state) do
    info = get_distributed_process_info(pid)
    {:reply, {:ok, info}, state}
  end

  @impl true
  def handle_info(:periodic_analysis, state) do
    # Perform lightweight periodic analysis
    Task.start(fn ->
      try do
        metrics = perform_cluster_analysis()
        case Process.whereis(Aiex.Events.EventBus) do
          nil -> :ok  # EventBus not started (e.g., in tests)
          _pid ->
            EventBus.publish(:performance_analysis, %{
              timestamp: DateTime.utc_now(),
              metrics: metrics,
              node: node()
            })
        end
      rescue
        error ->
          Logger.error("Periodic analysis failed: #{inspect(error)}")
      end
    end)
    
    # Schedule next analysis
    timer = Process.send_after(self(), :periodic_analysis, @analysis_interval)
    {:noreply, %{state | analysis_timer: timer}}
  end

  # Private Functions

  defp perform_cluster_analysis do
    nodes = [node() | Node.list()]
    
    # Gather metrics from all nodes in parallel
    tasks = Enum.map(nodes, fn node ->
      Task.async(fn ->
        try do
          {node, analyze_node(node)}
        catch
          _, _ -> {node, %{error: "Analysis failed"}}
        end
      end)
    end)
    
    # Collect results with timeout
    Enum.map(tasks, fn task ->
      case Task.yield(task, 5000) || Task.shutdown(task) do
        {:ok, result} -> result
        _ -> {task.node, %{error: "Timeout"}}
      end
    end)
    |> Map.new()
  end

  defp analyze_node(node) do
    :rpc.call(node, __MODULE__, :local_node_analysis, [], 5000)
  end

  @doc false
  def local_node_analysis do
    %{
      memory: get_memory_stats(),
      processes: get_process_stats(),
      system: get_system_stats(),
      schedulers: get_scheduler_stats(),
      io: get_io_stats()
    }
  end

  defp get_memory_stats do
    memory = :erlang.memory()
    
    %{
      total: memory[:total],
      processes: memory[:processes],
      ets: memory[:ets],
      atom: memory[:atom],
      binary: memory[:binary],
      code: memory[:code],
      system: memory[:system]
    }
  end

  defp get_process_stats do
    %{
      count: :erlang.system_info(:process_count),
      limit: :erlang.system_info(:process_limit),
      reductions: :recon.proc_count(:reductions, 5),
      memory_hogs: :recon.proc_count(:memory, 5),
      message_queue_hogs: :recon.proc_count(:message_queue_len, 5)
    }
  end

  defp get_system_stats do
    %{
      uptime: :erlang.statistics(:wall_clock) |> elem(0),
      run_queue: :erlang.statistics(:run_queue),
      cpu_topology: :erlang.system_info(:cpu_topology),
      logical_processors: :erlang.system_info(:logical_processors),
      otp_release: :erlang.system_info(:otp_release)
    }
  end

  defp get_scheduler_stats do
    :recon.scheduler_usage(1000)
    |> Enum.with_index(1)
    |> Enum.map(fn {usage, id} ->
      {id, usage}
    end)
    |> Map.new()
  end

  defp get_io_stats do
    {{:input, input}, {:output, output}} = :erlang.statistics(:io)
    
    %{
      input_bytes: input,
      output_bytes: output
    }
  end

  defp perform_memory_analysis do
    nodes = [node() | Node.list()]
    
    # Analyze memory on each node
    node_memory = Enum.map(nodes, fn node ->
      memory_data = :rpc.call(node, __MODULE__, :local_memory_analysis, [], 5000)
      {node, memory_data}
    end)
    |> Map.new()
    
    %{
      timestamp: DateTime.utc_now(),
      nodes: node_memory,
      total_cluster_memory: calculate_total_memory(node_memory),
      memory_distribution: calculate_memory_distribution(node_memory)
    }
  end

  @doc false
  def local_memory_analysis do
    %{
      fragmentation: :recon_alloc.memory(:usage),
      allocators: :recon_alloc.memory(:allocated_types),
      binaries: :recon.bin_leak(10),
      large_objects: find_large_objects()
    }
  end

  defp find_large_objects do
    :ets.all()
    |> Enum.map(fn table ->
      info = :ets.info(table)
      {table, info[:memory] * :erlang.system_info(:wordsize)}
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(10)
  end

  defp calculate_total_memory(node_memory) do
    node_memory
    |> Enum.reduce(0, fn {_node, data}, acc ->
      case data do
        %{fragmentation: frag} when is_list(frag) ->
          allocated = Keyword.get(frag, :allocated, 0)
          acc + allocated
        _ -> acc
      end
    end)
  end

  defp calculate_memory_distribution(node_memory) do
    total = calculate_total_memory(node_memory)
    
    node_memory
    |> Enum.map(fn {node, data} ->
      node_memory = case data do
        %{fragmentation: frag} when is_list(frag) ->
          Keyword.get(frag, :allocated, 0)
        _ -> 0
      end
      
      percentage = if total > 0, do: (node_memory / total) * 100, else: 0
      {node, percentage}
    end)
    |> Map.new()
  end

  defp find_hot_processes_cluster(limit) do
    nodes = [node() | Node.list()]
    
    # Gather hot processes from all nodes
    all_processes = Enum.flat_map(nodes, fn node ->
      case :rpc.call(node, __MODULE__, :local_hot_processes, [limit], 5000) do
        {:badrpc, _} -> []
        processes -> processes
      end
    end)
    
    # Sort by resource consumption and take top N
    all_processes
    |> Enum.sort_by(fn {_pid, info} -> 
      memory = info[:memory] || 0
      reductions = info[:reductions] || 0
      memory + reductions
    end, :desc)
    |> Enum.take(limit)
  end

  @doc false
  def local_hot_processes(limit) do
    # Find processes with high memory usage
    memory_hogs = :recon.proc_count(:memory, limit)
    |> Enum.map(fn {pid, memory, info} ->
      {pid, [memory: memory, type: :memory] ++ process_details(pid, info)}
    end)
    
    # Find processes with high reduction count
    cpu_hogs = :recon.proc_count(:reductions, limit)
    |> Enum.map(fn {pid, reductions, info} ->
      {pid, [reductions: reductions, type: :cpu] ++ process_details(pid, info)}
    end)
    
    # Find processes with large message queues
    queue_hogs = :recon.proc_count(:message_queue_len, limit)
    |> Enum.map(fn {pid, queue_len, info} ->
      {pid, [message_queue: queue_len, type: :queue] ++ process_details(pid, info)}
    end)
    
    # Merge and deduplicate
    (memory_hogs ++ cpu_hogs ++ queue_hogs)
    |> Enum.uniq_by(&elem(&1, 0))
  end

  defp process_details(pid, info) do
    [
      name: info[:registered_name] || :undefined,
      current_function: info[:current_function],
      initial_call: info[:initial_call],
      status: info[:status],
      node: node(pid)
    ]
  end

  defp perform_gc_analysis do
    nodes = [node() | Node.list()]
    
    gc_stats = Enum.map(nodes, fn node ->
      stats = :rpc.call(node, __MODULE__, :local_gc_analysis, [], 5000)
      {node, stats}
    end)
    |> Map.new()
    
    %{
      timestamp: DateTime.utc_now(),
      nodes: gc_stats,
      recommendations: generate_gc_recommendations(gc_stats)
    }
  end

  @doc false
  def local_gc_analysis do
    gc_stats = :erlang.statistics(:garbage_collection)
    
    %{
      number_of_gcs: elem(gc_stats, 0),
      words_reclaimed: elem(gc_stats, 1),
      fullsweep_after: :erlang.system_info(:fullsweep_after),
      heap_sizes: analyze_heap_sizes(),
      gc_config: get_gc_config()
    }
  end

  defp analyze_heap_sizes do
    processes = Process.list()
    
    heap_sizes = Enum.map(processes, fn pid ->
      case Process.info(pid, [:heap_size, :total_heap_size]) do
        [{:heap_size, heap}, {:total_heap_size, total}] ->
          {heap, total}
        _ -> {0, 0}
      end
    end)
    
    {heaps, totals} = Enum.unzip(heap_sizes)
    
    %{
      average_heap: average(heaps),
      average_total: average(totals),
      max_heap: Enum.max(heaps, fn -> 0 end),
      max_total: Enum.max(totals, fn -> 0 end)
    }
  end

  defp average(list) when length(list) > 0 do
    Enum.sum(list) / length(list)
  end
  defp average(_), do: 0

  defp get_gc_config do
    %{
      min_heap_size: :erlang.system_info(:min_heap_size),
      min_bin_vheap_size: :erlang.system_info(:min_bin_vheap_size),
      fullsweep_after: :erlang.system_info(:fullsweep_after)
    }
  end

  defp generate_gc_recommendations(gc_stats) do
    recommendations = []
    
    # Check for excessive GC activity
    recommendations = gc_stats
    |> Enum.reduce(recommendations, fn {node, stats}, recs ->
      case stats do
        %{number_of_gcs: gcs} when gcs > 100_000 ->
          ["High GC activity on #{node}: Consider increasing heap sizes" | recs]
        _ -> recs
      end
    end)
    
    # Check for large heap sizes
    recommendations = gc_stats
    |> Enum.reduce(recommendations, fn {node, stats}, recs ->
      case stats do
        %{heap_sizes: %{max_total: max}} when max > 50_000_000 ->
          ["Large heap detected on #{node}: Monitor for memory leaks" | recs]
        _ -> recs
      end
    end)
    
    recommendations
  end

  defp get_distributed_process_info(pid) do
    node = node(pid)
    
    case :rpc.call(node, Process, :info, [pid], 5000) do
      {:badrpc, _} -> %{error: "Failed to get process info"}
      nil -> %{error: "Process not found"}
      info -> Map.new(info)
    end
  end
end