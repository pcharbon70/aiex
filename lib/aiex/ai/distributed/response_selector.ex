defmodule Aiex.AI.Distributed.ResponseSelector do
  @moduledoc """
  Implements distributed ML-based response selection using consensus algorithms 
  across nodes with pg coordination.
  
  This module provides:
  - Distributed ML ranking across nodes for response quality assessment
  - Distributed preference learning system to learn from user choices
  - pg-based consensus selection for distributed response choice coordination
  - Distributed override system for manual response preference
  - Cluster confidence scoring system for response quality confidence
  - Distributed adaptive learning to improve selection over time
  - Strategy synchronization across cluster nodes
  - Distributed explanations for selection decisions
  """
  
  use GenServer
  require Logger
  
  alias Aiex.AI.Distributed.{QualityMetrics, ConsensusEngine}
  alias Aiex.EventBus
  alias Aiex.Telemetry
  
  @pg_scope :aiex_response_selector
  @ml_model_sync_interval 300_000  # 5 minutes
  @preference_learning_batch_size 50
  @adaptive_learning_threshold 0.75
  
  defstruct [
    :node_id,
    :ml_models,
    :preference_data,
    :confidence_tracker,
    :selection_history,
    :override_rules,
    :learning_weights,
    :strategy_config,
    :peer_nodes
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Select best response using distributed ML ranking and consensus.
  """
  def select_response(responses, context \\ %{}, options \\ []) do
    GenServer.call(__MODULE__, {:select_response, responses, context, options})
  end
  
  @doc """
  Record user preference for adaptive learning.
  """
  def record_preference(selection_id, chosen_response, rejected_responses, feedback \\ %{}) do
    GenServer.call(__MODULE__, {:record_preference, selection_id, chosen_response, rejected_responses, feedback})
  end
  
  @doc """
  Set manual override rule for specific contexts.
  """
  def set_override_rule(context_pattern, preference_rule) do
    GenServer.call(__MODULE__, {:set_override_rule, context_pattern, preference_rule})
  end
  
  @doc """
  Get selection statistics and confidence metrics.
  """
  def get_selection_stats do
    GenServer.call(__MODULE__, :get_selection_stats)
  end
  
  @doc """
  Trigger adaptive learning update across cluster.
  """
  def trigger_adaptive_learning do
    GenServer.call(__MODULE__, :trigger_adaptive_learning)
  end
  
  @doc """
  Get explanation for a selection decision.
  """
  def explain_selection(selection_id) do
    GenServer.call(__MODULE__, {:explain_selection, selection_id})
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, Node.self())
    
    # Join pg group for distributed coordination
    :pg.join(@pg_scope, self())
    
    state = %__MODULE__{
      node_id: node_id,
      ml_models: initialize_ml_models(),
      preference_data: [],
      confidence_tracker: %{},
      selection_history: [],
      override_rules: %{},
      learning_weights: default_learning_weights(),
      strategy_config: default_strategy_config(),
      peer_nodes: []
    }
    
    # Schedule periodic tasks
    schedule_model_sync()
    schedule_adaptive_learning()
    
    Logger.info("ResponseSelector started on node #{node_id}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:select_response, responses, context, options}, _from, state) do
    selection_id = generate_selection_id()
    
    try do
      # Step 1: Distribute ML ranking across nodes
      ml_rankings = distribute_ml_ranking(responses, context, state)
      
      # Step 2: Check for override rules
      override_result = check_override_rules(responses, context, state.override_rules)
      
      # Step 3: Apply pg-based consensus selection
      consensus_result = apply_pg_consensus(ml_rankings, override_result, state)
      
      # Step 4: Calculate cluster confidence scoring
      confidence_score = calculate_cluster_confidence(consensus_result, ml_rankings, state)
      
      # Step 5: Record selection in history
      selection_record = %{
        id: selection_id,
        responses: responses,
        context: context,
        ml_rankings: ml_rankings,
        override_applied: override_result != nil,
        consensus_result: consensus_result,
        confidence_score: confidence_score,
        timestamp: System.system_time(:millisecond),
        node_id: state.node_id
      }
      
      new_state = %{state | 
        selection_history: [selection_record | state.selection_history] |> Enum.take(1000)
      }
      
      # Emit telemetry and events
      emit_selection_telemetry(selection_record)
      emit_selection_event(selection_record)
      
      result = %{
        selected_response: consensus_result.selected_response,
        selection_id: selection_id,
        confidence: confidence_score,
        explanation: generate_selection_explanation(selection_record),
        metadata: %{
          ml_rankings_count: length(ml_rankings),
          override_applied: override_result != nil,
          consensus_method: consensus_result.consensus_method,
          peer_nodes_consulted: length(state.peer_nodes)
        }
      }
      
      {:reply, {:ok, result}, new_state}
    rescue
      error ->
        Logger.error("Error in response selection: #{inspect(error)}")
        {:reply, {:error, :selection_failed}, state}
    end
  end
  
  @impl true
  def handle_call({:record_preference, selection_id, chosen_response, rejected_responses, feedback}, _from, state) do
    preference_entry = %{
      selection_id: selection_id,
      chosen_response: chosen_response,
      rejected_responses: rejected_responses,
      feedback: feedback,
      timestamp: System.system_time(:millisecond),
      node_id: state.node_id
    }
    
    new_preference_data = [preference_entry | state.preference_data] |> Enum.take(1000)
    new_state = %{state | preference_data: new_preference_data}
    
    # Broadcast preference to peer nodes for distributed learning
    broadcast_preference_update(preference_entry)
    
    # Trigger adaptive learning if we have enough data
    if length(new_preference_data) >= @preference_learning_batch_size do
      Task.start(fn -> update_ml_models_from_preferences(new_preference_data) end)
    end
    
    Logger.debug("Recorded preference for selection #{selection_id}")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:set_override_rule, context_pattern, preference_rule}, _from, state) do
    new_rules = Map.put(state.override_rules, context_pattern, preference_rule)
    new_state = %{state | override_rules: new_rules}
    
    # Broadcast override rule to peer nodes
    broadcast_override_rule(context_pattern, preference_rule)
    
    Logger.info("Set override rule for pattern: #{inspect(context_pattern)}")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_selection_stats, _from, state) do
    stats = %{
      node_id: state.node_id,
      total_selections: length(state.selection_history),
      preference_data_points: length(state.preference_data),
      override_rules_count: map_size(state.override_rules),
      avg_confidence: calculate_avg_confidence(state.selection_history),
      ml_model_performance: get_ml_model_performance(state.ml_models),
      learning_weights: state.learning_weights,
      strategy_config: state.strategy_config,
      peer_nodes_count: length(state.peer_nodes),
      recent_selections: Enum.take(state.selection_history, 10),
      timestamp: System.system_time(:millisecond)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:trigger_adaptive_learning, _from, state) do
    if length(state.preference_data) >= 10 do
      # Perform adaptive learning update
      updated_weights = perform_adaptive_learning(state.preference_data, state.learning_weights)
      updated_models = update_ml_models(state.ml_models, state.preference_data)
      
      new_state = %{state | 
        learning_weights: updated_weights,
        ml_models: updated_models
      }
      
      # Broadcast updates to peer nodes
      broadcast_learning_update(updated_weights, updated_models)
      
      Logger.info("Adaptive learning update completed")
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :insufficient_data}, state}
    end
  end
  
  @impl true
  def handle_call({:explain_selection, selection_id}, _from, state) do
    case Enum.find(state.selection_history, &(&1.id == selection_id)) do
      nil ->
        {:reply, {:error, :selection_not_found}, state}
      
      selection_record ->
        explanation = generate_detailed_explanation(selection_record, state)
        {:reply, {:ok, explanation}, state}
    end
  end
  
  @impl true
  def handle_info(:sync_ml_models, state) do
    # Synchronize ML models with peer nodes
    updated_state = sync_models_with_peers(state)
    schedule_model_sync()
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(:perform_adaptive_learning, state) do
    # Perform periodic adaptive learning
    if length(state.preference_data) >= @preference_learning_batch_size do
      updated_state = perform_periodic_adaptive_learning(state)
      {:noreply, updated_state}
    else
      {:noreply, state}
    end
    
    schedule_adaptive_learning()
  end
  
  @impl true
  def handle_info({:preference_update, preference_data}, state) do
    # Received preference update from peer node
    new_preference_data = [preference_data | state.preference_data] |> Enum.take(1000)
    new_state = %{state | preference_data: new_preference_data}
    
    Logger.debug("Received preference update from peer node")
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:override_rule_update, context_pattern, preference_rule}, state) do
    # Received override rule update from peer node
    new_rules = Map.put(state.override_rules, context_pattern, preference_rule)
    new_state = %{state | override_rules: new_rules}
    
    Logger.debug("Received override rule update from peer node")
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:learning_update, weights, models}, state) do
    # Received learning update from peer node
    new_state = %{state | 
      learning_weights: merge_learning_weights(state.learning_weights, weights),
      ml_models: merge_ml_models(state.ml_models, models)
    }
    
    Logger.debug("Received learning update from peer node")
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp distribute_ml_ranking(responses, context, state) do
    # Distribute ML ranking computation across available nodes
    peer_nodes = get_peer_nodes()
    
    if Enum.empty?(peer_nodes) do
      # Single node - perform ranking locally
      [perform_local_ml_ranking(responses, context, state.ml_models)]
    else
      # Multi-node - distribute work
      responses_per_node = distribute_responses_across_nodes(responses, peer_nodes)
      
      ranking_tasks = Enum.map(responses_per_node, fn {node, node_responses} ->
        Task.async(fn ->
          if node == Node.self() do
            perform_local_ml_ranking(node_responses, context, state.ml_models)
          else
            request_remote_ml_ranking(node, node_responses, context)
          end
        end)
      end)
      
      # Collect results with timeout
      ranking_results = Task.await_many(ranking_tasks, 10_000)
      
      # Aggregate rankings from all nodes
      aggregate_ml_rankings(ranking_results)
    end
  end
  
  defp perform_local_ml_ranking(responses, context, ml_models) do
    # Apply ML models to rank responses
    Enum.map(responses, fn response ->
      features = extract_features(response, context)
      
      # Apply each ML model
      model_scores = Enum.map(ml_models, fn {model_name, model} ->
        score = apply_ml_model(model, features)
        {model_name, score}
      end) |> Enum.into(%{})
      
      # Calculate combined ML score
      combined_score = calculate_combined_ml_score(model_scores)
      
      %{
        response: response,
        ml_score: combined_score,
        model_scores: model_scores,
        features: features,
        node_id: Node.self()
      }
    end)
  end
  
  defp apply_pg_consensus(ml_rankings, override_result, state) do
    if override_result do
      override_result
    else
      # Use pg to coordinate consensus across nodes
      consensus_request = %{
        ml_rankings: ml_rankings,
        strategy: state.strategy_config.consensus_strategy,
        weights: state.learning_weights,
        timestamp: System.system_time(:millisecond)
      }
      
      # Broadcast consensus request to peer nodes
      pg_members = :pg.get_members(@pg_scope)
      
      if length(pg_members) > 1 do
        # Multi-node consensus
        consensus_responses = broadcast_consensus_request(consensus_request, pg_members)
        aggregate_consensus_results(consensus_responses)
      else
        # Single node - use local consensus
        apply_local_consensus(ml_rankings, state)
      end
    end
  end
  
  defp calculate_cluster_confidence(consensus_result, ml_rankings, state) do
    # Calculate confidence based on multiple factors
    factors = %{
      consensus_agreement: calculate_consensus_agreement(consensus_result),
      ml_score_variance: calculate_ml_score_variance(ml_rankings),
      historical_accuracy: get_historical_accuracy(state.selection_history),
      peer_node_agreement: calculate_peer_agreement(consensus_result),
      override_confidence: if(consensus_result.override_applied, do: 1.0, else: 0.8)
    }
    
    # Weighted combination of confidence factors
    weights = %{
      consensus_agreement: 0.3,
      ml_score_variance: 0.2,
      historical_accuracy: 0.2,
      peer_node_agreement: 0.2,
      override_confidence: 0.1
    }
    
    Enum.reduce(factors, 0.0, fn {factor, value}, acc ->
      weight = Map.get(weights, factor, 0.0)
      acc + (value * weight)
    end)
  end
  
  defp check_override_rules(responses, context, override_rules) do
    # Check if any override rules apply to this context
    Enum.find_value(override_rules, fn {pattern, rule} ->
      if context_matches_pattern?(context, pattern) do
        apply_override_rule(responses, rule)
      end
    end)
  end
  
  defp perform_adaptive_learning(preference_data, current_weights) do
    # Analyze preference patterns to update learning weights
    preference_patterns = analyze_preference_patterns(preference_data)
    
    # Update weights based on successful predictions
    updated_weights = Enum.reduce(preference_patterns, current_weights, fn {pattern, success_rate}, weights ->
      adjustment = calculate_weight_adjustment(success_rate)
      update_weights_for_pattern(weights, pattern, adjustment)
    end)
    
    # Ensure weights are normalized
    normalize_learning_weights(updated_weights)
  end
  
  defp generate_selection_explanation(selection_record) do
    %{
      selection_id: selection_record.id,
      primary_factors: [
        "ML ranking scores from distributed computation",
        "Consensus agreement across #{length(selection_record.ml_rankings)} nodes",
        if(selection_record.override_applied, do: "Manual override rule applied", else: nil)
      ] |> Enum.reject(&is_nil/1),
      confidence_breakdown: %{
        overall_confidence: selection_record.confidence_score,
        ml_confidence: calculate_ml_confidence(selection_record.ml_rankings),
        consensus_confidence: selection_record.consensus_result.confidence
      },
      alternative_considerations: extract_alternative_analysis(selection_record)
    }
  end
  
  defp generate_detailed_explanation(selection_record, state) do
    %{
      basic_explanation: generate_selection_explanation(selection_record),
      detailed_analysis: %{
        ml_model_contributions: analyze_ml_model_contributions(selection_record.ml_rankings),
        consensus_voting_breakdown: selection_record.consensus_result.voting_breakdown,
        historical_context: get_historical_selection_context(selection_record, state),
        peer_node_analysis: analyze_peer_node_contributions(selection_record),
        learning_weight_influence: analyze_learning_weight_influence(selection_record, state.learning_weights)
      },
      recommendations: generate_selection_recommendations(selection_record, state)
    }
  end
  
  # Helper Functions
  
  defp initialize_ml_models do
    %{
      quality_predictor: %{type: :linear_regression, weights: [], bias: 0.0},
      relevance_scorer: %{type: :decision_tree, tree: nil},
      preference_learner: %{type: :neural_network, layers: []}
    }
  end
  
  defp default_learning_weights do
    %{
      quality_weight: 0.4,
      relevance_weight: 0.3,
      preference_weight: 0.2,
      consensus_weight: 0.1
    }
  end
  
  defp default_strategy_config do
    %{
      consensus_strategy: :hybrid,
      ml_ranking_threshold: 0.7,
      confidence_threshold: 0.6,
      override_precedence: true
    }
  end
  
  defp get_peer_nodes do
    :pg.get_members(@pg_scope)
    |> Enum.reject(&(&1 == self()))
    |> Enum.map(&node/1)
    |> Enum.uniq()
  end
  
  defp generate_selection_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp extract_features(response, context) do
    %{
      content_length: String.length(extract_content(response)),
      has_code: contains_code?(extract_content(response)),
      response_time: Map.get(response, :duration_ms, 0),
      provider: Map.get(response, :provider, :unknown),
      context_relevance: calculate_context_relevance(response, context),
      quality_indicators: count_quality_indicators(extract_content(response))
    }
  end
  
  defp extract_content(response) do
    case response do
      %{content: content} when is_binary(content) -> content
      %{"content" => content} when is_binary(content) -> content
      binary when is_binary(binary) -> binary
      _ -> inspect(response)
    end
  end
  
  defp contains_code?(content) do
    String.contains?(content, "```") or
    String.contains?(content, "def ") or
    Regex.match?(~r/\b[a-zA-Z_][a-zA-Z0-9_]*\s*\(/, content)
  end
  
  defp calculate_context_relevance(_response, _context) do
    # Placeholder for context relevance calculation
    0.8
  end
  
  defp count_quality_indicators(content) do
    indicators = [
      String.contains?(content, "```"),    # Code blocks
      String.contains?(content, "**"),     # Emphasis
      String.contains?(content, "-"),      # Lists
      String.length(content) > 100,       # Substantial content
      String.contains?(content, "because") # Explanations
    ]
    
    Enum.count(indicators, & &1)
  end
  
  defp apply_ml_model(model, features) do
    # Simplified ML model application
    case model.type do
      :linear_regression ->
        apply_linear_regression(model, features)
      
      :decision_tree ->
        apply_decision_tree(model, features)
      
      :neural_network ->
        apply_neural_network(model, features)
      
      _ ->
        0.5  # Default score
    end
  end
  
  defp apply_linear_regression(model, features) do
    # Simple linear regression scoring
    feature_values = [
      features.content_length / 1000,  # Normalize
      if(features.has_code, do: 1.0, else: 0.0),
      features.response_time / 10000,  # Normalize
      features.context_relevance,
      features.quality_indicators / 5   # Normalize
    ]
    
    # Apply weights (if available) or use defaults
    weights = Map.get(model, :weights, [0.2, 0.3, -0.1, 0.4, 0.2])
    bias = Map.get(model, :bias, 0.0)
    
    score = Enum.zip(feature_values, weights)
    |> Enum.reduce(bias, fn {value, weight}, acc -> acc + value * weight end)
    
    # Normalize to 0-1 range
    max(0.0, min(1.0, score))
  end
  
  defp apply_decision_tree(_model, features) do
    # Simple decision tree logic
    cond do
      features.quality_indicators >= 3 -> 0.9
      features.has_code and features.content_length > 200 -> 0.8
      features.context_relevance > 0.7 -> 0.7
      true -> 0.5
    end
  end
  
  defp apply_neural_network(_model, _features) do
    # Placeholder for neural network
    0.6
  end
  
  defp calculate_combined_ml_score(model_scores) do
    # Weighted combination of model scores
    weights = %{
      quality_predictor: 0.4,
      relevance_scorer: 0.4,
      preference_learner: 0.2
    }
    
    Enum.reduce(model_scores, 0.0, fn {model, score}, acc ->
      weight = Map.get(weights, model, 0.0)
      acc + score * weight
    end)
  end
  
  defp distribute_responses_across_nodes(responses, peer_nodes) do
    # Simple round-robin distribution
    all_nodes = [Node.self() | peer_nodes]
    
    responses
    |> Enum.with_index()
    |> Enum.group_by(fn {_response, index} ->
      Enum.at(all_nodes, rem(index, length(all_nodes)))
    end)
    |> Enum.map(fn {node, indexed_responses} ->
      {node, Enum.map(indexed_responses, &elem(&1, 0))}
    end)
  end
  
  defp request_remote_ml_ranking(node, responses, context) do
    # This would make a remote call to the specified node
    # For now, simulate with local ranking
    Logger.debug("Simulating remote ML ranking request to node #{node}")
    perform_local_ml_ranking(responses, context, initialize_ml_models())
  end
  
  defp aggregate_ml_rankings(ranking_results) do
    # Combine rankings from multiple nodes
    List.flatten(ranking_results)
  end
  
  defp broadcast_consensus_request(request, pg_members) do
    # Simulate consensus request broadcast
    Enum.map(pg_members, fn member ->
      if member != self() do
        # Would send actual message in real implementation
        simulate_consensus_response(request)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
  
  defp simulate_consensus_response(request) do
    # Simulate consensus response from peer node
    %{
      node_id: Node.self(),
      selected_response: List.first(request.ml_rankings).response,
      confidence: 0.8,
      voting_weight: 1.0
    }
  end
  
  defp aggregate_consensus_results(responses) do
    # Aggregate consensus responses from multiple nodes
    if Enum.empty?(responses) do
      %{selected_response: nil, confidence: 0.0, consensus_method: :failed}
    else
      # Simple majority selection
      selected = responses
      |> Enum.max_by(& &1.confidence)
      
      %{
        selected_response: selected.selected_response,
        confidence: selected.confidence,
        consensus_method: :distributed_majority,
        participating_nodes: length(responses)
      }
    end
  end
  
  defp apply_local_consensus(ml_rankings, state) do
    # Apply consensus using only local data
    best_ranking = Enum.max_by(ml_rankings, & &1.ml_score)
    
    %{
      selected_response: best_ranking.response,
      confidence: best_ranking.ml_score,
      consensus_method: :local_ml_ranking,
      override_applied: false
    }
  end
  
  defp context_matches_pattern?(context, pattern) do
    # Simple pattern matching - could be more sophisticated
    case pattern do
      %{type: type} -> Map.get(context, :type) == type
      %{domain: domain} -> Map.get(context, :domain) == domain
      _ -> false
    end
  end
  
  defp apply_override_rule(responses, rule) do
    # Apply override rule to select response
    case rule do
      %{prefer_provider: provider} ->
        preferred = Enum.find(responses, &(Map.get(&1, :provider) == provider))
        if preferred do
          %{
            selected_response: preferred,
            confidence: 1.0,
            consensus_method: :override_rule,
            override_applied: true
          }
        else
          nil
        end
      
      _ -> nil
    end
  end
  
  defp calculate_consensus_agreement(consensus_result) do
    # Calculate how much agreement there was in consensus
    Map.get(consensus_result, :confidence, 0.5)
  end
  
  defp calculate_ml_score_variance(ml_rankings) do
    scores = Enum.map(ml_rankings, & &1.ml_score)
    
    if length(scores) < 2 do
      0.0
    else
      mean = Enum.sum(scores) / length(scores)
      variance = Enum.sum(Enum.map(scores, &(:math.pow(&1 - mean, 2)))) / length(scores)
      
      # Convert variance to confidence (lower variance = higher confidence)
      1.0 - min(variance, 1.0)
    end
  end
  
  defp get_historical_accuracy(selection_history) do
    # Calculate historical accuracy of selections
    if length(selection_history) < 5 do
      0.7  # Default assumption
    else
      # Would analyze feedback on historical selections
      # For now, return moderate confidence
      0.75
    end
  end
  
  defp calculate_peer_agreement(consensus_result) do
    # Calculate agreement among peer nodes
    participating_nodes = Map.get(consensus_result, :participating_nodes, 1)
    
    if participating_nodes <= 1 do
      0.5  # Single node, moderate confidence
    else
      # Higher agreement with more participating nodes
      min(1.0, participating_nodes / 5.0)
    end
  end
  
  defp broadcast_preference_update(preference_data) do
    # Broadcast preference update to peer nodes
    pg_members = :pg.get_members(@pg_scope)
    
    Enum.each(pg_members, fn member ->
      if member != self() do
        send(member, {:preference_update, preference_data})
      end
    end)
  end
  
  defp broadcast_override_rule(context_pattern, preference_rule) do
    # Broadcast override rule to peer nodes
    pg_members = :pg.get_members(@pg_scope)
    
    Enum.each(pg_members, fn member ->
      if member != self() do
        send(member, {:override_rule_update, context_pattern, preference_rule})
      end
    end)
  end
  
  defp broadcast_learning_update(weights, models) do
    # Broadcast learning update to peer nodes
    pg_members = :pg.get_members(@pg_scope)
    
    Enum.each(pg_members, fn member ->
      if member != self() do
        send(member, {:learning_update, weights, models})
      end
    end)
  end
  
  defp update_ml_models_from_preferences(preference_data) do
    # Update ML models based on user preferences
    Logger.debug("Updating ML models from #{length(preference_data)} preference data points")
    # Implementation would train models on preference data
  end
  
  defp calculate_avg_confidence(selection_history) do
    if Enum.empty?(selection_history) do
      0.0
    else
      total_confidence = Enum.sum(Enum.map(selection_history, & &1.confidence_score))
      total_confidence / length(selection_history)
    end
  end
  
  defp get_ml_model_performance(ml_models) do
    # Get performance metrics for ML models
    Enum.map(ml_models, fn {name, model} ->
      {name, %{
        type: model.type,
        status: :active,
        last_updated: System.system_time(:millisecond)
      }}
    end) |> Enum.into(%{})
  end
  
  defp analyze_preference_patterns(preference_data) do
    # Analyze patterns in user preferences
    preference_data
    |> Enum.group_by(&Map.get(&1.chosen_response, :provider))
    |> Enum.map(fn {provider, preferences} ->
      success_rate = length(preferences) / max(1, length(preference_data))
      {provider, success_rate}
    end)
    |> Enum.into(%{})
  end
  
  defp calculate_weight_adjustment(success_rate) do
    # Calculate how much to adjust weights based on success rate
    cond do
      success_rate > @adaptive_learning_threshold -> 0.1
      success_rate < 0.3 -> -0.1
      true -> 0.0
    end
  end
  
  defp update_weights_for_pattern(weights, pattern, adjustment) do
    # Update weights for specific pattern
    case pattern do
      provider when is_atom(provider) ->
        # Adjust quality weight for this provider
        Map.update(weights, :quality_weight, 0.4, &(&1 + adjustment))
      
      _ -> weights
    end
  end
  
  defp normalize_learning_weights(weights) do
    # Ensure all weights are in valid range and sum appropriately
    Enum.map(weights, fn {key, value} ->
      {key, max(0.1, min(0.8, value))}
    end) |> Enum.into(%{})
  end
  
  defp emit_selection_telemetry(selection_record) do
    Telemetry.emit([:aiex, :ai, :response_selection], %{
      selection_duration_ms: 100,  # Would measure actual duration
      confidence_score: selection_record.confidence_score,
      ml_rankings_count: length(selection_record.ml_rankings)
    }, %{
      selection_id: selection_record.id,
      override_applied: selection_record.override_applied,
      node_id: selection_record.node_id
    })
  end
  
  defp emit_selection_event(selection_record) do
    EventBus.emit("ai_response_selected", %{
      selection_id: selection_record.id,
      selected_provider: Map.get(selection_record.consensus_result.selected_response, :provider),
      confidence: selection_record.confidence_score,
      node_id: selection_record.node_id
    })
  end
  
  defp schedule_model_sync do
    Process.send_after(self(), :sync_ml_models, @ml_model_sync_interval)
  end
  
  defp schedule_adaptive_learning do
    Process.send_after(self(), :perform_adaptive_learning, @ml_model_sync_interval * 2)
  end
  
  defp sync_models_with_peers(state) do
    # Synchronize ML models with peer nodes
    Logger.debug("Synchronizing ML models with peer nodes")
    state  # For now, return unchanged state
  end
  
  defp perform_periodic_adaptive_learning(state) do
    # Perform periodic adaptive learning
    if length(state.preference_data) >= @preference_learning_batch_size do
      updated_weights = perform_adaptive_learning(state.preference_data, state.learning_weights)
      %{state | learning_weights: updated_weights}
    else
      state
    end
  end
  
  defp merge_learning_weights(local_weights, remote_weights) do
    # Merge learning weights from remote node
    Enum.reduce(remote_weights, local_weights, fn {key, remote_value}, acc ->
      local_value = Map.get(acc, key, 0.5)
      # Simple averaging
      merged_value = (local_value + remote_value) / 2
      Map.put(acc, key, merged_value)
    end)
  end
  
  defp merge_ml_models(local_models, remote_models) do
    # Merge ML models from remote node
    # For now, keep local models (would implement proper model merging)
    local_models
  end
  
  defp update_ml_models(models, preference_data) do
    # Update ML models based on preference data
    Logger.debug("Updating ML models with #{length(preference_data)} preference examples")
    models  # For now, return unchanged models
  end
  
  defp calculate_ml_confidence(ml_rankings) do
    scores = Enum.map(ml_rankings, & &1.ml_score)
    if Enum.empty?(scores), do: 0.0, else: Enum.max(scores)
  end
  
  defp extract_alternative_analysis(selection_record) do
    # Extract analysis of alternative responses
    ml_rankings = selection_record.ml_rankings
    selected_provider = Map.get(selection_record.consensus_result.selected_response, :provider)
    
    alternatives = Enum.reject(ml_rankings, &(Map.get(&1.response, :provider) == selected_provider))
    
    Enum.map(alternatives, fn alt ->
      %{
        provider: Map.get(alt.response, :provider),
        ml_score: alt.ml_score,
        score_difference: selection_record.consensus_result.selected_response |> 
          get_ml_score_for_response(ml_rankings) |> Kernel.-(alt.ml_score)
      }
    end)
  end
  
  defp get_ml_score_for_response(response, ml_rankings) do
    case Enum.find(ml_rankings, &(&1.response == response)) do
      nil -> 0.0
      ranking -> ranking.ml_score
    end
  end
  
  defp analyze_ml_model_contributions(ml_rankings) do
    # Analyze how each ML model contributed to rankings
    Enum.map(ml_rankings, fn ranking ->
      %{
        response_provider: Map.get(ranking.response, :provider),
        overall_ml_score: ranking.ml_score,
        model_breakdown: ranking.model_scores
      }
    end)
  end
  
  defp get_historical_selection_context(selection_record, state) do
    # Get historical context for this selection
    similar_selections = Enum.filter(state.selection_history, fn record ->
      Map.get(record.context, :type) == Map.get(selection_record.context, :type)
    end)
    
    %{
      similar_selections_count: length(similar_selections),
      recent_provider_preferences: calculate_recent_provider_preferences(similar_selections)
    }
  end
  
  defp calculate_recent_provider_preferences(similar_selections) do
    recent_selections = Enum.take(similar_selections, 10)
    
    recent_selections
    |> Enum.map(&Map.get(&1.consensus_result.selected_response, :provider))
    |> Enum.frequencies()
  end
  
  defp analyze_peer_node_contributions(selection_record) do
    # Analyze contributions from peer nodes
    node_rankings = Enum.group_by(selection_record.ml_rankings, & &1.node_id)
    
    Enum.map(node_rankings, fn {node_id, rankings} ->
      %{
        node_id: node_id,
        rankings_contributed: length(rankings),
        avg_ml_score: Enum.sum(Enum.map(rankings, & &1.ml_score)) / length(rankings)
      }
    end)
  end
  
  defp analyze_learning_weight_influence(selection_record, learning_weights) do
    # Analyze how learning weights influenced selection
    %{
      applied_weights: learning_weights,
      weight_impact_on_selection: "Learning weights influenced consensus by favoring quality (#{learning_weights.quality_weight}) and relevance (#{learning_weights.relevance_weight})"
    }
  end
  
  defp generate_selection_recommendations(selection_record, state) do
    # Generate recommendations based on selection analysis
    recommendations = []
    
    recommendations = if selection_record.confidence_score < 0.6 do
      ["Consider adding more training data for ML models" | recommendations]
    else
      recommendations
    end
    
    recommendations = if length(state.preference_data) < 20 do
      ["Collect more user preference feedback to improve selection accuracy" | recommendations]
    else
      recommendations
    end
    
    recommendations = if map_size(state.override_rules) == 0 do
      ["Consider setting override rules for specific contexts" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
end