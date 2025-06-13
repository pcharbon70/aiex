defmodule Aiex.AI.Distributed.ConsensusEngine do
  @moduledoc """
  Implements consensus mechanisms for selecting the best AI response
  from multiple providers and distributed nodes.
  
  Provides various voting strategies and consensus algorithms:
  - Simple majority voting
  - Quality-weighted voting
  - Ranked choice voting
  - Hybrid consensus with multiple factors
  """
  
  use GenServer
  require Logger
  
  alias Aiex.AI.Distributed.QualityMetrics
  alias Aiex.EventBus
  
  @type response :: %{
    provider: atom(),
    content: binary(),
    quality_score: float(),
    timestamp: integer(),
    success: boolean()
  }
  
  @type consensus_result :: %{
    selected_response: response(),
    confidence: float(),
    voting_breakdown: map(),
    consensus_method: atom(),
    metadata: map()
  }
  
  defstruct [
    :voting_strategy,
    :minimum_responses,
    :confidence_threshold,
    :consensus_history,
    :performance_weights
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Reach consensus on best response from multiple options.
  """
  def reach_consensus(responses, options \\ []) do
    GenServer.call(__MODULE__, {:reach_consensus, responses, options})
  end
  
  @doc """
  Get consensus engine statistics.
  """
  def get_consensus_stats do
    GenServer.call(__MODULE__, :get_consensus_stats)
  end
  
  @doc """
  Set voting strategy (:majority, :quality_weighted, :ranked_choice, :hybrid).
  """
  def set_voting_strategy(strategy) do
    GenServer.call(__MODULE__, {:set_voting_strategy, strategy})
  end
  
  @doc """
  Update performance weights for providers.
  """
  def update_performance_weights(weights) do
    GenServer.call(__MODULE__, {:update_performance_weights, weights})
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    voting_strategy = Keyword.get(opts, :voting_strategy, :hybrid)
    minimum_responses = Keyword.get(opts, :minimum_responses, 2)
    confidence_threshold = Keyword.get(opts, :confidence_threshold, 0.6)
    
    state = %__MODULE__{
      voting_strategy: voting_strategy,
      minimum_responses: minimum_responses,
      confidence_threshold: confidence_threshold,
      consensus_history: [],
      performance_weights: %{}
    }
    
    Logger.info("ConsensusEngine started with strategy: #{voting_strategy}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:reach_consensus, responses, options}, _from, state) do
    if length(responses) < state.minimum_responses do
      result = {:error, :insufficient_responses}
      {:reply, result, state}
    else
      consensus_result = perform_consensus(responses, state, options)
      
      # Record consensus in history
      history_entry = %{
        timestamp: System.system_time(:millisecond),
        responses_count: length(responses),
        selected_provider: consensus_result.selected_response.provider,
        confidence: consensus_result.confidence,
        method: consensus_result.consensus_method
      }
      
      new_history = [history_entry | state.consensus_history] |> Enum.take(1000)
      new_state = %{state | consensus_history: new_history}
      
      # Emit event
      EventBus.emit("ai_consensus_reached", %{
        provider: consensus_result.selected_response.provider,
        confidence: consensus_result.confidence,
        method: consensus_result.consensus_method,
        alternatives_count: length(responses) - 1
      })
      
      {:reply, {:ok, consensus_result}, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_consensus_stats, _from, state) do
    stats = %{
      voting_strategy: state.voting_strategy,
      minimum_responses: state.minimum_responses,
      confidence_threshold: state.confidence_threshold,
      total_consensus_decisions: length(state.consensus_history),
      avg_confidence: calculate_avg_confidence(state.consensus_history),
      provider_selection_frequency: calculate_provider_frequency(state.consensus_history),
      method_usage: calculate_method_usage(state.consensus_history),
      recent_performance: get_recent_performance(state.consensus_history),
      timestamp: System.system_time(:millisecond)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:set_voting_strategy, strategy}, _from, state) do
    valid_strategies = [:majority, :quality_weighted, :ranked_choice, :hybrid]
    
    if strategy in valid_strategies do
      Logger.info("Voting strategy changed to: #{strategy}")
      {:reply, :ok, %{state | voting_strategy: strategy}}
    else
      {:reply, {:error, :invalid_strategy}, state}
    end
  end
  
  @impl true
  def handle_call({:update_performance_weights, weights}, _from, state) do
    new_state = %{state | performance_weights: weights}
    Logger.info("Performance weights updated for #{map_size(weights)} providers")
    {:reply, :ok, new_state}
  end
  
  # Private Functions
  
  defp perform_consensus(responses, state, options) do
    # Ensure all responses have quality scores
    responses_with_quality = Enum.map(responses, fn response ->
      if Map.has_key?(response, :quality_score) do
        response
      else
        quality_score = QualityMetrics.assess_response_quality(response)
        Map.put(response, :quality_score, quality_score)
      end
    end)
    
    # Apply consensus method
    voting_strategy = Keyword.get(options, :voting_strategy, state.voting_strategy)
    
    case voting_strategy do
      :majority ->
        majority_consensus(responses_with_quality, state)
      
      :quality_weighted ->
        quality_weighted_consensus(responses_with_quality, state)
      
      :ranked_choice ->
        ranked_choice_consensus(responses_with_quality, state)
      
      :hybrid ->
        hybrid_consensus(responses_with_quality, state)
      
      _ ->
        # Fallback to hybrid
        hybrid_consensus(responses_with_quality, state)
    end
  end
  
  defp majority_consensus(responses, _state) do
    # Simple majority based on response similarity
    # For AI responses, we'll use quality scores as proxy for "votes"
    selected_response = Enum.max_by(responses, & &1.quality_score)
    
    # Calculate confidence based on how much better the winner is
    quality_scores = Enum.map(responses, & &1.quality_score)
    avg_quality = Enum.sum(quality_scores) / length(quality_scores)
    max_quality = selected_response.quality_score
    
    confidence = if avg_quality > 0, do: max_quality / avg_quality, else: 0.5
    confidence = min(confidence, 1.0)
    
    %{
      selected_response: selected_response,
      confidence: confidence,
      voting_breakdown: %{
        quality_scores: quality_scores,
        winner_quality: max_quality,
        avg_quality: avg_quality
      },
      consensus_method: :majority,
      metadata: %{
        responses_considered: length(responses)
      }
    }
  end
  
  defp quality_weighted_consensus(responses, state) do
    # Weight responses by quality scores and historical performance
    weighted_responses = Enum.map(responses, fn response ->
      base_weight = response.quality_score
      
      # Apply historical performance weight if available
      performance_weight = Map.get(state.performance_weights, response.provider, 1.0)
      
      final_weight = base_weight * performance_weight
      
      Map.put(response, :consensus_weight, final_weight)
    end)
    
    selected_response = Enum.max_by(weighted_responses, & &1.consensus_weight)
    
    # Calculate confidence based on weight distribution
    total_weight = Enum.sum(Enum.map(weighted_responses, & &1.consensus_weight))
    winner_weight = selected_response.consensus_weight
    
    confidence = if total_weight > 0, do: winner_weight / total_weight, else: 0.5
    
    %{
      selected_response: selected_response,
      confidence: confidence,
      voting_breakdown: %{
        weights: Enum.map(weighted_responses, fn r -> 
          {r.provider, r.consensus_weight} 
        end) |> Enum.into(%{}),
        total_weight: total_weight,
        winner_weight: winner_weight
      },
      consensus_method: :quality_weighted,
      metadata: %{
        performance_weights_applied: map_size(state.performance_weights) > 0
      }
    }
  end
  
  defp ranked_choice_consensus(responses, _state) do
    # Rank responses by multiple criteria and use ranked choice voting
    criteria = [:quality_score, :response_time, :provider_reliability]
    
    # Calculate rankings for each criterion
    rankings = Enum.map(criteria, fn criterion ->
      ranked = case criterion do
        :quality_score ->
          Enum.sort_by(responses, & &1.quality_score, :desc)
        
        :response_time ->
          # Faster is better, but we need duration_ms field
          if Enum.all?(responses, &Map.has_key?(&1, :duration_ms)) do
            Enum.sort_by(responses, & &1.duration_ms, :asc)
          else
            responses  # No change if duration not available
          end
        
        :provider_reliability ->
          # Use quality as proxy for reliability
          Enum.sort_by(responses, & &1.quality_score, :desc)
      end
      
      {criterion, ranked}
    end) |> Enum.into(%{})
    
    # Calculate Borda count scores
    borda_scores = calculate_borda_scores(responses, rankings)
    
    {winner_provider, winner_score} = Enum.max_by(borda_scores, fn {_provider, score} -> score end)
    selected_response = Enum.find(responses, &(&1.provider == winner_provider))
    
    # Calculate confidence
    total_possible_score = length(responses) * length(criteria)
    confidence = winner_score / total_possible_score
    
    %{
      selected_response: selected_response,
      confidence: confidence,
      voting_breakdown: %{
        borda_scores: borda_scores,
        rankings: rankings,
        criteria_used: criteria
      },
      consensus_method: :ranked_choice,
      metadata: %{
        total_criteria: length(criteria)
      }
    }
  end
  
  defp hybrid_consensus(responses, state) do
    # Combine multiple consensus methods for robust decision making
    majority_result = majority_consensus(responses, state)
    quality_result = quality_weighted_consensus(responses, state)
    ranked_result = ranked_choice_consensus(responses, state)
    
    # Weight the different methods
    method_weights = %{
      majority: 0.3,
      quality_weighted: 0.4,
      ranked_choice: 0.3
    }
    
    # Calculate composite scores for each response
    composite_scores = Enum.map(responses, fn response ->
      provider = response.provider
      
      scores = %{
        majority: if(majority_result.selected_response.provider == provider, do: 1.0, else: 0.0),
        quality_weighted: if(quality_result.selected_response.provider == provider, do: 1.0, else: 0.0),
        ranked_choice: if(ranked_result.selected_response.provider == provider, do: 1.0, else: 0.0)
      }
      
      composite_score = Enum.reduce(method_weights, 0.0, fn {method, weight}, acc ->
        acc + (Map.get(scores, method, 0.0) * weight)
      end)
      
      {provider, composite_score}
    end) |> Enum.into(%{})
    
    # Select winner and calculate confidence
    {winner_provider, winner_score} = Enum.max_by(composite_scores, fn {_provider, score} -> score end)
    selected_response = Enum.find(responses, &(&1.provider == winner_provider))
    
    # Confidence is based on margin of victory and individual method confidences
    avg_method_confidence = (majority_result.confidence + quality_result.confidence + ranked_result.confidence) / 3
    margin_boost = if winner_score > 0.6, do: 0.1, else: 0.0
    
    confidence = min(avg_method_confidence + margin_boost, 1.0)
    
    %{
      selected_response: selected_response,
      confidence: confidence,
      voting_breakdown: %{
        composite_scores: composite_scores,
        method_results: %{
          majority: majority_result.selected_response.provider,
          quality_weighted: quality_result.selected_response.provider,
          ranked_choice: ranked_result.selected_response.provider
        },
        method_confidences: %{
          majority: majority_result.confidence,
          quality_weighted: quality_result.confidence,
          ranked_choice: ranked_result.confidence
        }
      },
      consensus_method: :hybrid,
      metadata: %{
        methods_agreed: count_agreeing_methods([majority_result, quality_result, ranked_result]),
        hybrid_score: winner_score
      }
    }
  end
  
  defp calculate_borda_scores(responses, rankings) do
    providers = Enum.map(responses, & &1.provider)
    
    # Initialize scores
    initial_scores = Enum.map(providers, &{&1, 0}) |> Enum.into(%{})
    
    # Calculate Borda points for each ranking
    Enum.reduce(rankings, initial_scores, fn {_criterion, ranked_responses}, scores ->
      ranked_responses
      |> Enum.with_index()
      |> Enum.reduce(scores, fn {response, index}, acc ->
        # Higher index means lower rank, so invert the score
        points = length(ranked_responses) - index - 1
        Map.update(acc, response.provider, points, &(&1 + points))
      end)
    end)
  end
  
  defp count_agreeing_methods(method_results) do
    selected_providers = Enum.map(method_results, & &1.selected_response.provider)
    
    selected_providers
    |> Enum.frequencies()
    |> Map.values()
    |> Enum.max()
  end
  
  defp calculate_avg_confidence(history) do
    if Enum.empty?(history) do
      0.0
    else
      total_confidence = Enum.sum(Enum.map(history, & &1.confidence))
      total_confidence / length(history)
    end
  end
  
  defp calculate_provider_frequency(history) do
    history
    |> Enum.map(& &1.selected_provider)
    |> Enum.frequencies()
  end
  
  defp calculate_method_usage(history) do
    history
    |> Enum.map(& &1.method)
    |> Enum.frequencies()
  end
  
  defp get_recent_performance(history) do
    recent_entries = Enum.take(history, 10)
    
    if Enum.empty?(recent_entries) do
      %{}
    else
      %{
        avg_confidence: calculate_avg_confidence(recent_entries),
        provider_distribution: calculate_provider_frequency(recent_entries),
        decision_count: length(recent_entries)
      }
    end
  end
end