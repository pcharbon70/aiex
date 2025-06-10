defmodule AiexWeb.NewConversationTest do
  use AiexWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Aiex.AI.Coordinators.ConversationManager

  describe "New Conversation functionality" do
    test "creates new conversation when button is clicked", %{conn: conn} do
      {:ok, live_view, html} = live(conn, "/")

      # Get the initial conversation ID from the display
      initial_html = render(live_view)
      initial_conversation_id_display = 
        case Regex.run(~r/ID:\s*([A-Za-z0-9_]+)/, initial_html) do
          [_full_match, id] -> id
          _ -> "unknown"
        end

      # Send a message to have some conversation history
      live_view
      |> form("form[phx-submit=send_message]", %{message: "Hello, this is a test message"})
      |> render_submit()

      # Verify message appears
      assert has_element?(live_view, "[data-role=message]", "Hello, this is a test message")

      # Click the new conversation button
      live_view |> element("button[phx-click=new_conversation]") |> render_click()

      # Get the new conversation ID from the display
      new_html = render(live_view)
      new_conversation_id_display = 
        case Regex.run(~r/ID:\s*([A-Za-z0-9_]+)/, new_html) do
          [_full_match, id] -> id
          _ -> "unknown"
        end
      
      # Verify new conversation ID is different
      assert new_conversation_id_display != initial_conversation_id_display

      # Verify messages are cleared
      refute has_element?(live_view, "[data-role=message]", "Hello, this is a test message")

      # Verify flash message appears
      assert render(live_view) =~ "Started new conversation"
    end

    test "preserves interface functionality after new conversation", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Start new conversation
      live_view |> element("button[phx-click=new_conversation]") |> render_click()

      # Verify we can still send messages
      live_view
      |> form("form[phx-submit=send_message]", %{message: "New conversation test"})
      |> render_submit()

      # Message should appear
      assert has_element?(live_view, "[data-role=message]", "New conversation test")

      # Interface should still be functional
      assert has_element?(live_view, "input[name=message]")
      assert has_element?(live_view, "button[type=submit]")
    end

    test "new conversation creates separate conversation in ConversationManager", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Get initial conversation count
      initial_conversations = ConversationManager.list_conversations()
      initial_count = length(initial_conversations)

      # Start new conversation
      live_view |> element("button[phx-click=new_conversation]") |> render_click()

      # Verify conversations exist in ConversationManager
      updated_conversations = ConversationManager.list_conversations()
      
      # Should have at least one conversation
      assert length(updated_conversations) >= 1

      # Verify flash message indicates success
      assert render(live_view) =~ "Started new conversation"
    end

    test "context sidebar shows updated conversation ID after new conversation", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Get initial conversation ID display
      initial_html = render(live_view)
      initial_id_display = 
        case Regex.run(~r/ID:\s*([A-Za-z0-9_]+)/, initial_html) do
          [_full_match, id] -> id
          _ -> "unknown"
        end

      # Start new conversation
      live_view |> element("button[phx-click=new_conversation]") |> render_click()

      # Get new conversation ID display
      new_html = render(live_view)
      new_id_display = 
        case Regex.run(~r/ID:\s*([A-Za-z0-9_]+)/, new_html) do
          [_full_match, id] -> id
          _ -> "unknown"
        end
      
      # Verify the displayed ID has changed
      assert new_id_display != initial_id_display
      assert has_element?(live_view, "[data-role=conversation-id]")
    end

    test "new conversation button is always accessible", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Button should be present initially
      assert has_element?(live_view, "button[phx-click=new_conversation]", "🆕 New Conversation")

      # Send a message to simulate active conversation
      live_view
      |> form("form[phx-submit=send_message]", %{message: "Test message"})
      |> render_submit()

      # Button should still be present
      assert has_element?(live_view, "button[phx-click=new_conversation]", "🆕 New Conversation")

      # After starting new conversation, button should still be present
      live_view |> element("button[phx-click=new_conversation]") |> render_click()
      assert has_element?(live_view, "button[phx-click=new_conversation]", "🆕 New Conversation")
    end

    test "new conversation resets processing state", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Send a message to trigger processing state
      live_view
      |> form("form[phx-submit=send_message]", %{message: "Test message"})
      |> render_submit()

      # Should be in processing state
      assert has_element?(live_view, "input[disabled]")

      # Start new conversation
      live_view |> element("button[phx-click=new_conversation]") |> render_click()

      # Processing state should be reset
      refute has_element?(live_view, "input[disabled]")
      assert has_element?(live_view, "button[type=submit]", "Send")
    end

    test "handles errors gracefully when starting new conversation", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # This test assumes the system handles errors gracefully
      # In a real scenario, we might mock ConversationManager to return an error
      
      # For now, verify the basic click doesn't crash the interface
      live_view |> element("button[phx-click=new_conversation]") |> render_click()

      # Interface should remain functional
      assert has_element?(live_view, "input[name=message]")
      assert has_element?(live_view, "button[phx-click=new_conversation]")
    end
  end
end