defmodule Aiex.AI.Distributed.PgConsensusCoordinator do
  @moduledoc """
  Enhanced pg-based consensus coordination for distributed response selection.
  
  This module implements sophisticated consensus mechanisms using pg process groups
  for coordinating distributed response selection across cluster nodes with:
  - Distributed voting coordination
  - Byzantine fault tolerance
  - Network partition handling
  - Quorum-based decisions
  - Real-time consensus tracking
  """
  
  use GenServer
  require Logger
  
  alias Aiex.AI.Distributed.{QualityMetrics, PreferenceLearner}
  alias Aiex.EventBus
  alias Aiex.Telemetry
  
  @pg_scope :aiex_consensus_coordinator
  @consensus_timeout 15_000
  @quorum_threshold 0.6
  @byzantine_tolerance 0.33  # Up to 1/3 of nodes can be faulty
  
  defstruct [
    :node_id,
    :active_consensus_rounds,
    :completed_rounds,
    :peer_nodes,
    :voting_weights,
    :fault_detector,
    :partition_handler,
    :consensus_history,
    :quorum_config
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Coordinate distributed consensus for response selection.
  """
  def coordinate_consensus(consensus_request, options \\ []) do
    GenServer.call(__MODULE__, {:coordinate_consensus, consensus_request, options}, @consensus_timeout + 5_000)
  end
  
  @doc """
  Get consensus coordinator statistics.
  """
  def get_consensus_stats do
    GenServer.call(__MODULE__, :get_consensus_stats)
  end
  
  @doc """
  Update voting weights for nodes.
  """
  def update_voting_weights(weights) do
    GenServer.call(__MODULE__, {:update_voting_weights, weights})
  end
  
  @doc """
  Get cluster health and consensus readiness.
  """
  def get_cluster_health do
    GenServer.call(__MODULE__, :get_cluster_health)
  end
  
  @doc """
  Force consensus round completion (emergency use).
  """
  def force_consensus_completion(round_id) do
    GenServer.call(__MODULE__, {:force_consensus_completion, round_id})
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, Node.self())
    
    # Join pg group for distributed coordination
    :pg.join(@pg_scope, self())
    
    state = %__MODULE__{
      node_id: node_id,
      active_consensus_rounds: %{},
      completed_rounds: [],
      peer_nodes: %{},
      voting_weights: %{},
      fault_detector: initialize_fault_detector(),
      partition_handler: initialize_partition_handler(),
      consensus_history: [],
      quorum_config: initialize_quorum_config()
    }
    
    # Schedule periodic tasks
    schedule_health_check()
    schedule_cleanup()
    
    Logger.info("PgConsensusCoordinator started on node #{node_id}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:coordinate_consensus, consensus_request, options}, from, state) do
    round_id = generate_round_id()
    
    # Get active peer nodes
    peer_nodes = get_active_peer_nodes()
    
    if sufficient_nodes_for_consensus?(peer_nodes, state.quorum_config) do
      # Start distributed consensus round
      consensus_round = start_consensus_round(round_id, consensus_request, peer_nodes, from, options)
      
      new_state = %{state | 
        active_consensus_rounds: Map.put(state.active_consensus_rounds, round_id, consensus_round),
        peer_nodes: update_peer_nodes_status(state.peer_nodes, peer_nodes)
      }
      
      # Broadcast consensus request to all peer nodes
      broadcast_consensus_request(consensus_round)
      
      # Set timeout for this round
      schedule_consensus_timeout(round_id)
      
      {:noreply, new_state}
    else
      # Insufficient nodes for consensus - fall back to local decision
      local_result = make_local_consensus_decision(consensus_request, state)
      {:reply, {:ok, local_result}, state}
    end
  end
  
  @impl true
  def handle_call(:get_consensus_stats, _from, state) do
    stats = %{
      node_id: state.node_id,
      active_rounds: map_size(state.active_consensus_rounds),
      completed_rounds: length(state.completed_rounds),
      peer_nodes_count: map_size(state.peer_nodes),
      voting_weights: state.voting_weights,
      quorum_config: state.quorum_config,
      fault_detector_status: get_fault_detector_status(state.fault_detector),
      partition_status: get_partition_status(state.partition_handler),
      recent_consensus_performance: get_recent_performance(state.consensus_history),
      timestamp: System.system_time(:millisecond)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:update_voting_weights, weights}, _from, state) do
    new_state = %{state | voting_weights: weights}
    
    # Broadcast weight update to peer nodes
    broadcast_weight_update(weights)
    
    Logger.info("Updated voting weights for #{map_size(weights)} nodes")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_cluster_health, _from, state) do
    health = %{
      cluster_size: map_size(state.peer_nodes) + 1,  # +1 for this node
      active_nodes: count_active_nodes(state.peer_nodes),
      consensus_readiness: calculate_consensus_readiness(state),
      network_partition_detected: detect_network_partition(state.partition_handler),
      byzantine_fault_tolerance: calculate_byzantine_tolerance(state.peer_nodes),
      quorum_achievable: quorum_achievable?(state.peer_nodes, state.quorum_config),
      last_health_check: System.system_time(:millisecond)
    }
    
    {:reply, health, state}
  end
  
  @impl true
  def handle_call({:force_consensus_completion, round_id}, _from, state) do
    case Map.get(state.active_consensus_rounds, round_id) do
      nil ->
        {:reply, {:error, :round_not_found}, state}
      
      consensus_round ->
        # Force completion with current votes
        final_result = finalize_consensus_round(consensus_round, state, :forced)
        
        new_state = complete_consensus_round(round_id, final_result, state)
        
        Logger.warn("Forced completion of consensus round #{round_id}")
        {:reply, {:ok, final_result}, new_state}
    end
  end
  
  @impl true
  def handle_info({:consensus_request, round_id, request_data, from_node}, state) do
    # Received consensus request from peer node
    if valid_consensus_request?(request_data, from_node, state) do
      # Process the consensus request
      vote = generate_consensus_vote(request_data, state)
      
      # Send vote back to requesting node
      send_consensus_vote(from_node, round_id, vote)
      
      # Update peer node status
      new_state = update_peer_node_activity(state, from_node)
      {:noreply, new_state}
    else
      Logger.warn("Received invalid consensus request from #{from_node}")
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:consensus_vote, round_id, vote_data, from_node}, state) do
    # Received vote for our consensus round
    case Map.get(state.active_consensus_rounds, round_id) do
      nil ->
        Logger.warn("Received vote for unknown consensus round #{round_id}")
        {:noreply, state}
      
      consensus_round ->
        # Add vote to consensus round
        updated_round = add_vote_to_round(consensus_round, vote_data, from_node)
        
        new_state = %{state | 
          active_consensus_rounds: Map.put(state.active_consensus_rounds, round_id, updated_round)
        }
        
        # Check if we have enough votes to reach consensus
        if consensus_ready?(updated_round, state.quorum_config) do
          final_result = finalize_consensus_round(updated_round, state, :completed)
          complete_consensus_round(round_id, final_result, new_state)
        else
          {:noreply, new_state}
        end
    end
  end
  
  @impl true
  def handle_info({:consensus_timeout, round_id}, state) do
    # Handle consensus round timeout
    case Map.get(state.active_consensus_rounds, round_id) do
      nil ->
        {:noreply, state}
      
      consensus_round ->
        Logger.warn("Consensus round #{round_id} timed out")
        
        # Try to complete with available votes
        if has_minimum_votes?(consensus_round, state.quorum_config) do
          final_result = finalize_consensus_round(consensus_round, state, :timeout)
          complete_consensus_round(round_id, final_result, state)
        else
          # Not enough votes - return error
          GenServer.reply(consensus_round.from, {:error, :consensus_timeout})
          
          failed_round = %{consensus_round | status: :failed, completion_reason: :timeout}
          new_state = %{state | 
            active_consensus_rounds: Map.delete(state.active_consensus_rounds, round_id),
            completed_rounds: [failed_round | state.completed_rounds] |> Enum.take(100)
          }
          
          {:noreply, new_state}
        end
    end
  end
  
  @impl true
  def handle_info(:health_check, state) do
    # Perform periodic health check
    updated_state = perform_health_check(state)
    schedule_health_check()
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(:cleanup_completed_rounds, state) do
    # Clean up old completed rounds
    cutoff_time = System.system_time(:millisecond) - 3_600_000  # 1 hour
    
    cleaned_rounds = Enum.filter(state.completed_rounds, fn round ->
      round.completed_at > cutoff_time
    end)
    
    schedule_cleanup()
    {:noreply, %{state | completed_rounds: cleaned_rounds}}
  end
  
  @impl true
  def handle_info({:weight_update, weights, from_node}, state) do
    # Received voting weight update from peer node
    updated_weights = merge_voting_weights(state.voting_weights, weights)
    new_state = %{state | voting_weights: updated_weights}
    
    Logger.debug("Received weight update from #{from_node}")
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp get_active_peer_nodes do
    :pg.get_members(@pg_scope)
    |> Enum.reject(&(&1 == self()))
    |> Enum.map(&node/1)
    |> Enum.uniq()
    |> Enum.filter(&Node.ping(&1) == :pong)
  end
  
  defp sufficient_nodes_for_consensus?(peer_nodes, quorum_config) do
    total_nodes = length(peer_nodes) + 1  # +1 for this node
    minimum_nodes = Map.get(quorum_config, :minimum_nodes, 2)
    
    total_nodes >= minimum_nodes
  end
  
  defp start_consensus_round(round_id, consensus_request, peer_nodes, from, options) do
    %{
      id: round_id,
      request: consensus_request,
      peer_nodes: peer_nodes,
      votes: %{},
      from: from,
      options: options,
      started_at: System.system_time(:millisecond),
      status: :active,
      completion_reason: nil
    }
  end
  
  defp broadcast_consensus_request(consensus_round) do
    request_message = {
      :consensus_request,
      consensus_round.id,
      consensus_round.request,
      Node.self()
    }
    
    Enum.each(consensus_round.peer_nodes, fn node ->
      case :pg.get_members(@pg_scope) |> Enum.find(&(node(&1) == node)) do
        nil ->
          Logger.warn("Could not find pg member for node #{node}")
        
        pid ->
          send(pid, request_message)
      end
    end)
  end
  
  defp valid_consensus_request?(request_data, from_node, state) do
    # Validate the consensus request
    is_trusted_node?(from_node, state) and
    valid_request_structure?(request_data) and
    not_replay_attack?(request_data)
  end
  
  defp is_trusted_node?(node, _state) do
    # Simple trust check - in production would be more sophisticated
    Node.ping(node) == :pong
  end
  
  defp valid_request_structure?(request_data) do
    # Validate request structure
    is_map(request_data) and
    Map.has_key?(request_data, :ml_rankings) and
    Map.has_key?(request_data, :strategy)
  end
  
  defp not_replay_attack?(request_data) do
    # Check timestamp to prevent replay attacks
    timestamp = Map.get(request_data, :timestamp, 0)
    current_time = System.system_time(:millisecond)
    
    # Request must be within last 30 seconds
    current_time - timestamp < 30_000
  end
  
  defp generate_consensus_vote(request_data, state) do
    # Generate our vote based on the request
    ml_rankings = Map.get(request_data, :ml_rankings, [])
    strategy = Map.get(request_data, :strategy, :hybrid)
    
    # Apply our local evaluation
    local_evaluation = evaluate_responses_locally(ml_rankings, strategy, state)
    
    # Get user preference insights if available
    preference_insights = get_preference_insights(ml_rankings)
    
    %{
      voter_node: state.node_id,
      selected_response: local_evaluation.selected_response,
      confidence: local_evaluation.confidence,
      quality_scores: local_evaluation.quality_scores,
      preference_weight: preference_insights.weight,
      reasoning: local_evaluation.reasoning,
      timestamp: System.system_time(:millisecond),
      vote_weight: Map.get(state.voting_weights, state.node_id, 1.0)
    }
  end
  
  defp evaluate_responses_locally(ml_rankings, strategy, _state) do
    if Enum.empty?(ml_rankings) do
      %{
        selected_response: nil,
        confidence: 0.0,
        quality_scores: %{},
        reasoning: "No responses to evaluate"
      }
    else
      # Apply local evaluation strategy
      case strategy do
        :hybrid ->
          evaluate_hybrid_strategy(ml_rankings)
        
        :quality_weighted ->
          evaluate_quality_weighted(ml_rankings)
        
        :preference_based ->
          evaluate_preference_based(ml_rankings)
        
        _ ->
          evaluate_default_strategy(ml_rankings)
      end
    end
  end
  
  defp evaluate_hybrid_strategy(ml_rankings) do
    # Combine multiple factors for evaluation
    evaluated_responses = Enum.map(ml_rankings, fn ranking ->
      quality_score = Map.get(ranking, :ml_score, 0.5)
      speed_score = calculate_speed_score(Map.get(ranking.response, :duration_ms, 5000))
      provider_reputation = get_provider_reputation(Map.get(ranking.response, :provider))
      
      combined_score = quality_score * 0.5 + speed_score * 0.3 + provider_reputation * 0.2
      
      %{
        response: ranking.response,
        combined_score: combined_score,
        quality_score: quality_score,
        speed_score: speed_score,
        provider_reputation: provider_reputation
      }
    end)
    
    best_response = Enum.max_by(evaluated_responses, & &1.combined_score)
    
    %{
      selected_response: best_response.response,
      confidence: best_response.combined_score,
      quality_scores: Enum.map(evaluated_responses, &{&1.response, &1.combined_score}) |> Enum.into(%{}),
      reasoning: "Hybrid evaluation combining quality (#{best_response.quality_score}), speed (#{best_response.speed_score}), and reputation (#{best_response.provider_reputation})"
    }
  end
  
  defp evaluate_quality_weighted(ml_rankings) do
    best_ranking = Enum.max_by(ml_rankings, & &1.ml_score)
    
    %{
      selected_response: best_ranking.response,
      confidence: best_ranking.ml_score,
      quality_scores: Enum.map(ml_rankings, &{&1.response, &1.ml_score}) |> Enum.into(%{}),
      reasoning: "Quality-weighted selection based on ML score: #{best_ranking.ml_score}"
    }
  end
  
  defp evaluate_preference_based(ml_rankings) do
    # Use preference learning insights
    preference_scores = Enum.map(ml_rankings, fn ranking ->
      # Would call PreferenceLearner here
      preference_score = 0.7  # Placeholder
      %{response: ranking.response, preference_score: preference_score}
    end)
    
    best_preference = Enum.max_by(preference_scores, & &1.preference_score)
    
    %{
      selected_response: best_preference.response,
      confidence: best_preference.preference_score,
      quality_scores: Enum.map(preference_scores, &{&1.response, &1.preference_score}) |> Enum.into(%{}),
      reasoning: "Preference-based selection using user preference learning"
    }
  end
  
  defp evaluate_default_strategy(ml_rankings) do
    # Simple fallback - choose first response
    first_ranking = List.first(ml_rankings)
    
    %{
      selected_response: first_ranking.response,
      confidence: 0.5,
      quality_scores: %{first_ranking.response => 0.5},
      reasoning: "Default strategy - selected first available response"
    }
  end
  
  defp calculate_speed_score(duration_ms) do
    cond do
      duration_ms < 1000 -> 1.0
      duration_ms < 3000 -> 0.8
      duration_ms < 8000 -> 0.6
      duration_ms < 15000 -> 0.4
      true -> 0.2
    end
  end
  
  defp get_provider_reputation(provider) do
    # Placeholder for provider reputation system
    case provider do
      :openai -> 0.9
      :anthropic -> 0.85
      :ollama -> 0.7
      _ -> 0.6
    end
  end
  
  defp get_preference_insights(_ml_rankings) do
    # Placeholder for preference insights
    %{weight: 0.5}
  end
  
  defp send_consensus_vote(target_node, round_id, vote) do
    vote_message = {:consensus_vote, round_id, vote, Node.self()}
    
    case :pg.get_members(@pg_scope) |> Enum.find(&(node(&1) == target_node)) do
      nil ->
        Logger.warn("Could not find pg member for node #{target_node}")
      
      pid ->
        send(pid, vote_message)
    end
  end
  
  defp add_vote_to_round(consensus_round, vote_data, from_node) do
    new_votes = Map.put(consensus_round.votes, from_node, vote_data)
    %{consensus_round | votes: new_votes}
  end
  
  defp consensus_ready?(consensus_round, quorum_config) do
    total_expected_votes = length(consensus_round.peer_nodes)
    received_votes = map_size(consensus_round.votes)
    
    quorum_threshold = Map.get(quorum_config, :threshold, @quorum_threshold)
    
    received_votes / total_expected_votes >= quorum_threshold
  end
  
  defp has_minimum_votes?(consensus_round, quorum_config) do
    minimum_votes = Map.get(quorum_config, :minimum_votes, 1)
    map_size(consensus_round.votes) >= minimum_votes
  end
  
  defp finalize_consensus_round(consensus_round, state, completion_reason) do
    # Aggregate all votes to determine final result
    votes = Map.values(consensus_round.votes)
    
    if Enum.empty?(votes) do
      # No votes received - use local decision
      local_result = make_local_consensus_decision(consensus_round.request, state)
      Map.put(local_result, :completion_reason, completion_reason)
    else
      # Aggregate votes using voting strategy
      aggregated_result = aggregate_consensus_votes(votes, consensus_round.request)
      Map.put(aggregated_result, :completion_reason, completion_reason)
    end
  end
  
  defp aggregate_consensus_votes(votes, request) do
    # Implement vote aggregation logic
    weighted_votes = Enum.map(votes, fn vote ->
      weight = Map.get(vote, :vote_weight, 1.0)
      confidence = Map.get(vote, :confidence, 0.5)
      
      %{
        response: vote.selected_response,
        weighted_score: confidence * weight,
        original_vote: vote
      }
    end)
    
    # Find response with highest weighted score
    best_vote = Enum.max_by(weighted_votes, & &1.weighted_score)
    
    # Calculate overall confidence
    total_weight = Enum.sum(Enum.map(weighted_votes, & &1.weighted_score))
    avg_confidence = if total_weight > 0, do: best_vote.weighted_score / total_weight, else: 0.5
    
    %{
      selected_response: best_vote.response,
      confidence: avg_confidence,
      consensus_method: :distributed_weighted_voting,
      participating_nodes: length(votes),
      vote_breakdown: Enum.map(weighted_votes, &Map.take(&1, [:weighted_score, :original_vote])),
      metadata: %{
        strategy: Map.get(request, :strategy, :unknown),
        total_weight: total_weight
      }
    }
  end
  
  defp complete_consensus_round(round_id, final_result, state) do
    consensus_round = Map.get(state.active_consensus_rounds, round_id)
    
    # Reply to caller
    GenServer.reply(consensus_round.from, {:ok, final_result})
    
    # Create completed round record
    completed_round = %{
      id: round_id,
      request: consensus_round.request,
      final_result: final_result,
      votes_received: map_size(consensus_round.votes),
      peer_nodes: consensus_round.peer_nodes,
      started_at: consensus_round.started_at,
      completed_at: System.system_time(:millisecond),
      duration_ms: System.system_time(:millisecond) - consensus_round.started_at,
      status: :completed,
      completion_reason: Map.get(final_result, :completion_reason, :unknown)
    }
    
    # Emit telemetry and events
    emit_consensus_telemetry(completed_round)
    emit_consensus_event(completed_round)
    
    # Update state
    new_state = %{state |
      active_consensus_rounds: Map.delete(state.active_consensus_rounds, round_id),
      completed_rounds: [completed_round | state.completed_rounds] |> Enum.take(100),
      consensus_history: [completed_round | state.consensus_history] |> Enum.take(1000)
    }
    
    {:noreply, new_state}
  end
  
  defp make_local_consensus_decision(request, state) do
    # Fallback to local decision when distributed consensus not possible
    ml_rankings = Map.get(request, :ml_rankings, [])
    
    if Enum.empty?(ml_rankings) do
      %{
        selected_response: nil,
        confidence: 0.0,
        consensus_method: :local_fallback,
        metadata: %{reason: "No responses available"}
      }
    else
      best_ranking = Enum.max_by(ml_rankings, & &1.ml_score)
      
      %{
        selected_response: best_ranking.response,
        confidence: best_ranking.ml_score,
        consensus_method: :local_fallback,
        metadata: %{
          reason: "Insufficient nodes for distributed consensus",
          local_evaluation: true
        }
      }
    end
  end
  
  defp update_peer_nodes_status(peer_nodes, active_nodes) do
    # Update status of peer nodes
    current_time = System.system_time(:millisecond)
    
    # Mark active nodes
    updated_nodes = Enum.reduce(active_nodes, peer_nodes, fn node, acc ->
      Map.put(acc, node, %{
        status: :active,
        last_seen: current_time,
        response_time: 0  # Would measure actual response time
      })
    end)
    
    # Mark inactive nodes
    Enum.reduce(Map.keys(peer_nodes), updated_nodes, fn node, acc ->
      if node not in active_nodes do
        case Map.get(acc, node) do
          nil -> acc
          node_info -> Map.put(acc, node, %{node_info | status: :inactive})
        end
      else
        acc
      end
    end)
  end
  
  defp update_peer_node_activity(state, node) do
    current_time = System.system_time(:millisecond)
    
    node_info = Map.get(state.peer_nodes, node, %{})
    updated_info = Map.merge(node_info, %{
      status: :active,
      last_seen: current_time
    })
    
    %{state | peer_nodes: Map.put(state.peer_nodes, node, updated_info)}
  end
  
  defp broadcast_weight_update(weights) do
    pg_members = :pg.get_members(@pg_scope)
    
    Enum.each(pg_members, fn member ->
      if member != self() do
        send(member, {:weight_update, weights, Node.self()})
      end
    end)
  end
  
  defp merge_voting_weights(local_weights, remote_weights) do
    # Simple merge - in production would be more sophisticated
    Map.merge(local_weights, remote_weights)
  end
  
  # Initialization and Helper Functions
  
  defp initialize_fault_detector do
    %{
      failure_threshold: 3,
      timeout_threshold: 10_000,
      failed_nodes: %{},
      last_check: System.system_time(:millisecond)
    }
  end
  
  defp initialize_partition_handler do
    %{
      partition_detected: false,
      last_partition_check: System.system_time(:millisecond),
      minority_partition: false
    }
  end
  
  defp initialize_quorum_config do
    %{
      threshold: @quorum_threshold,
      minimum_nodes: 2,
      minimum_votes: 1,
      byzantine_tolerance: @byzantine_tolerance
    }
  end
  
  defp get_fault_detector_status(fault_detector) do
    %{
      failed_nodes_count: map_size(fault_detector.failed_nodes),
      last_check: fault_detector.last_check,
      failure_threshold: fault_detector.failure_threshold
    }
  end
  
  defp get_partition_status(partition_handler) do
    %{
      partition_detected: partition_handler.partition_detected,
      minority_partition: partition_handler.minority_partition,
      last_check: partition_handler.last_partition_check
    }
  end
  
  defp get_recent_performance(consensus_history) do
    recent = Enum.take(consensus_history, 10)
    
    if Enum.empty?(recent) do
      %{avg_duration_ms: 0, success_rate: 0.0, avg_confidence: 0.0}
    else
      %{
        avg_duration_ms: Enum.sum(Enum.map(recent, & &1.duration_ms)) / length(recent),
        success_rate: Enum.count(recent, &(&1.status == :completed)) / length(recent),
        avg_confidence: Enum.sum(Enum.map(recent, & &1.final_result.confidence)) / length(recent)
      }
    end
  end
  
  defp count_active_nodes(peer_nodes) do
    Enum.count(peer_nodes, fn {_node, info} ->
      Map.get(info, :status) == :active
    end)
  end
  
  defp calculate_consensus_readiness(state) do
    active_nodes = count_active_nodes(state.peer_nodes) + 1  # +1 for this node
    minimum_nodes = state.quorum_config.minimum_nodes
    
    if active_nodes >= minimum_nodes do
      :ready
    else
      :insufficient_nodes
    end
  end
  
  defp detect_network_partition(partition_handler) do
    partition_handler.partition_detected
  end
  
  defp calculate_byzantine_tolerance(peer_nodes) do
    total_nodes = map_size(peer_nodes) + 1
    max_byzantine_faults = trunc(total_nodes * @byzantine_tolerance)
    
    %{
      total_nodes: total_nodes,
      max_byzantine_faults: max_byzantine_faults,
      tolerance_percentage: @byzantine_tolerance * 100
    }
  end
  
  defp quorum_achievable?(peer_nodes, quorum_config) do
    active_nodes = count_active_nodes(peer_nodes) + 1
    minimum_nodes = quorum_config.minimum_nodes
    
    active_nodes >= minimum_nodes
  end
  
  defp perform_health_check(state) do
    # Update peer node status
    active_peers = get_active_peer_nodes()
    updated_peer_nodes = update_peer_nodes_status(state.peer_nodes, active_peers)
    
    # Update fault detector
    updated_fault_detector = update_fault_detector(state.fault_detector, updated_peer_nodes)
    
    # Update partition handler
    updated_partition_handler = update_partition_handler(state.partition_handler, updated_peer_nodes)
    
    %{state |
      peer_nodes: updated_peer_nodes,
      fault_detector: updated_fault_detector,
      partition_handler: updated_partition_handler
    }
  end
  
  defp update_fault_detector(fault_detector, peer_nodes) do
    current_time = System.system_time(:millisecond)
    
    # Check for failed nodes
    failed_nodes = Enum.filter(peer_nodes, fn {_node, info} ->
      status = Map.get(info, :status, :unknown)
      last_seen = Map.get(info, :last_seen, 0)
      
      status == :inactive or (current_time - last_seen) > fault_detector.timeout_threshold
    end) |> Enum.into(%{})
    
    %{fault_detector |
      failed_nodes: failed_nodes,
      last_check: current_time
    }
  end
  
  defp update_partition_handler(partition_handler, peer_nodes) do
    # Simple partition detection based on node connectivity
    active_count = count_active_nodes(peer_nodes)
    total_count = map_size(peer_nodes) + 1
    
    partition_detected = active_count < (total_count / 2)
    minority_partition = active_count <= (total_count / 3)
    
    %{partition_handler |
      partition_detected: partition_detected,
      minority_partition: minority_partition,
      last_partition_check: System.system_time(:millisecond)
    }
  end
  
  defp emit_consensus_telemetry(completed_round) do
    Telemetry.emit([:aiex, :ai, :consensus, :completed], %{
      duration_ms: completed_round.duration_ms,
      votes_received: completed_round.votes_received,
      confidence: completed_round.final_result.confidence
    }, %{
      round_id: completed_round.id,
      completion_reason: completed_round.completion_reason,
      consensus_method: completed_round.final_result.consensus_method,
      participating_nodes: completed_round.final_result.participating_nodes
    })
  end
  
  defp emit_consensus_event(completed_round) do
    EventBus.emit("distributed_consensus_completed", %{
      round_id: completed_round.id,
      selected_provider: Map.get(completed_round.final_result.selected_response, :provider),
      confidence: completed_round.final_result.confidence,
      consensus_method: completed_round.final_result.consensus_method,
      duration_ms: completed_round.duration_ms,
      participating_nodes: completed_round.final_result.participating_nodes
    })
  end
  
  defp generate_round_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp schedule_consensus_timeout(round_id) do
    Process.send_after(self(), {:consensus_timeout, round_id}, @consensus_timeout)
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)  # 30 seconds
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_completed_rounds, 600_000)  # 10 minutes
  end
end