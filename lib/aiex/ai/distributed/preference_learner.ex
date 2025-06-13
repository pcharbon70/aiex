defmodule Aiex.AI.Distributed.PreferenceLearner do
  @moduledoc """
  Implements distributed preference learning system to learn from user choices
  across the cluster using pg coordination and Mnesia storage.
  
  This module provides:
  - User preference tracking and analysis
  - Distributed preference synchronization
  - Preference pattern recognition
  - Adaptive model updates based on user feedback
  - Cross-node preference aggregation
  """
  
  use GenServer
  require Logger
  
  alias Aiex.EventBus
  alias Aiex.Telemetry
  
  @pg_scope :aiex_preference_learner
  @preference_table :preference_data
  @pattern_table :preference_patterns
  @model_table :preference_models
  
  @preference_batch_size 25
  @pattern_analysis_interval 600_000  # 10 minutes
  @model_update_threshold 0.15
  
  defstruct [
    :node_id,
    :preference_cache,
    :pattern_analyzer,
    :model_weights,
    :learning_rate,
    :confidence_tracker,
    :sync_status,
    :peer_nodes
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Record a user preference for learning.
  """
  def record_preference(user_id, context, chosen_response, alternatives, feedback \\ %{}) do
    GenServer.call(__MODULE__, {:record_preference, user_id, context, chosen_response, alternatives, feedback})
  end
  
  @doc """
  Get preference predictions for a context.
  """
  def predict_preference(user_id, context, responses) do
    GenServer.call(__MODULE__, {:predict_preference, user_id, context, responses})
  end
  
  @doc """
  Get user preference profile.
  """
  def get_user_profile(user_id) do
    GenServer.call(__MODULE__, {:get_user_profile, user_id})
  end
  
  @doc """
  Get global preference statistics.
  """
  def get_preference_stats do
    GenServer.call(__MODULE__, :get_preference_stats)
  end
  
  @doc """
  Trigger preference pattern analysis.
  """
  def analyze_patterns do
    GenServer.call(__MODULE__, :analyze_patterns)
  end
  
  @doc """
  Update preference models across cluster.
  """
  def update_models do
    GenServer.call(__MODULE__, :update_models)
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, Node.self())
    
    # Join pg group for distributed coordination
    :pg.join(@pg_scope, self())
    
    # Initialize Mnesia tables if needed
    initialize_mnesia_tables()
    
    state = %__MODULE__{
      node_id: node_id,
      preference_cache: %{},
      pattern_analyzer: initialize_pattern_analyzer(),
      model_weights: initialize_model_weights(),
      learning_rate: 0.01,
      confidence_tracker: %{},
      sync_status: :synchronized,
      peer_nodes: []
    }
    
    # Schedule periodic tasks
    schedule_pattern_analysis()
    schedule_model_sync()
    
    Logger.info("PreferenceLearner started on node #{node_id}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:record_preference, user_id, context, chosen_response, alternatives, feedback}, _from, state) do
    preference_record = %{
      id: generate_preference_id(),
      user_id: user_id,
      context: context,
      chosen_response: chosen_response,
      alternatives: alternatives,
      feedback: feedback,
      timestamp: System.system_time(:millisecond),
      node_id: state.node_id
    }
    
    # Store in local cache
    new_cache = update_preference_cache(state.preference_cache, preference_record)
    
    # Store in Mnesia for distributed access
    store_preference_in_mnesia(preference_record)
    
    # Broadcast to peer nodes
    broadcast_preference_to_peers(preference_record)
    
    # Update local models if enough data
    new_state = maybe_update_local_models(%{state | preference_cache: new_cache}, preference_record)
    
    # Emit events
    emit_preference_event(preference_record)
    
    Logger.debug("Recorded preference for user #{user_id}")
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:predict_preference, user_id, context, responses}, _from, state) do
    try do
      # Get user's historical preferences
      user_preferences = get_user_preferences(user_id, state)
      
      # Extract features for each response
      response_features = Enum.map(responses, &extract_response_features(&1, context))
      
      # Apply preference models
      predictions = Enum.map(response_features, fn features ->
        preference_score = calculate_preference_score(features, user_preferences, state.model_weights)
        confidence = calculate_prediction_confidence(features, user_preferences, state.confidence_tracker)
        
        %{
          response: features.response,
          preference_score: preference_score,
          confidence: confidence,
          reasoning: generate_preference_reasoning(features, user_preferences)
        }
      end)
      
      # Sort by preference score
      sorted_predictions = Enum.sort_by(predictions, & &1.preference_score, :desc)
      
      result = %{
        predictions: sorted_predictions,
        user_profile_strength: calculate_profile_strength(user_preferences),
        context_familiarity: calculate_context_familiarity(context, user_preferences),
        timestamp: System.system_time(:millisecond)
      }
      
      {:reply, {:ok, result}, state}
    rescue
      error ->
        Logger.error("Error predicting preference: #{inspect(error)}")
        {:reply, {:error, :prediction_failed}, state}
    end
  end
  
  @impl true
  def handle_call({:get_user_profile, user_id}, _from, state) do
    user_preferences = get_user_preferences(user_id, state)
    
    profile = %{
      user_id: user_id,
      total_preferences: length(user_preferences),
      preference_patterns: analyze_user_patterns(user_preferences),
      favorite_providers: calculate_favorite_providers(user_preferences),
      context_preferences: calculate_context_preferences(user_preferences),
      confidence_level: calculate_user_confidence(user_id, state.confidence_tracker),
      last_activity: get_last_activity(user_preferences),
      profile_strength: calculate_profile_strength(user_preferences)
    }
    
    {:reply, profile, state}
  end
  
  @impl true
  def handle_call(:get_preference_stats, _from, state) do
    # Aggregate stats from all nodes
    local_stats = calculate_local_stats(state)
    cluster_stats = aggregate_cluster_stats(local_stats)
    
    stats = %{
      node_stats: local_stats,
      cluster_stats: cluster_stats,
      model_performance: get_model_performance(state.model_weights),
      pattern_insights: get_pattern_insights(state.pattern_analyzer),
      sync_status: state.sync_status,
      timestamp: System.system_time(:millisecond)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:analyze_patterns, _from, state) do
    # Perform pattern analysis on preference data
    all_preferences = get_all_preferences_from_cache_and_mnesia(state)
    
    new_patterns = analyze_preference_patterns(all_preferences)
    updated_analyzer = update_pattern_analyzer(state.pattern_analyzer, new_patterns)
    
    # Store patterns in Mnesia for cluster access
    store_patterns_in_mnesia(new_patterns)
    
    # Broadcast pattern updates to peers
    broadcast_pattern_updates(new_patterns)
    
    new_state = %{state | pattern_analyzer: updated_analyzer}
    
    Logger.info("Completed preference pattern analysis - found #{length(new_patterns)} patterns")
    {:reply, {:ok, new_patterns}, new_state}
  end
  
  @impl true
  def handle_call(:update_models, _from, state) do
    # Update preference models based on recent data
    all_preferences = get_all_preferences_from_cache_and_mnesia(state)
    
    if length(all_preferences) >= @preference_batch_size do
      updated_weights = train_preference_models(all_preferences, state.model_weights, state.learning_rate)
      
      # Validate model improvement
      if model_improvement_significant?(state.model_weights, updated_weights, all_preferences) do
        # Store updated models in Mnesia
        store_models_in_mnesia(updated_weights)
        
        # Broadcast model updates to peers
        broadcast_model_updates(updated_weights)
        
        new_state = %{state | model_weights: updated_weights}
        
        Logger.info("Updated preference models with improved performance")
        {:reply, {:ok, :model_updated}, new_state}
      else
        Logger.debug("Model update did not show significant improvement")
        {:reply, {:ok, :no_improvement}, state}
      end
    else
      {:reply, {:error, :insufficient_data}, state}
    end
  end
  
  @impl true
  def handle_info(:analyze_patterns, state) do
    # Periodic pattern analysis
    Task.start(fn ->
      GenServer.call(__MODULE__, :analyze_patterns)
    end)
    
    schedule_pattern_analysis()
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:sync_models, state) do
    # Sync models with peer nodes
    updated_state = sync_models_with_peers(state)
    schedule_model_sync()
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info({:preference_update, preference_record}, state) do
    # Received preference update from peer node
    new_cache = update_preference_cache(state.preference_cache, preference_record)
    store_preference_in_mnesia(preference_record)
    
    new_state = %{state | preference_cache: new_cache}
    Logger.debug("Received preference update from peer node")
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:pattern_update, patterns}, state) do
    # Received pattern update from peer node
    updated_analyzer = merge_pattern_updates(state.pattern_analyzer, patterns)
    new_state = %{state | pattern_analyzer: updated_analyzer}
    
    Logger.debug("Received pattern update from peer node")
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:model_update, model_weights}, state) do
    # Received model update from peer node
    merged_weights = merge_model_weights(state.model_weights, model_weights)
    new_state = %{state | model_weights: merged_weights}
    
    Logger.debug("Received model update from peer node")
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp initialize_mnesia_tables do
    # Create Mnesia tables for distributed preference storage
    tables = [
      {@preference_table, [
        {:attributes, [:id, :user_id, :context, :chosen_response, :alternatives, :feedback, :timestamp, :node_id]},
        {:type, :set},
        {:disc_copies, [Node.self()]}
      ]},
      {@pattern_table, [
        {:attributes, [:id, :pattern_type, :pattern_data, :confidence, :timestamp, :node_id]},
        {:type, :set},
        {:disc_copies, [Node.self()]}
      ]},
      {@model_table, [
        {:attributes, [:id, :model_type, :weights, :performance, :timestamp, :node_id]},
        {:type, :set},
        {:disc_copies, [Node.self()]}
      ]}
    ]
    
    Enum.each(tables, fn {table_name, options} ->
      case :mnesia.create_table(table_name, options) do
        {:atomic, :ok} ->
          Logger.debug("Created Mnesia table: #{table_name}")
        
        {:aborted, {:already_exists, ^table_name}} ->
          Logger.debug("Mnesia table already exists: #{table_name}")
        
        error ->
          Logger.error("Failed to create Mnesia table #{table_name}: #{inspect(error)}")
      end
    end)
  end
  
  defp initialize_pattern_analyzer do
    %{
      provider_patterns: %{},
      context_patterns: %{},
      temporal_patterns: %{},
      feature_importance: %{},
      pattern_confidence: %{}
    }
  end
  
  defp initialize_model_weights do
    %{
      provider_weight: 0.3,
      quality_weight: 0.25,
      speed_weight: 0.15,
      context_weight: 0.2,
      historical_weight: 0.1,
      feature_weights: %{
        content_length: 0.1,
        has_code: 0.2,
        response_time: 0.15,
        quality_score: 0.25,
        context_relevance: 0.2,
        user_history: 0.1
      }
    }
  end
  
  defp update_preference_cache(cache, preference_record) do
    user_id = preference_record.user_id
    user_preferences = Map.get(cache, user_id, [])
    
    # Add new preference and keep last 100 per user
    updated_preferences = [preference_record | user_preferences] |> Enum.take(100)
    
    Map.put(cache, user_id, updated_preferences)
  end
  
  defp store_preference_in_mnesia(preference_record) do
    transaction = fn ->
      :mnesia.write({@preference_table, 
        preference_record.id,
        preference_record.user_id,
        preference_record.context,
        preference_record.chosen_response,
        preference_record.alternatives,
        preference_record.feedback,
        preference_record.timestamp,
        preference_record.node_id
      })
    end
    
    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        :ok
      
      {:aborted, reason} ->
        Logger.error("Failed to store preference in Mnesia: #{inspect(reason)}")
        :error
    end
  end
  
  defp broadcast_preference_to_peers(preference_record) do
    pg_members = :pg.get_members(@pg_scope)
    
    Enum.each(pg_members, fn member ->
      if member != self() do
        send(member, {:preference_update, preference_record})
      end
    end)
  end
  
  defp get_user_preferences(user_id, state) do
    # Get from cache first, then from Mnesia if needed
    case Map.get(state.preference_cache, user_id) do
      nil ->
        load_user_preferences_from_mnesia(user_id)
      
      cached_preferences ->
        cached_preferences
    end
  end
  
  defp load_user_preferences_from_mnesia(user_id) do
    transaction = fn ->
      :mnesia.match_object({@preference_table, :_, user_id, :_, :_, :_, :_, :_, :_})
    end
    
    case :mnesia.transaction(transaction) do
      {:atomic, records} ->
        Enum.map(records, &mnesia_record_to_preference/1)
      
      {:aborted, reason} ->
        Logger.error("Failed to load user preferences from Mnesia: #{inspect(reason)}")
        []
    end
  end
  
  defp mnesia_record_to_preference({@preference_table, id, user_id, context, chosen_response, alternatives, feedback, timestamp, node_id}) do
    %{
      id: id,
      user_id: user_id,
      context: context,
      chosen_response: chosen_response,
      alternatives: alternatives,
      feedback: feedback,
      timestamp: timestamp,
      node_id: node_id
    }
  end
  
  defp extract_response_features(response, context) do
    content = extract_content(response)
    
    %{
      response: response,
      provider: Map.get(response, :provider, :unknown),
      content_length: String.length(content),
      has_code: contains_code?(content),
      quality_score: Map.get(response, :quality_score, 0.5),
      response_time: Map.get(response, :duration_ms, 0),
      context_type: Map.get(context, :type, :general),
      context_domain: Map.get(context, :domain, :general),
      complexity_score: calculate_complexity_score(content),
      readability_score: calculate_readability_score(content)
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
  
  defp calculate_complexity_score(content) do
    # Simple complexity scoring based on content characteristics
    factors = [
      String.length(content) / 1000,  # Length factor
      if(String.contains?(content, "```"), do: 0.3, else: 0.0),  # Code factor
      (String.split(content, "\n") |> length()) / 50,  # Line count factor
      (Regex.scan(~r/[A-Z][a-z]+/, content) |> length()) / 20  # Technical terms factor
    ]
    
    Enum.sum(factors) |> min(1.0)
  end
  
  defp calculate_readability_score(content) do
    # Simple readability scoring
    words = String.split(content, ~r/\s+/) |> length()
    sentences = String.split(content, ~r/[.!?]+/) |> length()
    
    if sentences > 0 and words > 0 do
      avg_words_per_sentence = words / sentences
      
      cond do
        avg_words_per_sentence < 10 -> 0.9  # Very readable
        avg_words_per_sentence < 20 -> 0.7  # Readable
        avg_words_per_sentence < 30 -> 0.5  # Moderate
        true -> 0.3  # Complex
      end
    else
      0.5
    end
  end
  
  defp calculate_preference_score(features, user_preferences, model_weights) do
    if Enum.empty?(user_preferences) do
      # No user history, use default scoring
      default_preference_score(features, model_weights)
    else
      # Use user-specific preference model
      user_preference_score(features, user_preferences, model_weights)
    end
  end
  
  defp default_preference_score(features, model_weights) do
    # Default scoring without user history
    base_scores = %{
      quality: features.quality_score * model_weights.quality_weight,
      speed: calculate_speed_score(features.response_time) * model_weights.speed_weight,
      complexity: (1.0 - features.complexity_score) * 0.1,  # Prefer simpler responses
      readability: features.readability_score * 0.1
    }
    
    Enum.sum(Map.values(base_scores))
  end
  
  defp user_preference_score(features, user_preferences, model_weights) do
    # Calculate score based on user's historical preferences
    
    # Provider preference
    provider_score = calculate_provider_preference_score(features.provider, user_preferences) * model_weights.provider_weight
    
    # Quality preference
    quality_score = features.quality_score * model_weights.quality_weight
    
    # Speed preference
    speed_score = calculate_speed_score(features.response_time) * model_weights.speed_weight
    
    # Context preference
    context_score = calculate_context_preference_score(features, user_preferences) * model_weights.context_weight
    
    # Historical similarity
    historical_score = calculate_historical_similarity_score(features, user_preferences) * model_weights.historical_weight
    
    provider_score + quality_score + speed_score + context_score + historical_score
  end
  
  defp calculate_provider_preference_score(provider, user_preferences) do
    provider_frequencies = user_preferences
    |> Enum.map(&Map.get(&1.chosen_response, :provider))
    |> Enum.frequencies()
    
    total_choices = length(user_preferences)
    provider_choices = Map.get(provider_frequencies, provider, 0)
    
    if total_choices > 0 do
      provider_choices / total_choices
    else
      0.5  # Default neutral score
    end
  end
  
  defp calculate_speed_score(response_time_ms) do
    # Convert response time to preference score (faster = higher score)
    cond do
      response_time_ms < 1000 -> 1.0
      response_time_ms < 3000 -> 0.8
      response_time_ms < 8000 -> 0.6
      response_time_ms < 15000 -> 0.4
      true -> 0.2
    end
  end
  
  defp calculate_context_preference_score(features, user_preferences) do
    # Find similar contexts in user's history
    similar_contexts = Enum.filter(user_preferences, fn pref ->
      Map.get(pref.context, :type) == features.context_type or
      Map.get(pref.context, :domain) == features.context_domain
    end)
    
    if Enum.empty?(similar_contexts) do
      0.5  # No context history
    else
      # Analyze preferences in similar contexts
      analyze_context_specific_preferences(features, similar_contexts)
    end
  end
  
  defp analyze_context_specific_preferences(features, similar_contexts) do
    # Analyze what user prefers in similar contexts
    chosen_features = Enum.map(similar_contexts, fn pref ->
      extract_response_features(pref.chosen_response, pref.context)
    end)
    
    # Calculate similarity to historically chosen responses
    similarity_scores = Enum.map(chosen_features, fn chosen ->
      calculate_feature_similarity(features, chosen)
    end)
    
    if Enum.empty?(similarity_scores) do
      0.5
    else
      Enum.sum(similarity_scores) / length(similarity_scores)
    end
  end
  
  defp calculate_feature_similarity(features1, features2) do
    # Calculate similarity between two feature sets
    similarity_factors = [
      if(features1.provider == features2.provider, do: 0.3, else: 0.0),
      (1.0 - abs(features1.quality_score - features2.quality_score)) * 0.2,
      (1.0 - abs(features1.complexity_score - features2.complexity_score)) * 0.2,
      (1.0 - abs(features1.readability_score - features2.readability_score)) * 0.15,
      if(features1.has_code == features2.has_code, do: 0.15, else: 0.0)
    ]
    
    Enum.sum(similarity_factors)
  end
  
  defp calculate_historical_similarity_score(features, user_preferences) do
    # Calculate how similar this response is to user's historical choices
    if length(user_preferences) < 3 do
      0.5  # Insufficient history
    else
      recent_preferences = Enum.take(user_preferences, 10)
      chosen_responses = Enum.map(recent_preferences, & &1.chosen_response)
      
      similarity_scores = Enum.map(chosen_responses, fn chosen ->
        chosen_features = extract_response_features(chosen, %{})
        calculate_feature_similarity(features, chosen_features)
      end)
      
      Enum.sum(similarity_scores) / length(similarity_scores)
    end
  end
  
  defp calculate_prediction_confidence(features, user_preferences, confidence_tracker) do
    # Calculate confidence in the prediction
    base_confidence = 0.5
    
    # Higher confidence with more user data
    data_confidence = min(length(user_preferences) / 20, 0.3)
    
    # Historical accuracy for this user
    user_accuracy = Map.get(confidence_tracker, features.response.provider, 0.7)
    accuracy_confidence = user_accuracy * 0.2
    
    base_confidence + data_confidence + accuracy_confidence
  end
  
  defp generate_preference_reasoning(features, user_preferences) do
    if Enum.empty?(user_preferences) do
      "Based on general quality metrics (no user history available)"
    else
      provider_pref = calculate_provider_preference_score(features.provider, user_preferences)
      
      cond do
        provider_pref > 0.7 ->
          "Matches user's strong preference for #{features.provider} provider"
        
        features.quality_score > 0.8 ->
          "High quality score aligns with user's quality preferences"
        
        features.readability_score > 0.8 ->
          "High readability matches user's preference for clear responses"
        
        true ->
          "Balanced scoring across user's historical preferences"
      end
    end
  end
  
  defp maybe_update_local_models(state, preference_record) do
    # Update local models if conditions are met
    user_preferences = get_user_preferences(preference_record.user_id, state)
    
    if length(user_preferences) >= @preference_batch_size and 
       should_update_models?(user_preferences, state.model_weights) do
      
      updated_weights = update_user_specific_weights(user_preferences, state.model_weights)
      %{state | model_weights: updated_weights}
    else
      state
    end
  end
  
  defp should_update_models?(user_preferences, _current_weights) do
    # Check if we should update models based on recent feedback
    recent_preferences = Enum.take(user_preferences, 5)
    length(recent_preferences) >= 3
  end
  
  defp update_user_specific_weights(user_preferences, current_weights) do
    # Update weights based on user preferences
    provider_analysis = analyze_provider_preferences(user_preferences)
    quality_analysis = analyze_quality_preferences(user_preferences)
    
    %{current_weights |
      provider_weight: adjust_weight(current_weights.provider_weight, provider_analysis),
      quality_weight: adjust_weight(current_weights.quality_weight, quality_analysis)
    }
  end
  
  defp analyze_provider_preferences(user_preferences) do
    # Analyze user's provider preferences
    providers = Enum.map(user_preferences, &Map.get(&1.chosen_response, :provider))
    provider_freq = Enum.frequencies(providers)
    
    # Calculate preference strength
    if map_size(provider_freq) <= 1 do
      :strong_preference
    else
      max_freq = Enum.max(Map.values(provider_freq))
      total = length(providers)
      
      if max_freq / total > 0.7, do: :strong_preference, else: :moderate_preference
    end
  end
  
  defp analyze_quality_preferences(user_preferences) do
    # Analyze user's quality preferences
    quality_scores = user_preferences
    |> Enum.map(&Map.get(&1.chosen_response, :quality_score, 0.5))
    |> Enum.reject(&is_nil/1)
    
    if Enum.empty?(quality_scores) do
      :unknown
    else
      avg_quality = Enum.sum(quality_scores) / length(quality_scores)
      
      cond do
        avg_quality > 0.8 -> :high_quality_preference
        avg_quality > 0.6 -> :moderate_quality_preference
        true -> :low_quality_tolerance
      end
    end
  end
  
  defp adjust_weight(current_weight, analysis) do
    case analysis do
      :strong_preference -> min(current_weight + 0.1, 0.8)
      :moderate_preference -> current_weight
      :high_quality_preference -> min(current_weight + 0.05, 0.6)
      _ -> current_weight
    end
  end
  
  defp emit_preference_event(preference_record) do
    EventBus.emit("user_preference_recorded", %{
      user_id: preference_record.user_id,
      chosen_provider: Map.get(preference_record.chosen_response, :provider),
      context_type: Map.get(preference_record.context, :type),
      node_id: preference_record.node_id
    })
  end
  
  defp calculate_profile_strength(user_preferences) do
    case length(user_preferences) do
      n when n < 5 -> :weak
      n when n < 20 -> :moderate
      n when n < 50 -> :strong
      _ -> :very_strong
    end
  end
  
  defp calculate_context_familiarity(context, user_preferences) do
    similar_contexts = Enum.count(user_preferences, fn pref ->
      Map.get(pref.context, :type) == Map.get(context, :type)
    end)
    
    case similar_contexts do
      0 -> :unfamiliar
      n when n < 3 -> :somewhat_familiar
      n when n < 10 -> :familiar
      _ -> :very_familiar
    end
  end
  
  defp analyze_user_patterns(user_preferences) do
    %{
      provider_patterns: analyze_provider_patterns(user_preferences),
      temporal_patterns: analyze_temporal_patterns(user_preferences),
      context_patterns: analyze_context_patterns(user_preferences),
      quality_patterns: analyze_quality_patterns(user_preferences)
    }
  end
  
  defp analyze_provider_patterns(user_preferences) do
    user_preferences
    |> Enum.map(&Map.get(&1.chosen_response, :provider))
    |> Enum.frequencies()
  end
  
  defp analyze_temporal_patterns(user_preferences) do
    # Analyze patterns by time of day, day of week, etc.
    time_groups = Enum.group_by(user_preferences, fn pref ->
      datetime = DateTime.from_unix!(pref.timestamp, :millisecond)
      datetime.hour
    end)
    
    Enum.map(time_groups, fn {hour, prefs} ->
      {hour, length(prefs)}
    end) |> Enum.into(%{})
  end
  
  defp analyze_context_patterns(user_preferences) do
    user_preferences
    |> Enum.map(&Map.get(&1.context, :type, :general))
    |> Enum.frequencies()
  end
  
  defp analyze_quality_patterns(user_preferences) do
    quality_scores = user_preferences
    |> Enum.map(&Map.get(&1.chosen_response, :quality_score, 0.5))
    |> Enum.reject(&is_nil/1)
    
    if Enum.empty?(quality_scores) do
      %{avg: 0.5, min: 0.5, max: 0.5}
    else
      %{
        avg: Enum.sum(quality_scores) / length(quality_scores),
        min: Enum.min(quality_scores),
        max: Enum.max(quality_scores)
      }
    end
  end
  
  defp calculate_favorite_providers(user_preferences) do
    user_preferences
    |> Enum.map(&Map.get(&1.chosen_response, :provider))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_provider, count} -> count end, :desc)
    |> Enum.take(3)
  end
  
  defp calculate_context_preferences(user_preferences) do
    user_preferences
    |> Enum.group_by(&Map.get(&1.context, :type, :general))
    |> Enum.map(fn {context_type, prefs} ->
      providers = Enum.map(prefs, &Map.get(&1.chosen_response, :provider))
      favorite_provider = providers |> Enum.frequencies() |> Enum.max_by(&elem(&1, 1), fn -> {:none, 0} end) |> elem(0)
      
      {context_type, %{
        count: length(prefs),
        favorite_provider: favorite_provider
      }}
    end) |> Enum.into(%{})
  end
  
  defp calculate_user_confidence(user_id, confidence_tracker) do
    Map.get(confidence_tracker, user_id, 0.5)
  end
  
  defp get_last_activity(user_preferences) do
    if Enum.empty?(user_preferences) do
      nil
    else
      user_preferences
      |> Enum.map(& &1.timestamp)
      |> Enum.max()
    end
  end
  
  defp generate_preference_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp schedule_pattern_analysis do
    Process.send_after(self(), :analyze_patterns, @pattern_analysis_interval)
  end
  
  defp schedule_model_sync do
    Process.send_after(self(), :sync_models, @pattern_analysis_interval * 2)
  end
  
  # Placeholder implementations for complex functions
  
  defp calculate_local_stats(state) do
    %{
      cached_users: map_size(state.preference_cache),
      total_preferences: Enum.sum(Enum.map(state.preference_cache, fn {_user, prefs} -> length(prefs) end)),
      model_weights: state.model_weights,
      sync_status: state.sync_status
    }
  end
  
  defp aggregate_cluster_stats(local_stats) do
    # Would aggregate stats from all nodes
    local_stats
  end
  
  defp get_model_performance(_model_weights) do
    %{accuracy: 0.75, precision: 0.72, recall: 0.78}
  end
  
  defp get_pattern_insights(_pattern_analyzer) do
    %{patterns_discovered: 5, confidence_avg: 0.7}
  end
  
  defp get_all_preferences_from_cache_and_mnesia(state) do
    # Combine cache and Mnesia data
    cached_prefs = state.preference_cache |> Map.values() |> List.flatten()
    
    # Would also load from Mnesia for complete dataset
    cached_prefs
  end
  
  defp analyze_preference_patterns(_preferences) do
    # Complex pattern analysis implementation
    []
  end
  
  defp update_pattern_analyzer(analyzer, _new_patterns) do
    analyzer
  end
  
  defp store_patterns_in_mnesia(_patterns) do
    :ok
  end
  
  defp broadcast_pattern_updates(_patterns) do
    :ok
  end
  
  defp train_preference_models(preferences, current_weights, learning_rate) do
    # Simple weight adjustment based on recent preferences
    Logger.debug("Training preference models with #{length(preferences)} examples")
    
    # Analyze recent preferences for weight adjustments
    recent_prefs = Enum.take(preferences, 20)
    
    provider_success = analyze_provider_success_rates(recent_prefs)
    quality_importance = analyze_quality_importance(recent_prefs)
    
    # Adjust weights with learning rate
    %{current_weights |
      provider_weight: adjust_weight_with_learning_rate(current_weights.provider_weight, provider_success, learning_rate),
      quality_weight: adjust_weight_with_learning_rate(current_weights.quality_weight, quality_importance, learning_rate)
    }
  end
  
  defp analyze_provider_success_rates(preferences) do
    # Analyze which providers are chosen most often
    providers = Enum.map(preferences, &Map.get(&1.chosen_response, :provider))
    frequencies = Enum.frequencies(providers)
    
    if map_size(frequencies) <= 1 do
      1.0  # Strong provider preference
    else
      max_freq = Enum.max(Map.values(frequencies))
      max_freq / length(providers)
    end
  end
  
  defp analyze_quality_importance(preferences) do
    # Analyze if users consistently choose high-quality responses
    quality_scores = preferences
    |> Enum.map(&Map.get(&1.chosen_response, :quality_score, 0.5))
    |> Enum.reject(&is_nil/1)
    
    if Enum.empty?(quality_scores) do
      0.5
    else
      Enum.sum(quality_scores) / length(quality_scores)
    end
  end
  
  defp adjust_weight_with_learning_rate(current_weight, importance_score, learning_rate) do
    # Adjust weight toward importance score with learning rate
    adjustment = (importance_score - current_weight) * learning_rate
    new_weight = current_weight + adjustment
    
    # Keep weights in reasonable bounds
    max(0.1, min(0.8, new_weight))
  end
  
  defp model_improvement_significant?(old_weights, new_weights, preferences) do
    # Simple check - would implement proper validation
    weight_changes = Enum.map(old_weights, fn {key, old_value} ->
      new_value = Map.get(new_weights, key, old_value)
      abs(new_value - old_value)
    end)
    
    max_change = Enum.max(weight_changes)
    max_change > @model_update_threshold and length(preferences) >= @preference_batch_size
  end
  
  defp store_models_in_mnesia(_model_weights) do
    # Store updated models in Mnesia
    :ok
  end
  
  defp broadcast_model_updates(_model_weights) do
    # Broadcast to peer nodes
    :ok
  end
  
  defp sync_models_with_peers(state) do
    # Sync with peer nodes
    state
  end
  
  defp merge_pattern_updates(analyzer, _patterns) do
    analyzer
  end
  
  defp merge_model_weights(local_weights, remote_weights) do
    # Simple averaging of weights
    Enum.reduce(remote_weights, local_weights, fn {key, remote_value}, acc ->
      local_value = Map.get(acc, key, 0.5)
      merged_value = (local_value + remote_value) / 2
      Map.put(acc, key, merged_value)
    end)
  end
end