defmodule Aiex.AI.Distributed.ABTestingFramework do
  @moduledoc """
  A/B testing framework for comparing AI responses and consensus strategies.
  
  Provides statistical analysis to determine which AI providers, consensus
  methods, or configurations perform better over time with statistical
  significance testing.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.EventBus
  alias Aiex.Telemetry
  
  @type test_variant :: :control | :treatment | binary()
  
  @type test_config :: %{
    name: binary(),
    description: binary(),
    variants: [test_variant()],
    traffic_split: map(),
    metrics: [atom()],
    minimum_sample_size: integer(),
    confidence_level: float(),
    test_duration_hours: integer()
  }
  
  @type test_result :: %{
    variant: test_variant(),
    metrics: map(),
    timestamp: integer(),
    request_id: binary()
  }
  
  defstruct [
    :active_tests,
    :completed_tests,
    :test_results,
    :traffic_allocator,
    :statistical_analyzer
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Create a new A/B test.
  """
  def create_test(test_config) do
    GenServer.call(__MODULE__, {:create_test, test_config})
  end
  
  @doc """
  Get variant assignment for a request.
  """
  def get_variant_assignment(test_name, request_id) do
    GenServer.call(__MODULE__, {:get_variant_assignment, test_name, request_id})
  end
  
  @doc """
  Record test result for a variant.
  """
  def record_test_result(test_name, variant, metrics, request_id) do
    GenServer.cast(__MODULE__, {:record_test_result, test_name, variant, metrics, request_id})
  end
  
  @doc """
  Get test statistics and results.
  """
  def get_test_results(test_name) do
    GenServer.call(__MODULE__, {:get_test_results, test_name})
  end
  
  @doc """
  Get all active tests.
  """
  def get_active_tests do
    GenServer.call(__MODULE__, :get_active_tests)
  end
  
  @doc """
  Stop a test and finalize results.
  """
  def stop_test(test_name) do
    GenServer.call(__MODULE__, {:stop_test, test_name})
  end
  
  @doc """
  Get framework statistics.
  """
  def get_framework_stats do
    GenServer.call(__MODULE__, :get_framework_stats)
  end
  
  # Server Implementation
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      active_tests: %{},
      completed_tests: %{},
      test_results: %{},
      traffic_allocator: %{},
      statistical_analyzer: %{}
    }
    
    Logger.info("ABTestingFramework started")
    
    # Schedule periodic test evaluation
    schedule_test_evaluation()
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:create_test, test_config}, _from, state) do
    test_name = test_config.name
    
    if Map.has_key?(state.active_tests, test_name) do
      {:reply, {:error, :test_already_exists}, state}
    else
      # Validate test configuration
      case validate_test_config(test_config) do
        :ok ->
          enhanced_config = Map.merge(test_config, %{
            created_at: System.system_time(:millisecond),
            status: :active,
            start_time: System.system_time(:millisecond)
          })
          
          new_state = %{state |
            active_tests: Map.put(state.active_tests, test_name, enhanced_config),
            test_results: Map.put(state.test_results, test_name, []),
            traffic_allocator: Map.put(state.traffic_allocator, test_name, %{
              assignments: %{},
              variant_counts: initialize_variant_counts(test_config.variants)
            })
          }
          
          Logger.info("Created A/B test: #{test_name}")
          
          EventBus.emit("ab_test_created", %{
            test_name: test_name,
            variants: test_config.variants,
            traffic_split: test_config.traffic_split
          })
          
          {:reply, :ok, new_state}
        
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end
  
  @impl true
  def handle_call({:get_variant_assignment, test_name, request_id}, _from, state) do
    case Map.get(state.active_tests, test_name) do
      nil ->
        {:reply, {:error, :test_not_found}, state}
      
      test_config ->
        allocator = Map.get(state.traffic_allocator, test_name, %{})
        
        # Check if request already has assignment
        existing_assignment = Map.get(allocator[:assignments] || %{}, request_id)
        
        if existing_assignment do
          {:reply, {:ok, existing_assignment}, state}
        else
          # Assign new variant
          variant = assign_variant(test_config, allocator)
          
          # Update allocator state
          new_allocator = %{
            assignments: Map.put(allocator[:assignments] || %{}, request_id, variant),
            variant_counts: Map.update(allocator[:variant_counts] || %{}, variant, 1, &(&1 + 1))
          }
          
          new_state = %{state |
            traffic_allocator: Map.put(state.traffic_allocator, test_name, new_allocator)
          }
          
          {:reply, {:ok, variant}, new_state}
        end
    end
  end
  
  @impl true
  def handle_call({:get_test_results, test_name}, _from, state) do
    case Map.get(state.active_tests, test_name) do
      nil ->
        case Map.get(state.completed_tests, test_name) do
          nil -> {:reply, {:error, :test_not_found}, state}
          completed_test -> {:reply, {:ok, get_complete_test_analysis(test_name, completed_test, state)}, state}
        end
      
      active_test ->
        analysis = analyze_test_results(test_name, active_test, state)
        {:reply, {:ok, analysis}, state}
    end
  end
  
  @impl true
  def handle_call(:get_active_tests, _from, state) do
    {:reply, Map.keys(state.active_tests), state}
  end
  
  @impl true
  def handle_call({:stop_test, test_name}, _from, state) do
    case Map.get(state.active_tests, test_name) do
      nil ->
        {:reply, {:error, :test_not_found}, state}
      
      test_config ->
        # Finalize test
        final_analysis = analyze_test_results(test_name, test_config, state)
        
        completed_test = Map.merge(test_config, %{
          completed_at: System.system_time(:millisecond),
          status: :completed,
          final_analysis: final_analysis
        })
        
        new_state = %{state |
          active_tests: Map.delete(state.active_tests, test_name),
          completed_tests: Map.put(state.completed_tests, test_name, completed_test)
        }
        
        Logger.info("Completed A/B test: #{test_name}")
        
        EventBus.emit("ab_test_completed", %{
          test_name: test_name,
          final_analysis: final_analysis
        })
        
        {:reply, {:ok, final_analysis}, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_framework_stats, _from, state) do
    stats = %{
      active_tests_count: map_size(state.active_tests),
      completed_tests_count: map_size(state.completed_tests),
      total_test_results: Enum.sum(Enum.map(state.test_results, fn {_name, results} -> length(results) end)),
      active_test_names: Map.keys(state.active_tests),
      framework_uptime_ms: get_framework_uptime(),
      timestamp: System.system_time(:millisecond)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:record_test_result, test_name, variant, metrics, request_id}, state) do
    if Map.has_key?(state.active_tests, test_name) do
      result = %{
        variant: variant,
        metrics: metrics,
        request_id: request_id,
        timestamp: System.system_time(:millisecond)
      }
      
      current_results = Map.get(state.test_results, test_name, [])
      new_results = [result | current_results]
      
      new_state = %{state |
        test_results: Map.put(state.test_results, test_name, new_results)
      }
      
      # Emit telemetry
      Telemetry.emit([:aiex, :ab_testing, :result_recorded], %{
        result_count: length(new_results)
      }, %{
        test_name: test_name,
        variant: variant
      })
      
      {:noreply, new_state}
    else
      Logger.warn("Attempted to record result for unknown test: #{test_name}")
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info(:evaluate_tests, state) do
    # Evaluate all active tests for statistical significance
    evaluated_tests = Enum.map(state.active_tests, fn {test_name, test_config} ->
      analysis = analyze_test_results(test_name, test_config, state)
      {test_name, analysis}
    end)
    
    # Check for tests that should be stopped early due to significance
    tests_to_complete = Enum.filter(evaluated_tests, fn {_name, analysis} ->
      should_complete_early?(analysis)
    end)
    
    # Auto-complete tests if configured
    new_state = Enum.reduce(tests_to_complete, state, fn {test_name, _analysis}, acc ->
      case handle_call({:stop_test, test_name}, nil, acc) do
        {:reply, _result, updated_state} -> updated_state
        _ -> acc
      end
    end)
    
    schedule_test_evaluation()
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp validate_test_config(config) do
    required_fields = [:name, :variants, :traffic_split, :metrics]
    
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(config, field)
    end)
    
    cond do
      not Enum.empty?(missing_fields) ->
        {:error, {:missing_fields, missing_fields}}
      
      length(config.variants) < 2 ->
        {:error, :insufficient_variants}
      
      not valid_traffic_split?(config.traffic_split, config.variants) ->
        {:error, :invalid_traffic_split}
      
      true ->
        :ok
    end
  end
  
  defp valid_traffic_split?(traffic_split, variants) do
    # Check that traffic split covers all variants and sums to 1.0
    variant_coverage = Enum.all?(variants, fn variant ->
      Map.has_key?(traffic_split, variant)
    end)
    
    total_traffic = Map.values(traffic_split) |> Enum.sum()
    
    variant_coverage and abs(total_traffic - 1.0) < 0.01
  end
  
  defp initialize_variant_counts(variants) do
    Enum.map(variants, &{&1, 0}) |> Enum.into(%{})
  end
  
  defp assign_variant(test_config, allocator) do
    variant_counts = allocator[:variant_counts] || %{}
    traffic_split = test_config.traffic_split
    
    # Calculate current distribution
    total_assignments = Map.values(variant_counts) |> Enum.sum()
    
    if total_assignments == 0 do
      # First assignment, use random selection
      weighted_random_selection(traffic_split)
    else
      # Balance based on desired distribution
      balanced_variant_selection(traffic_split, variant_counts, total_assignments)
    end
  end
  
  defp weighted_random_selection(traffic_split) do
    random_value = :rand.uniform()
    
    traffic_split
    |> Enum.sort_by(fn {_variant, weight} -> weight end, :desc)
    |> Enum.reduce_while({0.0, nil}, fn {variant, weight}, {cumulative, _} ->
      new_cumulative = cumulative + weight
      
      if random_value <= new_cumulative do
        {:halt, {new_cumulative, variant}}
      else
        {:cont, {new_cumulative, variant}}
      end
    end)
    |> elem(1)
  end
  
  defp balanced_variant_selection(traffic_split, variant_counts, total_assignments) do
    # Find the variant that is most under-represented
    target_distributions = Enum.map(traffic_split, fn {variant, target_proportion} ->
      target_count = target_proportion * total_assignments
      actual_count = Map.get(variant_counts, variant, 0)
      deficit = target_count - actual_count
      
      {variant, deficit}
    end)
    
    {best_variant, _deficit} = Enum.max_by(target_distributions, fn {_variant, deficit} -> deficit end)
    best_variant
  end
  
  defp analyze_test_results(test_name, test_config, state) do
    results = Map.get(state.test_results, test_name, [])
    
    if Enum.empty?(results) do
      %{
        test_name: test_name,
        status: :insufficient_data,
        sample_sizes: %{},
        metrics_analysis: %{},
        statistical_significance: %{},
        recommendation: :continue_test
      }
    else
      # Group results by variant
      results_by_variant = Enum.group_by(results, & &1.variant)
      
      # Calculate sample sizes
      sample_sizes = Enum.map(results_by_variant, fn {variant, variant_results} ->
        {variant, length(variant_results)}
      end) |> Enum.into(%{})
      
      # Analyze metrics for each variant
      metrics_analysis = analyze_metrics_by_variant(results_by_variant, test_config.metrics)
      
      # Calculate statistical significance
      statistical_significance = calculate_statistical_significance(metrics_analysis, sample_sizes)
      
      # Generate recommendation
      recommendation = generate_recommendation(test_config, metrics_analysis, statistical_significance, sample_sizes)
      
      %{
        test_name: test_name,
        status: :active,
        sample_sizes: sample_sizes,
        metrics_analysis: metrics_analysis,
        statistical_significance: statistical_significance,
        recommendation: recommendation,
        test_duration_hours: calculate_test_duration(test_config),
        confidence_intervals: calculate_confidence_intervals(metrics_analysis, sample_sizes)
      }
    end
  end
  
  defp analyze_metrics_by_variant(results_by_variant, tracked_metrics) do
    Enum.map(results_by_variant, fn {variant, results} ->
      variant_metrics = Enum.map(tracked_metrics, fn metric ->
        metric_values = Enum.map(results, fn result ->
          Map.get(result.metrics, metric, 0)
        end)
        
        analysis = if Enum.empty?(metric_values) do
          %{mean: 0, std_dev: 0, min: 0, max: 0, count: 0}
        else
          %{
            mean: Enum.sum(metric_values) / length(metric_values),
            std_dev: calculate_std_dev(metric_values),
            min: Enum.min(metric_values),
            max: Enum.max(metric_values),
            count: length(metric_values)
          }
        end
        
        {metric, analysis}
      end) |> Enum.into(%{})
      
      {variant, variant_metrics}
    end) |> Enum.into(%{})
  end
  
  defp calculate_statistical_significance(metrics_analysis, sample_sizes) do
    # Perform t-tests between variants for each metric
    variants = Map.keys(metrics_analysis)
    
    if length(variants) < 2 do
      %{}
    else
      # Compare first variant (control) with others
      control_variant = List.first(variants)
      treatment_variants = List.delete(variants, control_variant)
      
      Enum.map(treatment_variants, fn treatment_variant ->
        control_metrics = Map.get(metrics_analysis, control_variant, %{})
        treatment_metrics = Map.get(metrics_analysis, treatment_variant, %{})
        
        metric_comparisons = Enum.map(control_metrics, fn {metric, control_stats} ->
          treatment_stats = Map.get(treatment_metrics, metric, %{})
          
          p_value = calculate_t_test_p_value(control_stats, treatment_stats)
          significant = p_value < 0.05
          
          {metric, %{
            p_value: p_value,
            significant: significant,
            effect_size: calculate_effect_size(control_stats, treatment_stats)
          }}
        end) |> Enum.into(%{})
        
        {:"#{control_variant}_vs_#{treatment_variant}", metric_comparisons}
      end) |> Enum.into(%{})
    end
  end
  
  defp calculate_t_test_p_value(control_stats, treatment_stats) do
    # Simplified t-test calculation
    # In production, you'd want a more robust statistical library
    
    if control_stats[:count] < 2 or treatment_stats[:count] < 2 do
      1.0  # Not enough data for significance
    else
      mean_diff = abs(treatment_stats[:mean] - control_stats[:mean])
      pooled_std = :math.sqrt((control_stats[:std_dev] ** 2 + treatment_stats[:std_dev] ** 2) / 2)
      
      if pooled_std == 0 do
        1.0
      else
        t_statistic = mean_diff / (pooled_std * :math.sqrt(2))
        # Very simplified p-value approximation
        1.0 / (1.0 + t_statistic)
      end
    end
  end
  
  defp calculate_effect_size(control_stats, treatment_stats) do
    # Cohen's d effect size
    if control_stats[:std_dev] == 0 and treatment_stats[:std_dev] == 0 do
      0.0
    else
      pooled_std = :math.sqrt((control_stats[:std_dev] ** 2 + treatment_stats[:std_dev] ** 2) / 2)
      
      if pooled_std == 0 do
        0.0
      else
        (treatment_stats[:mean] - control_stats[:mean]) / pooled_std
      end
    end
  end
  
  defp calculate_confidence_intervals(metrics_analysis, sample_sizes) do
    Enum.map(metrics_analysis, fn {variant, metrics} ->
      variant_intervals = Enum.map(metrics, fn {metric, stats} ->
        sample_size = Map.get(sample_sizes, variant, 0)
        
        interval = if sample_size > 1 do
          # 95% confidence interval
          standard_error = stats[:std_dev] / :math.sqrt(sample_size)
          margin_of_error = 1.96 * standard_error  # z-score for 95% CI
          
          %{
            lower: stats[:mean] - margin_of_error,
            upper: stats[:mean] + margin_of_error,
            margin_of_error: margin_of_error
          }
        else
          %{
            lower: stats[:mean],
            upper: stats[:mean],
            margin_of_error: 0
          }
        end
        
        {metric, interval}
      end) |> Enum.into(%{})
      
      {variant, variant_intervals}
    end) |> Enum.into(%{})
  end
  
  defp generate_recommendation(test_config, metrics_analysis, statistical_significance, sample_sizes) do
    min_sample_size = Map.get(test_config, :minimum_sample_size, 100)
    max_sample_size = Map.values(sample_sizes) |> Enum.max(fn -> 0 end)
    
    has_significance = Enum.any?(statistical_significance, fn {_comparison, metrics} ->
      Enum.any?(metrics, fn {_metric, stats} -> stats.significant end)
    end)
    
    cond do
      max_sample_size < min_sample_size ->
        :continue_test
      
      has_significance ->
        :significant_result
      
      calculate_test_duration(test_config) > Map.get(test_config, :test_duration_hours, 168) ->
        :inconclusive_stop
      
      true ->
        :continue_test
    end
  end
  
  defp should_complete_early?(analysis) do
    analysis.recommendation in [:significant_result, :inconclusive_stop]
  end
  
  defp calculate_test_duration(test_config) do
    start_time = Map.get(test_config, :start_time, System.system_time(:millisecond))
    current_time = System.system_time(:millisecond)
    (current_time - start_time) / (1000 * 60 * 60)  # Hours
  end
  
  defp calculate_std_dev(values) do
    if length(values) < 2 do
      0.0
    else
      mean = Enum.sum(values) / length(values)
      variance = Enum.sum(Enum.map(values, fn x -> (x - mean) ** 2 end)) / (length(values) - 1)
      :math.sqrt(variance)
    end
  end
  
  defp get_complete_test_analysis(test_name, completed_test, _state) do
    Map.get(completed_test, :final_analysis, %{test_name: test_name, status: :completed})
  end
  
  defp get_framework_uptime do
    # This would need to be tracked from process start
    # For now, return a placeholder
    System.system_time(:millisecond)
  end
  
  defp schedule_test_evaluation do
    # Evaluate tests every 5 minutes
    Process.send_after(self(), :evaluate_tests, 5 * 60 * 1000)
  end
end