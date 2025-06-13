defmodule Aiex.AI.Distributed.ResponseComparator do
  @moduledoc """
  Manages parallel AI request execution across multiple providers and nodes
  for response comparison and selection.
  
  Implements response quality assessment, consensus mechanisms, and statistical
  analysis to select the best response from multiple AI providers.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.EventBus
  alias Aiex.Telemetry
  alias Aiex.AI.Distributed.{Coordinator, QualityMetrics}
  
  @comparison_timeout 30_000
  @max_parallel_requests 5
  @min_responses_for_consensus 2
  
  defstruct [
    :active_comparisons,
    :completed_comparisons,
    :quality_assessor,
    :consensus_strategy,
    :performance_history
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Execute request across multiple providers for comparison.
  
  Returns the best response based on quality metrics and consensus.
  """
  def compare_responses(request, options \\ []) do
    GenServer.call(__MODULE__, {:compare_responses, request, options}, @comparison_timeout + 5_000)
  end
  
  @doc """
  Get comparison statistics.
  """
  def get_comparison_stats do
    GenServer.call(__MODULE__, :get_comparison_stats)
  end
  
  @doc """
  Get performance history for providers.
  """
  def get_provider_performance do
    GenServer.call(__MODULE__, :get_provider_performance)
  end
  
  @doc """
  Set consensus strategy (:majority, :quality_weighted, :best_quality, :hybrid).
  """
  def set_consensus_strategy(strategy) do
    GenServer.call(__MODULE__, {:set_consensus_strategy, strategy})
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    consensus_strategy = Keyword.get(opts, :consensus_strategy, :hybrid)
    
    state = %__MODULE__{
      active_comparisons: %{},
      completed_comparisons: [],
      quality_assessor: nil,
      consensus_strategy: consensus_strategy,
      performance_history: %{}
    }
    
    Logger.info("ResponseComparator started with consensus strategy: #{consensus_strategy}")
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:compare_responses, request, options}, from, state) do
    comparison_id = generate_comparison_id()
    providers = get_target_providers(request, options)
    
    if length(providers) < @min_responses_for_consensus do
      {:reply, {:error, :insufficient_providers}, state}
    else
      # Start parallel execution
      comparison = start_parallel_execution(comparison_id, request, providers, from, options)
      
      new_state = %{state | 
        active_comparisons: Map.put(state.active_comparisons, comparison_id, comparison)
      }
      
      {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_comparison_stats, _from, state) do
    stats = %{
      active_comparisons: map_size(state.active_comparisons),
      completed_comparisons: length(state.completed_comparisons),
      consensus_strategy: state.consensus_strategy,
      avg_comparison_time: calculate_avg_comparison_time(state.completed_comparisons),
      provider_usage: calculate_provider_usage(state.completed_comparisons),
      quality_trends: get_quality_trends(state.performance_history),
      timestamp: System.system_time(:millisecond)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:get_provider_performance, _from, state) do
    performance = Enum.map(state.performance_history, fn {provider, history} ->
      {provider, %{
        avg_quality_score: calculate_avg_quality(history),
        avg_response_time: calculate_avg_response_time(history),
        success_rate: calculate_success_rate(history),
        total_requests: length(history),
        recent_trend: get_recent_trend(history)
      }}
    end)
    |> Enum.into(%{})
    
    {:reply, performance, state}
  end
  
  @impl true
  def handle_call({:set_consensus_strategy, strategy}, _from, state) do
    if strategy in [:majority, :quality_weighted, :best_quality, :hybrid] do
      Logger.info("Consensus strategy changed to: #{strategy}")
      {:reply, :ok, %{state | consensus_strategy: strategy}}
    else
      {:reply, {:error, :invalid_strategy}, state}
    end
  end
  
  @impl true
  def handle_info({:response_received, comparison_id, provider, response_data}, state) do
    case Map.get(state.active_comparisons, comparison_id) do
      nil ->
        Logger.warn("Received response for unknown comparison: #{comparison_id}")
        {:noreply, state}
      
      comparison ->
        updated_comparison = add_response_to_comparison(comparison, provider, response_data)
        
        new_state = %{state | 
          active_comparisons: Map.put(state.active_comparisons, comparison_id, updated_comparison)
        }
        
        # Check if we have enough responses or if all providers have responded
        if comparison_ready?(updated_comparison) do
          finalize_comparison(comparison_id, updated_comparison, new_state)
        else
          {:noreply, new_state}
        end
    end
  end
  
  @impl true
  def handle_info({:comparison_timeout, comparison_id}, state) do
    case Map.get(state.active_comparisons, comparison_id) do
      nil ->
        {:noreply, state}
      
      comparison ->
        Logger.warn("Comparison #{comparison_id} timed out with #{length(comparison.responses)} responses")
        finalize_comparison(comparison_id, comparison, state)
    end
  end
  
  @impl true
  def handle_info(:cleanup_completed_comparisons, state) do
    # Remove old completed comparisons to prevent memory bloat
    cutoff_time = System.system_time(:millisecond) - 3_600_000  # 1 hour
    
    cleaned_comparisons = Enum.filter(state.completed_comparisons, fn comparison ->
      comparison.completed_at > cutoff_time
    end)
    
    schedule_cleanup()
    
    {:noreply, %{state | completed_comparisons: cleaned_comparisons}}
  end
  
  # Private Functions
  
  defp start_parallel_execution(comparison_id, request, providers, from, options) do
    # Start requests to all providers
    provider_tasks = Enum.map(providers, fn provider ->
      target_request = Map.put(request, :requirements, %{provider: provider})
      
      task = Task.async(fn ->
        start_time = System.monotonic_time(:millisecond)
        
        result = case Coordinator.route_request(target_request, options) do
          {:ok, response} ->
            end_time = System.monotonic_time(:millisecond)
            duration = end_time - start_time
            
            {provider, %{
              response: response,
              duration_ms: duration,
              success: true,
              timestamp: System.system_time(:millisecond)
            }}
          
          {:error, reason} ->
            end_time = System.monotonic_time(:millisecond)
            duration = end_time - start_time
            
            {provider, %{
              error: reason,
              duration_ms: duration,
              success: false,
              timestamp: System.system_time(:millisecond)
            }}
        end
        
        send(self(), {:response_received, comparison_id, provider, elem(result, 1)})
        result
      end)
      
      {provider, task}
    end)
    
    # Set timeout for the comparison
    Process.send_after(self(), {:comparison_timeout, comparison_id}, @comparison_timeout)
    
    %{
      id: comparison_id,
      request: request,
      providers: providers,
      provider_tasks: provider_tasks,
      responses: [],
      from: from,
      started_at: System.system_time(:millisecond),
      options: options
    }
  end
  
  defp add_response_to_comparison(comparison, provider, response_data) do
    new_response = Map.put(response_data, :provider, provider)
    %{comparison | responses: [new_response | comparison.responses]}
  end
  
  defp comparison_ready?(comparison) do
    response_count = length(comparison.responses)
    provider_count = length(comparison.providers)
    
    # Ready if we have minimum responses or all providers responded
    response_count >= @min_responses_for_consensus or response_count >= provider_count
  end
  
  defp finalize_comparison(comparison_id, comparison, state) do
    # Select best response using consensus strategy
    best_response = select_best_response(comparison.responses, state.consensus_strategy)
    
    # Update performance history
    new_performance_history = update_performance_history(state.performance_history, comparison.responses)
    
    # Create completed comparison record
    completed_comparison = %{
      id: comparison_id,
      request: comparison.request,
      responses: comparison.responses,
      selected_response: best_response,
      consensus_strategy: state.consensus_strategy,
      started_at: comparison.started_at,
      completed_at: System.system_time(:millisecond),
      duration_ms: System.system_time(:millisecond) - comparison.started_at
    }
    
    # Reply to caller
    GenServer.reply(comparison.from, {:ok, best_response})
    
    # Emit telemetry
    emit_comparison_telemetry(completed_comparison)
    
    # Emit event
    EventBus.emit("ai_response_comparison_completed", %{
      comparison_id: comparison_id,
      providers: Enum.map(comparison.responses, & &1.provider),
      selected_provider: best_response.provider,
      consensus_strategy: state.consensus_strategy
    })
    
    # Update state
    new_state = %{state |
      active_comparisons: Map.delete(state.active_comparisons, comparison_id),
      completed_comparisons: [completed_comparison | state.completed_comparisons],
      performance_history: new_performance_history
    }
    
    {:noreply, new_state}
  end
  
  defp select_best_response(responses, consensus_strategy) do
    successful_responses = Enum.filter(responses, & &1.success)
    
    if Enum.empty?(successful_responses) do
      # Return least bad error if all failed
      Enum.min_by(responses, & &1.duration_ms)
    else
      case consensus_strategy do
        :majority ->
          select_by_majority(successful_responses)
        
        :quality_weighted ->
          select_by_quality_weighted(successful_responses)
        
        :best_quality ->
          select_by_best_quality(successful_responses)
        
        :hybrid ->
          select_by_hybrid(successful_responses)
      end
    end
  end
  
  defp select_by_majority(responses) do
    # Simple majority based on response similarity
    # For now, just return the first successful response
    List.first(responses)
  end
  
  defp select_by_quality_weighted(responses) do
    responses_with_quality = Enum.map(responses, fn response ->
      quality_score = QualityMetrics.assess_response_quality(response)
      Map.put(response, :quality_score, quality_score)
    end)
    
    Enum.max_by(responses_with_quality, & &1.quality_score)
  end
  
  defp select_by_best_quality(responses) do
    responses_with_quality = Enum.map(responses, fn response ->
      quality_score = QualityMetrics.assess_response_quality(response)
      Map.put(response, :quality_score, quality_score)
    end)
    
    Enum.max_by(responses_with_quality, & &1.quality_score)
  end
  
  defp select_by_hybrid(responses) do
    responses_with_scores = Enum.map(responses, fn response ->
      quality_score = QualityMetrics.assess_response_quality(response)
      speed_score = calculate_speed_score(response.duration_ms)
      hybrid_score = quality_score * 0.7 + speed_score * 0.3
      
      response
      |> Map.put(:quality_score, quality_score)
      |> Map.put(:speed_score, speed_score)
      |> Map.put(:hybrid_score, hybrid_score)
    end)
    
    Enum.max_by(responses_with_scores, & &1.hybrid_score)
  end
  
  defp calculate_speed_score(duration_ms) do
    # Convert duration to score (faster = higher score)
    max_duration = 30_000  # 30 seconds
    min_duration = 500     # 0.5 seconds
    
    clamped_duration = max(min_duration, min(duration_ms, max_duration))
    1.0 - (clamped_duration - min_duration) / (max_duration - min_duration)
  end
  
  defp get_target_providers(request, options) do
    # Get providers from options or use defaults
    requested_providers = Keyword.get(options, :providers, [])
    
    if Enum.empty?(requested_providers) do
      # Default to available providers based on request requirements
      get_available_providers_for_request(request)
    else
      requested_providers
    end
  end
  
  defp get_available_providers_for_request(_request) do
    # For now, return common providers
    # In real implementation, this would check ModelCoordinator for availability
    [:openai, :anthropic, :ollama]
  end
  
  defp update_performance_history(history, responses) do
    Enum.reduce(responses, history, fn response, acc ->
      provider = response.provider
      provider_history = Map.get(acc, provider, [])
      
      performance_entry = %{
        duration_ms: response.duration_ms,
        success: response.success,
        quality_score: QualityMetrics.assess_response_quality(response),
        timestamp: response.timestamp
      }
      
      # Keep last 100 entries per provider
      updated_history = [performance_entry | provider_history]
      |> Enum.take(100)
      
      Map.put(acc, provider, updated_history)
    end)
  end
  
  defp calculate_avg_comparison_time(comparisons) do
    if Enum.empty?(comparisons) do
      0.0
    else
      total_time = Enum.sum(Enum.map(comparisons, & &1.duration_ms))
      total_time / length(comparisons)
    end
  end
  
  defp calculate_provider_usage(comparisons) do
    Enum.flat_map(comparisons, fn comparison ->
      Enum.map(comparison.responses, & &1.provider)
    end)
    |> Enum.frequencies()
  end
  
  defp get_quality_trends(performance_history) do
    Enum.map(performance_history, fn {provider, history} ->
      if length(history) >= 5 do
        recent = Enum.take(history, 5)
        older = Enum.drop(history, 5) |> Enum.take(5)
        
        recent_avg = calculate_avg_quality(recent)
        older_avg = calculate_avg_quality(older)
        
        trend = cond do
          recent_avg > older_avg + 0.1 -> :improving
          recent_avg < older_avg - 0.1 -> :declining
          true -> :stable
        end
        
        {provider, trend}
      else
        {provider, :insufficient_data}
      end
    end)
    |> Enum.into(%{})
  end
  
  defp calculate_avg_quality(history) do
    if Enum.empty?(history) do
      0.0
    else
      total_quality = Enum.sum(Enum.map(history, & &1.quality_score))
      total_quality / length(history)
    end
  end
  
  defp calculate_avg_response_time(history) do
    if Enum.empty?(history) do
      0.0
    else
      total_time = Enum.sum(Enum.map(history, & &1.duration_ms))
      total_time / length(history)
    end
  end
  
  defp calculate_success_rate(history) do
    if Enum.empty?(history) do
      0.0
    else
      successful = Enum.count(history, & &1.success)
      successful / length(history)
    end
  end
  
  defp get_recent_trend(history) do
    if length(history) < 10 do
      :insufficient_data
    else
      recent = Enum.take(history, 5)
      older = Enum.slice(history, 5, 5)
      
      recent_quality = calculate_avg_quality(recent)
      older_quality = calculate_avg_quality(older)
      
      cond do
        recent_quality > older_quality + 0.1 -> :improving
        recent_quality < older_quality - 0.1 -> :declining
        true -> :stable
      end
    end
  end
  
  defp emit_comparison_telemetry(comparison) do
    Telemetry.emit([:aiex, :ai, :response_comparison], %{
      duration_ms: comparison.duration_ms,
      response_count: length(comparison.responses),
      successful_responses: Enum.count(comparison.responses, & &1.success)
    }, %{
      comparison_id: comparison.id,
      consensus_strategy: comparison.consensus_strategy,
      selected_provider: comparison.selected_response.provider
    })
  end
  
  defp generate_comparison_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_completed_comparisons, 600_000)  # 10 minutes
  end
end