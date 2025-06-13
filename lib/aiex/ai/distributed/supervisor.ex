defmodule Aiex.AI.Distributed.Supervisor do
  @moduledoc """
  Supervisor for distributed AI coordination components.
  
  Manages the distributed AI coordinator, node capability manager,
  request router, and load balancer with proper fault tolerance
  and startup order dependencies.
  """
  
  use Supervisor
  require Logger
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Check if distributed AI coordination should be enabled
    ai_intelligence_config = Application.get_env(:aiex, :ai_intelligence, [])
    coordination_enabled = Keyword.get(ai_intelligence_config, :coordination_enabled, true)
    
    children = if coordination_enabled do
      [
        # Start NodeCapabilityManager first as others depend on it
        {Aiex.AI.Distributed.NodeCapabilityManager, []},
        
        # Start RequestRouter next as Coordinator depends on it
        {Aiex.AI.Distributed.RequestRouter, []},
        
        # Start LoadBalancer 
        {Aiex.AI.Distributed.LoadBalancer, get_load_balancer_opts()},
        
        # Start Response Comparison and Consensus components
        {Aiex.AI.Distributed.ConsensusEngine, get_consensus_engine_opts()},
        {Aiex.AI.Distributed.ResponseComparator, get_response_comparator_opts()},
        {Aiex.AI.Distributed.ABTestingFramework, []},
        
        # Start DistributedAICoordinator last as it orchestrates everything
        {Aiex.AI.Distributed.Coordinator, []}
      ]
    else
      Logger.info("Distributed AI coordination disabled")
      []
    end
    
    if coordination_enabled do
      Logger.info("Starting distributed AI coordination with #{length(children)} components")
    end
    
    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.init(children, opts)
  end
  
  @doc """
  Get status of all distributed AI components.
  """
  def status do
    children = Supervisor.which_children(__MODULE__)
    
    %{
      supervisor: __MODULE__,
      children_count: length(children),
      components: Enum.map(children, fn {id, pid, type, modules} ->
        %{
          id: id,
          pid: pid,
          type: type,
          modules: modules,
          status: if(is_pid(pid) and Process.alive?(pid), do: :running, else: :not_running)
        }
      end),
      coordinator: get_component_status(Aiex.AI.Distributed.Coordinator),
      capability_manager: get_component_status(Aiex.AI.Distributed.NodeCapabilityManager),
      request_router: get_component_status(Aiex.AI.Distributed.RequestRouter),
      load_balancer: get_component_status(Aiex.AI.Distributed.LoadBalancer),
      consensus_engine: get_component_status(Aiex.AI.Distributed.ConsensusEngine),
      response_comparator: get_component_status(Aiex.AI.Distributed.ResponseComparator),
      ab_testing_framework: get_component_status(Aiex.AI.Distributed.ABTestingFramework)
    }
  end
  
  @doc """
  Get comprehensive cluster topology from coordinator.
  """
  def get_cluster_topology do
    case Process.whereis(Aiex.AI.Distributed.Coordinator) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.Coordinator.get_cluster_topology()
      nil ->
        {:error, :coordinator_not_running}
    end
  end
  
  @doc """
  Get load balancing statistics.
  """
  def get_load_balancing_stats do
    case Process.whereis(Aiex.AI.Distributed.LoadBalancer) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.LoadBalancer.get_load_balancing_stats()
      nil ->
        {:error, :load_balancer_not_running}
    end
  end
  
  @doc """
  Get node capabilities.
  """
  def get_node_capabilities do
    case Process.whereis(Aiex.AI.Distributed.NodeCapabilityManager) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.NodeCapabilityManager.get_current_capabilities()
      nil ->
        {:error, :capability_manager_not_running}
    end
  end
  
  @doc """
  Get request routing statistics.
  """
  def get_routing_stats do
    case Process.whereis(Aiex.AI.Distributed.RequestRouter) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.RequestRouter.get_routing_stats()
      nil ->
        {:error, :request_router_not_running}
    end
  end
  
  @doc """
  Route an AI request through the distributed system.
  """
  def route_ai_request(request, options \\ []) do
    case Process.whereis(Aiex.AI.Distributed.Coordinator) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.Coordinator.route_request(request, options)
      nil ->
        {:error, :coordinator_not_running}
    end
  end
  
  @doc """
  Force capability assessment update.
  """
  def force_capability_assessment do
    case Process.whereis(Aiex.AI.Distributed.NodeCapabilityManager) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.NodeCapabilityManager.force_assessment()
        :ok
      nil ->
        {:error, :capability_manager_not_running}
    end
  end
  
  @doc """
  Change load balancing algorithm.
  """
  def set_load_balancing_algorithm(algorithm) do
    case Process.whereis(Aiex.AI.Distributed.LoadBalancer) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.LoadBalancer.set_algorithm(algorithm)
      nil ->
        {:error, :load_balancer_not_running}
    end
  end
  
  @doc """
  Compare AI responses across multiple providers.
  """
  def compare_ai_responses(request, options \\ []) do
    case Process.whereis(Aiex.AI.Distributed.ResponseComparator) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.ResponseComparator.compare_responses(request, options)
      nil ->
        {:error, :response_comparator_not_running}
    end
  end
  
  @doc """
  Get response comparison statistics.
  """
  def get_comparison_stats do
    case Process.whereis(Aiex.AI.Distributed.ResponseComparator) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.ResponseComparator.get_comparison_stats()
      nil ->
        {:error, :response_comparator_not_running}
    end
  end
  
  @doc """
  Reach consensus on best response from multiple options.
  """
  def reach_consensus(responses, options \\ []) do
    case Process.whereis(Aiex.AI.Distributed.ConsensusEngine) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.ConsensusEngine.reach_consensus(responses, options)
      nil ->
        {:error, :consensus_engine_not_running}
    end
  end
  
  @doc """
  Get consensus engine statistics.
  """
  def get_consensus_stats do
    case Process.whereis(Aiex.AI.Distributed.ConsensusEngine) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.ConsensusEngine.get_consensus_stats()
      nil ->
        {:error, :consensus_engine_not_running}
    end
  end
  
  @doc """
  Set consensus voting strategy.
  """
  def set_consensus_strategy(strategy) do
    case Process.whereis(Aiex.AI.Distributed.ConsensusEngine) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.ConsensusEngine.set_voting_strategy(strategy)
      nil ->
        {:error, :consensus_engine_not_running}
    end
  end
  
  @doc """
  Create an A/B test for AI response comparison.
  """
  def create_ab_test(test_config) do
    case Process.whereis(Aiex.AI.Distributed.ABTestingFramework) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.ABTestingFramework.create_test(test_config)
      nil ->
        {:error, :ab_testing_framework_not_running}
    end
  end
  
  @doc """
  Get A/B testing framework statistics.
  """
  def get_ab_testing_stats do
    case Process.whereis(Aiex.AI.Distributed.ABTestingFramework) do
      pid when is_pid(pid) ->
        Aiex.AI.Distributed.ABTestingFramework.get_framework_stats()
      nil ->
        {:error, :ab_testing_framework_not_running}
    end
  end
  
  # Private helper functions
  
  defp get_component_status(module) do
    case Process.whereis(module) do
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          :running
        else
          :dead
        end
      nil ->
        :not_running
    end
  end
  
  defp get_load_balancer_opts do
    ai_intelligence_config = Application.get_env(:aiex, :ai_intelligence, [])
    
    [
      algorithm: Keyword.get(ai_intelligence_config, :load_balancing_algorithm, :adaptive)
    ]
  end
  
  defp get_consensus_engine_opts do
    ai_intelligence_config = Application.get_env(:aiex, :ai_intelligence, [])
    
    [
      voting_strategy: Keyword.get(ai_intelligence_config, :consensus_voting_strategy, :hybrid),
      minimum_responses: Keyword.get(ai_intelligence_config, :minimum_consensus_responses, 2),
      confidence_threshold: Keyword.get(ai_intelligence_config, :consensus_confidence_threshold, 0.6)
    ]
  end
  
  defp get_response_comparator_opts do
    ai_intelligence_config = Application.get_env(:aiex, :ai_intelligence, [])
    
    [
      consensus_strategy: Keyword.get(ai_intelligence_config, :response_comparison_strategy, :hybrid)
    ]
  end
end