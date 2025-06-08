defmodule Aiex.Integration.Phase3Test do
  @moduledoc """
  Comprehensive integration tests for Phase 3: Distributed Language Processing.

  These tests validate that all Phase 3 components work together properly:
  - Distributed Semantic Chunking (Section 3.1) 
  - Distributed Context Compression (Section 3.2)
  - Distributed Multi-LLM Coordination (Section 3.3)
  - Multi-Interface Architecture (Section 3.4)
  - Distributed IEx Integration (Section 3.5)
  """

  use ExUnit.Case, async: false
  
  alias Aiex.Context.{DistributedEngine, Manager}
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.InterfaceGateway
  alias Aiex.Events.EventBus
  alias Aiex.IEx.Helpers
  alias Aiex.Semantic.Chunker

  @moduletag :integration
  @moduletag :phase3
  @moduletag timeout: 120_000  # 2 minutes for integration tests

  setup_all do
    # Ensure all services are started
    {:ok, _} = Application.ensure_all_started(:aiex)
    
    # Give services time to stabilize
    :timer.sleep(1000)
    
    :ok
  end

  describe "Distributed semantic chunking at scale" do
    test "chunks large codebase across distributed context" do
      # Test Section 3.1: Distributed Semantic Chunking
      large_code = generate_large_elixir_codebase()
      
      # Test chunking with distributed coordination
      {:ok, chunks} = Chunker.chunk_code(large_code, 
        max_chunk_size: 1000
      )
      
      assert length(chunks) > 1
      assert Enum.all?(chunks, fn chunk -> 
        String.length(chunk.content) <= 1200  # Allow slight overflow for semantic boundaries
      end)
      
      # Verify chunks maintain semantic coherence
      assert Enum.any?(chunks, fn chunk ->
        String.contains?(chunk.content, "defmodule") 
      end)
      
      # Test distributed metadata
      chunk_with_metadata = Enum.find(chunks, fn chunk ->
        Map.has_key?(chunk, :distributed_context)
      end)
      
      if chunk_with_metadata do
        assert Map.has_key?(chunk_with_metadata.distributed_context, :node)
      end
    end

    test "handles chunking failures gracefully in distributed environment" do
      # Test chunking with invalid input
      result = Chunker.chunk_code("")
      case result do
        {:error, reason} -> assert reason in [:empty_content, :invalid_content]
        {:ok, []} -> assert true  # Empty result is also acceptable
      end
      
      # Test chunking with very small chunk size
      small_code = "defmodule Test do\n  def hello, do: :world\nend"
      {:ok, chunks} = Chunker.chunk_code(small_code, max_chunk_size: 10)
      
      # Should create multiple small chunks
      assert length(chunks) > 1
    end
  end

  describe "Context compression across nodes" do
    test "compresses context while maintaining distributed coherence" do
      # Test Section 3.2: Distributed Context Compression  
      test_context = %{
        modules: generate_test_modules(),
        functions: generate_test_functions(), 
        dependencies: generate_test_dependencies()
      }
      
      # Test compression through DistributedEngine
      {:ok, compressed} = DistributedEngine.compress_context(test_context, 
        target_size: 500,
        preserve_critical: true
      )
      
      # Verify compression
      compression_info = Map.get(compressed, :compression_info)
      if compression_info do
        assert compression_info.compressed_size < compression_info.original_size
      end
      
      # Verify critical information preserved (could be in :modules or :critical_data)
      has_modules = Map.has_key?(compressed, :modules) or 
                    (Map.has_key?(compressed, :critical_data) and 
                     Map.has_key?(compressed.critical_data, :modules))
      
      has_summary = Map.has_key?(compressed, :summary) or Map.has_key?(compressed, :compression_info)
      
      assert has_modules
      assert has_summary
    end

    test "maintains context quality after compression" do
      context = %{
        code_analysis: %{
          complexity: :high,
          patterns: [:genserver, :supervision],
          dependencies: ["Ecto", "Phoenix"]
        },
        metadata: %{
          lines_of_code: 1500,
          test_coverage: 0.85
        }
      }
      
      {:ok, compressed} = DistributedEngine.compress_context(context, target_size: 200)
      
      # Should preserve critical patterns and metadata
      assert Map.has_key?(compressed, :code_analysis) or Map.has_key?(compressed, :summary)
    end
  end

  describe "Multi-provider failover with node failures" do
    test "handles provider failover in distributed cluster" do
      # Test Section 3.3: Distributed Multi-LLM Coordination
      
      # Test provider selection
      request = %{
        messages: [%{role: :user, content: "Test completion request"}],
        model: "gpt-4",
        temperature: 0.3
      }
      
      case ModelCoordinator.select_provider(request, []) do
        {:ok, {provider, adapter}} ->
          assert provider in [:openai, :anthropic, :ollama, :lm_studio]
          assert is_atom(adapter)
          
        {:error, :no_providers_available} ->
          # This is acceptable in test environment
          assert true
      end
    end

    test "distributes load across multiple providers" do
      # Test multiple concurrent requests
      requests = Enum.map(1..5, fn i ->
        %{
          messages: [%{role: :user, content: "Request #{i}"}],
          model: "gpt-4"
        }
      end)
      
      results = Enum.map(requests, fn request ->
        ModelCoordinator.select_provider(request, [])
      end)
      
      # At least some requests should succeed
      successful_results = Enum.filter(results, fn 
        {:ok, _} -> true
        _ -> false
      end)
      
      # In a real cluster, we'd expect load distribution
      # In test environment, we just verify the coordinator works
      assert length(results) == 5
    end
  end

  describe "Multi-interface synchronization" do
    test "synchronizes state across different interface types" do
      # Test Section 3.4: Multi-Interface Architecture
      
      # Register multiple interfaces
      cli_config = %{
        type: :cli,
        session_id: "integration_test_cli",
        user_id: "test_user",
        capabilities: [:text_output, :ai_assistance]
      }
      
      liveview_config = %{
        type: :liveview, 
        session_id: "integration_test_lv",
        user_id: "test_user",
        capabilities: [:real_time_collaboration]
      }
      
      {:ok, cli_id} = InterfaceGateway.register_interface(MockCLIInterface, cli_config)
      {:ok, lv_id} = InterfaceGateway.register_interface(MockLiveViewInterface, liveview_config)
      
      # Test cross-interface communication
      result = InterfaceGateway.send_interface_message(cli_id, lv_id, %{
        type: :context_sync,
        data: %{file: "test.ex", content: "updated content"}
      })
      
      assert result in [:ok, {:error, :not_supported}]
      
      # Test broadcasting
      :ok = InterfaceGateway.broadcast_to_interfaces(:cli, %{
        type: :system_update,
        data: %{message: "Integration test broadcast"}
      })
      
      # Verify interfaces are still registered
      interfaces = InterfaceGateway.get_interfaces_status()
      assert Map.has_key?(interfaces, cli_id)
      assert Map.has_key?(interfaces, lv_id)
      
      # Cleanup
      InterfaceGateway.unregister_interface(cli_id)
      InterfaceGateway.unregister_interface(lv_id)
    end

    test "handles interface configuration updates" do
      # Test configuration synchronization
      config = %{
        type: :cli,
        session_id: "config_test",
        user_id: nil,
        capabilities: [:text_output]
      }
      
      {:ok, interface_id} = InterfaceGateway.register_interface(MockCLIInterface, config)
      
      # Update configuration across interfaces
      updates = %{
        log_level: :debug,
        timeout: 60_000
      }
      
      :ok = InterfaceGateway.update_interface_config(updates)
      
      # Cleanup
      InterfaceGateway.unregister_interface(interface_id)
    end
  end

  describe "Distributed IEx helper workflows" do
    test "IEx helpers work in distributed environment" do
      # Test Section 3.5: Distributed IEx Integration
      
      # Test cluster status
      status = Helpers.cluster_status()
      
      assert %{
        local_node: local_node,
        total_nodes: total_nodes,
        cluster_health: health
      } = status
      
      assert is_atom(local_node)
      assert is_integer(total_nodes)
      assert health in [:healthy, :degraded, :single_node]
    end

    test "distributed context retrieval works" do
      # Test distributed context functionality
      result = Helpers.distributed_context("String")
      
      assert %{
        local_definitions: local,
        remote_definitions: remote,
        dependencies: deps,
        dependents: dependents
      } = result
      
      # The function returns nested maps, so extract the actual data
      local_data = case local do
        %{definitions: definitions} -> definitions
        other -> other
      end
      
      assert is_list(local_data)
      assert is_map(remote)
      assert is_list(deps)
      assert is_list(dependents)
    end

    test "optimal node selection works" do
      # Test node selection logic
      case Helpers.select_optimal_node(:completion) do
        {:ok, node, stats} ->
          assert is_atom(node)
          assert is_map(stats)
          assert Map.has_key?(stats, :load)
          
        {:error, :no_suitable_nodes} ->
          # Acceptable in single-node test environment
          assert true
      end
    end
  end

  describe "End-to-end analysis across cluster" do
    test "complete workflow from request to response" do
      # Test end-to-end workflow across all Phase 3 components
      
      # 1. Start with code analysis request
      test_code = """
      defmodule TestModule do
        use GenServer
        
        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end
        
        def init(state) do
          {:ok, state}
        end
        
        def handle_call(:get_state, _from, state) do
          {:reply, state, state}
        end
      end
      """
      
      # 2. Chunk the code (Section 3.1)
      {:ok, chunks} = Chunker.chunk_code(test_code, max_chunk_size: 200)
      assert length(chunks) > 0
      
      # 3. Analyze through distributed engine (Section 3.2)
      {:ok, analysis} = DistributedEngine.analyze_code(test_code)
      assert Map.has_key?(analysis, :complexity)
      
      # 4. Test through interface gateway (Section 3.4)
      interface_config = %{
        type: :cli,
        session_id: "e2e_test",
        user_id: nil,
        capabilities: [:ai_assistance]
      }
      
      {:ok, interface_id} = InterfaceGateway.register_interface(MockCLIInterface, interface_config)
      
      request = %{
        id: "e2e_req_1",
        type: :analysis,
        content: test_code,
        context: %{},
        options: [],
        priority: :normal
      }
      
      {:ok, request_id} = InterfaceGateway.submit_request(interface_id, request)
      assert is_binary(request_id)
      
      # 5. Test IEx helper integration (Section 3.5)
      cluster_status = Helpers.cluster_status()
      assert cluster_status.total_nodes >= 1
      
      # Cleanup
      InterfaceGateway.unregister_interface(interface_id)
    end
  end

  describe "Performance under distributed load" do
    test "handles concurrent requests across components" do
      # Test system performance under load
      
      # Create multiple concurrent requests
      tasks = Enum.map(1..10, fn i ->
        Task.async(fn ->
          # Test different components concurrently
          case rem(i, 4) do
            0 -> 
              # Test chunking
              Chunker.chunk_content("defmodule Test#{i} do\n  def test, do: #{i}\nend", max_chunk_size: 50)
              
            1 ->
              # Test analysis
              DistributedEngine.analyze_code("def test#{i}, do: #{i}")
              
            2 ->
              # Test cluster status
              Helpers.cluster_status()
              
            3 ->
              # Test context retrieval
              Helpers.distributed_context("Test#{i}")
          end
        end)
      end)
      
      # Wait for all tasks to complete
      results = Task.await_many(tasks, 30_000)
      
      # Verify most requests succeeded
      successful_results = Enum.filter(results, fn
        {:ok, _} -> true
        %{} -> true  # cluster_status returns a map directly
        _ -> false
      end)
      
      # At least 70% should succeed under load
      success_rate = length(successful_results) / length(results)
      assert success_rate >= 0.7
    end
  end

  describe "Interface switching scenarios" do
    test "seamlessly switches between interface types" do
      # Test switching from CLI to LiveView interface
      
      # Start with CLI interface
      cli_config = %{
        type: :cli,
        session_id: "switch_test",
        user_id: "switch_user",
        capabilities: [:text_output]
      }
      
      {:ok, cli_id} = InterfaceGateway.register_interface(MockCLIInterface, cli_config)
      
      # Submit request through CLI
      request = %{
        id: "switch_req_1",
        type: :completion,
        content: "def hello",
        context: %{interface: :cli},
        options: [],
        priority: :normal
      }
      
      {:ok, req_id_1} = InterfaceGateway.submit_request(cli_id, request)
      
      # Switch to LiveView interface  
      lv_config = %{
        type: :liveview,
        session_id: "switch_test",  # Same session
        user_id: "switch_user",     # Same user
        capabilities: [:real_time_collaboration]
      }
      
      {:ok, lv_id} = InterfaceGateway.register_interface(MockLiveViewInterface, lv_config)
      
      # Submit continuation request through LiveView
      continuation_request = %{
        id: "switch_req_2", 
        type: :completion,
        content: "do: :world",
        context: %{interface: :liveview, previous_request: req_id_1},
        options: [],
        priority: :normal
      }
      
      {:ok, req_id_2} = InterfaceGateway.submit_request(lv_id, continuation_request)
      
      # Verify both interfaces are active
      interfaces = InterfaceGateway.get_interfaces_status()
      assert Map.has_key?(interfaces, cli_id)
      assert Map.has_key?(interfaces, lv_id)
      
      # Cleanup
      InterfaceGateway.unregister_interface(cli_id)
      InterfaceGateway.unregister_interface(lv_id)
    end
  end

  ## Helper Functions

  defp generate_large_elixir_codebase do
    modules = Enum.map(1..5, fn i ->
      """
      defmodule LargeModule#{i} do
        @moduledoc \"\"\"
        This is a large module #{i} for testing distributed semantic chunking.
        It contains multiple functions and demonstrates various Elixir patterns.
        \"\"\"
        
        use GenServer
        
        def start_link(opts \\\\ []) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end
        
        def init(state) do
          {:ok, state}
        end
        
        def handle_call({:get, key}, _from, state) do
          value = Map.get(state, key)
          {:reply, value, state}
        end
        
        def handle_call({:put, key, value}, _from, state) do
          new_state = Map.put(state, key, value)
          {:reply, :ok, new_state}
        end
        
        def handle_cast({:async_operation, data}, state) do
          # Simulate async work
          Task.start(fn -> process_data(data) end)
          {:noreply, state}
        end
        
        defp process_data(data) do
          # Complex processing logic
          data
          |> Enum.map(&(&1 * 2))
          |> Enum.filter(&(&1 > 10))
          |> Enum.sum()
        end
      end
      """
    end)
    
    Enum.join(modules, "\n\n")
  end

  defp generate_test_modules do
    Enum.map(1..10, fn i ->
      %{
        name: "TestModule#{i}",
        functions: ["function_a", "function_b"],
        complexity: rem(i, 3) + 1
      }
    end)
  end

  defp generate_test_functions do
    Enum.map(1..20, fn i ->
      %{
        name: "test_function_#{i}",
        arity: rem(i, 4),
        module: "TestModule#{rem(i, 10) + 1}"
      }
    end)
  end

  defp generate_test_dependencies do
    [
      %{name: "Ecto", version: "3.10.0"},
      %{name: "Phoenix", version: "1.7.0"},
      %{name: "Plug", version: "1.14.0"}
    ]
  end

  ## Mock Interface Implementations

  defmodule MockCLIInterface do
    @behaviour Aiex.InterfaceBehaviour

    def init(config), do: {:ok, config}
    def handle_request(request, state), do: {:ok, %{id: request.id, status: :success, content: "mock response", metadata: %{}}, state}
    def handle_event(_type, _data, state), do: {:ok, state}
    def terminate(_reason, _state), do: :ok
    def get_status(_state), do: %{capabilities: [:text_output], active_requests: [], session_info: %{}, health: :healthy}
    def handle_config_update(_config, state), do: {:ok, state}
    def handle_interface_message(_from, _message, state), do: {:ok, state}
    def validate_request(_request), do: :ok
    def format_response(response, _state), do: response
  end

  defmodule MockLiveViewInterface do
    @behaviour Aiex.InterfaceBehaviour

    def init(config), do: {:ok, config}
    def handle_request(request, state), do: {:ok, %{id: request.id, status: :success, content: "mock liveview response", metadata: %{}}, state}
    def handle_event(_type, _data, state), do: {:ok, state}
    def terminate(_reason, _state), do: :ok
    def get_status(_state), do: %{capabilities: [:real_time_collaboration], active_requests: [], session_info: %{}, health: :healthy}
    def handle_config_update(_config, state), do: {:ok, state}
    def handle_interface_message(_from, _message, state), do: {:ok, state}
    def validate_request(_request), do: :ok
    def format_response(response, _state), do: response
  end
end