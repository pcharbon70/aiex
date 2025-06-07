defmodule Aiex.InterfaceGatewayTest do
  use ExUnit.Case, async: false

  alias Aiex.InterfaceGateway
  alias Aiex.InterfaceBehaviour

  setup do
    # The gateway is already started by the application
    # Just ensure it's available
    Process.whereis(InterfaceGateway) || flunk("InterfaceGateway not started")
    :ok
  end

  describe "interface registration" do
    test "registers interface successfully" do
      config = %{
        type: :test,
        session_id: "test_session",
        user_id: nil,
        capabilities: [:test_capability],
        settings: %{}
      }

      assert {:ok, interface_id} = InterfaceGateway.register_interface(TestInterface, config)
      assert is_binary(interface_id)
      assert String.starts_with?(interface_id, "test_")
    end

    test "unregisters interface successfully" do
      config = %{
        type: :test,
        session_id: "test_session",
        user_id: nil,
        capabilities: [:test_capability],
        settings: %{}
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(TestInterface, config)
      assert :ok = InterfaceGateway.unregister_interface(interface_id)
      assert {:error, :not_found} = InterfaceGateway.unregister_interface(interface_id)
    end
  end

  describe "request handling" do
    test "submits request successfully" do
      config = %{
        type: :test,
        session_id: "test_session",
        user_id: nil,
        capabilities: [:test_capability],
        settings: %{}
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(TestInterface, config)

      request = %{
        id: "test_request",
        type: :completion,
        content: "test content",
        context: %{},
        options: []
      }

      assert {:ok, request_id} = InterfaceGateway.submit_request(interface_id, request)
      assert is_binary(request_id)
    end

    test "fails to submit request for unregistered interface" do
      request = %{
        id: "test_request",
        type: :completion,
        content: "test content",
        context: %{},
        options: []
      }

      assert {:error, :interface_not_found} =
               InterfaceGateway.submit_request("nonexistent", request)
    end
  end

  describe "request status" do
    test "returns request status" do
      config = %{
        type: :test,
        session_id: "test_session",
        user_id: nil,
        capabilities: [:test_capability],
        settings: %{}
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(TestInterface, config)

      request = %{
        id: "test_request",
        type: :completion,
        content: "test content",
        context: %{},
        options: []
      }

      {:ok, request_id} = InterfaceGateway.submit_request(interface_id, request)

      assert {:ok, status} = InterfaceGateway.get_request_status(request_id)
      assert status.id == request_id
      assert status.interface_id == interface_id
      assert status.status == :processing
    end

    test "returns error for unknown request" do
      assert {:error, :not_found} = InterfaceGateway.get_request_status("unknown_request")
    end
  end

  describe "cluster status" do
    test "returns cluster status information" do
      status = InterfaceGateway.get_cluster_status()

      assert is_map(status)
      assert Map.has_key?(status, :node)
      assert Map.has_key?(status, :interfaces)
      assert Map.has_key?(status, :active_requests)
      assert Map.has_key?(status, :cluster_nodes)
    end
  end

  describe "event subscription" do
    test "subscribes interface to events" do
      config = %{
        type: :test,
        session_id: "test_session",
        user_id: nil,
        capabilities: [:test_capability],
        settings: %{}
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(TestInterface, config)

      assert :ok =
               InterfaceGateway.subscribe_events(interface_id, [
                 :request_completed,
                 :request_failed
               ])
    end

    test "fails to subscribe events for unregistered interface" do
      assert {:error, :interface_not_found} =
               InterfaceGateway.subscribe_events("nonexistent", [:test_event])
    end
  end
end

# Mock interface module for testing
defmodule TestInterface do
  @behaviour Aiex.InterfaceBehaviour

  @impl true
  def init(_config), do: {:ok, %{}}

  @impl true
  def handle_request(_request, state), do: {:ok, %{}, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  @impl true
  def get_status(_state) do
    %{
      capabilities: [:test_capability],
      active_requests: [],
      session_info: %{}
    }
  end
end
