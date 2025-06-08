defmodule Aiex.AI.Behaviours.AIEngineTest do
  use ExUnit.Case, async: true
  
  alias Aiex.AI.Behaviours.AIEngine
  
  # Mock AI engine implementation for testing
  defmodule MockAIEngine do
    @behaviour AIEngine
    
    @impl AIEngine
    def process(request, context) do
      case request do
        %{type: :test_success} -> {:ok, %{result: "success"}}
        %{type: :test_error} -> {:error, "test error"}
        _ -> {:error, "unknown request type"}
      end
    end
    
    @impl AIEngine
    def can_handle?(request_type) do
      request_type in [:test_success, :test_error, :mock_analysis]
    end
    
    @impl AIEngine
    def get_metadata do
      %{
        name: "Mock AI Engine",
        description: "Test implementation",
        supported_types: [:test_success, :test_error, :mock_analysis],
        version: "1.0.0"
      }
    end
    
    @impl AIEngine
    def prepare(_options), do: :ok
    
    @impl AIEngine
    def cleanup, do: :ok
  end
  
  describe "AIEngine behaviour" do
    test "implements all required callbacks" do
      # Verify the behavior defines expected callbacks
      callbacks = AIEngine.behaviour_info(:callbacks)
      
      expected_callbacks = [
        {:process, 2},
        {:can_handle?, 1},
        {:get_metadata, 0},
        {:prepare, 1},
        {:cleanup, 0}
      ]
      
      for callback <- expected_callbacks do
        assert callback in callbacks, "Missing callback: #{inspect(callback)}"
      end
    end
    
    test "process/2 handles successful requests" do
      request = %{type: :test_success, data: "test"}
      context = %{session_id: "test"}
      
      assert {:ok, %{result: "success"}} = MockAIEngine.process(request, context)
    end
    
    test "process/2 handles error cases" do
      request = %{type: :test_error}
      context = %{}
      
      assert {:error, "test error"} = MockAIEngine.process(request, context)
    end
    
    test "can_handle?/1 validates request types" do
      assert MockAIEngine.can_handle?(:test_success)
      assert MockAIEngine.can_handle?(:test_error) 
      assert MockAIEngine.can_handle?(:mock_analysis)
      refute MockAIEngine.can_handle?(:unsupported_type)
    end
    
    test "get_metadata/0 returns required information" do
      metadata = MockAIEngine.get_metadata()
      
      assert is_map(metadata)
      assert Map.has_key?(metadata, :name)
      assert Map.has_key?(metadata, :description)
      assert Map.has_key?(metadata, :supported_types)
      assert Map.has_key?(metadata, :version)
      
      assert is_binary(metadata.name)
      assert is_binary(metadata.description)
      assert is_list(metadata.supported_types)
      assert is_binary(metadata.version)
    end
    
    test "prepare/1 initializes engine" do
      assert :ok = MockAIEngine.prepare([])
      assert :ok = MockAIEngine.prepare([option: :value])
    end
    
    test "cleanup/0 cleans up resources" do
      assert :ok = MockAIEngine.cleanup()
    end
  end
  
  describe "optional callbacks" do
    test "prepare and cleanup are optional" do
      optional_callbacks = AIEngine.behaviour_info(:optional_callbacks)
      
      assert {:prepare, 1} in optional_callbacks
      assert {:cleanup, 0} in optional_callbacks
    end
  end
end