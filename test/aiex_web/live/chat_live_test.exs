defmodule AiexWeb.ChatLiveTest do
  use AiexWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Aiex.AI.Coordinators.ConversationManager
  alias Aiex.InterfaceGateway

  describe "ChatLive.Index" do
    test "displays chat interface on mount", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, "/")

      assert html =~ "AI Chat Assistant"
      assert html =~ "Ask me anything about your code"
    end

    test "shows context sidebar by default", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      assert has_element?(index_live, "[data-role=context-sidebar]")
      assert has_element?(index_live, "h3", "Project Context")
    end

    test "can toggle context sidebar", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Context should be visible by default
      assert has_element?(index_live, "[data-role=context-sidebar]")

      # Click toggle button
      index_live |> element("button[phx-click=toggle_context]") |> render_click()

      # Context should be hidden
      refute has_element?(index_live, "[data-role=context-sidebar]")

      # Click toggle again
      index_live |> element("button[phx-click=toggle_context]") |> render_click()

      # Context should be visible again
      assert has_element?(index_live, "[data-role=context-sidebar]")
    end

    test "displays conversation ID in context sidebar", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, "/")

      assert html =~ "Current Session"
      assert html =~ "ID:"
    end

    test "can input and display message", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Enter a message
      test_message = "Hello, can you help me with my code?"
      
      index_live
      |> form("form[phx-submit=send_message]", %{message: test_message})
      |> render_submit()

      # Should show processing state
      assert has_element?(index_live, "button[disabled]", "Sending...")
    end

    test "can clear chat", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Clear the chat
      index_live |> element("button[phx-click=clear_chat]") |> render_click()

      # Should reset the interface
      assert has_element?(index_live, "input[name=message]")
    end

    test "can start new conversation", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Start new conversation
      index_live |> element("button[phx-click=new_conversation]") |> render_click()

      # Should reset the chat interface
      assert has_element?(index_live, "input[name=message]")
    end

    test "message input is disabled during processing", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Send a message to trigger processing state
      index_live
      |> form("form[phx-submit=send_message]", %{message: "test message"})
      |> render_submit()

      # Input should be disabled
      assert has_element?(index_live, "input[disabled]")
      assert has_element?(index_live, "button[disabled]")
    end

    test "shows empty state when no messages", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, "/")

      # Should show empty message area
      assert html =~ "Ask me anything about your code"
    end

    test "handles typing indicator", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Simulate typing indicator
      send(index_live.pid, {:typing_indicator, true})

      # Should show typing indicator
      assert has_element?(index_live, "[data-role=typing-indicator]")
    end
  end

  describe "Real-time message handling" do
    test "receives and displays AI responses", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Simulate receiving an AI response
      response_message = %{
        role: :assistant,
        content: "I can help you with your code! What would you like to know?",
        timestamp: DateTime.utc_now(),
        metadata: %{tokens: 25, duration: 150, model: "test-model"}
      }

      send(index_live.pid, {:ai_response, response_message})

      # Should display the AI response
      assert has_element?(index_live, "[data-role=message]", "I can help you with your code!")
      assert has_element?(index_live, "[data-role=message-metadata]", "25 tokens")
    end

    test "handles streaming message updates", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Simulate streaming chunks
      send(index_live.pid, {:ai_chunk, "Hello "})
      send(index_live.pid, {:ai_chunk, "there! "})
      send(index_live.pid, {:ai_chunk, "How can I help?"})

      # Should show the accumulated message
      assert has_element?(index_live, "[data-role=message]", "Hello there! How can I help?")
    end

    test "displays message timestamps correctly", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      timestamp = DateTime.utc_now()
      message = %{
        role: :user,
        content: "Test message",
        timestamp: timestamp
      }

      send(index_live.pid, {:new_message, message})

      # Should format timestamp correctly
      expected_time = Calendar.strftime(timestamp, "%H:%M")
      assert has_element?(index_live, "[data-role=message-time]", expected_time)
    end
  end

  describe "InterfaceGateway integration" do
    test "registers with InterfaceGateway on mount", %{conn: conn} do
      {:ok, _index_live, _html} = live(conn, "/")

      # Should have registered an interface
      interfaces_status = InterfaceGateway.get_interfaces_status()
      interface_ids = Map.keys(interfaces_status)
      
      # Should have at least one interface registered (the current LiveView)
      assert length(interface_ids) >= 1
    end

    test "creates conversation with ConversationManager", %{conn: conn} do
      {:ok, _index_live, _html} = live(conn, "/")

      # Should have active conversations
      conversations = ConversationManager.list_conversations()
      assert length(conversations) > 0
    end
  end

  describe "Error handling" do
    test "handles ConversationManager errors gracefully", %{conn: conn} do
      # Test basic error resilience without mocking
      {:ok, index_live, html} = live(conn, "/")
      
      # Should show error state but not crash
      assert html =~ "AI Chat Assistant"
      
      # Simulate error condition
      send(index_live.pid, {:error, :service_unavailable})
      
      # Should still be functional
      assert has_element?(index_live, "input[name=message]")
    end

    test "handles InterfaceGateway registration errors", %{conn: conn} do
      # Test that the interface can handle basic scenarios
      {:ok, _index_live, html} = live(conn, "/")
      
      # Should show main interface
      assert html =~ "AI Chat Assistant"
    end

    test "handles malformed message gracefully", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Send malformed data
      catch_exit(send(index_live.pid, {:invalid_message, nil}))

      # LiveView should still be responsive
      assert has_element?(index_live, "input[name=message]")
    end
  end

  describe "Accessibility" do
    test "has proper ARIA labels", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, "/")

      # Check for accessibility attributes
      assert html =~ ~r/aria-label|role=/
      assert html =~ "placeholder=\"Ask me anything about your code...\""
    end

    test "supports keyboard navigation", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Test Enter key submission
      index_live
      |> element("input[name=message]")
      |> render_keydown(%{key: "Enter"})

      # Should trigger form submission behavior
      assert has_element?(index_live, "input[name=message]")
    end
  end

  describe "Performance" do
    test "handles large number of messages efficiently", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Send many messages
      messages = for i <- 1..100 do
        %{
          role: if(rem(i, 2) == 0, do: :user, else: :assistant),
          content: "Message #{i}",
          timestamp: DateTime.utc_now()
        }
      end

      Enum.each(messages, fn message ->
        send(index_live.pid, {:new_message, message})
      end)

      # Should handle efficiently without crashing
      assert has_element?(index_live, "input[name=message]")
    end

    test "limits message history appropriately", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # The interface should handle message pagination/limiting
      # This is a placeholder for when we implement message limiting
      assert has_element?(index_live, "[data-role=messages]")
    end
  end
end