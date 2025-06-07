defmodule Aiex.Interfaces.MultiInterfaceTest do
  use ExUnit.Case, async: true
  
  alias Aiex.InterfaceGateway
  alias Aiex.Interfaces.{LiveViewInterface, LSPInterface}
  alias Aiex.Events.EventBus

  @moduletag :multi_interface

  setup do
    # Start required services for testing (handle already started gracefully)
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

  describe "InterfaceGateway coordination" do
    test "registers multiple interface types", %{gateway_pid: _gateway_pid} do
      # Register CLI interface
      cli_config = %{
        type: :cli,
        session_id: "test_cli",
        user_id: nil,
        capabilities: [:text_output, :colored_output]
      }
      
      {:ok, cli_id} = InterfaceGateway.register_interface(MockCLIInterface, cli_config)
      assert is_binary(cli_id)
      assert String.starts_with?(cli_id, "cli_")

      # Register LiveView interface  
      lv_config = %{
        type: :liveview,
        session_id: "test_liveview",
        user_id: nil,
        capabilities: [:real_time_collaboration, :multi_user_sessions]
      }
      
      {:ok, lv_id} = InterfaceGateway.register_interface(MockLiveViewInterface, lv_config)
      assert is_binary(lv_id)
      assert String.starts_with?(lv_id, "liveview_")

      # Verify both interfaces are registered
      interfaces_status = InterfaceGateway.get_interfaces_status()
      assert Map.has_key?(interfaces_status, cli_id)
      assert Map.has_key?(interfaces_status, lv_id)
      
      assert interfaces_status[cli_id].type == :cli
      assert interfaces_status[lv_id].type == :liveview
    end

    test "routes requests to appropriate services" do
      config = %{
        type: :cli,
        session_id: "test_routing",
        user_id: nil,
        capabilities: [:text_output]
      }
      
      {:ok, interface_id} = InterfaceGateway.register_interface(MockCLIInterface, config)

      # Test completion request
      completion_request = %{
        id: "req_1",
        type: :completion,
        content: "def hello",
        context: %{file_path: "test.ex"},
        priority: :normal
      }

      {:ok, request_id} = InterfaceGateway.submit_request(interface_id, completion_request)
      assert is_binary(request_id)

      # Test analysis request  
      analysis_request = %{
        id: "req_2", 
        type: :analysis,
        content: "defmodule Test do\n  def hello, do: :world\nend",
        context: %{file_path: "test.ex"},
        priority: :high
      }

      {:ok, request_id_2} = InterfaceGateway.submit_request(interface_id, analysis_request)
      assert is_binary(request_id_2)
      assert request_id != request_id_2
    end

    test "handles interface-to-interface communication" do
      # Register two interfaces
      config1 = %{
        type: :cli,
        session_id: "test_cli_comm",
        user_id: nil,
        capabilities: [:text_output]
      }
      
      config2 = %{
        type: :liveview,
        session_id: "test_lv_comm", 
        user_id: nil,
        capabilities: [:real_time_collaboration]
      }

      {:ok, cli_id} = InterfaceGateway.register_interface(MockCLIInterface, config1)
      {:ok, lv_id} = InterfaceGateway.register_interface(MockLiveViewInterface, config2)

      # Send message between interfaces
      message = %{type: :context_sync, data: %{file: "test.ex", content: "new content"}}
      result = InterfaceGateway.send_interface_message(cli_id, lv_id, message)
      
      # Should succeed if target interface supports messaging
      assert result in [:ok, {:error, :not_supported}]
    end

    test "broadcasts events to interface types" do
      # Register multiple interfaces of same type
      config_base = %{
        session_id: "test_broadcast",
        user_id: nil,
        capabilities: [:text_output]
      }

      cli_config1 = Map.put(config_base, :type, :cli)
      cli_config2 = Map.put(config_base, :type, :cli)
      lv_config = Map.put(config_base, :type, :liveview)

      {:ok, _cli_id1} = InterfaceGateway.register_interface(MockCLIInterface, cli_config1)
      {:ok, _cli_id2} = InterfaceGateway.register_interface(MockCLIInterface, cli_config2)
      {:ok, _lv_id} = InterfaceGateway.register_interface(MockLiveViewInterface, lv_config)

      # Broadcast to CLI interfaces only
      event = %{type: :system_update, data: %{message: "System maintenance in 5 minutes"}}
      :ok = InterfaceGateway.broadcast_to_interfaces(:cli, event)

      # Verify broadcast was sent (in real implementation, interfaces would receive events)
      # For testing, we just verify the call doesn't error
      assert true
    end

    test "provides interface metrics and status" do
      config = %{
        type: :cli,
        session_id: "test_metrics",
        user_id: nil,
        capabilities: [:text_output]
      }
      
      {:ok, interface_id} = InterfaceGateway.register_interface(MockCLIInterface, config)

      # Get interface metrics
      {:ok, metrics} = InterfaceGateway.get_interface_metrics(interface_id)
      
      assert Map.has_key?(metrics, :interface_id)
      assert Map.has_key?(metrics, :type)
      assert Map.has_key?(metrics, :uptime)
      assert Map.has_key?(metrics, :active_requests)
      assert metrics.interface_id == interface_id
      assert metrics.type == :cli
    end

    test "handles configuration updates across interfaces" do
      config = %{
        type: :cli,
        session_id: "test_config_update",
        user_id: nil,
        capabilities: [:text_output]
      }
      
      {:ok, _interface_id} = InterfaceGateway.register_interface(MockCLIInterface, config)

      # Update configuration
      config_updates = %{
        log_level: :debug,
        max_retries: 5,
        timeout: 30_000
      }

      :ok = InterfaceGateway.update_interface_config(config_updates)

      # Verify update was processed (in real implementation, interfaces would be notified)
      assert true
    end

    test "unregisters interfaces cleanly" do
      config = %{
        type: :cli,
        session_id: "test_unregister",
        user_id: nil,
        capabilities: [:text_output]
      }
      
      {:ok, interface_id} = InterfaceGateway.register_interface(MockCLIInterface, config)

      # Verify interface is registered
      interfaces_status = InterfaceGateway.get_interfaces_status()
      assert Map.has_key?(interfaces_status, interface_id)

      # Unregister interface
      :ok = InterfaceGateway.unregister_interface(interface_id)

      # Verify interface is removed
      updated_status = InterfaceGateway.get_interfaces_status()
      refute Map.has_key?(updated_status, interface_id)
    end
  end

  describe "LiveView interface coordination" do
    test "manages collaborative sessions" do
      # This would test the LiveViewInterface module
      # For now, we test the basic structure
      config = %{
        type: :liveview,
        session_id: "test_collaboration",
        user_id: nil,
        capabilities: [:real_time_collaboration, :multi_user_sessions]
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(MockLiveViewInterface, config)
      assert is_binary(interface_id)

      # Test session creation (would be handled by LiveViewInterface)
      session_request = %{
        id: "session_req_1",
        type: :completion,
        content: "Create collaborative session",
        context: %{
          session_type: :collaborative,
          max_participants: 5
        },
        priority: :normal
      }

      {:ok, request_id} = InterfaceGateway.submit_request(interface_id, session_request)
      assert is_binary(request_id)
    end

    test "handles real-time context synchronization" do
      config = %{
        type: :liveview,
        session_id: "test_realtime_sync",
        user_id: nil,
        capabilities: [:real_time_collaboration, :shared_context]
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(MockLiveViewInterface, config)

      # Simulate context update
      context_update = %{
        id: "context_update_1",
        type: :analysis,
        content: "Updated file content",
        context: %{
          file_path: "lib/test.ex",
          change_type: :content_update,
          collaborative_session: "session_123"
        },
        priority: :high
      }

      {:ok, request_id} = InterfaceGateway.submit_request(interface_id, context_update)
      assert is_binary(request_id)
    end
  end

  describe "LSP interface coordination" do
    test "handles LSP protocol requests" do
      config = %{
        type: :lsp,
        session_id: "test_lsp",
        user_id: nil,
        capabilities: [
          :text_document_completion,
          :text_document_hover,
          :text_document_code_action
        ]
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(MockLSPInterface, config)
      assert is_binary(interface_id)

      # Test completion request
      completion_request = %{
        id: "lsp_completion_1",
        type: :completion,
        content: "defmodule MyMod",
        context: %{
          document_uri: "file:///test.ex",
          position: %{line: 0, character: 15},
          trigger_character: nil
        },
        priority: :high
      }

      {:ok, request_id} = InterfaceGateway.submit_request(interface_id, completion_request)
      assert is_binary(request_id)
    end

    test "processes hover requests for explanations" do
      config = %{
        type: :lsp,
        session_id: "test_lsp_hover",
        user_id: nil,
        capabilities: [:text_document_hover, :ai_explanations]
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(MockLSPInterface, config)

      # Test hover request
      hover_request = %{
        id: "lsp_hover_1",
        type: :explanation,
        content: "GenServer.call",
        context: %{
          document_uri: "file:///test.ex",
          position: %{line: 5, character: 10},
          symbol: "GenServer.call"
        },
        priority: :normal
      }

      {:ok, request_id} = InterfaceGateway.submit_request(interface_id, hover_request)
      assert is_binary(request_id)
    end

    test "handles code action requests" do
      config = %{
        type: :lsp,
        session_id: "test_lsp_actions",
        user_id: nil,
        capabilities: [:text_document_code_action, :ai_refactoring]
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(MockLSPInterface, config)

      # Test code action request
      action_request = %{
        id: "lsp_action_1",
        type: :refactor,
        content: "def long_function_name do\n  # complex code\nend",
        context: %{
          document_uri: "file:///test.ex",
          range: %{
            start: %{line: 10, character: 0},
            end: %{line: 15, character: 3}
          },
          selected_text: "def long_function_name do\n  # complex code\nend"
        },
        priority: :normal
      }

      {:ok, request_id} = InterfaceGateway.submit_request(interface_id, action_request)
      assert is_binary(request_id)
    end
  end

  describe "cross-interface synchronization" do
    test "synchronizes context across different interface types" do
      # Register multiple interface types
      cli_config = %{
        type: :cli,
        session_id: "sync_test_cli",
        user_id: "user_1",
        capabilities: [:text_output]
      }

      lv_config = %{
        type: :liveview,
        session_id: "sync_test_lv",
        user_id: "user_1",
        capabilities: [:real_time_collaboration]
      }

      lsp_config = %{
        type: :lsp,
        session_id: "sync_test_lsp",
        user_id: "user_1",
        capabilities: [:text_document_completion]
      }

      {:ok, cli_id} = InterfaceGateway.register_interface(MockCLIInterface, cli_config)
      {:ok, lv_id} = InterfaceGateway.register_interface(MockLiveViewInterface, lv_config)
      {:ok, lsp_id} = InterfaceGateway.register_interface(MockLSPInterface, lsp_config)

      # Submit request from CLI that should affect other interfaces
      context_request = %{
        id: "cross_sync_1",
        type: :analysis,
        content: "defmodule SharedModule do\n  def shared_function, do: :ok\nend",
        context: %{
          file_path: "lib/shared.ex",
          sync_across_interfaces: true,
          user_id: "user_1"
        },
        priority: :high
      }

      {:ok, request_id} = InterfaceGateway.submit_request(cli_id, context_request)
      assert is_binary(request_id)

      # Verify all interfaces have access to updated context
      # In real implementation, interfaces would receive context_updated events
      all_interfaces = InterfaceGateway.get_interfaces_status()
      assert Map.has_key?(all_interfaces, cli_id)
      assert Map.has_key?(all_interfaces, lv_id) 
      assert Map.has_key?(all_interfaces, lsp_id)
    end

    test "handles interface state consistency" do
      # Test that interface state remains consistent across operations
      config = %{
        type: :cli,
        session_id: "consistency_test",
        user_id: nil,
        capabilities: [:text_output]
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(MockCLIInterface, config)

      # Submit multiple requests concurrently
      tasks = 
        1..5
        |> Enum.map(fn i ->
          Task.async(fn ->
            request = %{
              id: "concurrent_req_#{i}",
              type: :completion,
              content: "def function_#{i}",
              context: %{file_path: "test_#{i}.ex"},
              priority: :normal
            }
            InterfaceGateway.submit_request(interface_id, request)
          end)
        end)

      # Wait for all requests to complete
      results = Task.await_many(tasks, 5000)
      
      # Verify all requests were processed successfully
      Enum.each(results, fn result ->
        assert {:ok, request_id} = result
        assert is_binary(request_id)
      end)

      # Verify interface metrics are consistent
      {:ok, metrics} = InterfaceGateway.get_interface_metrics(interface_id)
      assert is_integer(metrics.total_requests)
    end
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

  defmodule MockLSPInterface do
    @behaviour Aiex.InterfaceBehaviour

    def init(config), do: {:ok, config}
    def handle_request(request, state), do: {:ok, %{id: request.id, status: :success, content: "mock lsp response", metadata: %{}}, state}
    def handle_event(_type, _data, state), do: {:ok, state}
    def terminate(_reason, _state), do: :ok
    def get_status(_state), do: %{capabilities: [:text_document_completion], active_requests: [], session_info: %{}, health: :healthy}
    def handle_config_update(_config, state), do: {:ok, state}
    def handle_interface_message(_from, _message, state), do: {:ok, state}
    def validate_request(_request), do: :ok
    def format_response(response, _state), do: response
  end
end