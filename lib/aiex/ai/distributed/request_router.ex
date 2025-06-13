defmodule Aiex.AI.Distributed.RequestRouter do
  @moduledoc """
  Intelligent AI request router with affinity, priority, and context sharing.
  
  Routes AI requests to appropriate engines based on request characteristics,
  manages cross-node context sharing for consistent responses, and provides
  request tracing and performance monitoring.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.AI.Engines.{CodeAnalyzer, GenerationEngine, ExplanationEngine, RefactoringEngine, TestGenerator}
  alias Aiex.Events.EventBus
  alias Aiex.Telemetry.DistributedAggregator
  
  @request_timeout 30_000
  @context_sync_timeout 5_000
  @priority_levels [:low, :normal, :high, :urgent]
  
  defstruct [
    :node,
    :request_queue,
    :active_requests,
    :routing_stats,
    :context_cache,
    request_history: [],
    max_history: 1000
  ]
  
  # Request types and their corresponding engines
  @request_engine_mapping %{
    :code_analysis => CodeAnalyzer,
    :code_generation => GenerationEngine,
    :explanation => ExplanationEngine,
    :refactoring => RefactoringEngine,
    :test_generation => TestGenerator,
    :documentation => GenerationEngine,
    :bug_fixing => RefactoringEngine,
    :optimization => RefactoringEngine
  }
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Process an AI request with intelligent routing.
  """
  def process_request(request) do
    GenServer.call(__MODULE__, {:process_request, request}, @request_timeout)
  end
  
  @doc """
  Route request with specific options (priority, affinity, etc).
  """
  def route_request(request, options \\ []) do
    GenServer.call(__MODULE__, {:route_request, request, options}, @request_timeout)
  end
  
  @doc """
  Get routing statistics and performance metrics.
  """
  def get_routing_stats do
    GenServer.call(__MODULE__, :get_routing_stats)
  end
  
  @doc """
  Get current request queue status.
  """
  def get_queue_status do
    GenServer.call(__MODULE__, :get_queue_status)
  end
  
  @doc """
  Share context information across nodes for consistent responses.
  """
  def share_context(context_id, context_data) do
    GenServer.cast(__MODULE__, {:share_context, context_id, context_data})
  end
  
  @doc """
  Get shared context for a request.
  """
  def get_shared_context(context_id) do
    GenServer.call(__MODULE__, {:get_shared_context, context_id}, @context_sync_timeout)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      node: Node.self(),
      request_queue: :queue.new(),
      active_requests: %{},
      routing_stats: initialize_routing_stats(),
      context_cache: %{},
      request_history: []
    }
    
    Logger.info("AI request router started on #{state.node}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:process_request, request}, from, state) do
    # Process request with default routing options
    options = []
    handle_route_request(request, options, from, state)
  end
  
  def handle_call({:route_request, request, options}, from, state) do
    handle_route_request(request, options, from, state)
  end
  
  def handle_call(:get_routing_stats, _from, state) do
    {:reply, state.routing_stats, state}
  end
  
  def handle_call(:get_queue_status, _from, state) do
    queue_status = %{
      queue_length: :queue.len(state.request_queue),
      active_requests: map_size(state.active_requests),
      node: state.node,
      timestamp: System.system_time(:millisecond)
    }
    
    {:reply, queue_status, state}
  end
  
  def handle_call({:get_shared_context, context_id}, _from, state) do
    context = Map.get(state.context_cache, context_id)
    {:reply, {:ok, context}, state}
  end
  
  @impl true
  def handle_cast({:share_context, context_id, context_data}, state) do
    # Cache context data for cross-node sharing
    updated_cache = Map.put(state.context_cache, context_id, %{
      data: context_data,
      timestamp: System.system_time(:millisecond),
      node: state.node
    })
    
    # Publish context sharing event
    EventBus.publish("ai_context:shared", %{
      context_id: context_id,
      node: state.node,
      timestamp: System.system_time(:millisecond)
    })
    
    updated_state = %{state | context_cache: updated_cache}
    {:noreply, updated_state}
  end
  
  def handle_cast({:request_completed, request_id, result, metrics}, state) do
    # Remove from active requests and update stats
    updated_active = Map.delete(state.active_requests, request_id)
    updated_stats = update_routing_stats(state.routing_stats, result, metrics)
    
    # Add to history
    history_entry = %{
      request_id: request_id,
      result: result,
      metrics: metrics,
      timestamp: System.system_time(:millisecond)
    }
    
    updated_history = [history_entry | state.request_history] |> Enum.take(state.max_history)
    
    updated_state = %{state | 
      active_requests: updated_active,
      routing_stats: updated_stats,
      request_history: updated_history
    }
    
    {:noreply, updated_state}
  end
  
  # Private functions
  
  defp handle_route_request(request, options, from, state) do
    request_id = generate_request_id()
    
    # Enrich request with routing metadata
    enriched_request = enrich_request(request, options, request_id)
    
    # Add to active requests
    updated_active = Map.put(state.active_requests, request_id, %{
      request: enriched_request,
      from: from,
      started_at: System.system_time(:millisecond),
      options: options
    })
    
    updated_state = %{state | active_requests: updated_active}
    
    # Process request asynchronously
    Task.start(fn ->
      result = execute_request(enriched_request, options)
      
      # Calculate metrics
      duration = System.system_time(:millisecond) - 
        get_in(updated_state.active_requests, [request_id, :started_at])
      
      metrics = %{
        duration_ms: duration,
        success: match?({:ok, _}, result),
        request_type: enriched_request.type,
        engine_used: enriched_request.target_engine,
        node: state.node
      }
      
      # Reply to caller
      GenServer.reply(from, result)
      
      # Notify completion
      GenServer.cast(__MODULE__, {:request_completed, request_id, result, metrics})
      
      # Record telemetry
      DistributedAggregator.record_metric("ai_request.completed", 1, %{
        type: enriched_request.type,
        success: metrics.success,
        duration_ms: duration
      })
    end)
    
    {:noreply, updated_state}
  end
  
  defp enrich_request(request, options, request_id) do
    # Determine request type and target engine
    request_type = determine_request_type(request)
    target_engine = get_target_engine(request_type)
    
    # Extract or generate context ID
    context_id = Map.get(request, :context_id) || 
                 Keyword.get(options, :context_id) || 
                 generate_context_id()
    
    # Build enriched request
    %{
      id: request_id,
      type: request_type,
      target_engine: target_engine,
      context_id: context_id,
      content: Map.get(request, :content, ""),
      requirements: Map.get(request, :requirements, %{}),
      options: Map.get(request, :options, %{}),
      priority: Keyword.get(options, :priority, :normal),
      affinity: Keyword.get(options, :affinity, :none),
      created_at: System.system_time(:millisecond),
      node: Node.self()
    }
  end
  
  defp determine_request_type(request) do
    # Determine request type from content and metadata
    explicit_type = Map.get(request, :type)
    
    if explicit_type do
      explicit_type
    else
      # Infer from content
      content = Map.get(request, :content, "")
      infer_request_type_from_content(content)
    end
  end
  
  defp infer_request_type_from_content(content) do
    content_lower = String.downcase(content)
    
    cond do
      String.contains?(content_lower, ["analyze", "analysis", "review"]) ->
        :code_analysis
      
      String.contains?(content_lower, ["generate", "create", "write"]) ->
        :code_generation
      
      String.contains?(content_lower, ["explain", "describe", "what does"]) ->
        :explanation
      
      String.contains?(content_lower, ["refactor", "improve", "optimize"]) ->
        :refactoring
      
      String.contains?(content_lower, ["test", "testing", "unit test"]) ->
        :test_generation
      
      String.contains?(content_lower, ["document", "documentation", "doc"]) ->
        :documentation
      
      String.contains?(content_lower, ["bug", "fix", "error", "issue"]) ->
        :bug_fixing
      
      true ->
        :explanation  # Default fallback
    end
  end
  
  defp get_target_engine(request_type) do
    Map.get(@request_engine_mapping, request_type, ExplanationEngine)
  end
  
  defp execute_request(request, options) do
    Logger.debug("Executing AI request #{request.id} of type #{request.type}")
    
    try do
      # Sync context if needed
      context = sync_request_context(request)
      
      # Execute based on request type and target engine
      result = case request.target_engine do
        CodeAnalyzer ->
          execute_code_analysis(request, context)
        
        GenerationEngine ->
          execute_generation(request, context)
        
        ExplanationEngine ->
          execute_explanation(request, context)
        
        RefactoringEngine ->
          execute_refactoring(request, context)
        
        TestGenerator ->
          execute_test_generation(request, context)
        
        _ ->
          {:error, {:unsupported_engine, request.target_engine}}
      end
      
      # Share context if result includes context updates
      if match?({:ok, %{context: _}}, result) do
        {:ok, response} = result
        share_context(request.context_id, response.context)
      end
      
      result
      
    rescue
      error ->
        Logger.error("Request execution failed: #{Exception.message(error)}")
        {:error, {:execution_failed, Exception.message(error)}}
    end
  end
  
  defp sync_request_context(request) do
    # Get context from ContextManager and distributed cache
    case ContextManager.get_context(request.context_id) do
      {:ok, context} ->
        # Try to get additional context from distributed cache
        case get_shared_context(request.context_id) do
          {:ok, shared_context} when not is_nil(shared_context) ->
            merge_contexts(context, shared_context.data)
          _ ->
            context
        end
      
      {:error, _reason} ->
        # Try to get from distributed cache only
        case get_shared_context(request.context_id) do
          {:ok, shared_context} when not is_nil(shared_context) ->
            shared_context.data
          _ ->
            %{}  # Empty context as fallback
        end
    end
  end
  
  defp execute_code_analysis(request, context) do
    # Delegate to CodeAnalyzer with request content and context
    CodeAnalyzer.analyze_code(%{
      content: request.content,
      file_path: Map.get(request.options, :file_path),
      analysis_type: Map.get(request.options, :analysis_type, :comprehensive),
      context: context
    })
  end
  
  defp execute_generation(request, context) do
    # Delegate to GenerationEngine
    GenerationEngine.generate_code(%{
      prompt: request.content,
      type: Map.get(request.options, :generation_type, :function),
      context: context,
      requirements: request.requirements
    })
  end
  
  defp execute_explanation(request, context) do
    # Delegate to ExplanationEngine
    ExplanationEngine.explain_code(%{
      content: request.content,
      explanation_type: Map.get(request.options, :explanation_type, :detailed),
      context: context
    })
  end
  
  defp execute_refactoring(request, context) do
    # Delegate to RefactoringEngine
    RefactoringEngine.refactor_code(%{
      content: request.content,
      refactoring_type: Map.get(request.options, :refactoring_type, :improve),
      context: context,
      constraints: Map.get(request.options, :constraints, [])
    })
  end
  
  defp execute_test_generation(request, context) do
    # Delegate to TestGenerator
    TestGenerator.generate_tests(%{
      content: request.content,
      test_type: Map.get(request.options, :test_type, :unit),
      context: context,
      coverage_target: Map.get(request.options, :coverage_target, 80)
    })
  end
  
  defp merge_contexts(local_context, shared_context) do
    # Simple merge strategy - shared context takes precedence
    Map.merge(local_context, shared_context)
  end
  
  defp initialize_routing_stats do
    %{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      avg_response_time_ms: 0,
      requests_by_type: %{},
      requests_by_engine: %{},
      context_sharing_events: 0,
      last_reset: System.system_time(:millisecond)
    }
  end
  
  defp update_routing_stats(stats, result, metrics) do
    success = match?({:ok, _}, result)
    
    %{stats |
      total_requests: stats.total_requests + 1,
      successful_requests: stats.successful_requests + (if success, do: 1, else: 0),
      failed_requests: stats.failed_requests + (if success, do: 0, else: 1),
      avg_response_time_ms: update_avg_response_time(stats, metrics.duration_ms),
      requests_by_type: update_counter_map(stats.requests_by_type, metrics.request_type),
      requests_by_engine: update_counter_map(stats.requests_by_engine, metrics.engine_used)
    }
  end
  
  defp update_avg_response_time(stats, new_duration) do
    if stats.total_requests == 0 do
      new_duration
    else
      # Simple moving average
      alpha = 0.1
      alpha * new_duration + (1 - alpha) * stats.avg_response_time_ms
    end
  end
  
  defp update_counter_map(counter_map, key) do
    Map.update(counter_map, key, 1, &(&1 + 1))
  end
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end
  
  defp generate_context_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end