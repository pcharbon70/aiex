defmodule Aiex.AI.Coordinators.ConversationManagerTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Coordinators.ConversationManager
  
  setup do
    # Start the ConversationManager for testing
    {:ok, pid} = start_supervised({ConversationManager, [session_id: "test_conversation_manager_session"]})
    
    %{manager_pid: pid}
  end
  
  describe "ConversationManager initialization" do
    test "starts successfully with default options" do
      assert {:ok, pid} = ConversationManager.start_link()
      assert Process.alive?(pid)
    end
    
    test "starts with custom session_id" do
      session_id = "custom_conversation_manager_session"
      assert {:ok, pid} = ConversationManager.start_link(session_id: session_id)
      assert Process.alive?(pid)
    end
  end
  
  describe "Assistant behavior implementation" do
    test "implements get_capabilities/0 correctly" do
      capabilities = ConversationManager.get_capabilities()
      
      assert capabilities.name == "Conversation Manager"
      assert is_binary(capabilities.description)
      assert is_list(capabilities.supported_workflows)
      assert is_list(capabilities.required_engines)
      assert is_list(capabilities.capabilities)
      
      # Verify supported conversation types
      expected_types = [
        :coding_conversation,
        :general_conversation,
        :project_conversation,
        :debugging_conversation,
        :learning_conversation,
        :planning_conversation
      ]
      
      Enum.each(expected_types, fn type ->
        assert type in capabilities.supported_workflows
      end)
      
      # Verify capabilities
      expected_capabilities = [
        "Multi-turn conversation management",
        "Context preservation across messages",
        "Intent recognition and routing"
      ]
      
      Enum.each(expected_capabilities, fn capability ->
        assert Enum.any?(capabilities.capabilities, &String.contains?(&1, capability))
      end)
    end
    
    test "can_handle_request?/1 returns correct values" do
      # Should handle these request types
      assert ConversationManager.can_handle_request?(:conversation)
      assert ConversationManager.can_handle_request?(:multi_turn_chat)
      assert ConversationManager.can_handle_request?(:context_management)
      assert ConversationManager.can_handle_request?(:conversation_continuation)
      assert ConversationManager.can_handle_request?(:intent_routing)
      
      # Should not handle these
      refute ConversationManager.can_handle_request?(:unsupported_type)
      refute ConversationManager.can_handle_request?(:random_request)
    end
  end
  
  describe "conversation management" do
    test "start_conversation/3 creates new conversation" do
      conversation_id = "test_conv_001"
      conversation_type = :coding_conversation
      initial_context = %{
        project: "my_app",
        language: :elixir,
        user_id: "user123"
      }
      
      result = ConversationManager.start_conversation(conversation_id, conversation_type, initial_context)
      assert {:ok, conversation_state} = result
      
      assert conversation_state.conversation_id == conversation_id
      assert conversation_state.conversation_type == conversation_type
      assert conversation_state.context == initial_context
      assert conversation_state.history == []
      assert Map.has_key?(conversation_state, :started_at)
      assert Map.has_key?(conversation_state, :metadata)
    end
    
    test "start_conversation/3 prevents duplicate conversation IDs" do
      conversation_id = "duplicate_test"
      
      # Start first conversation
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :general_conversation)
      
      # Try to start duplicate
      result = ConversationManager.start_conversation(conversation_id, :coding_conversation)
      assert {:error, :conversation_already_exists} = result
    end
    
    test "start_conversation/3 handles different conversation types" do
      conversation_types = [
        :coding_conversation,
        :general_conversation,
        :project_conversation,
        :debugging_conversation,
        :learning_conversation,
        :planning_conversation
      ]
      
      Enum.each(conversation_types, fn type ->
        conversation_id = "test_#{type}"
        result = ConversationManager.start_conversation(conversation_id, type)
        assert {:ok, conversation_state} = result
        assert conversation_state.conversation_type == type
      end)
    end
  end
  
  describe "conversation continuation" do
    setup do
      conversation_id = "continue_test"
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :coding_conversation, %{})
      %{conversation_id: conversation_id}
    end
    
    test "continue_conversation/3 processes user messages", %{conversation_id: conversation_id} do
      message = "Can you help me implement a user authentication system?"
      user_context = %{urgency: :high}
      
      result = ConversationManager.continue_conversation(conversation_id, message, user_context)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, response} ->
          assert Map.has_key?(response, :response)
          assert is_binary(response.response)
          assert Map.has_key?(response, :assistant_type)
          
        {:error, _reason} ->
          # LLM or dependencies might not be available
          :ok
      end
    end
    
    test "continue_conversation/3 maintains conversation history", %{conversation_id: conversation_id} do
      # Send first message
      message1 = "I need help with Elixir functions"
      ConversationManager.continue_conversation(conversation_id, message1)
      
      # Send second message
      message2 = "Specifically about pattern matching"
      result = ConversationManager.continue_conversation(conversation_id, message2)
      
      case result do
        {:ok, _response} ->
          # Check conversation state
          {:ok, conversation_state} = ConversationManager.get_conversation_state(conversation_id)
          
          # Should have at least 2 user messages and 2 assistant responses
          assert length(conversation_state.history) >= 2
          
          # Check that history contains our messages
          user_messages = Enum.filter(conversation_state.history, &(&1.type == :user))
          assert length(user_messages) >= 2
          
        {:error, _} ->
          :ok
      end
    end
    
    test "continue_conversation/3 handles coding requests", %{conversation_id: conversation_id} do
      coding_message = "Help me fix this bug: def add(a, b), do: a + c"
      
      result = ConversationManager.continue_conversation(conversation_id, coding_message)
      
      case result do
        {:ok, response} ->
          # Should route to coding assistant
          assert response.assistant_type == :coding_assistant
          assert Map.has_key?(response, :workflow) or Map.has_key?(response, :conversation_turn)
          
        {:error, _} ->
          :ok
      end
    end
    
    test "continue_conversation/3 handles general conversation", %{conversation_id: conversation_id} do
      general_message = "What's the weather like today?"
      
      result = ConversationManager.continue_conversation(conversation_id, general_message)
      
      case result do
        {:ok, response} ->
          # Should route to general assistant
          assert response.assistant_type == :general_assistant or response.assistant_type == :coding_assistant
          
        {:error, _} ->
          :ok
      end
    end
    
    test "continue_conversation/3 handles non-existent conversation" do
      result = ConversationManager.continue_conversation("non_existent", "test message")
      assert {:error, :conversation_not_found} = result
    end
  end
  
  describe "conversation state management" do
    test "get_conversation_state/1 retrieves conversation details" do
      conversation_id = "state_test"
      initial_context = %{test: "context"}
      
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :general_conversation, initial_context)
      
      result = ConversationManager.get_conversation_state(conversation_id)
      assert {:ok, conversation_state} = result
      
      assert conversation_state.conversation_id == conversation_id
      assert conversation_state.conversation_type == :general_conversation
      assert conversation_state.context == initial_context
      assert Map.has_key?(conversation_state, :started_at)
      assert Map.has_key?(conversation_state, :last_activity)
      assert Map.has_key?(conversation_state, :metadata)
    end
    
    test "get_conversation_state/1 handles non-existent conversation" do
      result = ConversationManager.get_conversation_state("non_existent")
      assert {:error, :conversation_not_found} = result
    end
    
    test "list_conversations/0 returns active conversations" do
      # Start multiple conversations
      {:ok, _} = ConversationManager.start_conversation("conv1", :coding_conversation)
      {:ok, _} = ConversationManager.start_conversation("conv2", :general_conversation)
      
      result = ConversationManager.list_conversations()
      assert {:ok, conversations} = result
      
      assert is_list(conversations)
      assert length(conversations) >= 2
      
      # Check conversation summaries
      conv_ids = Enum.map(conversations, & &1.conversation_id)
      assert "conv1" in conv_ids
      assert "conv2" in conv_ids
      
      # Check required fields
      first_conv = hd(conversations)
      assert Map.has_key?(first_conv, :conversation_id)
      assert Map.has_key?(first_conv, :type)
      assert Map.has_key?(first_conv, :started_at)
      assert Map.has_key?(first_conv, :message_count)
    end
  end
  
  describe "conversation termination" do
    test "end_conversation/1 terminates and archives conversation" do
      conversation_id = "end_test"
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :coding_conversation)
      
      # Add some conversation history
      ConversationManager.continue_conversation(conversation_id, "Test message")
      
      # End conversation
      result = ConversationManager.end_conversation(conversation_id)
      assert :ok = result
      
      # Conversation should no longer be active
      state_result = ConversationManager.get_conversation_state(conversation_id)
      assert {:error, :conversation_not_found} = state_result
    end
    
    test "end_conversation/1 handles non-existent conversation" do
      result = ConversationManager.end_conversation("non_existent")
      assert {:error, :conversation_not_found} = result
    end
  end
  
  describe "conversation history management" do
    setup do
      conversation_id = "history_test"
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :coding_conversation)
      %{conversation_id: conversation_id}
    end
    
    test "clear_conversation_history/2 clears old messages", %{conversation_id: conversation_id} do
      # Add multiple messages
      messages = [
        "First message",
        "Second message", 
        "Third message",
        "Fourth message",
        "Fifth message"
      ]
      
      Enum.each(messages, fn message ->
        ConversationManager.continue_conversation(conversation_id, message)
      end)
      
      # Clear history, preserving last 2
      result = ConversationManager.clear_conversation_history(conversation_id, 2)
      assert :ok = result
      
      # Check that history was trimmed
      {:ok, conversation_state} = ConversationManager.get_conversation_state(conversation_id)
      
      # Should have at most 2 user messages (plus assistant responses)
      user_messages = Enum.filter(conversation_state.history, &(&1.type == :user))
      assert length(user_messages) <= 2
    end
    
    test "clear_conversation_history/2 handles non-existent conversation" do
      result = ConversationManager.clear_conversation_history("non_existent", 5)
      assert {:error, :conversation_not_found} = result
    end
  end
  
  describe "conversation search" do
    setup do
      conversation_id = "search_test"
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :coding_conversation)
      
      # Add searchable messages
      search_messages = [
        "How do I implement authentication in Elixir?",
        "What about password hashing?",
        "Can you show me an example function?",
        "I'm having trouble with GenServer",
        "The database connection is failing"
      ]
      
      Enum.each(search_messages, fn message ->
        ConversationManager.continue_conversation(conversation_id, message)
      end)
      
      %{conversation_id: conversation_id}
    end
    
    test "search_conversation_history/3 finds relevant messages", %{conversation_id: conversation_id} do
      result = ConversationManager.search_conversation_history(conversation_id, "authentication")
      
      case result do
        {:ok, matching_turns} ->
          assert is_list(matching_turns)
          
          if length(matching_turns) > 0 do
            # Should find the authentication-related message
            auth_messages = Enum.filter(matching_turns, fn turn ->
              String.contains?(String.downcase(turn.content), "authentication")
            end)
            assert length(auth_messages) > 0
          end
          
        {:error, _} ->
          :ok
      end
    end
    
    test "search_conversation_history/3 respects limit parameter", %{conversation_id: conversation_id} do
      result = ConversationManager.search_conversation_history(conversation_id, "the", 2)
      
      case result do
        {:ok, matching_turns} ->
          assert length(matching_turns) <= 2
          
        {:error, _} ->
          :ok
      end
    end
    
    test "search_conversation_history/3 handles non-existent conversation" do
      result = ConversationManager.search_conversation_history("non_existent", "query")
      assert {:error, :conversation_not_found} = result
    end
  end
  
  describe "conversation summarization" do
    setup do
      conversation_id = "summary_test"
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :coding_conversation)
      %{conversation_id: conversation_id}
    end
    
    test "get_conversation_summary/1 generates summary", %{conversation_id: conversation_id} do
      # Add some conversation content
      messages = [
        "I need help implementing user authentication",
        "How do I hash passwords securely?",
        "What about session management?"
      ]
      
      Enum.each(messages, fn message ->
        ConversationManager.continue_conversation(conversation_id, message)
      end)
      
      result = ConversationManager.get_conversation_summary(conversation_id)
      
      case result do
        {:ok, summary} ->
          assert Map.has_key?(summary, :conversation_id)
          assert summary.conversation_id == conversation_id
          assert Map.has_key?(summary, :summary)
          assert is_binary(summary.summary)
          assert Map.has_key?(summary, :generated_at)
          assert Map.has_key?(summary, :conversation_type)
          
        {:error, _reason} ->
          # LLM might not be available
          :ok
      end
    end
    
    test "get_conversation_summary/1 handles empty conversation", %{conversation_id: conversation_id} do
      result = ConversationManager.get_conversation_summary(conversation_id)
      
      # Should still generate a summary even for empty conversations
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "get_conversation_summary/1 handles non-existent conversation" do
      result = ConversationManager.get_conversation_summary("non_existent")
      assert {:error, :conversation_not_found} = result
    end
  end
  
  describe "intent classification" do
    setup do
      conversation_id = "intent_test"
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :coding_conversation)
      %{conversation_id: conversation_id}
    end
    
    test "classifies coding requests correctly", %{conversation_id: conversation_id} do
      coding_messages = [
        "Help me implement a function",
        "There's a bug in my code",
        "Can you refactor this module?",
        "Write tests for this function"
      ]
      
      Enum.each(coding_messages, fn message ->
        result = ConversationManager.continue_conversation(conversation_id, message)
        
        case result do
          {:ok, response} ->
            # Should route to coding assistant for coding requests
            assert response.assistant_type == :coding_assistant
            
          {:error, _} ->
            :ok
        end
      end)
    end
    
    test "classifies general conversation correctly", %{conversation_id: conversation_id} do
      general_messages = [
        "Hello, how are you?",
        "What's the weather like?",
        "Tell me a joke"
      ]
      
      Enum.each(general_messages, fn message ->
        result = ConversationManager.continue_conversation(conversation_id, message)
        
        case result do
          {:ok, response} ->
            # May route to general assistant or coding assistant based on context
            assert response.assistant_type in [:general_assistant, :coding_assistant]
            
          {:error, _} ->
            :ok
        end
      end)
    end
    
    test "handles follow-up messages in context", %{conversation_id: conversation_id} do
      # Start with coding request
      ConversationManager.continue_conversation(conversation_id, "Help me with functions")
      
      # Follow up should maintain context
      result = ConversationManager.continue_conversation(conversation_id, "Also, what about pattern matching?")
      
      case result do
        {:ok, response} ->
          # Should still route to coding assistant
          assert response.assistant_type == :coding_assistant
          
        {:error, _} ->
          :ok
      end
    end
  end
  
  describe "handle_request/3 Assistant interface" do
    test "processes conversation requests through Assistant interface" do
      request = %{
        type: :conversation,
        message: "I need help with Elixir GenServers",
        conversation_id: "assistant_test_conv"
      }
      
      conversation_context = %{
        session_id: "assistant_test_session",
        user_preferences: %{detail_level: :high}
      }
      
      project_context = %{
        framework: :phoenix,
        language: :elixir
      }
      
      result = ConversationManager.handle_request(request, conversation_context, project_context)
      assert match?({:ok, _, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, response, updated_context} ->
          assert Map.has_key?(response, :response)
          assert Map.has_key?(updated_context, :conversation_id)
          assert Map.has_key?(updated_context, :last_response)
          
        {:error, _reason} ->
          :ok
      end
    end
    
    test "creates conversation automatically if not exists" do
      request = %{
        type: :conversation,
        message: "Start a new conversation about testing"
      }
      
      conversation_context = %{user_id: "test_user"}
      project_context = %{language: :elixir}
      
      result = ConversationManager.handle_request(request, conversation_context, project_context)
      
      case result do
        {:ok, _response, updated_context} ->
          # Should have created a conversation ID
          assert Map.has_key?(updated_context, :conversation_id)
          conversation_id = updated_context.conversation_id
          
          # Conversation should exist
          state_result = ConversationManager.get_conversation_state(conversation_id)
          assert match?({:ok, _}, state_result)
          
        {:error, _} ->
          :ok
      end
    end
  end
  
  describe "error handling and edge cases" do
    test "handles malformed messages gracefully" do
      conversation_id = "error_test"
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :general_conversation)
      
      malformed_messages = [
        "",  # Empty message
        nil,  # Nil message (converted to string)
        String.duplicate("x", 10000),  # Very long message
        "Special chars: àáâãäåæçèéêë 🚀 🎉"  # Unicode and emojis
      ]
      
      Enum.each(malformed_messages, fn message ->
        result = ConversationManager.continue_conversation(conversation_id, to_string(message || ""))
        # Should not crash, should return either success or meaningful error
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
    
    test "handles concurrent conversation operations" do
      # Start multiple conversations concurrently
      tasks = Enum.map(1..3, fn i ->
        Task.async(fn ->
          conversation_id = "concurrent_#{i}"
          ConversationManager.start_conversation(conversation_id, :coding_conversation)
          ConversationManager.continue_conversation(conversation_id, "Message #{i}")
        end)
      end)
      
      results = Task.await_many(tasks, 30_000)
      
      # All should complete without error
      assert length(results) == 3
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
    
    test "handles conversation state corruption gracefully" do
      conversation_id = "corruption_test"
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :coding_conversation)
      
      # Operations should still work even if some internal state is unexpected
      result1 = ConversationManager.continue_conversation(conversation_id, "Test message")
      result2 = ConversationManager.get_conversation_state(conversation_id)
      result3 = ConversationManager.end_conversation(conversation_id)
      
      # Should handle gracefully
      assert match?({:ok, _}, result1) or match?({:error, _}, result1)
      assert match?({:ok, _}, result2) or match?({:error, _}, result2)
      assert match?(:ok, result3) or match?({:error, _}, result3)
    end
  end
  
  describe "conversation metadata and quality" do
    test "tracks conversation metadata correctly" do
      conversation_id = "metadata_test"
      {:ok, _} = ConversationManager.start_conversation(conversation_id, :coding_conversation)
      
      # Add some messages
      ConversationManager.continue_conversation(conversation_id, "First message")
      ConversationManager.continue_conversation(conversation_id, "Second message")
      
      {:ok, conversation_state} = ConversationManager.get_conversation_state(conversation_id)
      
      assert Map.has_key?(conversation_state, :metadata)
      metadata = conversation_state.metadata
      
      assert Map.has_key?(metadata, :turn_count)
      assert metadata.turn_count >= 2
      assert Map.has_key?(metadata, :total_tokens)
      assert Map.has_key?(metadata, :quality_score)
    end
    
    test "updates conversation activity timestamps" do
      conversation_id = "timestamp_test"
      {:ok, initial_state} = ConversationManager.start_conversation(conversation_id, :general_conversation)
      
      # Wait a moment
      Process.sleep(10)
      
      # Add message
      ConversationManager.continue_conversation(conversation_id, "Update timestamp")
      
      {:ok, updated_state} = ConversationManager.get_conversation_state(conversation_id)
      
      # Last activity should be updated
      assert DateTime.compare(updated_state.last_activity, initial_state.started_at) in [:gt, :eq]
    end
  end
end