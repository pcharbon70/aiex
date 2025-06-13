defmodule Aiex.AI.Distributed.ConfidenceScorer do
  @moduledoc """
  Implements cluster confidence scoring system for response quality confidence.
  
  This module provides:
  - Multi-dimensional confidence scoring
  - Cluster-wide confidence aggregation
  - Node-specific confidence tracking
  - Historical confidence analysis
  - Confidence calibration and validation
  - Real-time confidence monitoring
  """
  
  use GenServer
  require Logger
  
  alias Aiex.AI.Distributed.{QualityMetrics, PreferenceLearner}
  alias Aiex.EventBus
  alias Aiex.Telemetry
  
  @pg_scope :aiex_confidence_scorer
  @confidence_table :confidence_scores
  @confidence_history_table :confidence_history
  
  @confidence_window_size 100
  @calibration_interval 600_000  # 10 minutes
  @min_samples_for_calibration 20
  
  defstruct [
    :node_id,
    :confidence_models,
    :historical_scores,
    :calibration_data,
    :cluster_aggregates,
    :node_weights,
    :confidence_thresholds,
    :validation_metrics,
    :peer_nodes
  ]
  
  @type confidence_factors :: %{
    ml_confidence: float(),
    consensus_confidence: float(),
    historical_confidence: float(),
    peer_agreement: float(),
    data_quality: float(),
    model_uncertainty: float(),
    context_familiarity: float()
  }
  
  @type confidence_score :: %{
    overall_confidence: float(),
    factors: confidence_factors(),
    calibrated_confidence: float(),
    confidence_interval: {float(), float()},
    reliability_score: float(),
    metadata: map()
  }
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Calculate confidence score for a response selection.
  """
  def calculate_confidence(selection_data, context \\ %{}, options \\ []) do
    GenServer.call(__MODULE__, {:calculate_confidence, selection_data, context, options})
  end
  
  @doc """
  Update confidence model with feedback.
  """
  def update_confidence_model(prediction, actual_outcome, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:update_confidence_model, prediction, actual_outcome, metadata})
  end
  
  @doc """
  Get confidence statistics for the cluster.
  """
  def get_confidence_stats do
    GenServer.call(__MODULE__, :get_confidence_stats)
  end
  
  @doc """
  Calibrate confidence models across cluster.
  """
  def calibrate_models do
    GenServer.call(__MODULE__, :calibrate_models)
  end
  
  @doc """
  Get node-specific confidence metrics.
  """
  def get_node_confidence_metrics(node_id \\ nil) do
    target_node = node_id || Node.self()
    GenServer.call(__MODULE__, {:get_node_confidence_metrics, target_node})
  end
  
  @doc """
  Set confidence thresholds for different quality levels.
  """
  def set_confidence_thresholds(thresholds) do
    GenServer.call(__MODULE__, {:set_confidence_thresholds, thresholds})
  end
  
  @doc """
  Validate confidence prediction accuracy.
  """
  def validate_confidence_accuracy(time_window \\ 86_400_000) do
    GenServer.call(__MODULE__, {:validate_confidence_accuracy, time_window})
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, Node.self())
    
    # Join pg group for distributed coordination
    :pg.join(@pg_scope, self())
    
    # Initialize Mnesia tables
    initialize_mnesia_tables()
    
    state = %__MODULE__{
      node_id: node_id,
      confidence_models: initialize_confidence_models(),
      historical_scores: [],
      calibration_data: %{},
      cluster_aggregates: %{},
      node_weights: initialize_node_weights(),
      confidence_thresholds: initialize_confidence_thresholds(),
      validation_metrics: %{},
      peer_nodes: []
    }
    
    # Load historical data
    loaded_state = load_confidence_data_from_mnesia(state)
    
    # Schedule periodic tasks
    schedule_calibration()
    schedule_validation()
    
    Logger.info("ConfidenceScorer started on node #{node_id}")
    
    {:ok, loaded_state}
  end
  
  @impl true
  def handle_call({:calculate_confidence, selection_data, context, options}, _from, state) do
    try do
      # Extract confidence factors
      factors = extract_confidence_factors(selection_data, context, state)
      
      # Calculate raw confidence score
      raw_confidence = calculate_raw_confidence(factors, state.confidence_models)
      
      # Apply calibration
      calibrated_confidence = apply_calibration(raw_confidence, factors, state.calibration_data)
      
      # Calculate confidence interval
      confidence_interval = calculate_confidence_interval(calibrated_confidence, factors, state)
      
      # Calculate reliability score
      reliability_score = calculate_reliability_score(factors, state.validation_metrics)
      
      # Aggregate with cluster data if available
      cluster_confidence = aggregate_cluster_confidence(calibrated_confidence, state.cluster_aggregates)
      
      confidence_score = %{
        overall_confidence: cluster_confidence,
        factors: factors,
        calibrated_confidence: calibrated_confidence,
        confidence_interval: confidence_interval,
        reliability_score: reliability_score,
        metadata: %{
          node_id: state.node_id,
          calculation_method: determine_calculation_method(options),
          timestamp: System.system_time(:millisecond),
          context_hash: hash_context(context)
        }
      }
      
      # Record confidence score for learning
      new_state = record_confidence_score(state, confidence_score, selection_data)
      
      # Emit telemetry
      emit_confidence_telemetry(confidence_score)
      
      {:reply, {:ok, confidence_score}, new_state}
    rescue
      error ->
        Logger.error("Error calculating confidence: #{inspect(error)}")
        {:reply, {:error, :calculation_failed}, state}
    end
  end
  
  @impl true
  def handle_call({:update_confidence_model, prediction, actual_outcome, metadata}, _from, state) do
    # Update confidence model with feedback
    feedback_entry = %{
      predicted_confidence: prediction.overall_confidence,
      actual_outcome: actual_outcome,
      prediction_factors: prediction.factors,
      metadata: metadata,
      timestamp: System.system_time(:millisecond),
      node_id: state.node_id
    }
    
    # Store feedback
    new_state = add_feedback_to_calibration_data(state, feedback_entry)
    store_confidence_feedback(feedback_entry)
    
    # Update models if enough feedback accumulated
    updated_state = maybe_update_models(new_state)
    
    Logger.debug("Updated confidence model with feedback")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call(:get_confidence_stats, _from, state) do
    stats = %{
      node_id: state.node_id,
      historical_scores_count: length(state.historical_scores),
      confidence_models: get_model_info(state.confidence_models),
      calibration_data_points: count_calibration_data(state.calibration_data),
      cluster_aggregates: state.cluster_aggregates,
      node_weights: state.node_weights,
      confidence_thresholds: state.confidence_thresholds,
      validation_metrics: state.validation_metrics,
      recent_confidence_distribution: calculate_confidence_distribution(state.historical_scores),
      peer_nodes_count: length(state.peer_nodes),
      timestamp: System.system_time(:millisecond)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:calibrate_models, _from, state) do
    if sufficient_calibration_data?(state.calibration_data) do
      # Perform model calibration
      calibrated_models = calibrate_confidence_models(state.confidence_models, state.calibration_data)
      updated_calibration = update_calibration_parameters(state.calibration_data)
      
      new_state = %{state | 
        confidence_models: calibrated_models,
        calibration_data: updated_calibration
      }
      
      # Broadcast calibration update to peers
      broadcast_calibration_update(calibrated_models, updated_calibration)
      
      # Store calibrated models
      store_calibrated_models(calibrated_models)
      
      Logger.info("Confidence models calibrated successfully")
      {:reply, {:ok, :calibrated}, new_state}
    else
      Logger.debug("Insufficient calibration data for model update")
      {:reply, {:error, :insufficient_data}, state}
    end
  end
  
  @impl true
  def handle_call({:get_node_confidence_metrics, target_node}, _from, state) do
    if target_node == state.node_id do
      # Local metrics
      metrics = calculate_local_confidence_metrics(state)
      {:reply, {:ok, metrics}, state}
    else
      # Request metrics from remote node
      case request_remote_confidence_metrics(target_node) do
        {:ok, metrics} ->
          {:reply, {:ok, metrics}, state}
        
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end
  
  @impl true
  def handle_call({:set_confidence_thresholds, thresholds}, _from, state) do
    # Validate thresholds
    case validate_confidence_thresholds(thresholds) do
      :ok ->
        new_state = %{state | confidence_thresholds: thresholds}
        
        # Broadcast threshold update
        broadcast_threshold_update(thresholds)
        
        Logger.info("Updated confidence thresholds")
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:validate_confidence_accuracy, time_window}, _from, state) do
    # Validate confidence prediction accuracy over time window
    validation_result = validate_prediction_accuracy(state, time_window)
    
    # Update validation metrics
    new_state = %{state | validation_metrics: validation_result}
    
    {:reply, {:ok, validation_result}, new_state}
  end
  
  @impl true
  def handle_info(:calibrate_models, state) do
    # Periodic model calibration
    if sufficient_calibration_data?(state.calibration_data) do
      Task.start(fn ->
        GenServer.call(__MODULE__, :calibrate_models)
      end)
    end
    
    schedule_calibration()
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:validate_accuracy, state) do
    # Periodic accuracy validation
    Task.start(fn ->
      GenServer.call(__MODULE__, {:validate_confidence_accuracy, 86_400_000})
    end)
    
    schedule_validation()
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:calibration_update, models, calibration_data, from_node}, state) do
    # Received calibration update from peer node
    merged_models = merge_confidence_models(state.confidence_models, models)
    merged_calibration = merge_calibration_data(state.calibration_data, calibration_data)
    
    new_state = %{state | 
      confidence_models: merged_models,
      calibration_data: merged_calibration
    }
    
    Logger.debug("Received calibration update from #{from_node}")
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:threshold_update, thresholds, from_node}, state) do
    # Received threshold update from peer node
    new_state = %{state | confidence_thresholds: thresholds}
    
    Logger.debug("Received threshold update from #{from_node}")
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:confidence_request, request_id, from_node}, state) do
    # Received confidence metrics request from peer node
    metrics = calculate_local_confidence_metrics(state)
    
    # Send response back
    send_confidence_response(from_node, request_id, metrics)
    
    {:noreply, state}
  end
  
  # Private Functions
  
  defp initialize_mnesia_tables do
    tables = [
      {@confidence_table, [
        {:attributes, [:id, :overall_confidence, :factors, :calibrated_confidence, :reliability_score, :timestamp, :node_id]},
        {:type, :ordered_set},
        {:disc_copies, [Node.self()]}
      ]},
      {@confidence_history_table, [
        {:attributes, [:id, :predicted_confidence, :actual_outcome, :accuracy, :timestamp, :node_id]},
        {:type, :ordered_set},
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
  
  defp initialize_confidence_models do
    %{
      base_model: %{
        type: :weighted_average,
        weights: %{
          ml_confidence: 0.25,
          consensus_confidence: 0.20,
          historical_confidence: 0.15,
          peer_agreement: 0.15,
          data_quality: 0.10,
          model_uncertainty: 0.10,
          context_familiarity: 0.05
        }
      },
      calibration_model: %{
        type: :isotonic_regression,
        calibration_curve: [],
        reliability_curve: []
      },
      uncertainty_model: %{
        type: :bayesian,
        prior_alpha: 1.0,
        prior_beta: 1.0,
        observations: []
      }
    }
  end
  
  defp initialize_node_weights do
    %{
      Node.self() => 1.0
    }
  end
  
  defp initialize_confidence_thresholds do
    %{
      high_confidence: 0.8,
      medium_confidence: 0.6,
      low_confidence: 0.4,
      minimum_acceptable: 0.2
    }
  end
  
  defp extract_confidence_factors(selection_data, context, state) do
    # Extract various confidence factors
    %{
      ml_confidence: extract_ml_confidence(selection_data),
      consensus_confidence: extract_consensus_confidence(selection_data),
      historical_confidence: extract_historical_confidence(selection_data, state),
      peer_agreement: extract_peer_agreement(selection_data, state),
      data_quality: extract_data_quality(selection_data, context),
      model_uncertainty: extract_model_uncertainty(selection_data, state),
      context_familiarity: extract_context_familiarity(context, state)
    }
  end
  
  defp extract_ml_confidence(selection_data) do
    # Extract confidence from ML rankings
    ml_rankings = Map.get(selection_data, :ml_rankings, [])
    
    if Enum.empty?(ml_rankings) do
      0.5
    else
      scores = Enum.map(ml_rankings, & &1.ml_score)
      max_score = Enum.max(scores)
      score_variance = calculate_variance(scores)
      
      # Higher max score and lower variance = higher confidence
      base_confidence = max_score
      variance_penalty = min(score_variance, 0.3)
      
      max(0.0, base_confidence - variance_penalty)
    end
  end
  
  defp extract_consensus_confidence(selection_data) do
    # Extract confidence from consensus results
    consensus_result = Map.get(selection_data, :consensus_result, %{})
    Map.get(consensus_result, :confidence, 0.5)
  end
  
  defp extract_historical_confidence(selection_data, state) do
    # Calculate confidence based on historical performance
    selected_provider = get_selected_provider(selection_data)
    
    if selected_provider do
      calculate_provider_historical_confidence(selected_provider, state.historical_scores)
    else
      0.5
    end
  end
  
  defp extract_peer_agreement(selection_data, state) do
    # Calculate agreement among peer nodes
    participating_nodes = Map.get(selection_data, :participating_nodes, 1)
    
    case participating_nodes do
      n when n <= 1 -> 0.5  # Single node
      n when n <= 3 -> 0.7  # Small cluster
      n when n <= 5 -> 0.8  # Medium cluster
      _ -> 0.9              # Large cluster
    end
  end
  
  defp extract_data_quality(selection_data, context) do
    # Assess quality of input data
    factors = [
      has_sufficient_responses?(selection_data),
      has_quality_scores?(selection_data),
      has_complete_context?(context),
      has_recent_data?(selection_data)
    ]
    
    quality_count = Enum.count(factors, & &1)
    quality_count / length(factors)
  end
  
  defp extract_model_uncertainty(selection_data, state) do
    # Calculate model uncertainty
    ml_rankings = Map.get(selection_data, :ml_rankings, [])
    
    if length(ml_rankings) < 2 do
      0.3  # High uncertainty with few options
    else
      scores = Enum.map(ml_rankings, & &1.ml_score)
      score_std = calculate_standard_deviation(scores)
      
      # Lower standard deviation = lower uncertainty = higher confidence factor
      1.0 - min(score_std, 0.5)
    end
  end
  
  defp extract_context_familiarity(context, state) do
    # Calculate familiarity with this type of context
    context_type = Map.get(context, :type, :unknown)
    
    # Look for similar contexts in historical data
    similar_contexts = Enum.count(state.historical_scores, fn score ->
      score_context = Map.get(score.metadata, :context_hash)
      context_hash = hash_context(context)
      
      score_context == context_hash or
      Map.get(score.metadata, :context_type) == context_type
    end)
    
    # More familiar contexts = higher confidence
    familiarity_score = min(similar_contexts / 10, 1.0)
    max(0.3, familiarity_score)
  end
  
  defp calculate_raw_confidence(factors, confidence_models) do
    # Calculate weighted average confidence
    base_model = confidence_models.base_model
    weights = base_model.weights
    
    Enum.reduce(factors, 0.0, fn {factor, value}, acc ->
      weight = Map.get(weights, factor, 0.0)
      acc + (value * weight)
    end)
  end
  
  defp apply_calibration(raw_confidence, factors, calibration_data) do
    # Apply calibration to raw confidence score
    if Map.has_key?(calibration_data, :calibration_curve) and
       not Enum.empty?(calibration_data.calibration_curve) do
      
      # Apply isotonic regression calibration
      apply_isotonic_calibration(raw_confidence, calibration_data.calibration_curve)
    else
      # No calibration data available
      raw_confidence
    end
  end
  
  defp apply_isotonic_calibration(raw_confidence, calibration_curve) do
    # Find appropriate calibration point
    case find_calibration_point(raw_confidence, calibration_curve) do
      {lower, upper} ->
        # Interpolate between calibration points
        interpolate_calibration(raw_confidence, lower, upper)
      
      nil ->
        # No calibration point found, return raw confidence
        raw_confidence
    end
  end
  
  defp find_calibration_point(raw_confidence, calibration_curve) do
    # Find surrounding calibration points
    sorted_curve = Enum.sort_by(calibration_curve, &elem(&1, 0))
    
    case Enum.find_index(sorted_curve, fn {predicted, _actual} ->
      predicted >= raw_confidence
    end) do
      nil ->
        # Beyond calibration range
        nil
      
      0 ->
        # Below calibration range
        {List.first(sorted_curve), List.first(sorted_curve)}
      
      index ->
        lower = Enum.at(sorted_curve, index - 1)
        upper = Enum.at(sorted_curve, index)
        {lower, upper}
    end
  end
  
  defp interpolate_calibration(raw_confidence, {pred1, actual1}, {pred2, actual2}) do
    if pred1 == pred2 do
      actual1
    else
      # Linear interpolation
      ratio = (raw_confidence - pred1) / (pred2 - pred1)
      actual1 + ratio * (actual2 - actual1)
    end
  end
  
  defp calculate_confidence_interval(calibrated_confidence, factors, state) do
    # Calculate confidence interval using uncertainty model
    uncertainty_model = state.confidence_models.uncertainty_model
    
    # Base interval width on various uncertainty factors
    base_width = 0.1
    
    uncertainty_factors = [
      1.0 - factors.data_quality,
      factors.model_uncertainty,
      1.0 - factors.context_familiarity
    ]
    
    avg_uncertainty = Enum.sum(uncertainty_factors) / length(uncertainty_factors)
    interval_width = base_width + (avg_uncertainty * 0.2)
    
    lower_bound = max(0.0, calibrated_confidence - interval_width / 2)
    upper_bound = min(1.0, calibrated_confidence + interval_width / 2)
    
    {lower_bound, upper_bound}
  end
  
  defp calculate_reliability_score(factors, validation_metrics) do
    # Calculate reliability based on historical validation
    base_reliability = 0.7
    
    # Adjust based on validation metrics
    if Map.has_key?(validation_metrics, :accuracy) do
      accuracy_adjustment = (validation_metrics.accuracy - 0.5) * 0.4
      calibration_adjustment = Map.get(validation_metrics, :calibration_score, 0.0) * 0.2
      
      base_reliability + accuracy_adjustment + calibration_adjustment
    else
      base_reliability
    end
  end
  
  defp aggregate_cluster_confidence(local_confidence, cluster_aggregates) do
    # Aggregate confidence with cluster data
    if Map.has_key?(cluster_aggregates, :peer_confidences) and
       not Enum.empty?(cluster_aggregates.peer_confidences) do
      
      all_confidences = [local_confidence | cluster_aggregates.peer_confidences]
      
      # Weighted average based on node reliability
      weighted_sum = Enum.sum(all_confidences)
      weighted_sum / length(all_confidences)
    else
      local_confidence
    end
  end
  
  defp record_confidence_score(state, confidence_score, selection_data) do
    # Add to historical scores
    score_record = %{
      overall_confidence: confidence_score.overall_confidence,
      factors: confidence_score.factors,
      calibrated_confidence: confidence_score.calibrated_confidence,
      reliability_score: confidence_score.reliability_score,
      timestamp: System.system_time(:millisecond),
      metadata: confidence_score.metadata
    }
    
    new_historical_scores = [score_record | state.historical_scores]
    |> Enum.take(@confidence_window_size)
    
    # Store in Mnesia
    store_confidence_score(score_record)
    
    %{state | historical_scores: new_historical_scores}
  end
  
  defp store_confidence_score(score_record) do
    score_id = generate_score_id()
    
    transaction = fn ->
      :mnesia.write({@confidence_table,
        score_id,
        score_record.overall_confidence,
        score_record.factors,
        score_record.calibrated_confidence,
        score_record.reliability_score,
        score_record.timestamp,
        Node.self()
      })
    end
    
    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        :ok
      
      {:aborted, reason} ->
        Logger.error("Failed to store confidence score: #{inspect(reason)}")
        :error
    end
  end
  
  defp load_confidence_data_from_mnesia(state) do
    # Load recent confidence scores
    state
  end
  
  defp add_feedback_to_calibration_data(state, feedback_entry) do
    current_data = Map.get(state.calibration_data, :feedback, [])
    new_feedback = [feedback_entry | current_data] |> Enum.take(1000)
    
    new_calibration_data = Map.put(state.calibration_data, :feedback, new_feedback)
    %{state | calibration_data: new_calibration_data}
  end
  
  defp store_confidence_feedback(feedback_entry) do
    # Store feedback for model improvement
    Logger.debug("Stored confidence feedback")
  end
  
  defp maybe_update_models(state) do
    feedback_count = length(Map.get(state.calibration_data, :feedback, []))
    
    if feedback_count >= @min_samples_for_calibration do
      # Trigger model update
      Task.start(fn ->
        GenServer.call(__MODULE__, :calibrate_models)
      end)
    end
    
    state
  end
  
  defp sufficient_calibration_data?(calibration_data) do
    feedback_count = length(Map.get(calibration_data, :feedback, []))
    feedback_count >= @min_samples_for_calibration
  end
  
  defp calibrate_confidence_models(models, calibration_data) do
    feedback = Map.get(calibration_data, :feedback, [])
    
    if length(feedback) >= @min_samples_for_calibration do
      # Calibrate isotonic regression model
      calibration_curve = build_calibration_curve(feedback)
      
      updated_calibration_model = %{models.calibration_model | 
        calibration_curve: calibration_curve
      }
      
      %{models | calibration_model: updated_calibration_model}
    else
      models
    end
  end
  
  defp build_calibration_curve(feedback) do
    # Build calibration curve from feedback data
    feedback
    |> Enum.map(fn entry ->
      predicted = entry.predicted_confidence
      actual = if entry.actual_outcome == :correct, do: 1.0, else: 0.0
      {predicted, actual}
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {predicted, outcomes} ->
      actual_values = Enum.map(outcomes, &elem(&1, 1))
      avg_actual = Enum.sum(actual_values) / length(actual_values)
      {predicted, avg_actual}
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end
  
  defp update_calibration_parameters(calibration_data) do
    # Update calibration parameters
    calibration_data
  end
  
  defp broadcast_calibration_update(models, calibration_data) do
    pg_members = :pg.get_members(@pg_scope)
    
    Enum.each(pg_members, fn member ->
      if member != self() do
        send(member, {:calibration_update, models, calibration_data, Node.self()})
      end
    end)
  end
  
  defp store_calibrated_models(models) do
    # Store calibrated models
    Logger.debug("Stored calibrated confidence models")
  end
  
  defp calculate_local_confidence_metrics(state) do
    %{
      node_id: state.node_id,
      total_scores: length(state.historical_scores),
      avg_confidence: calculate_avg_confidence(state.historical_scores),
      confidence_distribution: calculate_confidence_distribution(state.historical_scores),
      calibration_status: get_calibration_status(state.calibration_data),
      validation_metrics: state.validation_metrics,
      timestamp: System.system_time(:millisecond)
    }
  end
  
  defp request_remote_confidence_metrics(target_node) do
    # Request metrics from remote node
    request_id = generate_request_id()
    
    case :pg.get_members(@pg_scope) |> Enum.find(&(node(&1) == target_node)) do
      nil ->
        {:error, :node_not_found}
      
      pid ->
        send(pid, {:confidence_request, request_id, Node.self()})
        
        # Wait for response (simplified)
        receive do
          {:confidence_response, ^request_id, metrics} ->
            {:ok, metrics}
        after
          5000 ->
            {:error, :timeout}
        end
    end
  end
  
  defp send_confidence_response(target_node, request_id, metrics) do
    case :pg.get_members(@pg_scope) |> Enum.find(&(node(&1) == target_node)) do
      nil ->
        Logger.warn("Could not send confidence response to #{target_node}")
      
      pid ->
        send(pid, {:confidence_response, request_id, metrics})
    end
  end
  
  defp validate_confidence_thresholds(thresholds) do
    required_keys = [:high_confidence, :medium_confidence, :low_confidence, :minimum_acceptable]
    
    if Enum.all?(required_keys, &Map.has_key?(thresholds, &1)) do
      values = Map.values(thresholds)
      
      if Enum.all?(values, &(&1 >= 0.0 and &1 <= 1.0)) do
        :ok
      else
        {:error, :invalid_threshold_values}
      end
    else
      {:error, :missing_required_thresholds}
    end
  end
  
  defp broadcast_threshold_update(thresholds) do
    pg_members = :pg.get_members(@pg_scope)
    
    Enum.each(pg_members, fn member ->
      if member != self() do
        send(member, {:threshold_update, thresholds, Node.self()})
      end
    end)
  end
  
  defp validate_prediction_accuracy(state, time_window) do
    cutoff_time = System.system_time(:millisecond) - time_window
    
    recent_feedback = state.calibration_data
    |> Map.get(:feedback, [])
    |> Enum.filter(&(&1.timestamp >= cutoff_time))
    
    if length(recent_feedback) >= 5 do
      accuracy = calculate_prediction_accuracy(recent_feedback)
      calibration_score = calculate_calibration_score(recent_feedback)
      
      %{
        accuracy: accuracy,
        calibration_score: calibration_score,
        sample_size: length(recent_feedback),
        time_window: time_window,
        timestamp: System.system_time(:millisecond)
      }
    else
      %{
        accuracy: 0.0,
        calibration_score: 0.0,
        sample_size: length(recent_feedback),
        error: :insufficient_samples
      }
    end
  end
  
  defp calculate_prediction_accuracy(feedback) do
    correct_predictions = Enum.count(feedback, fn entry ->
      predicted = entry.predicted_confidence
      actual = if entry.actual_outcome == :correct, do: 1.0, else: 0.0
      
      # Consider prediction accurate if within 0.2 of actual
      abs(predicted - actual) <= 0.2
    end)
    
    correct_predictions / length(feedback)
  end
  
  defp calculate_calibration_score(feedback) do
    # Calculate Brier score for calibration
    brier_scores = Enum.map(feedback, fn entry ->
      predicted = entry.predicted_confidence
      actual = if entry.actual_outcome == :correct, do: 1.0, else: 0.0
      
      :math.pow(predicted - actual, 2)
    end)
    
    avg_brier = Enum.sum(brier_scores) / length(brier_scores)
    
    # Convert to calibration score (higher is better)
    1.0 - avg_brier
  end
  
  # Helper Functions
  
  defp get_selected_provider(selection_data) do
    consensus_result = Map.get(selection_data, :consensus_result, %{})
    selected_response = Map.get(consensus_result, :selected_response)
    
    if selected_response do
      Map.get(selected_response, :provider)
    else
      nil
    end
  end
  
  defp calculate_provider_historical_confidence(provider, historical_scores) do
    provider_scores = Enum.filter(historical_scores, fn score ->
      # Would need to track provider in metadata
      true  # Placeholder
    end)
    
    if Enum.empty?(provider_scores) do
      0.5
    else
      confidences = Enum.map(provider_scores, & &1.overall_confidence)
      Enum.sum(confidences) / length(confidences)
    end
  end
  
  defp has_sufficient_responses?(selection_data) do
    ml_rankings = Map.get(selection_data, :ml_rankings, [])
    length(ml_rankings) >= 2
  end
  
  defp has_quality_scores?(selection_data) do
    ml_rankings = Map.get(selection_data, :ml_rankings, [])
    Enum.all?(ml_rankings, &Map.has_key?(&1, :ml_score))
  end
  
  defp has_complete_context?(context) do
    required_fields = [:type]
    Enum.all?(required_fields, &Map.has_key?(context, &1))
  end
  
  defp has_recent_data?(selection_data) do
    # Check if data is recent (within last hour)
    current_time = System.system_time(:millisecond)
    data_time = Map.get(selection_data, :timestamp, current_time)
    
    current_time - data_time < 3_600_000
  end
  
  defp calculate_variance(values) do
    if length(values) < 2 do
      0.0
    else
      mean = Enum.sum(values) / length(values)
      sum_squares = Enum.sum(Enum.map(values, &:math.pow(&1 - mean, 2)))
      sum_squares / length(values)
    end
  end
  
  defp calculate_standard_deviation(values) do
    :math.sqrt(calculate_variance(values))
  end
  
  defp hash_context(context) do
    context
    |> :erlang.term_to_binary()
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end
  
  defp determine_calculation_method(options) do
    Keyword.get(options, :method, :standard)
  end
  
  defp emit_confidence_telemetry(confidence_score) do
    Telemetry.emit([:aiex, :ai, :confidence, :calculated], %{
      overall_confidence: confidence_score.overall_confidence,
      calibrated_confidence: confidence_score.calibrated_confidence,
      reliability_score: confidence_score.reliability_score
    }, %{
      node_id: confidence_score.metadata.node_id,
      calculation_method: confidence_score.metadata.calculation_method
    })
  end
  
  defp get_model_info(models) do
    Enum.map(models, fn {name, model} ->
      {name, %{type: model.type, status: :active}}
    end) |> Enum.into(%{})
  end
  
  defp count_calibration_data(calibration_data) do
    length(Map.get(calibration_data, :feedback, []))
  end
  
  defp calculate_confidence_distribution(historical_scores) do
    if Enum.empty?(historical_scores) do
      %{high: 0, medium: 0, low: 0}
    else
      confidences = Enum.map(historical_scores, & &1.overall_confidence)
      
      %{
        high: Enum.count(confidences, &(&1 >= 0.8)),
        medium: Enum.count(confidences, &(&1 >= 0.6 and &1 < 0.8)),
        low: Enum.count(confidences, &(&1 < 0.6))
      }
    end
  end
  
  defp calculate_avg_confidence(historical_scores) do
    if Enum.empty?(historical_scores) do
      0.0
    else
      confidences = Enum.map(historical_scores, & &1.overall_confidence)
      Enum.sum(confidences) / length(confidences)
    end
  end
  
  defp get_calibration_status(calibration_data) do
    feedback_count = length(Map.get(calibration_data, :feedback, []))
    
    cond do
      feedback_count < @min_samples_for_calibration -> :insufficient_data
      feedback_count < 50 -> :basic_calibration
      feedback_count < 100 -> :good_calibration
      true -> :excellent_calibration
    end
  end
  
  defp merge_confidence_models(local_models, remote_models) do
    # Simple merge - in production would be more sophisticated
    local_models
  end
  
  defp merge_calibration_data(local_data, remote_data) do
    # Simple merge - in production would be more sophisticated
    local_data
  end
  
  defp generate_score_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
  
  defp schedule_calibration do
    Process.send_after(self(), :calibrate_models, @calibration_interval)
  end
  
  defp schedule_validation do
    Process.send_after(self(), :validate_accuracy, @calibration_interval * 2)
  end
end