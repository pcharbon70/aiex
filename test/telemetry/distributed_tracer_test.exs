defmodule Aiex.Telemetry.DistributedTracerTest do
  use ExUnit.Case, async: false
  
  alias Aiex.Telemetry.{DistributedTracer, DistributedAggregator}
  
  setup do
    # Start dependencies
    {:ok, _aggregator} = DistributedAggregator.start_link()
    {:ok, _tracer} = DistributedTracer.start_link(sampling_rate: 1.0)
    
    on_exit(fn ->
      if Process.whereis(DistributedTracer) do
        GenServer.stop(DistributedTracer)
      end
      if Process.whereis(DistributedAggregator) do
        GenServer.stop(DistributedAggregator)
      end
    end)
    
    :ok
  end
  
  describe "trace management" do
    test "starts and ends traces" do
      {trace_id, span_id} = DistributedTracer.start_trace("test_operation")
      
      assert is_binary(trace_id)
      assert is_binary(span_id)
      assert byte_size(trace_id) == 32  # 16 bytes hex encoded
      assert byte_size(span_id) == 16   # 8 bytes hex encoded
      
      # Check span context is set
      assert DistributedTracer.get_current_span_context() == {trace_id, span_id}
      
      # End the trace
      DistributedTracer.end_span(:ok)
      
      Process.sleep(100)
      
      # Get the trace
      spans = DistributedTracer.get_trace(trace_id)
      assert length(spans) == 1
      
      span = List.first(spans)
      assert span.trace_id == trace_id
      assert span.span_id == span_id
      assert span.operation_name == "test_operation"
      assert span.status == :ok
      assert is_integer(span.start_time)
      assert is_integer(span.end_time)
      assert span.end_time > span.start_time
    end
    
    test "creates child spans" do
      # Start parent trace
      {trace_id, parent_span_id} = DistributedTracer.start_trace("parent_operation")
      
      # Start child span
      {child_trace_id, child_span_id} = DistributedTracer.start_span("child_operation")
      
      # Should be same trace but different span
      assert child_trace_id == trace_id
      assert child_span_id != parent_span_id
      
      # End child span
      DistributedTracer.end_span()
      
      # Current context should return to parent
      assert DistributedTracer.get_current_span_context() == {trace_id, parent_span_id}
      
      # End parent span
      DistributedTracer.end_span()
      
      Process.sleep(100)
      
      # Check trace has both spans
      spans = DistributedTracer.get_trace(trace_id)
      assert length(spans) == 2
      
      child_span = Enum.find(spans, &(&1.span_id == child_span_id))
      assert child_span.parent_span_id == parent_span_id
    end
  end
  
  describe "span events and attributes" do
    test "adds events to spans" do
      {trace_id, _span_id} = DistributedTracer.start_trace("test_with_events")
      
      DistributedTracer.add_event("test_event", %{key: "value"})
      DistributedTracer.add_event("another_event", %{number: 42})
      
      DistributedTracer.end_span()
      
      Process.sleep(100)
      
      spans = DistributedTracer.get_trace(trace_id)
      span = List.first(spans)
      
      assert length(span.events) == 2
      
      events = Enum.sort_by(span.events, & &1.timestamp)
      assert List.first(events).name == "test_event"
      assert List.last(events).name == "another_event"
    end
    
    test "sets span attributes" do
      {trace_id, _span_id} = DistributedTracer.start_trace("test_with_attributes", %{initial: "value"})
      
      DistributedTracer.set_attributes(%{dynamic: "attribute", number: 123})
      
      DistributedTracer.end_span()
      
      Process.sleep(100)
      
      spans = DistributedTracer.get_trace(trace_id)
      span = List.first(spans)
      
      assert span.attributes["initial"] == "value"
      assert span.attributes["dynamic"] == "attribute"
      assert span.attributes["number"] == 123
      assert span.attributes["node"] == Node.self()
    end
  end
  
  describe "span context propagation" do
    test "propagates context through headers" do
      {trace_id, span_id} = DistributedTracer.start_trace("parent_operation")
      
      # Get propagation headers
      headers = DistributedTracer.get_propagation_headers()
      
      assert headers["x-trace-id"] == trace_id
      assert headers["x-span-id"] == span_id
      assert headers["x-parent-span-id"] == span_id
      
      DistributedTracer.end_span()
    end
    
    test "sets context from headers" do
      trace_id = "test_trace_id_123456"
      span_id = "test_span_id"
      parent_span_id = "parent_span"
      
      headers = %{
        "x-trace-id" => trace_id,
        "x-span-id" => span_id,
        "x-parent-span-id" => parent_span_id
      }
      
      result = DistributedTracer.set_span_context_from_headers(headers)
      
      assert result == {trace_id, span_id}
      assert DistributedTracer.get_current_span_context() == {trace_id, span_id}
    end
  end
  
  describe "with_span helper" do
    test "executes function within span" do
      result = DistributedTracer.with_span("test_function", %{type: "test"}, fn ->
        # Add some work
        DistributedTracer.add_event("work_done")
        :success
      end)
      
      assert result == :success
      
      # Span should be ended automatically
      assert DistributedTracer.get_current_span_context() == nil
    end
    
    test "handles exceptions within span" do
      assert_raise RuntimeError, "test error", fn ->
        DistributedTracer.with_span("failing_function", fn ->
          raise "test error"
        end)
      end
      
      # Span should be ended automatically even on error
      assert DistributedTracer.get_current_span_context() == nil
    end
  end
end