defmodule Aiex.AI.Behaviours.AssistantTest do
  use ExUnit.Case, async: true
  
  alias Aiex.AI.Behaviours.Assistant
  
  # Mock assistant implementation for testing
  defmodule MockAssistant do
    @behaviour Assistant
    
    @impl Assistant
    def handle_request(request, conversation_context, project_context) do
      case request do
        %{type: :coding_task, task: "simple"} ->
          updated_context = Map.put(conversation_context, :last_request, :coding_task)
          response = %{result: "Task completed", suggestions: ["Consider adding tests"]}
          {:ok, response, updated_context}
          
        %{type: :error_request} ->
          {:error, "Simulated error"}
          
        _ ->
          {:error, "Unsupported request type"}
      end
    end
    
    @impl Assistant
    def can_handle_request?(request_type) do
      request_type in [:coding_task, :explanation, :conversation]
    end
    
    @impl Assistant
    def get_capabilities do
      %{
        name: "Mock Assistant",
        description: "Test assistant implementation",
        supported_workflows: [:coding_task, :explanation, :conversation],
        required_engines: [:mock_engine]
      }
    end
    
    @impl Assistant
    def start_session(session_id, initial_context) do
      session_state = %{
        session_id: session_id,
        context: initial_context,
        started_at: DateTime.utc_now()
      }
      {:ok, session_state}
    end
    
    @impl Assistant
    def end_session(_session_id) do
      :ok
    end
  end
  
  describe "Assistant behaviour" do
    test "implements all required callbacks" do
      callbacks = Assistant.behaviour_info(:callbacks)
      
      expected_callbacks = [
        {:handle_request, 3},
        {:can_handle_request?, 1},
        {:get_capabilities, 0},
        {:start_session, 2},
        {:end_session, 1}
      ]
      
      for callback <- expected_callbacks do
        assert callback in callbacks, "Missing callback: #{inspect(callback)}"
      end
    end
    
    test "handle_request/3 processes requests successfully" do
      request = %{type: :coding_task, task: "simple", description: "Create a function"}
      conversation_context = %{messages: []}
      project_context = %{language: :elixir}
      
      assert {:ok, response, updated_context} = 
        MockAssistant.handle_request(request, conversation_context, project_context)
      
      assert is_map(response)
      assert Map.has_key?(response, :result)
      assert is_map(updated_context)
      assert updated_context.last_request == :coding_task
    end
    
    test "handle_request/3 handles errors" do
      request = %{type: :error_request}
      conversation_context = %{}
      project_context = %{}
      
      assert {:error, "Simulated error"} = 
        MockAssistant.handle_request(request, conversation_context, project_context)
    end
    
    test "can_handle_request?/1 validates request types" do
      assert MockAssistant.can_handle_request?(:coding_task)
      assert MockAssistant.can_handle_request?(:explanation)
      assert MockAssistant.can_handle_request?(:conversation)
      refute MockAssistant.can_handle_request?(:unsupported)
    end
    
    test "get_capabilities/0 returns required information" do
      capabilities = MockAssistant.get_capabilities()
      
      assert is_map(capabilities)
      assert Map.has_key?(capabilities, :name)
      assert Map.has_key?(capabilities, :description)
      assert Map.has_key?(capabilities, :supported_workflows)
      assert Map.has_key?(capabilities, :required_engines)
      
      assert is_binary(capabilities.name)
      assert is_binary(capabilities.description)
      assert is_list(capabilities.supported_workflows)
      assert is_list(capabilities.required_engines)
    end
    
    test "start_session/2 creates new session" do
      session_id = "test_session_123"
      initial_context = %{user: "test_user", project: "test_project"}
      
      assert {:ok, session_state} = MockAssistant.start_session(session_id, initial_context)
      
      assert is_map(session_state)
      assert session_state.session_id == session_id
      assert session_state.context == initial_context
      assert %DateTime{} = session_state.started_at
    end
    
    test "end_session/1 ends session successfully" do
      session_id = "test_session_123"
      assert :ok = MockAssistant.end_session(session_id)
    end
  end
  
  describe "optional callbacks" do
    test "start_session and end_session are optional" do
      optional_callbacks = Assistant.behaviour_info(:optional_callbacks)
      
      assert {:start_session, 2} in optional_callbacks
      assert {:end_session, 1} in optional_callbacks
    end
  end
end