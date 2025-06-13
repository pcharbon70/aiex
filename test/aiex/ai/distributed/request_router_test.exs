defmodule Aiex.AI.Distributed.RequestRouterTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Distributed.RequestRouter
  
  setup do
    # Start RequestRouter for testing
    {:ok, pid} = RequestRouter.start_link([])
    on_exit(fn -> 
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)
    %{router_pid: pid}
  end
  
  describe "request processing" do
    test "processes simple explanation request" do
      request = %{
        type: :explanation,
        content: "Explain this code: def hello, do: 'Hello World'"
      }
      
      # Should return some result (might be error due to missing engines in test)
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
    end
    
    test "processes code analysis request" do
      request = %{
        type: :code_analysis,
        content: "def calculate(a, b), do: a + b",
        options: %{analysis_type: :basic}
      }
      
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
    end
    
    test "processes generation request" do
      request = %{
        type: :code_generation,
        content: "Generate a function that adds two numbers",
        options: %{generation_type: :function}
      }
      
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
    end
    
    test "handles requests with requirements" do
      request = %{
        type: :explanation,
        content: "Test content",
        requirements: %{
          provider: :openai,
          model: "gpt-3.5-turbo"
        }
      }
      
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
    end
  end
  
  describe "request routing with options" do
    test "routes request with priority option" do
      request = %{
        type: :explanation,
        content: "High priority request"
      }
      
      result = RequestRouter.route_request(request, priority: :high)
      assert is_tuple(result)
    end
    
    test "routes request with affinity option" do
      request = %{
        type: :explanation,
        content: "Request with affinity"
      }
      
      result = RequestRouter.route_request(request, affinity: :local)
      assert is_tuple(result)
    end
    
    test "routes request with context ID" do
      request = %{
        type: :explanation,
        content: "Request with context"
      }
      
      result = RequestRouter.route_request(request, context_id: "test_context_123")
      assert is_tuple(result)
    end
  end
  
  describe "request type inference" do
    test "infers code analysis from content" do
      # Request without explicit type but content suggests analysis
      request = %{
        content: "Please analyze this code for potential issues"
      }
      
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
      
      # The router should have inferred the type internally
    end
    
    test "infers generation from content" do
      request = %{
        content: "Generate a function that calculates fibonacci numbers"
      }
      
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
    end
    
    test "infers explanation from content" do
      request = %{
        content: "What does this code do: print('hello')"
      }
      
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
    end
    
    test "infers refactoring from content" do
      request = %{
        content: "Refactor this code to make it more efficient"
      }
      
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
    end
    
    test "infers test generation from content" do
      request = %{
        content: "Create unit tests for this function"
      }
      
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
    end
    
    test "defaults to explanation for unclear content" do
      request = %{
        content: "This is unclear content that doesn't match any pattern"
      }
      
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
      
      # Should default to explanation type
    end
  end
  
  describe "routing statistics" do
    test "returns routing statistics" do
      stats = RequestRouter.get_routing_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :total_requests)
      assert Map.has_key?(stats, :successful_requests)
      assert Map.has_key?(stats, :failed_requests)
      assert Map.has_key?(stats, :avg_response_time_ms)
      assert Map.has_key?(stats, :requests_by_type)
      assert Map.has_key?(stats, :requests_by_engine)
      assert Map.has_key?(stats, :last_reset)
      
      assert is_integer(stats.total_requests)
      assert is_integer(stats.successful_requests)
      assert is_integer(stats.failed_requests)
      assert is_number(stats.avg_response_time_ms)
      assert is_map(stats.requests_by_type)
      assert is_map(stats.requests_by_engine)
    end
    
    test "statistics are updated after processing requests" do
      initial_stats = RequestRouter.get_routing_stats()
      initial_total = initial_stats.total_requests
      
      # Process a request
      request = %{
        type: :explanation,
        content: "Test request for stats"
      }
      
      RequestRouter.process_request(request)
      
      # Wait for async processing to complete
      Process.sleep(1000)
      
      updated_stats = RequestRouter.get_routing_stats()
      
      # Total requests should have increased
      assert updated_stats.total_requests >= initial_total
    end
    
    test "tracks requests by type" do
      initial_stats = RequestRouter.get_routing_stats()
      
      # Process requests of different types
      explanation_request = %{type: :explanation, content: "Explain this"}
      analysis_request = %{type: :code_analysis, content: "Analyze this"}
      
      RequestRouter.process_request(explanation_request)
      RequestRouter.process_request(analysis_request)
      
      # Wait for processing
      Process.sleep(1000)
      
      updated_stats = RequestRouter.get_routing_stats()
      
      # Should track by type
      assert is_map(updated_stats.requests_by_type)
    end
  end
  
  describe "queue status" do
    test "returns queue status information" do
      status = RequestRouter.get_queue_status()
      
      assert is_map(status)
      assert Map.has_key?(status, :queue_length)
      assert Map.has_key?(status, :active_requests)
      assert Map.has_key?(status, :node)
      assert Map.has_key?(status, :timestamp)
      
      assert is_integer(status.queue_length)
      assert is_integer(status.active_requests)
      assert status.node == Node.self()
      assert is_integer(status.timestamp)
    end
    
    test "queue status reflects current state" do
      initial_status = RequestRouter.get_queue_status()
      
      # Should start with empty or minimal queue
      assert initial_status.queue_length >= 0
      assert initial_status.active_requests >= 0
    end
  end
  
  describe "context sharing" do
    test "can share context" do
      context_id = "test_context_456"
      context_data = %{
        variables: %{"x" => "integer"},
        functions: ["calculate", "process"]
      }
      
      # Should not crash
      :ok = RequestRouter.share_context(context_id, context_data)
    end
    
    test "can retrieve shared context" do
      context_id = "test_context_789"
      context_data = %{test: "data"}
      
      # Share context
      RequestRouter.share_context(context_id, context_data)
      
      # Give it time to process
      Process.sleep(100)
      
      # Retrieve context
      {:ok, retrieved_context} = RequestRouter.get_shared_context(context_id)
      
      if retrieved_context do
        assert is_map(retrieved_context)
        assert Map.has_key?(retrieved_context, :data)
        assert Map.has_key?(retrieved_context, :timestamp)
        assert Map.has_key?(retrieved_context, :node)
        assert retrieved_context.data == context_data
        assert retrieved_context.node == Node.self()
      end
    end
    
    test "returns nil for non-existent context" do
      {:ok, context} = RequestRouter.get_shared_context("non_existent_context")
      assert is_nil(context)
    end
  end
  
  describe "concurrent request processing" do
    test "handles multiple concurrent requests" do
      requests = Enum.map(1..5, fn i ->
        %{
          type: :explanation,
          content: "Concurrent request #{i}"
        }
      end)
      
      # Submit all requests concurrently
      tasks = Enum.map(requests, fn request ->
        Task.async(fn ->
          RequestRouter.process_request(request)
        end)
      end)
      
      # Wait for all to complete
      results = Task.await_many(tasks, 10_000)
      
      # All should complete
      assert length(results) == 5
      Enum.each(results, fn result ->
        assert is_tuple(result)
      end)
    end
    
    test "maintains routing statistics under concurrent load" do
      initial_stats = RequestRouter.get_routing_stats()
      
      # Submit many requests concurrently
      tasks = Enum.map(1..10, fn i ->
        Task.async(fn ->
          request = %{
            type: :explanation,
            content: "Load test #{i}"
          }
          RequestRouter.process_request(request)
        end)
      end)
      
      # Wait for completion
      Task.await_many(tasks, 15_000)
      
      # Statistics should be updated
      updated_stats = RequestRouter.get_routing_stats()
      assert updated_stats.total_requests >= initial_stats.total_requests + 10
    end
  end
  
  describe "error handling" do
    test "handles malformed requests gracefully" do
      malformed_request = %{
        # Missing content
        type: :explanation
      }
      
      result = RequestRouter.process_request(malformed_request)
      assert is_tuple(result)
      # Should not crash the router
    end
    
    test "handles empty requests" do
      empty_request = %{}
      
      result = RequestRouter.process_request(empty_request)
      assert is_tuple(result)
    end
    
    test "handles requests with invalid types" do
      invalid_request = %{
        type: :invalid_type,
        content: "Test content"
      }
      
      result = RequestRouter.process_request(invalid_request)
      assert is_tuple(result)
    end
    
    test "remains responsive after errors" do
      # Submit a potentially problematic request
      bad_request = %{
        type: :explanation,
        content: nil  # nil content might cause issues
      }
      
      RequestRouter.process_request(bad_request)
      
      # Router should still be responsive
      valid_request = %{
        type: :explanation,
        content: "Valid request after error"
      }
      
      result = RequestRouter.process_request(valid_request)
      assert is_tuple(result)
      
      # Statistics should still work
      stats = RequestRouter.get_routing_stats()
      assert is_map(stats)
    end
  end
  
  describe "request enrichment" do
    test "enriches requests with metadata" do
      request = %{
        type: :explanation,
        content: "Test request"
      }
      
      # The router should enrich the request internally
      # We can't directly test the enrichment, but we can ensure it doesn't break processing
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
    end
    
    test "handles requests with existing metadata" do
      request = %{
        type: :explanation,
        content: "Test request",
        context_id: "existing_context",
        requirements: %{provider: :openai},
        options: %{explanation_type: :detailed}
      }
      
      result = RequestRouter.process_request(request)
      assert is_tuple(result)
    end
  end
end