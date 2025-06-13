defmodule Aiex.AI.Distributed.Coordinator do
  @moduledoc """
  Distributed AI coordinator for intelligent request routing and workload distribution.
  
  Manages AI coordinator discovery across cluster nodes, tracks node capabilities,
  and orchestrates intelligent request routing based on node characteristics,
  model availability, and current workload.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.AI.Distributed.{RequestRouter, NodeCapabilityManager}
  alias Aiex.Events.EventBus
  alias Aiex.Telemetry.DistributedAggregator
  alias Aiex.Release.DistributedRelease
  
  @coordinator_group :aiex_ai_coordinators
  @discovery_interval 5_000
  @health_check_interval 10_000
  @capability_update_interval 15_000
  
  defstruct [
    :node,
    :coordinator_id,
    :capabilities,
    :last_health_check,
    :request_queue,
    :active_requests,
    connected_coordinators: [],
    cluster_topology: %{},
    load_metrics: %{},
    started_at: nil
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Register this node as an AI coordinator in the cluster.
  """
  def register_coordinator do
    GenServer.call(__MODULE__, :register_coordinator)
  end
  
  @doc """
  Get all active AI coordinators in the cluster.
  """
  def get_coordinators do
    GenServer.call(__MODULE__, :get_coordinators)
  end
  
  @doc """
  Route an AI request to the most suitable coordinator.
  """
  def route_request(request, options \\ []) do
    GenServer.call(__MODULE__, {:route_request, request, options}, 30_000)
  end
  
  @doc """
  Get cluster topology and coordinator distribution.
  """
  def get_cluster_topology do
    GenServer.call(__MODULE__, :get_cluster_topology)
  end
  
  @doc """
  Get current load metrics across all coordinators.
  """
  def get_load_metrics do
    GenServer.call(__MODULE__, :get_load_metrics)
  end
  
  @doc """
  Update node capabilities (called by NodeCapabilityManager).
  """
  def update_capabilities(capabilities) do
    GenServer.cast(__MODULE__, {:update_capabilities, capabilities})
  end
  
  @doc """
  Notify completion of a request (for load tracking).
  """
  def notify_request_completed(request_id, metrics) do
    GenServer.cast(__MODULE__, {:request_completed, request_id, metrics})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Join the AI coordinators process group
    :pg.join(@coordinator_group, self())
    
    coordinator_id = generate_coordinator_id()
    node = Node.self()
    
    state = %__MODULE__{
      node: node,
      coordinator_id: coordinator_id,
      capabilities: get_initial_capabilities(),
      request_queue: :queue.new(),
      active_requests: %{},
      started_at: System.system_time(:millisecond)
    }
    
    # Schedule periodic tasks
    schedule_coordinator_discovery()
    schedule_health_check()
    schedule_capability_update()
    
    Logger.info("AI coordinator started: #{coordinator_id} on #{node}")
    
    # Publish coordinator startup event
    EventBus.publish("ai_coordinator:started", %{
      coordinator_id: coordinator_id,
      node: node,
      capabilities: state.capabilities
    })
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:register_coordinator, _from, state) do
    # Re-join process group to ensure registration
    :pg.join(@coordinator_group, self())
    
    # Update coordinator discovery
    coordinators = discover_coordinators()
    updated_state = %{state | connected_coordinators: coordinators}
    
    {:reply, {:ok, state.coordinator_id}, updated_state}
  end
  
  def handle_call(:get_coordinators, _from, state) do
    coordinators = get_coordinator_info(state.connected_coordinators)
    {:reply, coordinators, state}
  end
  
  def handle_call({:route_request, request, options}, from, state) do
    case route_request_to_best_coordinator(request, options, state) do
      {:local, _coordinator} ->
        # Handle request locally
        handle_local_request(request, from, state)
      
      {:remote, target_coordinator} ->
        # Forward to remote coordinator
        forward_to_remote_coordinator(request, target_coordinator, from, state)
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call(:get_cluster_topology, _from, state) do
    topology = build_cluster_topology(state)
    {:reply, topology, state}
  end
  
  def handle_call(:get_load_metrics, _from, state) do
    metrics = collect_load_metrics(state)
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_cast({:update_capabilities, capabilities}, state) do
    updated_state = %{state | capabilities: capabilities}
    
    # Broadcast capability update to other coordinators
    broadcast_capability_update(updated_state)
    
    {:noreply, updated_state}
  end
  
  def handle_cast({:request_completed, request_id, metrics}, state) do
    # Remove from active requests and update load metrics
    updated_active = Map.delete(state.active_requests, request_id)
    updated_load = update_load_metrics(state.load_metrics, metrics)
    
    updated_state = %{state | 
      active_requests: updated_active,
      load_metrics: updated_load
    }
    
    # Record telemetry
    DistributedAggregator.record_metric("ai_coordinator.request_completed", 1, %{
      coordinator_id: state.coordinator_id,
      duration_ms: metrics[:duration_ms] || 0,
      success: metrics[:success] || false
    })
    
    {:noreply, updated_state}
  end
  
  def handle_cast({:capability_update, from_coordinator, capabilities}, state) do
    # Update capabilities from remote coordinator
    updated_coordinators = update_coordinator_capabilities(
      state.connected_coordinators, 
      from_coordinator, 
      capabilities
    )
    
    updated_state = %{state | connected_coordinators: updated_coordinators}
    {:noreply, updated_state}
  end
  
  def handle_cast({:remote_request, request, reply_to}, state) do
    # Handle request forwarded from another coordinator
    case handle_remote_request(request, state) do
      {:ok, result} ->
        GenServer.reply(reply_to, {:ok, result})
      {:error, reason} ->
        GenServer.reply(reply_to, {:error, reason})
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:discover_coordinators, state) do
    coordinators = discover_coordinators()
    updated_state = %{state | connected_coordinators: coordinators}
    
    # Schedule next discovery
    schedule_coordinator_discovery()
    
    {:noreply, updated_state}
  end
  
  def handle_info(:health_check, state) do
    # Perform health check
    health_status = perform_health_check(state)
    updated_state = %{state | last_health_check: System.system_time(:millisecond)}
    
    # Report health to telemetry
    DistributedAggregator.record_metric("ai_coordinator.health_check", 1, %{
      coordinator_id: state.coordinator_id,
      status: health_status,
      active_requests: map_size(state.active_requests)
    })
    
    # Schedule next health check
    schedule_health_check()
    
    {:noreply, updated_state}
  end
  
  def handle_info(:update_capabilities, state) do
    # Get updated capabilities from NodeCapabilityManager
    case NodeCapabilityManager.get_current_capabilities() do
      {:ok, capabilities} ->
        updated_state = %{state | capabilities: capabilities}
        broadcast_capability_update(updated_state)
        schedule_capability_update()
        {:noreply, updated_state}
      
      {:error, _reason} ->
        schedule_capability_update()
        {:noreply, state}
    end
  end
  
  # Private functions
  
  defp discover_coordinators do
    try do
      :pg.get_members(@coordinator_group)
      |> Enum.reject(&(&1 == self()))
      |> Enum.map(&get_coordinator_details/1)
      |> Enum.reject(&is_nil/1)
    rescue
      _ -> []
    end
  end
  
  defp get_coordinator_details(pid) do
    try do
      case GenServer.call(pid, :get_coordinator_info, 5000) do
        {:ok, info} -> info
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end
  
  defp get_coordinator_info(coordinators) do
    Enum.map(coordinators, fn coordinator ->
      %{
        coordinator_id: coordinator.coordinator_id,
        node: coordinator.node,
        capabilities: coordinator.capabilities,
        active_requests: coordinator.active_requests_count || 0,
        load_metrics: coordinator.load_metrics || %{},
        health_status: coordinator.health_status || :unknown
      }
    end)
  end
  
  defp route_request_to_best_coordinator(request, options, state) do
    # Get routing strategy from options
    strategy = Keyword.get(options, :routing_strategy, :load_balanced)
    
    case strategy do
      :local_only ->
        {:local, state.coordinator_id}
      
      :load_balanced ->
        select_best_coordinator_by_load(request, state)
      
      :capability_matched ->
        select_best_coordinator_by_capability(request, state)
      
      :round_robin ->
        select_coordinator_round_robin(state)
      
      _ ->
        {:error, {:invalid_routing_strategy, strategy}}
    end
  end
  
  defp select_best_coordinator_by_load(request, state) do
    all_coordinators = [create_local_coordinator_info(state) | state.connected_coordinators]
    
    # Score coordinators based on current load
    scored_coordinators = Enum.map(all_coordinators, fn coordinator ->
      load_score = calculate_load_score(coordinator)
      capability_score = calculate_capability_score(coordinator, request)
      total_score = load_score * 0.7 + capability_score * 0.3
      
      {coordinator, total_score}
    end)
    
    # Select coordinator with best score
    case Enum.max_by(scored_coordinators, fn {_coordinator, score} -> score end, fn -> nil end) do
      {coordinator, _score} ->
        if coordinator.node == state.node do
          {:local, coordinator.coordinator_id}
        else
          {:remote, coordinator}
        end
      
      nil ->
        {:error, :no_available_coordinators}
    end
  end
  
  defp select_best_coordinator_by_capability(request, state) do
    required_capabilities = extract_required_capabilities(request)
    all_coordinators = [create_local_coordinator_info(state) | state.connected_coordinators]
    
    # Filter coordinators that meet requirements
    suitable_coordinators = Enum.filter(all_coordinators, fn coordinator ->
      meets_capability_requirements?(coordinator.capabilities, required_capabilities)
    end)
    
    case suitable_coordinators do
      [] ->
        {:error, :no_suitable_coordinators}
      
      [coordinator] ->
        if coordinator.node == state.node do
          {:local, coordinator.coordinator_id}
        else
          {:remote, coordinator}
        end
      
      coordinators ->
        # Select least loaded among suitable coordinators
        best_coordinator = Enum.min_by(coordinators, &calculate_load_score/1)
        
        if best_coordinator.node == state.node do
          {:local, best_coordinator.coordinator_id}
        else
          {:remote, best_coordinator}
        end
    end
  end
  
  defp select_coordinator_round_robin(state) do
    all_coordinators = [create_local_coordinator_info(state) | state.connected_coordinators]
    
    case all_coordinators do
      [] ->
        {:error, :no_available_coordinators}
      
      coordinators ->
        # Simple round-robin based on timestamp
        index = rem(System.system_time(:millisecond), length(coordinators))
        coordinator = Enum.at(coordinators, index)
        
        if coordinator.node == state.node do
          {:local, coordinator.coordinator_id}
        else
          {:remote, coordinator}
        end
    end
  end
  
  defp handle_local_request(request, from, state) do
    request_id = generate_request_id()
    
    # Add to active requests
    updated_active = Map.put(state.active_requests, request_id, %{
      request: request,
      started_at: System.system_time(:millisecond),
      from: from
    })
    
    updated_state = %{state | active_requests: updated_active}
    
    # Process request asynchronously
    Task.start(fn ->
      result = process_ai_request(request)
      
      # Calculate metrics
      duration = System.system_time(:millisecond) - 
        get_in(updated_state.active_requests, [request_id, :started_at])
      
      metrics = %{
        duration_ms: duration,
        success: match?({:ok, _}, result)
      }
      
      # Reply to caller
      GenServer.reply(from, result)
      
      # Notify completion
      notify_request_completed(request_id, metrics)
    end)
    
    {:noreply, updated_state}
  end
  
  defp forward_to_remote_coordinator(request, target_coordinator, from, state) do
    # Forward request to remote coordinator
    target_pid = target_coordinator.pid
    
    if target_pid && Process.alive?(target_pid) do
      GenServer.cast(target_pid, {:remote_request, request, from})
      {:noreply, state}
    else
      {:reply, {:error, :coordinator_unavailable}, state}
    end
  end
  
  defp handle_remote_request(request, state) do
    # Process request forwarded from another coordinator
    request_id = generate_request_id()
    
    # Add to active requests tracking
    updated_active = Map.put(state.active_requests, request_id, %{
      request: request,
      started_at: System.system_time(:millisecond),
      type: :remote
    })
    
    # Process the request
    result = process_ai_request(request)
    
    # Calculate metrics
    duration = System.system_time(:millisecond) - 
      get_in(updated_active, [request_id, :started_at])
    
    metrics = %{
      duration_ms: duration,
      success: match?({:ok, _}, result)
    }
    
    # Notify completion (async)
    Task.start(fn ->
      notify_request_completed(request_id, metrics)
    end)
    
    result
  end
  
  defp process_ai_request(request) do
    # Delegate to RequestRouter for actual AI processing
    RequestRouter.process_request(request)
  end
  
  defp create_local_coordinator_info(state) do
    %{
      coordinator_id: state.coordinator_id,
      node: state.node,
      capabilities: state.capabilities,
      active_requests_count: map_size(state.active_requests),
      load_metrics: state.load_metrics,
      health_status: :healthy,
      pid: self()
    }
  end
  
  defp calculate_load_score(coordinator) do
    active_requests = coordinator.active_requests_count || 0
    max_requests = get_in(coordinator.capabilities, [:max_concurrent_requests]) || 100
    
    # Higher score is better (less loaded)
    load_ratio = active_requests / max_requests
    max(0.0, 1.0 - load_ratio)
  end
  
  defp calculate_capability_score(coordinator, request) do
    required_capabilities = extract_required_capabilities(request)
    available_capabilities = coordinator.capabilities || %{}
    
    # Simple capability matching score
    matches = Enum.count(required_capabilities, fn {key, required_value} ->
      available_value = Map.get(available_capabilities, key)
      capability_matches?(available_value, required_value)
    end)
    
    if length(required_capabilities) > 0 do
      matches / length(required_capabilities)
    else
      1.0
    end
  end
  
  defp extract_required_capabilities(request) do
    # Extract capability requirements from request
    request
    |> Map.get(:requirements, %{})
    |> Map.get(:capabilities, [])
    |> Enum.into(%{})
  end
  
  defp meets_capability_requirements?(available, required) do
    Enum.all?(required, fn {key, required_value} ->
      available_value = Map.get(available, key)
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
  
  defp build_cluster_topology(state) do
    all_coordinators = [create_local_coordinator_info(state) | state.connected_coordinators]
    
    %{
      timestamp: System.system_time(:millisecond),
      total_coordinators: length(all_coordinators),
      local_coordinator: state.coordinator_id,
      coordinators: all_coordinators,
      cluster_health: assess_cluster_health(all_coordinators),
      load_distribution: calculate_load_distribution(all_coordinators)
    }
  end
  
  defp collect_load_metrics(state) do
    %{
      timestamp: System.system_time(:millisecond),
      coordinator_id: state.coordinator_id,
      active_requests: map_size(state.active_requests),
      queue_size: :queue.len(state.request_queue),
      capabilities: state.capabilities,
      load_metrics: state.load_metrics,
      uptime_ms: System.system_time(:millisecond) - state.started_at
    }
  end
  
  defp assess_cluster_health(coordinators) do
    if length(coordinators) == 0 do
      :critical
    else
      healthy_count = Enum.count(coordinators, fn coordinator ->
        coordinator.health_status == :healthy
      end)
      
      health_ratio = healthy_count / length(coordinators)
      
      cond do
        health_ratio >= 0.8 -> :healthy
        health_ratio >= 0.5 -> :degraded
        true -> :critical
      end
    end
  end
  
  defp calculate_load_distribution(coordinators) do
    if length(coordinators) == 0 do
      %{average_load: 0.0, max_load: 0.0, min_load: 0.0}
    else
      loads = Enum.map(coordinators, fn coordinator ->
        coordinator.active_requests_count || 0
      end)
      
      %{
        average_load: Enum.sum(loads) / length(loads),
        max_load: Enum.max(loads),
        min_load: Enum.min(loads),
        total_requests: Enum.sum(loads)
      }
    end
  end
  
  defp broadcast_capability_update(state) do
    # Broadcast to all connected coordinators
    Enum.each(state.connected_coordinators, fn coordinator ->
      if coordinator.pid && Process.alive?(coordinator.pid) do
        GenServer.cast(coordinator.pid, {
          :capability_update, 
          state.coordinator_id, 
          state.capabilities
        })
      end
    end)
  end
  
  defp update_coordinator_capabilities(coordinators, coordinator_id, capabilities) do
    Enum.map(coordinators, fn coordinator ->
      if coordinator.coordinator_id == coordinator_id do
        %{coordinator | capabilities: capabilities}
      else
        coordinator
      end
    end)
  end
  
  defp update_load_metrics(current_metrics, new_metrics) do
    # Simple moving average for key metrics
    alpha = 0.1  # Smoothing factor
    
    current_avg_duration = Map.get(current_metrics, :avg_duration_ms, 0)
    new_duration = Map.get(new_metrics, :duration_ms, 0)
    updated_avg_duration = alpha * new_duration + (1 - alpha) * current_avg_duration
    
    current_success_rate = Map.get(current_metrics, :success_rate, 1.0)
    new_success = if Map.get(new_metrics, :success, false), do: 1.0, else: 0.0
    updated_success_rate = alpha * new_success + (1 - alpha) * current_success_rate
    
    %{
      avg_duration_ms: updated_avg_duration,
      success_rate: updated_success_rate,
      last_updated: System.system_time(:millisecond)
    }
  end
  
  defp perform_health_check(state) do
    # Check various health indicators
    checks = [
      {:active_requests, map_size(state.active_requests) < 1000},
      {:queue_size, :queue.len(state.request_queue) < 100},
      {:memory, check_memory_usage()},
      {:capabilities, not is_nil(state.capabilities)}
    ]
    
    failed_checks = Enum.filter(checks, fn {_name, result} -> not result end)
    
    if length(failed_checks) == 0 do
      :healthy
    else
      Logger.warning("AI coordinator health check failed: #{inspect(failed_checks)}")
      :unhealthy
    end
  end
  
  defp check_memory_usage do
    memory = :erlang.memory()
    total = memory[:total] || 0
    # Consider unhealthy if using more than 1GB
    total < 1_000_000_000
  end
  
  defp get_initial_capabilities do
    %{
      max_concurrent_requests: Application.get_env(:aiex, :ai_intelligence)[:max_concurrent_requests] || 100,
      supported_providers: [:openai, :anthropic, :ollama, :lm_studio],
      supported_models: get_available_models(),
      processing_capabilities: [:text_generation, :code_analysis, :explanation],
      memory_mb: div(:erlang.memory(:total), 1024 * 1024),
      cpu_cores: System.schedulers_online()
    }
  end
  
  defp get_available_models do
    # This would integrate with actual model availability checking
    [
      "gpt-4", "gpt-3.5-turbo", "claude-3-sonnet", "claude-3-haiku",
      "llama2", "codellama", "mistral"
    ]
  end
  
  defp schedule_coordinator_discovery do
    Process.send_after(self(), :discover_coordinators, @discovery_interval)
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
  
  defp schedule_capability_update do
    Process.send_after(self(), :update_capabilities, @capability_update_interval)
  end
  
  defp generate_coordinator_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end
end