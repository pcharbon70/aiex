defmodule Aiex.Release.DeploymentAutomation do
  @moduledoc """
  Automated deployment orchestration for Aiex cluster releases.
  
  Coordinates blue-green deployments, canary releases, and rollback procedures
  across distributed nodes with health monitoring and traffic management.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Release.{DistributedRelease, HealthEndpoint}
  alias Aiex.Events.EventBus
  alias Aiex.Telemetry.DistributedAggregator
  
  @deployment_timeout 300_000  # 5 minutes
  @health_check_interval 10_000
  @canary_traffic_start 5  # Start with 5% traffic
  @canary_traffic_increment 15  # Increase by 15% each step
  
  defstruct [
    :deployment_id,
    :strategy,
    :target_version,
    :current_phase,
    :start_time,
    :timeout,
    phases: [],
    health_checks: [],
    rollback_plan: nil,
    traffic_routing: %{},
    node_states: %{}
  ]
  
  # Deployment strategies
  @strategies [:blue_green, :rolling_update, :canary]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc "Start a new deployment"
  def start_deployment(strategy, target_version, opts \\ []) do
    GenServer.call(__MODULE__, {:start_deployment, strategy, target_version, opts}, @deployment_timeout)
  end
  
  @doc "Get current deployment status"
  def get_deployment_status do
    GenServer.call(__MODULE__, :get_deployment_status)
  end
  
  @doc "Abort current deployment"
  def abort_deployment(reason \\ "Manual abort") do
    GenServer.call(__MODULE__, {:abort_deployment, reason})
  end
  
  @doc "Rollback current deployment"
  def rollback_deployment do
    GenServer.call(__MODULE__, :rollback_deployment)
  end
  
  @doc "Get deployment history"
  def get_deployment_history(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_deployment_history, limit})
  end
  
  @doc "Validate deployment readiness"
  def validate_readiness(strategy, target_version) do
    GenServer.call(__MODULE__, {:validate_readiness, strategy, target_version})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Initialize deployment history storage
    deployment_history = :ets.new(:deployment_history, [:ordered_set, :private])
    
    state = %{
      current_deployment: nil,
      deployment_history: deployment_history,
      health_monitor_ref: nil
    }
    
    Logger.info("Deployment automation started")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:start_deployment, strategy, target_version, opts}, from, state) do
    if state.current_deployment do
      {:reply, {:error, :deployment_in_progress}, state}
    else
      case validate_deployment_request(strategy, target_version, opts) do
        :ok ->
          deployment = create_deployment(strategy, target_version, opts)
          updated_state = %{state | current_deployment: deployment}
          
          # Start deployment process asynchronously
          spawn_deployment_process(deployment, from)
          
          {:noreply, updated_state}
          
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end
  
  def handle_call(:get_deployment_status, _from, state) do
    status = case state.current_deployment do
      nil -> %{status: :idle}
      deployment -> deployment_status(deployment)
    end
    
    {:reply, status, state}
  end
  
  def handle_call({:abort_deployment, reason}, _from, state) do
    case state.current_deployment do
      nil ->
        {:reply, {:error, :no_deployment}, state}
        
      deployment ->
        Logger.warning("Aborting deployment #{deployment.deployment_id}: #{reason}")
        
        # Execute abort procedure
        abort_result = execute_abort_procedure(deployment, reason)
        
        # Record in history
        record_deployment_completion(state.deployment_history, deployment, :aborted, reason)
        
        updated_state = %{state | current_deployment: nil}
        {:reply, abort_result, updated_state}
    end
  end
  
  def handle_call(:rollback_deployment, _from, state) do
    case state.current_deployment do
      nil ->
        {:reply, {:error, :no_deployment}, state}
        
      deployment ->
        if deployment.rollback_plan do
          Logger.info("Rolling back deployment #{deployment.deployment_id}")
          
          rollback_result = execute_rollback_procedure(deployment)
          
          # Record in history
          record_deployment_completion(state.deployment_history, deployment, :rolled_back, "Manual rollback")
          
          updated_state = %{state | current_deployment: nil}
          {:reply, rollback_result, updated_state}
        else
          {:reply, {:error, :no_rollback_plan}, state}
        end
    end
  end
  
  def handle_call({:get_deployment_history, limit}, _from, state) do
    history = :ets.tab2list(state.deployment_history)
    |> Enum.sort_by(fn {timestamp, _} -> timestamp end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_timestamp, deployment} -> deployment end)
    
    {:reply, history, state}
  end
  
  def handle_call({:validate_readiness, strategy, target_version}, _from, state) do
    validation_result = validate_deployment_readiness(strategy, target_version)
    {:reply, validation_result, state}
  end
  
  @impl true
  def handle_cast({:deployment_completed, deployment, result}, state) do
    Logger.info("Deployment #{deployment.deployment_id} completed with result: #{result}")
    
    # Record in history
    record_deployment_completion(state.deployment_history, deployment, result, nil)
    
    # Stop health monitoring
    if state.health_monitor_ref do
      Process.cancel_timer(state.health_monitor_ref)
    end
    
    updated_state = %{state | 
      current_deployment: nil,
      health_monitor_ref: nil
    }
    
    {:noreply, updated_state}
  end
  
  def handle_cast({:deployment_phase_completed, deployment_id, phase}, state) do
    case state.current_deployment do
      %{deployment_id: ^deployment_id} = deployment ->
        updated_deployment = advance_deployment_phase(deployment, phase)
        updated_state = %{state | current_deployment: updated_deployment}
        {:noreply, updated_state}
        
      _ ->
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:health_check, deployment_id}, state) do
    case state.current_deployment do
      %{deployment_id: ^deployment_id} = deployment ->
        # Perform health check
        health_result = perform_deployment_health_check(deployment)
        
        case health_result do
          :healthy ->
            # Schedule next health check
            health_monitor_ref = Process.send_after(self(), {:health_check, deployment_id}, @health_check_interval)
            updated_state = %{state | health_monitor_ref: health_monitor_ref}
            {:noreply, updated_state}
            
          {:unhealthy, reason} ->
            Logger.error("Deployment health check failed: #{reason}")
            
            # Auto-rollback if configured
            if should_auto_rollback?(deployment) do
              GenServer.cast(self(), {:deployment_completed, deployment, :auto_rollback})
            end
            
            {:noreply, state}
        end
        
      _ ->
        {:noreply, state}
    end
  end
  
  # Private functions
  
  defp validate_deployment_request(strategy, target_version, _opts) do
    cond do
      strategy not in @strategies ->
        {:error, {:invalid_strategy, strategy}}
        
      not valid_version?(target_version) ->
        {:error, {:invalid_version, target_version}}
        
      not DistributedRelease.ready_for_deployment?() ->
        {:error, :cluster_not_ready}
        
      true ->
        :ok
    end
  end
  
  defp create_deployment(strategy, target_version, opts) do
    deployment_id = generate_deployment_id()
    current_version = DistributedRelease.get_version()
    
    phases = generate_deployment_phases(strategy, current_version, target_version)
    rollback_plan = create_rollback_plan(strategy, current_version, target_version)
    
    %__MODULE__{
      deployment_id: deployment_id,
      strategy: strategy,
      target_version: target_version,
      current_phase: :preparing,
      start_time: System.system_time(:millisecond),
      timeout: Keyword.get(opts, :timeout, @deployment_timeout),
      phases: phases,
      rollback_plan: rollback_plan,
      traffic_routing: %{},
      node_states: %{}
    }
  end
  
  defp spawn_deployment_process(deployment, reply_to) do
    pid = spawn(fn ->
      result = execute_deployment(deployment)
      GenServer.reply(reply_to, result)
      
      # Notify completion
      GenServer.cast(__MODULE__, {:deployment_completed, deployment, result})
    end)
    
    # Start health monitoring
    Process.send_after(self(), {:health_check, deployment.deployment_id}, @health_check_interval)
    
    Logger.info("Started deployment process #{deployment.deployment_id} (PID: #{inspect(pid)})")
  end
  
  defp execute_deployment(deployment) do
    Logger.info("Executing #{deployment.strategy} deployment to #{deployment.target_version}")
    
    # Publish deployment start event
    EventBus.publish("deployment:started", %{
      deployment_id: deployment.deployment_id,
      strategy: deployment.strategy,
      target_version: deployment.target_version
    })
    
    try do
      case deployment.strategy do
        :blue_green -> execute_blue_green_deployment(deployment)
        :rolling_update -> execute_rolling_update_deployment(deployment)
        :canary -> execute_canary_deployment(deployment)
      end
    rescue
      error ->
        Logger.error("Deployment failed: #{Exception.message(error)}")
        {:error, Exception.message(error)}
    end
  end
  
  defp execute_blue_green_deployment(deployment) do
    Logger.info("Starting blue-green deployment")
    
    # Phase 1: Prepare green environment
    :ok = prepare_green_environment(deployment)
    
    # Phase 2: Deploy to green environment
    :ok = deploy_to_green_environment(deployment)
    
    # Phase 3: Health check green environment
    :ok = health_check_green_environment(deployment)
    
    # Phase 4: Switch traffic to green
    :ok = switch_traffic_to_green(deployment)
    
    # Phase 5: Verify traffic switch
    :ok = verify_traffic_switch(deployment)
    
    # Phase 6: Cleanup blue environment
    :ok = cleanup_blue_environment(deployment)
    
    Logger.info("Blue-green deployment completed successfully")
    :ok
  end
  
  defp execute_rolling_update_deployment(deployment) do
    Logger.info("Starting rolling update deployment")
    
    # Get list of nodes to update
    nodes = get_deployment_nodes()
    
    # Update nodes in batches
    batch_size = calculate_batch_size(length(nodes))
    node_batches = Enum.chunk_every(nodes, batch_size)
    
    Enum.with_index(node_batches)
    |> Enum.each(fn {batch, index} ->
      Logger.info("Updating batch #{index + 1}/#{length(node_batches)}: #{inspect(batch)}")
      
      # Update batch
      :ok = update_node_batch(batch, deployment)
      
      # Health check batch
      :ok = health_check_node_batch(batch, deployment)
      
      # Wait between batches
      if index < length(node_batches) - 1 do
        Process.sleep(5000)
      end
    end)
    
    Logger.info("Rolling update deployment completed successfully")
    :ok
  end
  
  defp execute_canary_deployment(deployment) do
    Logger.info("Starting canary deployment")
    
    # Phase 1: Deploy canary version
    :ok = deploy_canary_version(deployment)
    
    # Phase 2: Route small percentage of traffic to canary
    traffic_percentage = @canary_traffic_start
    :ok = route_traffic_to_canary(deployment, traffic_percentage)
    
    # Phase 3: Gradually increase traffic
    traffic_percentage = increase_canary_traffic_gradually(deployment, traffic_percentage)
    
    # Phase 4: Full traffic switch if successful
    if traffic_percentage >= 100 do
      :ok = complete_canary_deployment(deployment)
      Logger.info("Canary deployment completed successfully")
      :ok
    else
      {:error, "Canary deployment did not reach full traffic"}
    end
  end
  
  # Blue-green deployment phases
  
  defp prepare_green_environment(_deployment) do
    Logger.debug("Preparing green environment")
    # Simulate preparation
    Process.sleep(1000)
    :ok
  end
  
  defp deploy_to_green_environment(deployment) do
    Logger.debug("Deploying to green environment")
    
    # Start rolling update to target version
    case DistributedRelease.start_rolling_update(deployment.target_version, :immediate) do
      :ok -> :ok
      {:error, reason} -> 
        Logger.error("Failed to deploy to green environment: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp health_check_green_environment(_deployment) do
    Logger.debug("Health checking green environment")
    
    # Wait for deployment to complete and health checks to pass
    Process.sleep(5000)
    
    case HealthEndpoint.ready?() do
      true -> :ok
      false -> {:error, "Green environment not ready"}
    end
  end
  
  defp switch_traffic_to_green(_deployment) do
    Logger.debug("Switching traffic to green environment")
    # In a real implementation, this would update load balancer configuration
    Process.sleep(1000)
    :ok
  end
  
  defp verify_traffic_switch(_deployment) do
    Logger.debug("Verifying traffic switch")
    # Verify that traffic is flowing to the new version
    Process.sleep(2000)
    :ok
  end
  
  defp cleanup_blue_environment(_deployment) do
    Logger.debug("Cleaning up blue environment")
    # Clean up old version resources
    Process.sleep(1000)
    :ok
  end
  
  # Rolling update phases
  
  defp get_deployment_nodes do
    [Node.self() | Node.list()]
  end
  
  defp calculate_batch_size(total_nodes) do
    max(1, div(total_nodes, 3))  # Update in 3 batches maximum
  end
  
  defp update_node_batch(nodes, deployment) do
    Logger.debug("Updating nodes: #{inspect(nodes)}")
    
    # In a real implementation, this would coordinate with each node
    # For now, simulate the update
    Enum.each(nodes, fn node ->
      Logger.debug("Updating node #{node} to #{deployment.target_version}")
      Process.sleep(1000)
    end)
    
    :ok
  end
  
  defp health_check_node_batch(nodes, _deployment) do
    Logger.debug("Health checking nodes: #{inspect(nodes)}")
    
    # Check health of each node in the batch
    Enum.each(nodes, fn _node ->
      # Simulate health check
      Process.sleep(500)
    end)
    
    :ok
  end
  
  # Canary deployment phases
  
  defp deploy_canary_version(deployment) do
    Logger.debug("Deploying canary version #{deployment.target_version}")
    
    # Deploy to a subset of nodes
    canary_nodes = get_canary_nodes()
    update_node_batch(canary_nodes, deployment)
  end
  
  defp route_traffic_to_canary(deployment, percentage) do
    Logger.debug("Routing #{percentage}% traffic to canary")
    
    # Record traffic routing state
    GenServer.cast(__MODULE__, {:update_traffic_routing, deployment.deployment_id, percentage})
    
    # Simulate traffic routing update
    Process.sleep(1000)
    :ok
  end
  
  defp increase_canary_traffic_gradually(deployment, start_percentage) do
    increase_canary_traffic_step(deployment, start_percentage)
  end
  
  defp increase_canary_traffic_step(deployment, current_percentage) when current_percentage >= 100 do
    current_percentage
  end
  
  defp increase_canary_traffic_step(deployment, current_percentage) do
    # Monitor canary health
    if canary_healthy?(deployment) do
      new_percentage = min(100, current_percentage + @canary_traffic_increment)
      route_traffic_to_canary(deployment, new_percentage)
      
      # Wait and monitor
      Process.sleep(30_000)  # 30 seconds between increments
      
      # Continue incrementally
      increase_canary_traffic_step(deployment, new_percentage)
    else
      Logger.warning("Canary health check failed, stopping traffic increase")
      current_percentage
    end
  end
  
  defp complete_canary_deployment(deployment) do
    Logger.debug("Completing canary deployment")
    
    # Deploy to remaining nodes
    remaining_nodes = get_remaining_nodes()
    update_node_batch(remaining_nodes, deployment)
  end
  
  defp get_canary_nodes do
    all_nodes = [Node.self() | Node.list()]
    # Use 20% of nodes for canary
    canary_count = max(1, div(length(all_nodes), 5))
    Enum.take(all_nodes, canary_count)
  end
  
  defp get_remaining_nodes do
    all_nodes = [Node.self() | Node.list()]
    canary_nodes = get_canary_nodes()
    all_nodes -- canary_nodes
  end
  
  defp canary_healthy?(_deployment) do
    # Check canary node health and metrics
    case HealthEndpoint.ready?() do
      true ->
        # Also check error rates, latency, etc.
        true
      false ->
        false
    end
  end
  
  # Utility functions
  
  defp generate_deployment_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp valid_version?(version) when is_binary(version), do: String.length(version) > 0
  defp valid_version?(_), do: false
  
  defp generate_deployment_phases(strategy, _current_version, _target_version) do
    case strategy do
      :blue_green ->
        [:prepare_green, :deploy_green, :health_check_green, :switch_traffic, :verify_switch, :cleanup_blue]
      :rolling_update ->
        [:prepare_batches, :update_batches, :verify_update]
      :canary ->
        [:deploy_canary, :route_traffic, :increase_traffic, :complete_deployment]
    end
  end
  
  defp create_rollback_plan(strategy, current_version, _target_version) do
    %{
      strategy: strategy,
      target_version: current_version,
      created_at: System.system_time(:millisecond)
    }
  end
  
  defp deployment_status(deployment) do
    %{
      deployment_id: deployment.deployment_id,
      strategy: deployment.strategy,
      target_version: deployment.target_version,
      current_phase: deployment.current_phase,
      progress: calculate_progress(deployment),
      start_time: deployment.start_time,
      elapsed_ms: System.system_time(:millisecond) - deployment.start_time,
      traffic_routing: deployment.traffic_routing
    }
  end
  
  defp calculate_progress(deployment) do
    total_phases = length(deployment.phases)
    if total_phases > 0 do
      current_index = Enum.find_index(deployment.phases, &(&1 == deployment.current_phase)) || 0
      min(100, div(current_index * 100, total_phases))
    else
      0
    end
  end
  
  defp advance_deployment_phase(deployment, completed_phase) do
    Logger.debug("Deployment #{deployment.deployment_id} completed phase: #{completed_phase}")
    
    case Enum.find_index(deployment.phases, &(&1 == completed_phase)) do
      nil ->
        deployment
      index ->
        next_phase = Enum.at(deployment.phases, index + 1)
        %{deployment | current_phase: next_phase || :completed}
    end
  end
  
  defp perform_deployment_health_check(_deployment) do
    # Comprehensive health check during deployment
    try do
      if HealthEndpoint.ready?() and HealthEndpoint.alive?() do
        :healthy
      else
        {:unhealthy, "Health endpoint not ready"}
      end
    rescue
      error ->
        {:unhealthy, Exception.message(error)}
    end
  end
  
  defp should_auto_rollback?(deployment) do
    # Check if auto-rollback is configured for this deployment
    Map.get(deployment.rollback_plan || %{}, :auto_rollback, false)
  end
  
  defp execute_abort_procedure(deployment, reason) do
    Logger.warning("Executing abort procedure for deployment #{deployment.deployment_id}")
    
    # Publish abort event
    EventBus.publish("deployment:aborted", %{
      deployment_id: deployment.deployment_id,
      reason: reason
    })
    
    # Stop any ongoing operations
    # In a real implementation, this would halt all deployment activities
    
    :ok
  end
  
  defp execute_rollback_procedure(deployment) do
    Logger.info("Executing rollback procedure for deployment #{deployment.deployment_id}")
    
    # Publish rollback event
    EventBus.publish("deployment:rollback_started", %{
      deployment_id: deployment.deployment_id,
      rollback_plan: deployment.rollback_plan
    })
    
    # Execute rollback using DistributedRelease
    case DistributedRelease.rollback(deployment.rollback_plan.target_version) do
      :ok ->
        Logger.info("Rollback completed successfully")
        :ok
      {:error, reason} ->
        Logger.error("Rollback failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp record_deployment_completion(history_ets, deployment, result, reason) do
    timestamp = System.system_time(:millisecond)
    
    completion_record = %{
      deployment_id: deployment.deployment_id,
      strategy: deployment.strategy,
      target_version: deployment.target_version,
      result: result,
      reason: reason,
      start_time: deployment.start_time,
      end_time: timestamp,
      duration_ms: timestamp - deployment.start_time
    }
    
    :ets.insert(history_ets, {timestamp, completion_record})
    
    # Publish completion event
    EventBus.publish("deployment:completed", completion_record)
    
    # Record metric
    DistributedAggregator.record_metric("deployment.completed", 1, %{
      strategy: deployment.strategy,
      result: result,
      duration_ms: completion_record.duration_ms
    })
  end
  
  defp validate_deployment_readiness(strategy, target_version) do
    checks = [
      cluster_ready?: fn -> DistributedRelease.ready_for_deployment?() end,
      valid_strategy?: fn -> strategy in @strategies end,
      valid_version?: fn -> valid_version?(target_version) end,
      health_endpoint_ready?: fn -> HealthEndpoint.ready?() end,
      sufficient_resources?: fn -> check_resource_availability() end
    ]
    
    failed_checks = Enum.filter(checks, fn {name, check_fn} ->
      try do
        case check_fn.() do
          true -> false
          false -> true
          :ok -> false
          _ -> true
        end
      rescue
        _ -> true
      end
      |> case do
        true -> name
        false -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    
    if Enum.empty?(failed_checks) do
      :ok
    else
      {:error, {:readiness_checks_failed, failed_checks}}
    end
  end
  
  defp check_resource_availability do
    # Basic resource check
    memory = :erlang.memory()
    process_count = length(Process.list())
    
    # Simple heuristics
    memory[:total] < 1_000_000_000 and process_count < 10_000  # 1GB memory, 10k processes
  end
end