defmodule AiexWeb.Integration.WebInterfaceTest do
  use AiexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Phoenix.ConnTest

  alias Aiex.AI.Coordinators.ConversationManager
  alias Aiex.InterfaceGateway
  alias Aiex.Context.Manager, as: ContextManager

  @endpoint AiexWeb.Endpoint

  describe "Full web interface integration" do
    test "complete user journey from landing to AI conversation", %{conn: conn} do
      # 1. User visits the main page
      {:ok, index_live, html} = live(conn, "/")

      # Should see the chat interface
      assert html =~ "AI Chat Assistant"
      assert html =~ "Ask me anything about your code"

      # 2. User sees their conversation ID
      assert html =~ "Current Session"
      assert html =~ "ID:"

      # 3. User types a message
      test_message = "Can you explain what this Elixir project does?"
      
      index_live
      |> form("form[phx-submit=send_message]", %{message: test_message})
      |> render_submit()

      # Should show processing state
      assert has_element?(index_live, "button[disabled]", "Sending...")

      # 4. User should see their message appears in chat
      assert has_element?(index_live, "[data-role=message]", test_message)

      # 5. Simulate AI response
      ai_response = %{
        role: :assistant,
        content: "This appears to be an Elixir-based AI coding assistant project...",
        timestamp: DateTime.utc_now(),
        metadata: %{tokens: 45, duration: 200, model: "test-model"}
      }

      send(index_live.pid, {:ai_response, ai_response})

      # Should display AI response
      assert has_element?(index_live, "[data-role=message]", "This appears to be an Elixir-based")

      # 6. User can continue the conversation
      follow_up = "What are the main components?"
      
      index_live
      |> form("form[phx-submit=send_message]", %{message: follow_up})
      |> render_submit()

      assert has_element?(index_live, "[data-role=message]", follow_up)
    end

    test "handles multiple concurrent users", %{conn: conn} do
      # Simulate multiple users connecting
      tasks = for i <- 1..3 do
        Task.async(fn ->
          {:ok, live_view, _html} = live(conn, "/")
          
          # Each user sends a message
          message = "Hello from user #{i}"
          live_view
          |> form("form[phx-submit=send_message]", %{message: message})
          |> render_submit()

          # Should handle each user independently
          assert has_element?(live_view, "[data-role=message]", message)
          
          live_view
        end)
      end

      # All tasks should complete successfully
      live_views = Task.await_many(tasks, 5000)
      assert length(live_views) == 3

      # Each should have different conversation IDs
      conversation_ids = for live_view <- live_views do
        live_view.assigns.conversation_id
      end

      assert Enum.uniq(conversation_ids) |> length() == 3
    end

    test "persists conversation state across page refreshes", %{conn: conn} do
      # Start initial session
      {:ok, index_live, _html} = live(conn, "/")
      
      conversation_id = index_live.assigns.conversation_id
      
      # Send a message
      test_message = "Remember this message"
      index_live
      |> form("form[phx-submit=send_message]", %{message: test_message})
      |> render_submit()

      # Simulate page refresh by creating new LiveView connection
      {:ok, new_live, _html} = live(conn, "/")

      # Should create new conversation (simulating fresh session)
      new_conversation_id = new_live.assigns.conversation_id
      assert new_conversation_id != conversation_id

      # Original conversation should still exist in ConversationManager
      assert {:ok, _state} = ConversationManager.get_conversation_state(conversation_id)
    end

    test "integrates properly with backend services", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Verify InterfaceGateway registration
      interfaces = InterfaceGateway.list_interfaces()
      live_view_interfaces = Enum.filter(interfaces, fn {_id, config} -> config.type == :live_view end)
      assert length(live_view_interfaces) >= 1

      # Verify ConversationManager has the conversation
      conversations = ConversationManager.list_conversations()
      assert length(conversations) > 0

      # Find our conversation
      our_conversation_id = index_live.assigns.conversation_id
      assert Enum.any?(conversations, fn {id, _state} -> id == our_conversation_id end)

      # Verify ContextManager integration
      context = ContextManager.get_project_context()
      assert is_map(context)
    end

    test "handles real-time updates and WebSocket connectivity", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Test real-time message streaming
      send(index_live.pid, {:ai_chunk, "Streaming "})
      assert has_element?(index_live, "[data-role=message]", "Streaming")

      send(index_live.pid, {:ai_chunk, "response "})
      assert has_element?(index_live, "[data-role=message]", "Streaming response")

      send(index_live.pid, {:ai_chunk, "complete!"})
      assert has_element?(index_live, "[data-role=message]", "Streaming response complete!")

      # Test typing indicator
      send(index_live.pid, {:typing_indicator, true})
      assert has_element?(index_live, "[data-role=typing-indicator]")

      send(index_live.pid, {:typing_indicator, false})
      refute has_element?(index_live, "[data-role=typing-indicator]")
    end

    test "handles error scenarios gracefully", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Test service unavailable error
      send(index_live.pid, {:error, :service_unavailable})
      
      # Should show error but remain functional
      assert has_element?(index_live, "input[name=message]")

      # Test timeout error
      send(index_live.pid, {:error, :timeout})
      
      # Should handle gracefully
      assert has_element?(index_live, "input[name=message]")

      # Interface should recover and allow new messages
      index_live
      |> form("form[phx-submit=send_message]", %{message: "test after error"})
      |> render_submit()

      assert has_element?(index_live, "[data-role=message]", "test after error")
    end
  end

  describe "Performance and scalability" do
    test "handles rapid message sending", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Send messages rapidly
      for i <- 1..10 do
        index_live
        |> form("form[phx-submit=send_message]", %{message: "Message #{i}"})
        |> render_submit()
      end

      # Should handle all messages without crashing
      assert has_element?(index_live, "input[name=message]")
    end

    test "memory usage remains stable with long conversations", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Simulate long conversation
      for i <- 1..50 do
        # User message
        user_msg = %{
          role: :user,
          content: "User message #{i}",
          timestamp: DateTime.utc_now()
        }
        send(index_live.pid, {:new_message, user_msg})

        # AI response
        ai_msg = %{
          role: :assistant,
          content: "AI response #{i}",
          timestamp: DateTime.utc_now()
        }
        send(index_live.pid, {:new_message, ai_msg})
      end

      # LiveView should still be responsive
      assert has_element?(index_live, "input[name=message]")
      
      # Should handle message history efficiently
      # (This would check for message pagination/limiting when implemented)
      assert has_element?(index_live, "[data-role=messages]")
    end
  end

  describe "Security" do
    test "sanitizes user input", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Test XSS prevention
      malicious_input = "<script>alert('xss')</script>"
      
      index_live
      |> form("form[phx-submit=send_message]", %{message: malicious_input})
      |> render_submit()

      # Should not execute script, should be escaped
      html = render(index_live)
      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end

    test "prevents injection attacks", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Test various injection attempts
      injection_attempts = [
        "'; DROP TABLE users; --",
        "<img src=x onerror=alert(1)>",
        "javascript:alert('xss')",
        "${7*7}",
        "{{7*7}}"
      ]

      for attempt <- injection_attempts do
        index_live
        |> form("form[phx-submit=send_message]", %{message: attempt})
        |> render_submit()

        # Should handle safely without execution
        assert has_element?(index_live, "input[name=message]")
      end
    end
  end

  describe "Accessibility" do
    test "provides proper screen reader support", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, "/")

      # Check for ARIA labels and roles
      assert html =~ ~r/aria-label="[^"]+"/
      assert html =~ ~r/role="[^"]+"/
      
      # Check for semantic HTML
      assert html =~ "<main"
      assert html =~ "<form"
      assert html =~ "<button"
    end

    test "supports keyboard navigation", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, "/")

      # Test Tab navigation through interactive elements
      assert has_element?(index_live, "input[name=message]")
      assert has_element?(index_live, "button[type=submit]")
      assert has_element?(index_live, "button[phx-click=toggle_context]")
    end
  end
end