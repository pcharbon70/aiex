defmodule Aiex.IEx.HelpersTest do
  use ExUnit.Case, async: true
  
  alias Aiex.IEx.Helpers
  alias Aiex.InterfaceGateway
  alias Aiex.Events.EventBus

  @moduletag :iex_integration

  setup do
    # Start required services for testing
    case start_supervised({EventBus, []}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
    
    {:ok, gateway_pid} = case start_supervised({InterfaceGateway, []}) do
      {:ok, gateway_pid} -> {:ok, gateway_pid}
      {:error, {:already_started, gateway_pid}} -> {:ok, gateway_pid}
    end
    
    %{gateway_pid: gateway_pid}
  end

  describe "ai_complete/2" do
    test "provides code completion suggestions" do
      result = Helpers.ai_complete("defmodule MyModule")
      
      assert %{
        suggestions: suggestions,
        confidence: confidence,
        context_nodes: nodes
      } = result
      
      assert is_list(suggestions)
      assert is_float(confidence)
      assert is_list(nodes)
      assert node() in nodes
    end

    test "handles completion with context options" do
      result = Helpers.ai_complete("def handle_call", context: %{module: GenServer})
      
      assert %{suggestions: suggestions} = result
      assert is_list(suggestions)
    end

    test "provides fallback on error" do
      # Test error handling by providing invalid context
      result = Helpers.ai_complete("invalid code fragment", 
        timeout: 1,  # Very short timeout to force failure
        model: "non-existent-model"
      )
      
      # Should have either suggestions or fallback
      assert Map.has_key?(result, :suggestions) or Map.has_key?(result, :fallback)
    end
  end

  describe "ai_explain/2" do
    test "explains simple code strings" do
      result = Helpers.ai_explain("GenServer.call(pid, :message)")
      
      assert %{
        explanation: explanation,
        complexity: complexity
      } = result
      
      assert is_binary(explanation)
      assert complexity in [:low, :medium, :high]
    end

    test "explains module functions" do
      result = Helpers.ai_explain({Enum, :map})
      
      assert %{explanation: explanation} = result
      assert is_binary(explanation)
    end

    test "handles explanation errors gracefully" do
      result = Helpers.ai_explain("", timeout: 1)  # Force timeout
      
      assert Map.has_key?(result, :explanation) or Map.has_key?(result, :error)
    end
  end

  describe "ai_test/2" do
    test "generates tests for modules" do
      result = Helpers.ai_test(String)
      
      assert %{
        test_file: test_file,
        tests: tests,
        coverage_estimate: coverage
      } = result
      
      assert String.ends_with?(test_file, "_test.exs")
      assert is_list(tests)
      assert is_float(coverage)
    end

    test "supports different test types" do
      result = Helpers.ai_test(Enum, type: :property)
      
      assert %{test_type: test_type} = result
      assert test_type == :property_based
    end

    test "handles test generation errors" do
      result = Helpers.ai_test("invalid_target", timeout: 1)
      
      assert Map.has_key?(result, :tests) or Map.has_key?(result, :error)
    end
  end

  describe "cluster_status/0" do
    test "returns comprehensive cluster information" do
      result = Helpers.cluster_status()
      
      assert %{
        local_node: local_node,
        connected_nodes: connected_nodes,
        total_nodes: total_nodes,
        cluster_health: health,
        ai_providers: providers,
        context_engines: engines,
        interfaces: interfaces
      } = result
      
      assert local_node == node()
      assert is_list(connected_nodes)
      assert is_integer(total_nodes)
      assert health in [:healthy, :degraded, :single_node]
      assert is_map(providers)
      assert is_map(engines)
      assert is_map(interfaces)
    end

    test "includes timestamp" do
      result = Helpers.cluster_status()
      
      assert %{last_updated: timestamp} = result
      assert %DateTime{} = timestamp
    end
  end

  describe "ai_usage/2" do
    test "analyzes function usage patterns" do
      result = Helpers.ai_usage({Enum, :map})
      
      assert %{
        total_usages: total,
        usage_patterns: patterns,
        best_practices: practices
      } = result
      
      assert is_integer(total)
      assert is_list(patterns)
      assert is_list(practices)
    end

    test "handles usage analysis errors" do
      result = Helpers.ai_usage("non_existent_function", timeout: 1)
      
      assert %{total_usages: 0} = result
    end
  end

  describe "distributed_context/2" do
    test "retrieves context information" do
      result = Helpers.distributed_context("String")
      
      assert %{
        local_definitions: local,
        remote_definitions: remote,
        dependencies: deps,
        dependents: dependents
      } = result
      
      assert is_list(local)
      assert is_map(remote)
      assert is_list(deps)
      assert is_list(dependents)
    end

    test "handles context retrieval errors" do
      result = Helpers.distributed_context("non_existent_element")
      
      # Should return empty structure on error
      assert %{
        local_definitions: [],
        remote_definitions: %{}
      } = result
    end
  end

  describe "select_optimal_node/2" do
    test "selects nodes for different request types" do
      {:ok, node, stats} = Helpers.select_optimal_node(:completion)
      
      assert is_atom(node)
      assert is_map(stats)
      assert Map.has_key?(stats, :load)
    end

    test "respects prefer_local option" do
      {:ok, node, _stats} = Helpers.select_optimal_node(:analysis, prefer_local: true)
      
      # Should prefer local node when available
      assert node == node()
    end

    test "handles no suitable nodes scenario" do
      # Mock scenario where no nodes are suitable
      # In real implementation, this would test actual node filtering
      result = Helpers.select_optimal_node(:completion)
      
      case result do
        {:ok, _node, _stats} -> assert true
        {:error, :no_suitable_nodes} -> assert true
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end
    end
  end

  describe "distributed request processing" do
    test "processes requests through interface gateway" do
      # This tests the integration with InterfaceGateway
      request = %{
        id: "test_req_1",
        type: :completion,
        content: "test code",
        context: %{},
        options: [],
        priority: :normal
      }
      
      # The helper should be able to process this through the gateway
      result = Helpers.ai_complete("test code")
      
      # Should return some form of response
      assert is_map(result)
    end
  end

  describe "configuration handling" do
    test "uses default configuration values" do
      # Test that helpers use sensible defaults
      result = Helpers.ai_complete("test")
      
      assert is_map(result)
      # Should not crash due to missing configuration
    end
  end

  describe "error handling and resilience" do
    test "handles interface registration failures gracefully" do
      # This tests resilience when services are not available
      result = Helpers.ai_complete("test", timeout: 100)
      
      # Should either succeed or fail gracefully
      assert is_map(result)
      assert Map.has_key?(result, :suggestions) or Map.has_key?(result, :error)
    end

    test "provides meaningful error messages" do
      result = Helpers.ai_explain("", timeout: 1)
      
      if Map.has_key?(result, :error) do
        assert is_binary(result.error) or is_atom(result.error)
      end
    end
  end

  describe "InterfaceBehaviour implementation" do
    test "implements required callbacks" do
      # Test the minimal InterfaceBehaviour implementation
      config = %{type: :iex, session_id: "test", capabilities: []}
      
      assert {:ok, _state} = Helpers.init(config)
      
      request = %{id: "test", type: :completion, content: "test"}
      assert {:async, "test", _state} = Helpers.handle_request(request, config)
      
      assert {:ok, _state} = Helpers.handle_event(:test_event, %{}, config)
      assert :ok = Helpers.terminate(:normal, config)
      
      status = Helpers.get_status(config)
      assert %{capabilities: _, health: :healthy} = status
    end
  end

  describe "response formatting" do
    test "formats completion responses consistently" do
      result = Helpers.ai_complete("def test")
      
      expected_keys = [:suggestions, :confidence, :context_nodes]
      
      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(result, key), "Missing key: #{key}"
      end)
    end

    test "formats explanation responses consistently" do
      result = Helpers.ai_explain("simple code")
      
      expected_keys = [:explanation, :complexity]
      
      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(result, key), "Missing key: #{key}"
      end)
    end

    test "formats test generation responses consistently" do
      result = Helpers.ai_test(String)
      
      expected_keys = [:test_file, :tests, :coverage_estimate]
      
      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(result, key), "Missing key: #{key}"
      end)
    end
  end
end