defmodule Aiex.LLM.ModelCoordinator do
  @moduledoc """
  Distributed coordination for LLM providers using pg process groups.

  This module manages provider selection, load balancing, and health monitoring
  across multiple nodes in the cluster, providing intelligent failover and
  affinity-based routing for optimal performance.
  """

  use GenServer
  require Logger

  @pg_scope :llm_coordination
  @health_check_interval 30_000
  @provider_timeout 5_000

  defstruct [
    :node,
    :providers,
    :provider_health,
    :node_affinity,
    :load_balancer_state
  ]

  @type provider_info :: %{
    adapter: module(),
    config: map(),
    health: :healthy | :degraded | :unhealthy,
    last_check: DateTime.t(),
    local_affinity: boolean(),
    load_score: float()
  }

  @type t :: %__MODULE__{
    node: node(),
    providers: %{atom() => provider_info()},
    provider_health: %{atom() => :healthy | :degraded | :unhealthy},
    node_affinity: %{atom() => [node()]},
    load_balancer_state: map()
  }

  ## Client API

  @doc """
  Starts the model coordinator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Selects the best available provider for a request.
  """
  @spec select_provider(map(), keyword()) :: {:ok, {atom(), module()}} | {:error, any()}
  def select_provider(request, opts \\ []) do
    GenServer.call(__MODULE__, {:select_provider, request, opts}, @provider_timeout)
  end

  @doc """
  Reports the result of an LLM request for load balancing.
  """
  @spec report_request_result(atom(), :success | :error, map()) :: :ok
  def report_request_result(provider, result, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:request_result, provider, result, metadata})
  end

  @doc """
  Gets the current status of all providers across the cluster.
  """
  @spec get_cluster_status() :: %{node() => %{atom() => provider_info()}}
  def get_cluster_status do
    GenServer.call(__MODULE__, :get_cluster_status)
  end

  @doc """
  Forces a health check of all providers.
  """
  @spec force_health_check() :: :ok
  def force_health_check do
    GenServer.cast(__MODULE__, :force_health_check)
  end

  @doc """
  Registers a new provider or updates an existing one.
  """
  @spec register_provider(atom(), module(), map()) :: :ok
  def register_provider(name, adapter, config) do
    GenServer.call(__MODULE__, {:register_provider, name, adapter, config})
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Join the LLM coordination process group
    # pg should be started automatically by OTP
    # Skip pg coordination for now - will implement later
    # :pg.join(@pg_scope, :model_coordinators, self())
    
    # Initialize providers from config
    providers = initialize_providers(opts)
    
    # Schedule initial health check
    schedule_health_check()
    
    state = %__MODULE__{
      node: node(),
      providers: providers,
      provider_health: %{},
      node_affinity: %{},
      load_balancer_state: %{
        request_counts: %{},
        response_times: %{},
        error_rates: %{}
      }
    }

    Logger.info("LLM Model Coordinator started on node #{node()}")
    {:ok, state}
  end

  @impl true
  def handle_call({:select_provider, request, opts}, _from, state) do
    case select_optimal_provider(request, opts, state) do
      {:ok, {provider, _adapter}} = result ->
        # Update load balancing metrics
        new_state = update_request_metrics(provider, state)
        {:reply, result, new_state}
      
      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:register_provider, name, adapter, config}, _from, state) do
    provider_info = %{
      adapter: adapter,
      config: config,
      health: :healthy,
      last_check: DateTime.utc_now(),
      local_affinity: is_local_provider?(adapter),
      load_score: 0.0
    }

    new_providers = Map.put(state.providers, name, provider_info)
    new_state = %{state | providers: new_providers}

    # Broadcast provider registration to cluster
    broadcast_provider_update(name, :registered, provider_info)

    Logger.info("Registered LLM provider: #{name} (#{adapter})")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_cluster_status, _from, state) do
    # Collect status from all nodes
    cluster_status = collect_cluster_status(state)
    {:reply, cluster_status, state}
  end

  @impl true
  def handle_cast({:request_result, provider, result, metadata}, state) do
    new_state = update_provider_metrics(provider, result, metadata, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:force_health_check, state) do
    new_state = perform_health_checks(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:provider_update, node, provider, action, info}, state) do
    # Handle provider updates from other nodes
    new_state = handle_remote_provider_update(node, provider, action, info, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_checks(state)
    schedule_health_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:pg_notify, @pg_scope, :model_coordinators, {from_node, message}}, state) do
    if from_node != node() do
      new_state = handle_pg_message(message, state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  ## Private Functions

  defp initialize_providers(opts) do
    # Load provider configurations
    configured_providers = Keyword.get(opts, :providers, default_providers())
    
    Enum.into(configured_providers, %{}, fn {name, {adapter, config}} ->
      {name, %{
        adapter: adapter,
        config: config,
        health: :healthy,
        last_check: DateTime.utc_now(),
        local_affinity: is_local_provider?(adapter),
        load_score: 0.0
      }}
    end)
  end

  defp default_providers do
    [
      {:openai, {Aiex.LLM.Adapters.OpenAI, %{}}},
      {:anthropic, {Aiex.LLM.Adapters.Anthropic, %{}}},
      {:ollama, {Aiex.LLM.Adapters.Ollama, %{}}},
      {:lm_studio, {Aiex.LLM.Adapters.LMStudio, %{}}}
    ]
  end

  defp is_local_provider?(adapter) do
    # Local providers have better affinity for their hosting node
    adapter in [Aiex.LLM.Adapters.Ollama, Aiex.LLM.Adapters.LMStudio]
  end

  defp select_optimal_provider(request, opts, state) do
    # Get provider preferences from request or options
    preferred_providers = Keyword.get(opts, :providers, Map.keys(state.providers))
    model = Map.get(request, :model)
    
    # Filter available providers
    available_providers = 
      preferred_providers
      |> Enum.filter(&Map.has_key?(state.providers, &1))
      |> Enum.filter(&provider_healthy?(&1, state))
      |> Enum.filter(&supports_model?(&1, model, state))

    case available_providers do
      [] ->
        {:error, :no_available_providers}
      
      providers ->
        # Select based on load balancing strategy
        strategy = Keyword.get(opts, :selection_strategy, :load_balanced)
        selected = select_by_strategy(providers, strategy, state)
        
        provider_info = Map.get(state.providers, selected)
        {:ok, {selected, provider_info.adapter}}
    end
  end

  defp provider_healthy?(provider, state) do
    case Map.get(state.provider_health, provider) do
      :unhealthy -> false
      _ -> true
    end
  end

  defp supports_model?(_provider, nil, _state), do: true  # No specific model requirement
  defp supports_model?(provider, model, state) do
    provider_info = Map.get(state.providers, provider)
    
    try do
      supported_models = provider_info.adapter.supported_models()
      model in supported_models
    rescue
      _ -> true  # Assume support if we can't check
    end
  end

  defp select_by_strategy(providers, :random, _state) do
    Enum.random(providers)
  end

  defp select_by_strategy(providers, :round_robin, state) do
    # Simple round-robin based on request counts
    counts = state.load_balancer_state.request_counts
    
    providers
    |> Enum.min_by(fn provider ->
      Map.get(counts, provider, 0)
    end)
  end

  defp select_by_strategy(providers, :load_balanced, state) do
    # Select based on load scores (lower is better)
    providers
    |> Enum.min_by(fn provider ->
      provider_info = Map.get(state.providers, provider)
      calculate_load_score(provider, provider_info, state)
    end)
  end

  defp select_by_strategy(providers, :local_affinity, state) do
    # Prefer local providers first, then load balance
    local_providers = Enum.filter(providers, fn provider ->
      provider_info = Map.get(state.providers, provider)
      provider_info.local_affinity
    end)

    case local_providers do
      [] -> select_by_strategy(providers, :load_balanced, state)
      local -> select_by_strategy(local, :load_balanced, state)
    end
  end

  defp calculate_load_score(provider, provider_info, state) do
    base_score = provider_info.load_score || 0.0
    
    # Factor in recent error rate
    error_rate = get_error_rate(provider, state)
    response_time = get_avg_response_time(provider, state)
    
    # Combine metrics (lower score is better)
    base_score + (error_rate * 100.0) + (response_time / 1000.0)
  end

  defp get_error_rate(provider, state) do
    Map.get(state.load_balancer_state.error_rates, provider, 0.0)
  end

  defp get_avg_response_time(provider, state) do
    Map.get(state.load_balancer_state.response_times, provider, 0.0)
  end

  defp update_request_metrics(provider, state) do
    counts = state.load_balancer_state.request_counts
    new_counts = Map.update(counts, provider, 1, &(&1 + 1))
    
    new_lb_state = %{state.load_balancer_state | request_counts: new_counts}
    %{state | load_balancer_state: new_lb_state}
  end

  defp update_provider_metrics(provider, result, metadata, state) do
    # Update error rates
    error_rates = state.load_balancer_state.error_rates
    current_rate = Map.get(error_rates, provider, 0.0)
    
    new_error_rate = case result do
      :success -> current_rate * 0.95  # Decay error rate on success
      :error -> min(current_rate + 0.1, 1.0)  # Increase error rate on error
    end
    
    new_error_rates = Map.put(error_rates, provider, new_error_rate)
    
    # Update response times if provided
    response_times = state.load_balancer_state.response_times
    new_response_times = case Map.get(metadata, :response_time) do
      nil -> response_times
      time -> 
        current_avg = Map.get(response_times, provider, 0.0)
        # Exponential moving average
        new_avg = current_avg * 0.8 + time * 0.2
        Map.put(response_times, provider, new_avg)
    end
    
    new_lb_state = %{
      state.load_balancer_state | 
      error_rates: new_error_rates,
      response_times: new_response_times
    }
    
    new_state = %{state | load_balancer_state: new_lb_state}
    
    # Update provider health based on metrics
    update_provider_health(provider, new_error_rate, new_state)
  end

  defp update_provider_health(provider, error_rate, state) do
    new_health = cond do
      error_rate > 0.5 -> :unhealthy
      error_rate > 0.2 -> :degraded
      true -> :healthy
    end
    
    old_health = Map.get(state.provider_health, provider, :healthy)
    new_provider_health = Map.put(state.provider_health, provider, new_health)
    
    # Log health changes
    if old_health != new_health do
      Logger.info("Provider #{provider} health changed: #{old_health} -> #{new_health}")
      broadcast_health_update(provider, new_health)
    end
    
    %{state | provider_health: new_provider_health}
  end

  defp perform_health_checks(state) do
    # Perform health checks on all providers
    new_provider_health = 
      Enum.into(state.providers, %{}, fn {provider, info} ->
        health = check_provider_health(provider, info)
        {provider, health}
      end)
    
    %{state | provider_health: new_provider_health}
  end

  defp check_provider_health(_provider, provider_info) do
    # Simple health check - try to get supported models
    try do
      case provider_info.adapter.health_check(provider_info.config) do
        :ok -> :healthy
        {:error, _} -> :unhealthy
      end
    rescue
      _ -> :degraded
    catch
      :exit, _ -> :unhealthy
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp broadcast_provider_update(provider, action, info) do
    message = {:provider_update, node(), provider, action, info}
    broadcast_to_coordinators(message)
  end

  defp broadcast_health_update(provider, health) do
    message = {:health_update, node(), provider, health}
    broadcast_to_coordinators(message)
  end

  defp broadcast_to_coordinators(message) do
    try do
      :pg.get_members(@pg_scope, :model_coordinators)
      |> Enum.each(fn pid ->
        if pid != self() do
          send(pid, {:pg_notify, @pg_scope, :model_coordinators, {node(), message}})
        end
      end)
    catch
      _, _ -> :ok  # Ignore broadcast failures
    end
  end

  defp collect_cluster_status(state) do
    # For now, return local status
    # In a full implementation, would collect from all coordinator nodes
    %{node() => %{
      providers: state.providers,
      health: state.provider_health
    }}
  end

  defp handle_remote_provider_update(node, provider, action, _info, state) do
    Logger.debug("Received provider update from #{node}: #{provider} #{action}")
    
    # Update node affinity information
    affinity = Map.get(state.node_affinity, provider, [])
    new_affinity = case action do
      :registered -> Enum.uniq([node | affinity])
      :unregistered -> List.delete(affinity, node)
      _ -> affinity
    end
    
    new_node_affinity = Map.put(state.node_affinity, provider, new_affinity)
    %{state | node_affinity: new_node_affinity}
  end

  defp handle_pg_message({:health_update, from_node, provider, health}, state) do
    Logger.debug("Received health update from #{from_node}: #{provider} -> #{health}")
    # Store remote health information for routing decisions
    state
  end

  defp handle_pg_message(_message, state) do
    # Handle other pg messages
    state
  end
end