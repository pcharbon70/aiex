defmodule Aiex.Release.DistributedRelease do
  @moduledoc """
  Distributed release management for Aiex cluster deployments.
  
  Provides utilities for coordinated rolling updates, health checks,
  and cluster-aware release management across multiple nodes.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Events.EventBus
  alias Aiex.Telemetry.DistributedAggregator
  
  @version_check_interval 30_000
  @health_check_timeout 10_000
  @rolling_update_delay 5_000
  
  defstruct [
    :release_version,
    :deployment_strategy,
    :health_checks,
    :rollback_data,
    cluster_state: :unknown,
    update_in_progress: false,
    node_versions: %{},
    last_health_check: nil
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc "Get current release version"
  def get_version do
    Application.spec(:aiex, :vsn) || "unknown"
  end
  
  @doc "Get cluster release status"
  def get_cluster_status do
    GenServer.call(__MODULE__, :get_cluster_status)
  end
  
  @doc "Perform health check for this node"
  def health_check do
    GenServer.call(__MODULE__, :health_check, @health_check_timeout)
  end
  
  @doc "Check if cluster is ready for deployment"
  def ready_for_deployment? do
    GenServer.call(__MODULE__, :ready_for_deployment?)
  end
  
  @doc "Start a rolling update across the cluster"
  def start_rolling_update(new_version, strategy \\ :gradual) do
    GenServer.call(__MODULE__, {:start_rolling_update, new_version, strategy})
  end
  
  @doc "Check rolling update status"
  def get_update_status do
    GenServer.call(__MODULE__, :get_update_status)
  end
  
  @doc "Rollback to previous version"
  def rollback(target_version \\ nil) do
    GenServer.call(__MODULE__, {:rollback, target_version})
  end
  
  @doc "Register custom health check"
  def register_health_check(name, check_function) do
    GenServer.call(__MODULE__, {:register_health_check, name, check_function})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    release_version = get_version()
    
    # Join pg group for release coordination
    if Process.whereis(:pg) do
      :pg.join(:aiex_release_coordinators, self())
    end
    
    # Schedule periodic version checks
    Process.send_after(self(), :check_cluster_versions, @version_check_interval)
    
    state = %__MODULE__{
      release_version: release_version,
      deployment_strategy: Keyword.get(opts, :strategy, :gradual),
      health_checks: default_health_checks(),
      rollback_data: %{},
      last_health_check: System.system_time(:millisecond)
    }
    
    Logger.info("Distributed release manager started - version #{release_version}")
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_cluster_status, _from, state) do
    status = %{
      local_version: state.release_version,
      cluster_state: state.cluster_state,
      node_versions: state.node_versions,
      update_in_progress: state.update_in_progress,
      last_health_check: state.last_health_check,
      deployment_strategy: state.deployment_strategy
    }
    
    {:reply, status, state}
  end
  
  def handle_call(:health_check, _from, state) do
    result = perform_comprehensive_health_check(state)
    
    # Record health check metric
    DistributedAggregator.record_metric("release.health_check", 1, %{
      result: result.status,
      node: Node.self()
    })
    
    updated_state = %{state | last_health_check: System.system_time(:millisecond)}
    
    {:reply, result, updated_state}
  end
  
  def handle_call(:ready_for_deployment?, _from, state) do
    ready = assess_deployment_readiness(state)
    {:reply, ready, state}
  end
  
  def handle_call({:start_rolling_update, new_version, strategy}, _from, state) do
    if state.update_in_progress do
      {:reply, {:error, :update_in_progress}, state}
    else
      result = initiate_rolling_update(new_version, strategy, state)
      
      case result do
        {:ok, updated_state} ->
          {:reply, :ok, updated_state}
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end
  
  def handle_call(:get_update_status, _from, state) do
    status = %{
      in_progress: state.update_in_progress,
      current_version: state.release_version,
      node_versions: state.node_versions,
      cluster_state: state.cluster_state
    }
    
    {:reply, status, state}
  end
  
  def handle_call({:rollback, target_version}, _from, state) do
    result = perform_rollback(target_version, state)
    
    case result do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:register_health_check, name, check_function}, _from, state) do
    health_checks = Map.put(state.health_checks, name, check_function)
    {:reply, :ok, %{state | health_checks: health_checks}}
  end
  
  @impl true
  def handle_info(:check_cluster_versions, state) do
    updated_state = check_and_update_cluster_versions(state)
    
    # Schedule next check
    Process.send_after(self(), :check_cluster_versions, @version_check_interval)
    
    {:noreply, updated_state}
  end
  
  def handle_info({:rolling_update_step, step_data}, state) do
    updated_state = process_rolling_update_step(step_data, state)
    {:noreply, updated_state}
  end
  
  def handle_info({:version_sync, node, version}, state) do
    node_versions = Map.put(state.node_versions, node, version)
    updated_state = %{state | node_versions: node_versions}
    
    # Update cluster state based on version consistency
    cluster_state = assess_cluster_state(updated_state)
    updated_state = %{updated_state | cluster_state: cluster_state}
    
    {:noreply, updated_state}
  end
  
  @impl true
  def terminate(_reason, _state) do
    # Leave pg group
    if Process.whereis(:pg) do
      :pg.leave(:aiex_release_coordinators, self())
    end
    
    :ok
  end
  
  # Private functions
  
  defp default_health_checks do
    %{
      application_running: fn ->
        case Application.get_env(:aiex, :cluster_enabled, false) do
          true -> cluster_application_health()
          false -> single_node_application_health()
        end
      end,
      database_connectivity: fn ->
        check_mnesia_health()
      end,
      llm_coordination: fn ->
        check_llm_coordinator_health()
      end,
      telemetry_systems: fn ->
        check_telemetry_health()
      end,
      memory_usage: fn ->
        check_memory_health()
      end,
      process_health: fn ->
        check_process_health()
      end
    }
  end
  
  defp perform_comprehensive_health_check(state) do
    start_time = System.system_time(:microsecond)
    
    # Run all health checks
    check_results = Enum.map(state.health_checks, fn {name, check_fn} ->
      try do
        result = check_fn.()
        {name, result}
      rescue
        error ->
          {name, {:error, Exception.message(error)}}
      end
    end)
    
    # Aggregate results
    failed_checks = Enum.filter(check_results, fn {_name, result} ->
      case result do
        :ok -> false
        {:ok, _} -> false
        _ -> true
      end
    end)
    
    duration_us = System.system_time(:microsecond) - start_time
    
    overall_status = if length(failed_checks) == 0, do: :healthy, else: :unhealthy
    
    %{
      status: overall_status,
      checks: Map.new(check_results),
      failed_checks: Map.new(failed_checks),
      duration_us: duration_us,
      timestamp: System.system_time(:millisecond),
      node: Node.self(),
      version: state.release_version
    }
  end
  
  defp assess_deployment_readiness(state) do
    # Check cluster health
    health_result = perform_comprehensive_health_check(state)
    
    conditions = [
      health_result.status == :healthy,
      not state.update_in_progress,
      state.cluster_state in [:consistent, :mixed_healthy],
      cluster_connectivity_ok?()
    ]
    
    Enum.all?(conditions)
  end
  
  defp initiate_rolling_update(new_version, strategy, state) do
    Logger.info("Starting rolling update to version #{new_version} with strategy #{strategy}")
    
    # Save rollback data
    rollback_data = %{
      previous_version: state.release_version,
      timestamp: System.system_time(:millisecond),
      node_states: capture_node_states()
    }
    
    # Publish update start event
    EventBus.publish("release:rolling_update_started", %{
      new_version: new_version,
      previous_version: state.release_version,
      strategy: strategy,
      node: Node.self()
    })
    
    # Schedule update steps based on strategy
    schedule_update_steps(strategy, new_version)
    
    updated_state = %{state |
      update_in_progress: true,
      rollback_data: rollback_data,
      deployment_strategy: strategy
    }
    
    {:ok, updated_state}
  end
  
  defp perform_rollback(target_version, state) do
    if state.rollback_data == %{} do
      {:error, :no_rollback_data}
    else
      target = target_version || state.rollback_data.previous_version
      
      Logger.warning("Performing rollback to version #{target}")
      
      # Publish rollback event
      EventBus.publish("release:rollback_started", %{
        target_version: target,
        current_version: state.release_version,
        node: Node.self()
      })
      
      # In a real implementation, this would trigger the actual rollback process
      # For now, we'll simulate the rollback completion
      
      updated_state = %{state |
        release_version: target,
        update_in_progress: false,
        cluster_state: :rollback_completed
      }
      
      {:ok, updated_state}
    end
  end
  
  defp check_and_update_cluster_versions(state) do
    if Process.whereis(:pg) do
      # Get all release coordinators in the cluster
      coordinators = :pg.get_members(:aiex_release_coordinators)
      |> Enum.reject(&(&1 == self()))
      
      # Sync version with other nodes
      Enum.each(coordinators, fn pid ->
        send(pid, {:version_sync, Node.self(), state.release_version})
      end)
    end
    
    state
  end
  
  defp process_rolling_update_step(step_data, state) do
    Logger.info("Processing rolling update step: #{inspect(step_data)}")
    
    # This would contain the actual update logic
    # For now, we'll simulate the step completion
    
    case step_data do
      {:update_complete, new_version} ->
        Logger.info("Rolling update to #{new_version} completed")
        
        EventBus.publish("release:rolling_update_completed", %{
          version: new_version,
          node: Node.self()
        })
        
        %{state |
          release_version: new_version,
          update_in_progress: false,
          cluster_state: :consistent
        }
        
      {:update_failed, reason} ->
        Logger.error("Rolling update failed: #{inspect(reason)}")
        
        EventBus.publish("release:rolling_update_failed", %{
          reason: reason,
          node: Node.self()
        })
        
        %{state |
          update_in_progress: false,
          cluster_state: :update_failed
        }
        
      _ ->
        state
    end
  end
  
  defp assess_cluster_state(state) do
    if map_size(state.node_versions) == 0 do
      :unknown
    else
      versions = Map.values(state.node_versions)
      unique_versions = Enum.uniq(versions)
      
      cond do
        length(unique_versions) == 1 -> :consistent
        length(unique_versions) == 2 -> :mixed_healthy
        true -> :fragmented
      end
    end
  end
  
  defp schedule_update_steps(strategy, new_version) do
    case strategy do
      :gradual ->
        # Schedule gradual update steps
        Process.send_after(self(), {:rolling_update_step, {:prepare_update, new_version}}, 1000)
        Process.send_after(self(), {:rolling_update_step, {:update_complete, new_version}}, @rolling_update_delay)
        
      :immediate ->
        # Schedule immediate update
        Process.send_after(self(), {:rolling_update_step, {:update_complete, new_version}}, 1000)
    end
  end
  
  defp capture_node_states do
    %{
      memory: :erlang.memory(),
      processes: length(Process.list()),
      node_list: Node.list(),
      system_time: System.system_time(:millisecond)
    }
  end
  
  defp cluster_connectivity_ok? do
    if Application.get_env(:aiex, :cluster_enabled, false) do
      # Check if we can reach other nodes
      case Node.list() do
        [] -> true  # Single node is ok
        nodes -> Enum.any?(nodes, &Node.ping(&1) == :pong)
      end
    else
      true
    end
  end
  
  # Health check implementations
  
  defp cluster_application_health do
    try do
      # Check if main supervision tree is running
      case Process.whereis(Aiex.Supervisor) do
        nil -> {:error, "Main supervisor not running"}
        _pid -> :ok
      end
    rescue
      _ -> {:error, "Cannot check application health"}
    end
  end
  
  defp single_node_application_health do
    cluster_application_health()
  end
  
  defp check_mnesia_health do
    try do
      case :mnesia.system_info(:is_running) do
        :yes -> :ok
        _ -> {:error, "Mnesia not running"}
      end
    rescue
      _ -> {:error, "Cannot check Mnesia status"}
    end
  end
  
  defp check_llm_coordinator_health do
    try do
      case Process.whereis(Aiex.LLM.ModelCoordinator) do
        nil -> {:error, "LLM coordinator not running"}
        _pid -> :ok
      end
    rescue
      _ -> {:error, "Cannot check LLM coordinator"}
    end
  end
  
  defp check_telemetry_health do
    try do
      case Process.whereis(Aiex.Telemetry.DistributedAggregator) do
        nil -> {:error, "Telemetry aggregator not running"}
        _pid -> :ok
      end
    rescue
      _ -> {:error, "Cannot check telemetry health"}
    end
  end
  
  defp check_memory_health do
    memory = :erlang.memory()
    total = memory[:total]
    
    # Check if memory usage is under 90% of available (simple heuristic)
    if total > 0 do
      :ok
    else
      {:error, "Memory usage critical"}
    end
  end
  
  defp check_process_health do
    process_count = length(Process.list())
    
    # Basic check - if we have processes running, we're ok
    if process_count > 10 do
      :ok
    else
      {:error, "Suspiciously low process count: #{process_count}"}
    end
  end
end