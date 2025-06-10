defmodule AiexWeb.WebTestHelpers do
  @moduledoc """
  Helper functions for testing the web interface.
  """

  import Phoenix.LiveViewTest
  import ExUnit.Assertions

  @doc """
  Sends a chat message and waits for it to appear.
  """
  def send_chat_message(live_view, message) do
    live_view
    |> form("form[phx-submit=send_message]", %{message: message})
    |> render_submit()

    # Verify message appears in chat
    assert has_element?(live_view, "[data-role=message]", message)
    live_view
  end

  @doc """
  Simulates an AI response message.
  """
  def simulate_ai_response(live_view, content, metadata \\ %{}) do
    response = %{
      role: :assistant,
      content: content,
      timestamp: DateTime.utc_now(),
      metadata: Map.merge(%{tokens: 25, duration: 150, model: "test-model"}, metadata)
    }

    send(live_view.pid, {:ai_response, response})
    
    # Wait for response to appear
    assert has_element?(live_view, "[data-role=message]", content)
    live_view
  end

  @doc """
  Simulates streaming AI response chunks.
  """
  def simulate_streaming_response(live_view, chunks) when is_list(chunks) do
    for chunk <- chunks do
      send(live_view.pid, {:ai_chunk, chunk})
    end

    # Verify full message appears
    full_message = Enum.join(chunks, "")
    assert has_element?(live_view, "[data-role=message]", full_message)
    live_view
  end

  @doc """
  Toggles the context sidebar.
  """
  def toggle_context_sidebar(live_view) do
    live_view |> element("button[phx-click=toggle_context]") |> render_click()
  end

  @doc """
  Clears the chat.
  """
  def clear_chat(live_view) do
    live_view |> element("button[phx-click=clear_chat]") |> render_click()
  end

  @doc """
  Starts a new conversation.
  """
  def start_new_conversation(live_view) do
    live_view |> element("button[phx-click=new_conversation]") |> render_click()
  end

  @doc """
  Asserts that the typing indicator is visible.
  """
  def assert_typing_indicator_visible(live_view) do
    assert has_element?(live_view, "[data-role=typing-indicator]")
  end

  @doc """
  Asserts that the typing indicator is not visible.
  """
  def assert_typing_indicator_hidden(live_view) do
    refute has_element?(live_view, "[data-role=typing-indicator]")
  end

  @doc """
  Asserts that the interface is in processing state.
  """
  def assert_processing_state(live_view) do
    assert has_element?(live_view, "input[disabled]")
    assert has_element?(live_view, "button[disabled]", "Sending...")
  end

  @doc """
  Asserts that the interface is ready for input.
  """
  def assert_ready_state(live_view) do
    refute has_element?(live_view, "input[disabled]")
    assert has_element?(live_view, "button[type=submit]", "Send")
  end

  @doc """
  Asserts that a message with the given role and content exists.
  """
  def assert_message_exists(live_view, role, content) do
    selector = "[data-role=message][data-message-role=#{role}]"
    assert has_element?(live_view, selector, content)
  end

  @doc """
  Asserts the conversation ID is displayed correctly.
  """
  def assert_conversation_id_displayed(live_view) do
    conversation_id = live_view.assigns.conversation_id
    short_id = String.slice(conversation_id || "", 0..7)
    assert has_element?(live_view, "[data-role=conversation-id]", short_id)
  end

  @doc """
  Simulates an error condition.
  """
  def simulate_error(live_view, error_type) do
    send(live_view.pid, {:error, error_type})
    live_view
  end

  @doc """
  Creates a test message structure.
  """
  def create_test_message(role, content, metadata \\ %{}) do
    %{
      role: role,
      content: content,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end

  @doc """
  Waits for an element to appear with timeout.
  """
  def wait_for_element(live_view, selector, text \\ nil, timeout \\ 1000) do
    start_time = System.monotonic_time(:millisecond)
    
    wait_for_element_loop(live_view, selector, text, start_time, timeout)
  end

  defp wait_for_element_loop(live_view, selector, text, start_time, timeout) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time - start_time > timeout do
      if text do
        flunk("Element '#{selector}' with text '#{text}' did not appear within #{timeout}ms")
      else
        flunk("Element '#{selector}' did not appear within #{timeout}ms")
      end
    else
      if text do
        if has_element?(live_view, selector, text) do
          :ok
        else
          Process.sleep(10)
          wait_for_element_loop(live_view, selector, text, start_time, timeout)
        end
      else
        if has_element?(live_view, selector) do
          :ok
        else
          Process.sleep(10)
          wait_for_element_loop(live_view, selector, text, start_time, timeout)
        end
      end
    end
  end

  @doc """
  Sets up a mock InterfaceGateway for testing.
  """
  def setup_mock_interface_gateway do
    # Implementation depends on your mocking strategy
    :ok
  end

  @doc """
  Sets up a mock ConversationManager for testing.
  """
  def setup_mock_conversation_manager do
    # Implementation depends on your mocking strategy
    :ok
  end

  @doc """
  Verifies that the web interface integrates correctly with backend services.
  """
  def verify_backend_integration(live_view) do
    # Verify InterfaceGateway registration
    interfaces = Aiex.InterfaceGateway.list_interfaces()
    assert Enum.any?(interfaces, fn {_id, config} -> config.type == :live_view end)

    # Verify ConversationManager has conversations
    conversations = Aiex.AI.Coordinators.ConversationManager.list_conversations()
    conversation_id = live_view.assigns.conversation_id
    assert Enum.any?(conversations, fn {id, _state} -> id == conversation_id end)

    :ok
  end

  @doc """
  Creates a complete conversation flow for testing.
  """
  def complete_conversation_flow(live_view) do
    # 1. Send user message
    user_message = "Can you help me with Elixir?"
    send_chat_message(live_view, user_message)

    # 2. Simulate AI response
    ai_response = "I'd be happy to help you with Elixir! What specific topic would you like to explore?"
    simulate_ai_response(live_view, ai_response)

    # 3. Send follow-up
    follow_up = "How do GenServers work?"
    send_chat_message(live_view, follow_up)

    # 4. Simulate streaming response
    chunks = ["GenServers are ", "stateful processes ", "in Elixir that ", "handle concurrent operations."]
    simulate_streaming_response(live_view, chunks)

    live_view
  end
end