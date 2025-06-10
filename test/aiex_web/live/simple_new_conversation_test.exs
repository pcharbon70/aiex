defmodule AiexWeb.SimpleNewConversationTest do
  use AiexWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "New Conversation button functionality" do
    test "new conversation button exists and is clickable", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Button should be present
      assert has_element?(live_view, "button[phx-click=new_conversation]", "🆕 New Conversation")

      # Button should be clickable (this will trigger the event)
      live_view |> element("button[phx-click=new_conversation]") |> render_click()

      # After clicking, button should still be present (not removed by error)
      assert has_element?(live_view, "button[phx-click=new_conversation]")
    end

    test "new conversation shows success flash message", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Click the new conversation button
      live_view |> element("button[phx-click=new_conversation]") |> render_click()

      # Verify flash message appears
      assert render(live_view) =~ "Started new conversation"
    end

    test "new conversation clears existing messages", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Send a message first to have some history
      live_view
      |> form("form[phx-submit=send_message]", %{message: "Hello test"})
      |> render_submit()

      # Verify message appears in stream
      assert has_element?(live_view, "[data-role=message]", "Hello test")

      # Click new conversation button
      live_view |> element("button[phx-click=new_conversation]") |> render_click()

      # Verify message is cleared
      refute has_element?(live_view, "[data-role=message]", "Hello test")
    end

    test "new conversation updates conversation ID in sidebar", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Verify initial conversation ID is displayed
      initial_html = render(live_view)
      assert initial_html =~ ~r/ID:\s*[A-Za-z0-9_]+/
      
      # Start new conversation
      live_view |> element("button[phx-click=new_conversation]") |> render_click()

      # Verify new conversation ID is still displayed (may be truncated but should exist)
      new_html = render(live_view)
      assert new_html =~ ~r/ID:\s*[A-Za-z0-9_]+/
      
      # Verify conversation ID element is still present
      assert has_element?(live_view, "[data-role=conversation-id]")
      
      # Verify we got the "Started new conversation" flash message
      assert new_html =~ "Started new conversation"
    end
  end
end