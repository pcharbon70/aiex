defmodule Aiex.AI.Distributed.NodeCapabilityManager do
  @moduledoc """
  Manages and tracks node capabilities for AI coordination.
  
  Continuously monitors node resources, model availability, and performance
  characteristics to provide accurate capability information for intelligent
  request routing and load balancing.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.Events.EventBus
  alias Aiex.Telemetry.DistributedAggregator
  alias Aiex.AI.Distributed.Coordinator, as: AICoordinator
  
  @capability_check_interval 10_000
  @model_availability_check_interval 30_000
  @performance_assessment_interval 60_000
  
  defstruct [
    :node,
    :last_update,
    :capabilities,
    :model_availability,
    :performance_metrics,
    :resource_metrics,
    history: [],
    max_history: 100
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get current node capabilities.
  """
  def get_current_capabilities do
    GenServer.call(__MODULE__, :get_current_capabilities)
  end
  
  @doc """
  Get model availability status.
  """
  def get_model_availability do
    GenServer.call(__MODULE__, :get_model_availability)
  end
  
  @doc """
  Get performance metrics for this node.
  """
  def get_performance_metrics do
    GenServer.call(__MODULE__, :get_performance_metrics)
  end
  
  @doc """
  Force a capability assessment and update.
  """
  def force_assessment do
    GenServer.cast(__MODULE__, :force_assessment)
  end
  
  @doc """
  Check if node can handle a specific request type.
  """
  def can_handle_request?(request_requirements) do
    GenServer.call(__MODULE__, {:can_handle_request, request_requirements})
  end
  
  @doc """
  Get capability history for analysis.
  """
  def get_capability_history(limit \\ 10) do
    GenServer.call(__MODULE__, {:get_capability_history, limit})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    node = Node.self()
    
    state = %__MODULE__{
      node: node,
      capabilities: %{},
      model_availability: %{},
      performance_metrics: %{},
      resource_metrics: %{},
      history: []
    }
    
    # Perform initial assessment
    updated_state = perform_capability_assessment(state)
    
    # Schedule periodic assessments
    schedule_capability_check()
    schedule_model_availability_check()
    schedule_performance_assessment()
    
    Logger.info("Node capability manager started for #{node}")
    
    {:ok, updated_state}
  end
  
  @impl true
  def handle_call(:get_current_capabilities, _from, state) do
    {:reply, {:ok, state.capabilities}, state}
  end
  
  def handle_call(:get_model_availability, _from, state) do
    {:reply, {:ok, state.model_availability}, state}
  end
  
  def handle_call(:get_performance_metrics, _from, state) do
    {:reply, {:ok, state.performance_metrics}, state}
  end
  
  def handle_call({:can_handle_request, requirements}, _from, state) do
    can_handle = evaluate_request_compatibility(requirements, state.capabilities)
    {:reply, can_handle, state}
  end
  
  def handle_call({:get_capability_history, limit}, _from, state) do
    history = Enum.take(state.history, limit)
    {:reply, {:ok, history}, state}
  end
  
  @impl true
  def handle_cast(:force_assessment, state) do
    updated_state = perform_capability_assessment(state)
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(:capability_check, state) do
    updated_state = perform_capability_assessment(state)
    schedule_capability_check()
    {:noreply, updated_state}
  end
  
  def handle_info(:model_availability_check, state) do
    updated_state = check_model_availability(state)
    schedule_model_availability_check()
    {:noreply, updated_state}
  end
  
  def handle_info(:performance_assessment, state) do
    updated_state = assess_performance_metrics(state)
    schedule_performance_assessment()
    {:noreply, updated_state}
  end
  
  # Private functions
  
  defp perform_capability_assessment(state) do
    Logger.debug("Performing capability assessment for node #{state.node}")
    
    # Gather all capability information
    resource_metrics = assess_resource_metrics()
    model_availability = check_model_availability_sync()
    performance_metrics = assess_performance_metrics_sync()
    processing_capabilities = assess_processing_capabilities()
    
    capabilities = %{
      # Resource capabilities
      max_concurrent_requests: calculate_max_concurrent_requests(resource_metrics),
      memory_available_mb: resource_metrics.memory_available_mb,
      cpu_cores: resource_metrics.cpu_cores,
      cpu_usage_percent: resource_metrics.cpu_usage_percent,
      
      # Model capabilities
      supported_providers: get_supported_providers(),
      available_models: Map.keys(model_availability),
      model_loading_capability: assess_model_loading_capability(),
      
      # Processing capabilities
      processing_types: processing_capabilities.supported_types,
      max_context_length: processing_capabilities.max_context_length,
      batch_processing: processing_capabilities.batch_processing,
      
      # Performance characteristics
      avg_response_time_ms: performance_metrics.avg_response_time_ms,
      success_rate: performance_metrics.success_rate,
      throughput_requests_per_minute: performance_metrics.throughput_rpm,
      
      # Network and storage
      network_bandwidth_mbps: assess_network_bandwidth(),
      storage_available_gb: resource_metrics.storage_available_gb,
      
      # Timestamps and metadata
      last_updated: System.system_time(:millisecond),
      node: state.node,
      uptime_ms: get_uptime_ms()
    }
    
    # Update state
    updated_state = %{state | 
      capabilities: capabilities,
      model_availability: model_availability,
      performance_metrics: performance_metrics,
      resource_metrics: resource_metrics,
      last_update: System.system_time(:millisecond)
    }
    
    # Add to history
    history_entry = %{
      timestamp: System.system_time(:millisecond),
      capabilities: capabilities,
      resource_metrics: resource_metrics
    }
    
    updated_history = [history_entry | state.history] |> Enum.take(state.max_history)
    final_state = %{updated_state | history: updated_history}
    
    # Notify AI coordinator of capability updates
    AICoordinator.update_capabilities(capabilities)
    
    # Publish capability update event
    EventBus.publish("node_capability:updated", %{
      node: state.node,
      capabilities: capabilities,
      timestamp: System.system_time(:millisecond)
    })
    
    # Record telemetry
    DistributedAggregator.record_metric("node_capability.assessment_completed", 1, %{
      node: state.node,
      max_concurrent_requests: capabilities.max_concurrent_requests,
      available_models: length(Map.keys(model_availability))
    })
    
    final_state
  end
  
  defp assess_resource_metrics do
    memory = :erlang.memory()
    system_info = get_system_info()
    
    total_memory_bytes = memory[:total] || 0
    total_memory_mb = div(total_memory_bytes, 1024 * 1024)
    
    # Estimate available memory (conservative)
    available_memory_mb = max(0, 2048 - total_memory_mb)  # Assume 2GB limit
    
    %{
      memory_total_mb: total_memory_mb,
      memory_available_mb: available_memory_mb,
      memory_usage_percent: calculate_memory_usage_percent(memory),
      cpu_cores: System.schedulers_online(),
      cpu_usage_percent: estimate_cpu_usage(),
      process_count: length(Process.list()),
      storage_available_gb: estimate_storage_available(),
      load_average: get_load_average()
    }
  end
  
  defp check_model_availability_sync do
    try do
      # Check with ModelCoordinator for available models
      case ModelCoordinator.get_available_models() do
        {:ok, models} ->
          Enum.into(models, %{}, fn model ->
            {model, %{
              status: :available,
              last_checked: System.system_time(:millisecond),
              response_time_ms: test_model_response_time(model)
            }}
          end)
        
        {:error, _reason} ->
          %{}
      end
    rescue
      _ ->
        # Fallback to static model list
        get_static_model_availability()
    end
  end
  
  defp check_model_availability(state) do
    model_availability = check_model_availability_sync()
    %{state | model_availability: model_availability}
  end
  
  defp assess_performance_metrics_sync do
    # Get recent performance data from telemetry
    try do
      case DistributedAggregator.get_node_metrics(Node.self()) do
        {:ok, metrics} ->
          %{
            avg_response_time_ms: extract_avg_response_time(metrics),
            success_rate: extract_success_rate(metrics),
            throughput_rpm: extract_throughput(metrics),
            error_rate: extract_error_rate(metrics),
            last_calculated: System.system_time(:millisecond)
          }
        
        {:error, _reason} ->
          get_default_performance_metrics()
      end
    rescue
      _ ->
        get_default_performance_metrics()
    end
  end
  
  defp assess_performance_metrics(state) do
    performance_metrics = assess_performance_metrics_sync()
    %{state | performance_metrics: performance_metrics}
  end
  
  defp assess_processing_capabilities do
    %{
      supported_types: [
        :text_generation,
        :code_analysis,
        :code_generation,
        :explanation,
        :refactoring,
        :test_generation,
        :documentation
      ],
      max_context_length: get_max_context_length(),
      batch_processing: true,
      streaming_support: true,
      async_processing: true
    }
  end
  
  defp calculate_max_concurrent_requests(resource_metrics) do
    # Calculate based on available resources
    memory_factor = div(resource_metrics.memory_available_mb, 10)  # 10MB per request
    cpu_factor = resource_metrics.cpu_cores * 25  # 25 requests per core
    
    # Use conservative estimate
    base_limit = min(memory_factor, cpu_factor)
    max(10, min(base_limit, 200))  # Between 10 and 200
  end
  
  defp evaluate_request_compatibility(requirements, capabilities) do
    # Check if node can handle the request requirements
    checks = [
      check_provider_support(requirements, capabilities),
      check_model_support(requirements, capabilities),
      check_resource_requirements(requirements, capabilities),
      check_processing_type_support(requirements, capabilities)
    ]
    
    Enum.all?(checks)
  end
  
  defp check_provider_support(requirements, capabilities) do
    required_provider = Map.get(requirements, :provider)
    supported_providers = Map.get(capabilities, :supported_providers, [])
    
    is_nil(required_provider) or required_provider in supported_providers
  end
  
  defp check_model_support(requirements, capabilities) do
    required_model = Map.get(requirements, :model)
    available_models = Map.get(capabilities, :available_models, [])
    
    is_nil(required_model) or required_model in available_models
  end
  
  defp check_resource_requirements(requirements, capabilities) do
    required_memory = Map.get(requirements, :memory_mb, 0)
    available_memory = Map.get(capabilities, :memory_available_mb, 0)
    
    required_memory <= available_memory
  end
  
  defp check_processing_type_support(requirements, capabilities) do
    required_type = Map.get(requirements, :processing_type)
    supported_types = Map.get(capabilities, :processing_types, [])
    
    is_nil(required_type) or required_type in supported_types
  end
  
  # Helper functions
  
  defp get_system_info do
    %{
      otp_release: :erlang.system_info(:otp_release),
      erts_version: :erlang.system_info(:version),
      schedulers: :erlang.system_info(:schedulers),
      process_limit: :erlang.system_info(:process_limit)
    }
  end
  
  defp calculate_memory_usage_percent(memory) do
    total = memory[:total] || 1
    processes = memory[:processes] || 0
    system = memory[:system] || 0
    
    used = processes + system
    round((used / total) * 100)
  end
  
  defp estimate_cpu_usage do
    # Simple CPU usage estimation based on scheduler utilization
    try do
      case :cpu_sup.avg1() do
        load when is_number(load) ->
          min(100, round(load * 100 / System.schedulers_online()))
        _ ->
          50  # Default estimate
      end
    rescue
      _ ->
        # Fallback based on process count
        process_count = length(Process.list())
        min(100, div(process_count, 50))
    end
  end
  
  defp estimate_storage_available do
    # Estimate available storage (simplified)
    # In a real implementation, this would check actual disk space
    10.0  # 10GB default
  end
  
  defp get_load_average do
    try do
      {:ok, [one_min | _]} = :cpu_sup.avg1()
      one_min
    rescue
      _ -> 0.5
    end
  end
  
  defp test_model_response_time(model) do
    # Simple response time test (mock for now)
    # In real implementation, would test actual model response
    base_time = 1000  # 1 second base
    jitter = :rand.uniform(500)  # +/- 500ms jitter
    base_time + jitter
  end
  
  defp get_static_model_availability do
    %{
      "gpt-3.5-turbo" => %{status: :available, response_time_ms: 1500},
      "gpt-4" => %{status: :available, response_time_ms: 3000},
      "claude-3-sonnet" => %{status: :available, response_time_ms: 2000},
      "llama2" => %{status: :available, response_time_ms: 800}
    }
  end
  
  defp get_supported_providers do
    Application.get_env(:aiex, :llm)[:supported_providers] || 
    [:openai, :anthropic, :ollama, :lm_studio]
  end
  
  defp assess_model_loading_capability do
    # Assess whether node can load new models dynamically
    available_memory = :erlang.memory(:total)
    
    cond do
      available_memory > 2_000_000_000 -> :high    # > 2GB
      available_memory > 1_000_000_000 -> :medium  # > 1GB
      true -> :low
    end
  end
  
  defp assess_network_bandwidth do
    # Simplified network bandwidth assessment
    # In real implementation, would perform actual bandwidth tests
    100.0  # 100 Mbps default estimate
  end
  
  defp get_max_context_length do
    # Maximum context length this node can handle
    # Based on memory and processing capabilities
    memory_mb = div(:erlang.memory(:total), 1024 * 1024)
    
    cond do
      memory_mb > 4000 -> 32_000    # Large context for high-memory nodes
      memory_mb > 2000 -> 16_000    # Medium context
      true -> 8_000                 # Conservative context length
    end
  end
  
  defp extract_avg_response_time(metrics) do
    Map.get(metrics, "ai_request.response_time_avg", 2000)
  end
  
  defp extract_success_rate(metrics) do
    total = Map.get(metrics, "ai_request.total", 1)
    successful = Map.get(metrics, "ai_request.successful", 1)
    successful / total
  end
  
  defp extract_throughput(metrics) do
    Map.get(metrics, "ai_request.throughput_rpm", 10)
  end
  
  defp extract_error_rate(metrics) do
    total = Map.get(metrics, "ai_request.total", 1)
    errors = Map.get(metrics, "ai_request.errors", 0)
    errors / total
  end
  
  defp get_default_performance_metrics do
    %{
      avg_response_time_ms: 2000,
      success_rate: 0.95,
      throughput_rpm: 10,
      error_rate: 0.05,
      last_calculated: System.system_time(:millisecond)
    }
  end
  
  defp get_uptime_ms do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end
  
  defp schedule_capability_check do
    Process.send_after(self(), :capability_check, @capability_check_interval)
  end
  
  defp schedule_model_availability_check do
    Process.send_after(self(), :model_availability_check, @model_availability_check_interval)
  end
  
  defp schedule_performance_assessment do
    Process.send_after(self(), :performance_assessment, @performance_assessment_interval)
  end
end