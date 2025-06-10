defmodule AiexWeb.WelcomeMessageTest do
  use AiexWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "Welcome message" do
    test "shows welcome message when no messages are present", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Should show welcome message when no messages
      assert has_element?(live_view, "h3", "Welcome to AI Chat Assistant")
      assert has_element?(live_view, "p", "Ask me anything about your code")
      assert render(live_view) =~ "🤖"
    end

    test "welcome message disappears after sending a message", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Initially should show welcome message
      assert has_element?(live_view, "h3", "Welcome to AI Chat Assistant")

      # Send a message
      live_view
      |> form("form[phx-submit=send_message]", %{message: "Hello"})
      |> render_submit()

      # Welcome message should be gone (message sent, so no longer empty)
      # Note: The welcome message checks for empty streams, and we've added a message
      refute has_element?(live_view, "h3", "Welcome to AI Chat Assistant")
    end

    test "input area is always visible and accessible", %{conn: conn} do
      {:ok, live_view, _html} = live(conn, "/")

      # Input should be visible
      assert has_element?(live_view, "input[name=message]")
      assert has_element?(live_view, "button[type=submit]", "Send")
      
      # Input should be enabled (not disabled initially)
      refute has_element?(live_view, "input[disabled]")
    end
  end
end