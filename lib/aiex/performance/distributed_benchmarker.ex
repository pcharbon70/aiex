defmodule Aiex.Performance.DistributedBenchmarker do
  @moduledoc """
  Distributed benchmarking coordinator using Benchee.
  
  Coordinates benchmark execution across multiple nodes to measure
  performance characteristics of distributed operations.
  """

  use GenServer
  require Logger

  alias Aiex.Events.EventBus

  defmodule BenchmarkTask do
    @moduledoc false
    defstruct [
      :id,
      :name,
      :nodes,
      :scenarios,
      :config,
      :status,
      :results,
      :started_at,
      :completed_at
    ]
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :active_benchmarks,
      :completed_benchmarks,
      :benchmark_history
    ]
  end

  # Client API

  @doc """
  Starts the distributed benchmarker.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Runs a distributed benchmark across specified nodes.
  
  ## Options
  
    * `:nodes` - List of nodes to run on (defaults to all connected nodes)
    * `:time` - Time to run each benchmark scenario in seconds (default: 5)
    * `:warmup` - Warmup time in seconds (default: 2)
    * `:parallel` - Number of parallel processes (default: 1)
    * `:memory_time` - Time to run memory measurements (default: 0)
    
  ## Example
  
      scenarios = %{
        "local_call" => fn -> GenServer.call(MyServer, :ping) end,
        "remote_call" => fn -> GenServer.call({MyServer, :remote@node}, :ping) end
      }
      
      DistributedBenchmarker.run("RPC Performance", scenarios, nodes: [:node1, :node2])
  """
  def run(name, scenarios, opts \\ []) do
    GenServer.call(__MODULE__, {:run_benchmark, name, scenarios, opts}, :infinity)
  end

  @doc """
  Runs a comparison benchmark between distributed and local operations.
  """
  def compare_distributed_vs_local(operation_name, local_fn, distributed_fn, opts \\ []) do
    scenarios = %{
      "local_#{operation_name}" => local_fn,
      "distributed_#{operation_name}" => distributed_fn
    }
    
    run("#{operation_name} Comparison", scenarios, opts)
  end

  @doc """
  Gets the results of a completed benchmark.
  """
  def get_results(benchmark_id) do
    GenServer.call(__MODULE__, {:get_results, benchmark_id})
  end

  @doc """
  Lists all completed benchmarks.
  """
  def list_benchmarks do
    GenServer.call(__MODULE__, :list_benchmarks)
  end

  @doc """
  Runs standard distributed operation benchmarks.
  """
  def run_standard_benchmarks do
    GenServer.call(__MODULE__, :run_standard_benchmarks, :infinity)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %State{
      active_benchmarks: %{},
      completed_benchmarks: %{},
      benchmark_history: []
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:run_benchmark, name, scenarios, opts}, from, state) do
    benchmark_id = generate_benchmark_id()
    nodes = Keyword.get(opts, :nodes, [node() | Node.list()])
    
    benchmark = %BenchmarkTask{
      id: benchmark_id,
      name: name,
      nodes: nodes,
      scenarios: scenarios,
      config: build_benchmark_config(opts),
      status: :running,
      started_at: DateTime.utc_now()
    }
    
    # Start benchmark asynchronously
    Task.start_link(fn ->
      results = execute_distributed_benchmark(benchmark)
      GenServer.cast(__MODULE__, {:benchmark_completed, benchmark_id, results})
    end)
    
    new_state = %{state | active_benchmarks: Map.put(state.active_benchmarks, benchmark_id, benchmark)}
    
    {:reply, {:ok, benchmark_id}, new_state}
  end

  @impl true
  def handle_call({:get_results, benchmark_id}, _from, state) do
    result = case Map.get(state.completed_benchmarks, benchmark_id) do
      nil -> {:error, :not_found}
      benchmark -> {:ok, benchmark}
    end
    
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_benchmarks, _from, state) do
    benchmarks = state.benchmark_history
    |> Enum.map(fn id ->
      Map.get(state.completed_benchmarks, id)
    end)
    |> Enum.filter(&(&1 != nil))
    
    {:reply, {:ok, benchmarks}, state}
  end

  @impl true
  def handle_call(:run_standard_benchmarks, from, state) do
    # Define standard benchmarks
    scenarios = standard_benchmark_scenarios()
    
    # Delegate to regular benchmark run
    handle_call({:run_benchmark, "Standard Distributed Operations", scenarios, []}, from, state)
  end

  @impl true
  def handle_cast({:benchmark_completed, benchmark_id, results}, state) do
    case Map.get(state.active_benchmarks, benchmark_id) do
      nil ->
        {:noreply, state}
        
      benchmark ->
        completed_benchmark = %{benchmark | 
          status: :completed,
          results: results,
          completed_at: DateTime.utc_now()
        }
        
        # Emit completion event
        case Process.whereis(Aiex.Events.EventBus) do
          nil -> :ok  # EventBus not started (e.g., in tests)
          _pid ->
            EventBus.publish(:benchmark_completed, %{
              benchmark_id: benchmark_id,
              name: benchmark.name,
              duration: DateTime.diff(completed_benchmark.completed_at, benchmark.started_at)
            })
        end
        
        new_state = %{state |
          active_benchmarks: Map.delete(state.active_benchmarks, benchmark_id),
          completed_benchmarks: Map.put(state.completed_benchmarks, benchmark_id, completed_benchmark),
          benchmark_history: [benchmark_id | Enum.take(state.benchmark_history, 99)]
        }
        
        {:noreply, new_state}
    end
  end

  # Private Functions

  defp generate_benchmark_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp build_benchmark_config(opts) do
    %{
      time: Keyword.get(opts, :time, 5),
      warmup: Keyword.get(opts, :warmup, 2),
      parallel: Keyword.get(opts, :parallel, 1),
      memory_time: Keyword.get(opts, :memory_time, 0),
      formatters: [
        {Benchee.Formatters.Console, comparison: true, extended_statistics: true}
      ]
    }
  end

  defp execute_distributed_benchmark(benchmark) do
    %{nodes: nodes, scenarios: scenarios, config: config} = benchmark
    
    # Run benchmarks on each node
    node_results = Enum.map(nodes, fn node ->
      Logger.info("Running benchmark on node: #{node}")
      
      result = if node == node() do
        # Local execution
        run_local_benchmark(scenarios, config)
      else
        # Remote execution
        case :rpc.call(node, __MODULE__, :run_local_benchmark, [scenarios, config], :infinity) do
          {:badrpc, reason} ->
            %{error: "Failed to run on #{node}: #{inspect(reason)}"}
          result ->
            result
        end
      end
      
      {node, result}
    end)
    |> Map.new()
    
    # Aggregate results
    aggregate_benchmark_results(node_results)
  end

  @doc false
  def run_local_benchmark(scenarios, config) do
    try do
      # Convert config to Benchee format
      benchee_config = Map.take(config, [:time, :warmup, :parallel, :memory_time])
      |> Map.put(:formatters, [])  # Disable console output for remote runs
      
      # Run benchmark
      result = Benchee.run(scenarios, benchee_config)
      
      # Extract key metrics
      extract_benchmark_metrics(result)
    rescue
      error ->
        %{error: "Benchmark failed: #{inspect(error)}"}
    end
  end

  defp extract_benchmark_metrics(benchee_result) do
    benchee_result.scenarios
    |> Enum.map(fn scenario ->
      stats = scenario.run_time_data.statistics
      
      {scenario.name, %{
        average: stats.average,
        median: stats.median,
        std_dev: stats.std_dev,
        std_dev_ratio: stats.std_dev_ratio,
        p99: stats.percentiles[99],
        minimum: stats.minimum,
        maximum: stats.maximum,
        sample_size: stats.sample_size,
        mode: stats.mode,
        ips: scenario.run_time_data.statistics.ips
      }}
    end)
    |> Map.new()
  end

  defp aggregate_benchmark_results(node_results) do
    # Group results by scenario
    scenarios = node_results
    |> Enum.flat_map(fn {_node, result} ->
      case result do
        %{error: _} -> []
        metrics -> Map.keys(metrics)
      end
    end)
    |> Enum.uniq()
    
    # Aggregate metrics for each scenario
    aggregated = Enum.map(scenarios, fn scenario ->
      node_metrics = node_results
      |> Enum.filter(fn {_node, result} ->
        not Map.has_key?(result, :error) and Map.has_key?(result, scenario)
      end)
      |> Enum.map(fn {node, result} ->
        {node, Map.get(result, scenario)}
      end)
      
      {scenario, %{
        nodes: Map.new(node_metrics),
        aggregate: calculate_aggregate_metrics(node_metrics)
      }}
    end)
    |> Map.new()
    
    %{
      scenarios: aggregated,
      errors: collect_errors(node_results)
    }
  end

  defp calculate_aggregate_metrics(node_metrics) do
    all_values = node_metrics
    |> Enum.map(fn {_node, metrics} -> metrics end)
    
    %{
      cluster_average: average(Enum.map(all_values, & &1.average)),
      cluster_median: median(Enum.map(all_values, & &1.median)),
      cluster_p99: percentile(Enum.flat_map(all_values, fn m -> [m.p99] end), 99),
      cluster_min: Enum.min_by(all_values, & &1.minimum).minimum,
      cluster_max: Enum.max_by(all_values, & &1.maximum).maximum,
      total_ips: Enum.sum(Enum.map(all_values, & &1.ips))
    }
  end

  defp average(values) when length(values) > 0 do
    Enum.sum(values) / length(values)
  end
  defp average(_), do: 0

  defp median(values) when length(values) > 0 do
    sorted = Enum.sort(values)
    mid = div(length(sorted), 2)
    
    if rem(length(sorted), 2) == 0 do
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    else
      Enum.at(sorted, mid)
    end
  end
  defp median(_), do: 0

  defp percentile(values, p) when length(values) > 0 do
    sorted = Enum.sort(values)
    k = (length(sorted) - 1) * (p / 100)
    f = :erlang.trunc(k)
    c = k - f
    
    if f + 1 < length(sorted) do
      Enum.at(sorted, f) * (1 - c) + Enum.at(sorted, f + 1) * c
    else
      Enum.at(sorted, f)
    end
  end
  defp percentile(_, _), do: 0

  defp collect_errors(node_results) do
    node_results
    |> Enum.filter(fn {_node, result} ->
      Map.has_key?(result, :error)
    end)
    |> Map.new()
  end

  defp standard_benchmark_scenarios do
    %{
      # Process group operations
      "pg_join" => fn ->
        :pg.join(:benchmark_group, self())
      end,
      
      "pg_get_members" => fn ->
        :pg.get_members(:benchmark_group)
      end,
      
      # ETS operations
      "ets_insert" => fn ->
        :ets.insert(:benchmark_table, {:rand.uniform(1000), :data})
      end,
      
      "ets_lookup" => fn ->
        :ets.lookup(:benchmark_table, :rand.uniform(1000))
      end,
      
      # GenServer calls
      "local_genserver_call" => fn ->
        GenServer.call(__MODULE__, :ping)
      end,
      
      # Message passing
      "send_message" => fn ->
        send(self(), {:benchmark, :data})
      end,
      
      # Process spawning
      "spawn_process" => fn ->
        spawn(fn -> :ok end)
      end,
      
      # Registry operations  
      "registry_register" => fn ->
        Registry.register(Aiex.Registry, {:benchmark, :rand.uniform(1000)}, :value)
      end,
      
      "registry_lookup" => fn ->
        Registry.lookup(Aiex.Registry, {:benchmark, :rand.uniform(1000)})
      end
    }
  end

  # Support ping for benchmarks
  @impl true
  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end
end