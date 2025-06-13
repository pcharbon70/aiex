defmodule Aiex.Telemetry.DistributedTracer do
  @moduledoc """
  OpenTelemetry-compatible distributed tracing for Aiex cluster.
  
  Provides distributed tracing capabilities across the cluster with automatic
  span propagation and correlation ID management.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Telemetry.{DistributedAggregator, StructuredLogger}
  
  @span_context_key :aiex_span_context
  @trace_header "x-trace-id"
  @span_header "x-span-id"
  @parent_span_header "x-parent-span-id"
  
  defstruct [
    :spans_ets,
    :active_spans,
    :sampling_rate,
    :export_endpoint,
    enabled: true
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc "Start a new trace with the given operation name"
  def start_trace(operation_name, attributes \\ %{}) do
    trace_id = generate_trace_id()
    span_id = generate_span_id()
    
    span = %{
      trace_id: trace_id,
      span_id: span_id,
      parent_span_id: nil,
      operation_name: operation_name,
      start_time: System.system_time(:microsecond),
      end_time: nil,
      attributes: Map.merge(attributes, %{
        "node" => Node.self(),
        "service.name" => "aiex",
        "service.version" => Application.spec(:aiex, :vsn) || "unknown"
      }),
      events: [],
      status: :ok,
      links: []
    }
    
    # Set in process dictionary for automatic propagation
    Process.put(@span_context_key, {trace_id, span_id})
    StructuredLogger.set_trace_context(trace_id, span_id)
    
    GenServer.cast(__MODULE__, {:start_span, span})
    
    {trace_id, span_id}
  end
  
  @doc "Start a child span with automatic parent context"
  def start_span(operation_name, attributes \\ %{}) do
    case get_current_span_context() do
      {trace_id, parent_span_id} ->
        span_id = generate_span_id()
        
        span = %{
          trace_id: trace_id,
          span_id: span_id,
          parent_span_id: parent_span_id,
          operation_name: operation_name,
          start_time: System.system_time(:microsecond),
          end_time: nil,
          attributes: Map.merge(attributes, %{
            "node" => Node.self(),
            "parent.span_id" => parent_span_id
          }),
          events: [],
          status: :ok,
          links: []
        }
        
        # Update current span context
        Process.put(@span_context_key, {trace_id, span_id})
        StructuredLogger.set_trace_context(trace_id, span_id)
        
        GenServer.cast(__MODULE__, {:start_span, span})
        
        {trace_id, span_id}
        
      nil ->
        # No active trace, start a new one
        start_trace(operation_name, attributes)
    end
  end
  
  @doc "End the current span"
  def end_span(status \\ :ok, attributes \\ %{}) do
    case get_current_span_context() do
      {trace_id, span_id} ->
        GenServer.cast(__MODULE__, {:end_span, trace_id, span_id, status, attributes})
        
        # Restore parent span context if any
        restore_parent_context(trace_id, span_id)
        
      nil ->
        Logger.warning("Attempted to end span but no active span found")
    end
  end
  
  @doc "Add an event to the current span"
  def add_event(name, attributes \\ %{}) do
    case get_current_span_context() do
      {trace_id, span_id} ->
        event = %{
          name: name,
          timestamp: System.system_time(:microsecond),
          attributes: attributes
        }
        
        GenServer.cast(__MODULE__, {:add_event, trace_id, span_id, event})
        
      nil ->
        Logger.debug("No active span for event: #{name}")
    end
  end
  
  @doc "Set attributes on the current span"
  def set_attributes(attributes) do
    case get_current_span_context() do
      {trace_id, span_id} ->
        GenServer.cast(__MODULE__, {:set_attributes, trace_id, span_id, attributes})
        
      nil ->
        Logger.debug("No active span for attributes: #{inspect(attributes)}")
    end
  end
  
  @doc "Get the current span context"
  def get_current_span_context do
    Process.get(@span_context_key)
  end
  
  @doc "Set span context from remote headers"
  def set_span_context_from_headers(headers) do
    trace_id = Map.get(headers, @trace_header)
    span_id = Map.get(headers, @span_header)
    parent_span_id = Map.get(headers, @parent_span_header)
    
    if trace_id && span_id do
      Process.put(@span_context_key, {trace_id, span_id})
      StructuredLogger.set_trace_context(trace_id, span_id)
      
      # If this is from a remote call, record the parent relationship
      if parent_span_id do
        add_event("remote_call_received", %{
          "parent.span_id" => parent_span_id,
          "remote.node" => "unknown"
        })
      end
      
      {trace_id, span_id}
    else
      nil
    end
  end
  
  @doc "Get headers for propagating trace context"
  def get_propagation_headers do
    case get_current_span_context() do
      {trace_id, span_id} ->
        %{
          @trace_header => trace_id,
          @span_header => span_id,
          @parent_span_header => span_id
        }
        
      nil ->
        %{}
    end
  end
  
  @doc "Execute a function within a span"
  def with_span(operation_name, attributes \\ %{}, fun) do
    {_trace_id, _span_id} = start_span(operation_name, attributes)
    
    try do
      result = fun.()
      end_span(:ok)
      result
    rescue
      error ->
        end_span(:error, %{"error.message" => Exception.message(error)})
        reraise error, __STACKTRACE__
    end
  end
  
  @doc "Get trace for debugging"
  def get_trace(trace_id) do
    GenServer.call(__MODULE__, {:get_trace, trace_id})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    spans_ets = :ets.new(:distributed_spans, [:set, :private])
    
    state = %__MODULE__{
      spans_ets: spans_ets,
      active_spans: %{},
      sampling_rate: Keyword.get(opts, :sampling_rate, 1.0),
      export_endpoint: Keyword.get(opts, :export_endpoint),
      enabled: Keyword.get(opts, :enabled, true)
    }
    
    Logger.info("Distributed tracer started with sampling rate #{state.sampling_rate}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_trace, trace_id}, _from, state) do
    spans = :ets.select(state.spans_ets, [
      {{:"$1", :"$2"}, [{:==, {:map_get, :trace_id, :"$2"}, trace_id}], [:"$2"]}
    ])
    |> Enum.sort_by(& &1.start_time)
    
    {:reply, spans, state}
  end
  
  @impl true
  def handle_cast({:start_span, span}, state) do
    if should_sample?(span.trace_id, state.sampling_rate) do
      key = {span.trace_id, span.span_id}
      :ets.insert(state.spans_ets, {key, span})
      
      # Record metric
      DistributedAggregator.record_metric("traces.span.started", 1, %{
        operation: span.operation_name,
        node: Node.self()
      })
      
      # Log span start
      StructuredLogger.log_event("span.start", %{
        trace_id: span.trace_id,
        span_id: span.span_id,
        operation_name: span.operation_name
      })
    end
    
    {:noreply, state}
  end
  
  def handle_cast({:end_span, trace_id, span_id, status, attributes}, state) do
    key = {trace_id, span_id}
    
    case :ets.lookup(state.spans_ets, key) do
      [{^key, span}] ->
        duration = System.system_time(:microsecond) - span.start_time
        
        updated_span = %{span |
          end_time: System.system_time(:microsecond),
          status: status,
          attributes: Map.merge(span.attributes, Map.merge(attributes, %{
            "duration_us" => duration
          }))
        }
        
        :ets.insert(state.spans_ets, {key, updated_span})
        
        # Record metrics
        DistributedAggregator.record_metric("traces.span.completed", 1, %{
          operation: span.operation_name,
          status: status,
          node: Node.self()
        })
        
        DistributedAggregator.record_metric("traces.span.duration", duration, %{
          operation: span.operation_name,
          node: Node.self()
        })
        
        # Log span end
        StructuredLogger.log_event("span.end", %{
          trace_id: trace_id,
          span_id: span_id,
          operation_name: span.operation_name,
          duration_us: duration,
          status: status
        })
        
        # Export if configured
        if state.export_endpoint do
          export_span(updated_span, state)
        end
        
      [] ->
        Logger.warning("Attempted to end unknown span: #{trace_id}/#{span_id}")
    end
    
    {:noreply, state}
  end
  
  def handle_cast({:add_event, trace_id, span_id, event}, state) do
    key = {trace_id, span_id}
    
    case :ets.lookup(state.spans_ets, key) do
      [{^key, span}] ->
        updated_span = %{span | events: [event | span.events]}
        :ets.insert(state.spans_ets, {key, updated_span})
        
      [] ->
        Logger.debug("Attempted to add event to unknown span: #{trace_id}/#{span_id}")
    end
    
    {:noreply, state}
  end
  
  def handle_cast({:set_attributes, trace_id, span_id, attributes}, state) do
    key = {trace_id, span_id}
    
    case :ets.lookup(state.spans_ets, key) do
      [{^key, span}] ->
        updated_span = %{span | attributes: Map.merge(span.attributes, attributes)}
        :ets.insert(state.spans_ets, {key, updated_span})
        
      [] ->
        Logger.debug("Attempted to set attributes on unknown span: #{trace_id}/#{span_id}")
    end
    
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    :ets.delete(state.spans_ets)
    :ok
  end
  
  # Private functions
  
  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp generate_span_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp should_sample?(_trace_id, rate) when rate >= 1.0, do: true
  defp should_sample?(_trace_id, rate) when rate <= 0.0, do: false
  defp should_sample?(trace_id, rate) do
    # Use trace ID for consistent sampling decisions
    hash = :erlang.phash2(trace_id, 1000)
    hash < (rate * 1000)
  end
  
  defp restore_parent_context(trace_id, span_id) do
    # Find parent span in the same trace
    spans = :ets.select(:distributed_spans, [
      {{:"$1", :"$2"}, 
       [{:andalso, {:==, {:map_get, :trace_id, :"$2"}, trace_id},
                  {:==, {:map_get, :span_id, :"$2"}, span_id}}],
       [:"$2"]}
    ])
    
    case spans do
      [span] when not is_nil(span.parent_span_id) ->
        Process.put(@span_context_key, {trace_id, span.parent_span_id})
        StructuredLogger.set_trace_context(trace_id, span.parent_span_id)
        
      _ ->
        Process.delete(@span_context_key)
        StructuredLogger.set_trace_context(nil, nil)
    end
  end
  
  defp export_span(span, state) do
    # Export to external tracing system (implementation depends on the system)
    # This is a placeholder for actual export logic
    Logger.debug("Exporting span to #{state.export_endpoint}: #{span.operation_name}")
  end
end