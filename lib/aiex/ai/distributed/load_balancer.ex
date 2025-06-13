defmodule Aiex.AI.Distributed.LoadBalancer do
  @moduledoc """
  Advanced load balancing for AI requests across distributed coordinators.
  
  Implements multiple load balancing algorithms including weighted round-robin,
  least-connections, and adaptive algorithms that learn from request patterns
  and coordinator performance characteristics.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.AI.Distributed.{Coordinator, NodeCapabilityManager}
  alias Aiex.Events.EventBus
  alias Aiex.Telemetry.DistributedAggregator
  
  @algorithm_types [:round_robin, :weighted_round_robin, :least_connections, :adaptive, :capability_aware]
  @performance_window_ms 300_000  # 5 minutes
  @coordinator_timeout 5_000
  @circuit_breaker_failure_threshold 5
  @circuit_breaker_timeout 30_000
  
  defstruct [
    :current_algorithm,
    :coordinator_pool,
    :performance_history,
    :circuit_breakers,
    :algorithm_weights,
    round_robin_index: 0,
    request_counts: %{},
    last_performance_update: nil,
    algorithm_performance: %{}
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Select the best coordinator for a request using the current algorithm.
  """
  def select_coordinator(request, options \\ []) do
    GenServer.call(__MODULE__, {:select_coordinator, request, options})
  end
  
  @doc """
  Get current load balancing statistics.
  """
  def get_load_balancing_stats do
    GenServer.call(__MODULE__, :get_load_balancing_stats)
  end
  
  @doc """
  Switch load balancing algorithm.
  """
  def set_algorithm(algorithm) when algorithm in @algorithm_types do
    GenServer.call(__MODULE__, {:set_algorithm, algorithm})
  end
  
  @doc """
  Update coordinator performance metrics.
  """
  def update_coordinator_performance(coordinator_id, metrics) do
    GenServer.cast(__MODULE__, {:update_performance, coordinator_id, metrics})
  end
  
  @doc """
  Mark coordinator as failed (for circuit breaker).
  """
  def mark_coordinator_failed(coordinator_id, reason) do
    GenServer.cast(__MODULE__, {:mark_failed, coordinator_id, reason})
  end
  
  @doc """
  Mark coordinator as recovered (for circuit breaker).
  """
  def mark_coordinator_recovered(coordinator_id) do
    GenServer.cast(__MODULE__, {:mark_recovered, coordinator_id})
  end
  
  @doc """
  Get coordinator pool status.
  """
  def get_coordinator_pool_status do
    GenServer.call(__MODULE__, :get_coordinator_pool_status)
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    algorithm = Keyword.get(opts, :algorithm, :adaptive)
    
    state = %__MODULE__{
      current_algorithm: algorithm,
      coordinator_pool: %{},
      performance_history: %{},
      circuit_breakers: %{},
      algorithm_weights: initialize_algorithm_weights(),
      request_counts: %{},
      last_performance_update: System.system_time(:millisecond),
      algorithm_performance: initialize_algorithm_performance()
    }
    
    # Schedule periodic updates
    schedule_coordinator_pool_update()
    schedule_performance_analysis()
    
    Logger.info("AI load balancer started with #{algorithm} algorithm")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:select_coordinator, request, options}, _from, state) do
    case select_best_coordinator(request, options, state) do
      {:ok, coordinator_id} ->
        # Update request counts
        updated_counts = Map.update(state.request_counts, coordinator_id, 1, &(&1 + 1))
        updated_state = %{state | request_counts: updated_counts}
        
        {:reply, {:ok, coordinator_id}, updated_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call(:get_load_balancing_stats, _from, state) do
    stats = generate_load_balancing_stats(state)
    {:reply, stats, state}
  end
  
  def handle_call({:set_algorithm, algorithm}, _from, state) do
    Logger.info("Switching load balancing algorithm from #{state.current_algorithm} to #{algorithm}")
    
    updated_state = %{state | current_algorithm: algorithm}
    
    # Publish algorithm change event
    EventBus.publish("load_balancer:algorithm_changed", %{
      from: state.current_algorithm,
      to: algorithm,
      timestamp: System.system_time(:millisecond)
    })
    
    {:reply, :ok, updated_state}
  end
  
  def handle_call(:get_coordinator_pool_status, _from, state) do
    pool_status = %{
      total_coordinators: map_size(state.coordinator_pool),
      active_coordinators: count_active_coordinators(state),
      failed_coordinators: count_failed_coordinators(state),
      algorithm: state.current_algorithm,
      request_distribution: state.request_counts
    }
    
    {:reply, pool_status, state}
  end
  
  @impl true
  def handle_cast({:update_performance, coordinator_id, metrics}, state) do
    # Update performance history
    timestamp = System.system_time(:millisecond)
    
    performance_entry = %{
      timestamp: timestamp,
      metrics: metrics
    }
    
    updated_history = Map.update(state.performance_history, coordinator_id, [performance_entry], fn history ->
      [performance_entry | history]
      |> Enum.filter(&(timestamp - &1.timestamp < @performance_window_ms))
      |> Enum.take(100)  # Keep last 100 entries
    end)
    
    updated_state = %{state | performance_history: updated_history}
    
    # Record telemetry
    DistributedAggregator.record_metric("load_balancer.performance_updated", 1, %{
      coordinator_id: coordinator_id,
      response_time_ms: metrics[:response_time_ms] || 0,
      success_rate: metrics[:success_rate] || 0.0
    })
    
    {:noreply, updated_state}
  end
  
  def handle_cast({:mark_failed, coordinator_id, reason}, state) do
    Logger.warning("Marking coordinator #{coordinator_id} as failed: #{reason}")
    
    # Update circuit breaker
    updated_breakers = Map.update(state.circuit_breakers, coordinator_id, %{
      state: :open,
      failure_count: 1,
      last_failure: System.system_time(:millisecond),
      reason: reason
    }, fn breaker ->
      %{breaker | 
        failure_count: breaker.failure_count + 1,
        last_failure: System.system_time(:millisecond),
        state: if(breaker.failure_count >= @circuit_breaker_failure_threshold, do: :open, else: :half_open)
      }
    end)
    
    updated_state = %{state | circuit_breakers: updated_breakers}
    
    # Publish circuit breaker event
    EventBus.publish("load_balancer:circuit_breaker_opened", %{
      coordinator_id: coordinator_id,
      reason: reason,
      timestamp: System.system_time(:millisecond)
    })
    
    {:noreply, updated_state}
  end
  
  def handle_cast({:mark_recovered, coordinator_id}, state) do
    Logger.info("Marking coordinator #{coordinator_id} as recovered")
    
    # Reset circuit breaker
    updated_breakers = Map.put(state.circuit_breakers, coordinator_id, %{
      state: :closed,
      failure_count: 0,
      last_success: System.system_time(:millisecond)
    })
    
    updated_state = %{state | circuit_breakers: updated_breakers}
    
    # Publish recovery event
    EventBus.publish("load_balancer:circuit_breaker_closed", %{
      coordinator_id: coordinator_id,
      timestamp: System.system_time(:millisecond)
    })
    
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(:update_coordinator_pool, state) do
    updated_state = refresh_coordinator_pool(state)
    schedule_coordinator_pool_update()
    {:noreply, updated_state}
  end
  
  def handle_info(:analyze_performance, state) do
    updated_state = analyze_algorithm_performance(state)
    schedule_performance_analysis()
    {:noreply, updated_state}
  end
  
  # Private functions
  
  defp select_best_coordinator(request, options, state) do
    # Filter available coordinators (exclude circuit breaker failures)
    available_coordinators = get_available_coordinators(state)
    
    if Enum.empty?(available_coordinators) do
      {:error, :no_available_coordinators}
    else
      algorithm = Keyword.get(options, :algorithm, state.current_algorithm)
      
      case algorithm do
        :round_robin ->
          select_round_robin(available_coordinators, state)
        
        :weighted_round_robin ->
          select_weighted_round_robin(available_coordinators, state)
        
        :least_connections ->
          select_least_connections(available_coordinators, state)
        
        :adaptive ->
          select_adaptive(available_coordinators, request, state)
        
        :capability_aware ->
          select_capability_aware(available_coordinators, request, state)
        
        _ ->
          {:error, {:unsupported_algorithm, algorithm}}
      end
    end
  end
  
  defp get_available_coordinators(state) do
    current_time = System.system_time(:millisecond)
    
    state.coordinator_pool
    |> Enum.filter(fn {coordinator_id, coordinator} ->
      # Check if coordinator is healthy and circuit breaker is closed
      coordinator_healthy?(coordinator) and
      circuit_breaker_allows?(coordinator_id, current_time, state.circuit_breakers)
    end)
    |> Enum.into(%{})
  end
  
  defp coordinator_healthy?(coordinator) do
    Map.get(coordinator, :health_status, :unknown) in [:healthy, :degraded]
  end
  
  defp circuit_breaker_allows?(coordinator_id, current_time, circuit_breakers) do
    case Map.get(circuit_breakers, coordinator_id) do
      nil -> true  # No circuit breaker = allowed
      
      %{state: :closed} -> true
      
      %{state: :open, last_failure: last_failure} ->
        # Allow if timeout has passed
        current_time - last_failure > @circuit_breaker_timeout
      
      %{state: :half_open} -> true
      
      _ -> false
    end
  end
  
  defp select_round_robin(coordinators, state) do
    coordinator_ids = Map.keys(coordinators)
    index = rem(state.round_robin_index, length(coordinator_ids))
    selected_id = Enum.at(coordinator_ids, index)
    
    {:ok, selected_id}
  end
  
  defp select_weighted_round_robin(coordinators, state) do
    # Calculate weights based on coordinator capabilities
    weighted_coordinators = Enum.map(coordinators, fn {id, coordinator} ->
      weight = calculate_coordinator_weight(coordinator, state)
      {id, weight}
    end)
    
    # Select based on weights
    total_weight = Enum.sum(Enum.map(weighted_coordinators, fn {_id, weight} -> weight end))
    
    if total_weight > 0 do
      target_weight = :rand.uniform() * total_weight
      selected_id = select_by_weight(weighted_coordinators, target_weight, 0)
      {:ok, selected_id}
    else
      # Fallback to round robin
      select_round_robin(coordinators, state)
    end
  end
  
  defp select_least_connections(coordinators, state) do
    # Select coordinator with least active requests
    least_loaded = Enum.min_by(coordinators, fn {id, coordinator} ->
      active_requests = Map.get(coordinator, :active_requests, 0)
      request_count = Map.get(state.request_counts, id, 0)
      active_requests + request_count
    end)
    
    {selected_id, _coordinator} = least_loaded
    {:ok, selected_id}
  end
  
  defp select_adaptive(coordinators, request, state) do
    # Adaptive selection based on request characteristics and coordinator performance
    request_requirements = extract_request_requirements(request)
    
    scored_coordinators = Enum.map(coordinators, fn {id, coordinator} ->
      performance_score = calculate_performance_score(id, state.performance_history)
      capability_score = calculate_capability_match_score(coordinator, request_requirements)
      load_score = calculate_load_score(coordinator, state.request_counts)
      
      # Weighted combination of scores
      total_score = performance_score * 0.4 + capability_score * 0.3 + load_score * 0.3
      
      {id, total_score}
    end)
    
    # Select coordinator with highest score
    {selected_id, _score} = Enum.max_by(scored_coordinators, fn {_id, score} -> score end)
    {:ok, selected_id}
  end
  
  defp select_capability_aware(coordinators, request, state) do
    request_requirements = extract_request_requirements(request)
    
    # Filter coordinators that can handle the request
    suitable_coordinators = Enum.filter(coordinators, fn {_id, coordinator} ->
      can_handle_request?(coordinator, request_requirements)
    end)
    
    if Enum.empty?(suitable_coordinators) do
      # Fallback to best available coordinator
      select_adaptive(coordinators, request, state)
    else
      # Among suitable coordinators, select least loaded
      select_least_connections(Enum.into(suitable_coordinators, %{}), state)
    end
  end
  
  defp calculate_coordinator_weight(coordinator, state) do
    # Base weight from capabilities
    base_weight = Map.get(coordinator, :max_concurrent_requests, 100)
    
    # Adjust based on current load
    active_requests = Map.get(coordinator, :active_requests, 0)
    load_factor = max(0.1, (base_weight - active_requests) / base_weight)
    
    # Adjust based on recent performance
    performance_factor = get_performance_factor(coordinator.id, state.performance_history)
    
    base_weight * load_factor * performance_factor
  end
  
  defp select_by_weight(weighted_coordinators, target_weight, accumulated_weight) do
    [{id, weight} | rest] = weighted_coordinators
    new_accumulated = accumulated_weight + weight
    
    if target_weight <= new_accumulated do
      id
    else
      select_by_weight(rest, target_weight, new_accumulated)
    end
  end
  
  defp calculate_performance_score(coordinator_id, performance_history) do
    case Map.get(performance_history, coordinator_id) do
      nil -> 0.5  # Default score for unknown performance
      
      history ->
        # Calculate average performance metrics
        if length(history) > 0 do
          avg_response_time = history
          |> Enum.map(&get_in(&1, [:metrics, :response_time_ms]))
          |> Enum.filter(&(!is_nil(&1)))
          |> average_or_default(2000)
          
          avg_success_rate = history
          |> Enum.map(&get_in(&1, [:metrics, :success_rate]))
          |> Enum.filter(&(!is_nil(&1)))
          |> average_or_default(0.9)
          
          # Score based on speed and reliability (lower response time and higher success rate = better)
          response_score = max(0, 1.0 - (avg_response_time / 10000))  # Normalize to 0-1
          success_score = avg_success_rate
          
          (response_score + success_score) / 2
        else
          0.5
        end
    end
  end
  
  defp calculate_capability_match_score(coordinator, requirements) do
    # Score based on how well coordinator capabilities match requirements
    capabilities = Map.get(coordinator, :capabilities, %{})
    
    if Enum.empty?(requirements) do
      1.0  # Perfect match if no specific requirements
    else
      matches = Enum.count(requirements, fn {key, required_value} ->
        available_value = Map.get(capabilities, key)
        capability_matches?(available_value, required_value)
      end)
      
      matches / length(requirements)
    end
  end
  
  defp calculate_load_score(coordinator, request_counts) do
    coordinator_id = Map.get(coordinator, :id)
    active_requests = Map.get(coordinator, :active_requests, 0)
    queued_requests = Map.get(request_counts, coordinator_id, 0)
    max_requests = Map.get(coordinator, :max_concurrent_requests, 100)
    
    total_load = active_requests + queued_requests
    load_ratio = total_load / max_requests
    
    # Higher score for lower load
    max(0.0, 1.0 - load_ratio)
  end
  
  defp extract_request_requirements(request) do
    Map.get(request, :requirements, %{})
  end
  
  defp can_handle_request?(coordinator, requirements) do
    capabilities = Map.get(coordinator, :capabilities, %{})
    
    Enum.all?(requirements, fn {key, required_value} ->
      available_value = Map.get(capabilities, key)
      capability_matches?(available_value, required_value)
    end)
  end
  
  defp capability_matches?(available, required) when is_list(available) and is_binary(required) do
    required in available
  end
  
  defp capability_matches?(available, required) when is_number(available) and is_number(required) do
    available >= required
  end
  
  defp capability_matches?(available, required) do
    available == required
  end
  
  defp refresh_coordinator_pool(state) do
    # Get current coordinators from Coordinator module
    case Coordinator.get_coordinators() do
      coordinators when is_list(coordinators) ->
        coordinator_pool = Enum.into(coordinators, %{}, fn coordinator ->
          {coordinator.coordinator_id, coordinator}
        end)
        
        %{state | coordinator_pool: coordinator_pool}
      
      _ ->
        state
    end
  end
  
  defp analyze_algorithm_performance(state) do
    # Analyze performance of current algorithm and adjust if needed
    current_time = System.system_time(:millisecond)
    
    if current_time - state.last_performance_update > @performance_window_ms do
      # Calculate algorithm performance metrics
      algorithm_metrics = calculate_algorithm_metrics(state)
      
      updated_performance = Map.put(state.algorithm_performance, state.current_algorithm, algorithm_metrics)
      
      # Consider switching algorithm if performance is poor
      updated_state = maybe_switch_algorithm(state, algorithm_metrics)
      
      %{updated_state | 
        algorithm_performance: updated_performance,
        last_performance_update: current_time
      }
    else
      state
    end
  end
  
  defp calculate_algorithm_metrics(state) do
    # Calculate metrics for current algorithm
    %{
      total_requests: Enum.sum(Map.values(state.request_counts)),
      coordinator_distribution: calculate_distribution_variance(state.request_counts),
      timestamp: System.system_time(:millisecond)
    }
  end
  
  defp maybe_switch_algorithm(state, metrics) do
    # Simple heuristic: switch to adaptive if distribution is very uneven
    distribution_variance = metrics.coordinator_distribution
    
    if distribution_variance > 0.8 and state.current_algorithm != :adaptive do
      Logger.info("High distribution variance detected, switching to adaptive algorithm")
      %{state | current_algorithm: :adaptive}
    else
      state
    end
  end
  
  defp calculate_distribution_variance(request_counts) do
    if map_size(request_counts) < 2 do
      0.0
    else
      values = Map.values(request_counts)
      mean = Enum.sum(values) / length(values)
      variance = (Enum.map(values, &(:math.pow(&1 - mean, 2))) |> Enum.sum()) / length(values)
      variance / (mean * mean)  # Coefficient of variation
    end
  end
  
  defp generate_load_balancing_stats(state) do
    %{
      current_algorithm: state.current_algorithm,
      coordinator_pool_size: map_size(state.coordinator_pool),
      active_coordinators: count_active_coordinators(state),
      failed_coordinators: count_failed_coordinators(state),
      request_distribution: state.request_counts,
      algorithm_performance: state.algorithm_performance,
      circuit_breaker_status: get_circuit_breaker_summary(state.circuit_breakers),
      timestamp: System.system_time(:millisecond)
    }
  end
  
  defp count_active_coordinators(state) do
    Enum.count(state.coordinator_pool, fn {_id, coordinator} ->
      coordinator_healthy?(coordinator)
    end)
  end
  
  defp count_failed_coordinators(state) do
    Enum.count(state.circuit_breakers, fn {_id, breaker} ->
      Map.get(breaker, :state) == :open
    end)
  end
  
  defp get_circuit_breaker_summary(circuit_breakers) do
    Enum.into(circuit_breakers, %{}, fn {id, breaker} ->
      {id, Map.get(breaker, :state, :closed)}
    end)
  end
  
  defp get_performance_factor(coordinator_id, performance_history) do
    case Map.get(performance_history, coordinator_id) do
      nil -> 1.0
      history when length(history) > 0 ->
        recent_success_rate = history
        |> Enum.take(5)  # Last 5 requests
        |> Enum.map(&get_in(&1, [:metrics, :success_rate]))
        |> Enum.filter(&(!is_nil(&1)))
        |> average_or_default(0.9)
        
        max(0.1, recent_success_rate)
      _ -> 1.0
    end
  end
  
  defp average_or_default([], default), do: default
  defp average_or_default(list, _default) do
    Enum.sum(list) / length(list)
  end
  
  defp initialize_algorithm_weights do
    %{
      round_robin: 1.0,
      weighted_round_robin: 1.2,
      least_connections: 1.1,
      adaptive: 1.5,
      capability_aware: 1.3
    }
  end
  
  defp initialize_algorithm_performance do
    Enum.into(@algorithm_types, %{}, fn algorithm ->
      {algorithm, %{total_requests: 0, performance_score: 0.5}}
    end)
  end
  
  defp schedule_coordinator_pool_update do
    Process.send_after(self(), :update_coordinator_pool, 10_000)  # 10 seconds
  end
  
  defp schedule_performance_analysis do
    Process.send_after(self(), :analyze_performance, 60_000)  # 1 minute
  end
end