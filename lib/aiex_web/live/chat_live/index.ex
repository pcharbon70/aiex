defmodule AiexWeb.ChatLive.Index do
  use AiexWeb, :live_view

  alias Aiex.InterfaceGateway
  alias Aiex.AI.Coordinators.ConversationManager
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    # Register with InterfaceGateway
    interface_config = %{
      type: :live_view,
      session_id: "liveview_#{:erlang.unique_integer([:positive])}",
      user_id: get_user_id(socket),
      capabilities: [:text_input, :text_output, :real_time_updates, :file_upload],
      settings: %{
        theme: "light",
        syntax_highlighting: true,
        auto_scroll: true
      }
    }

    case InterfaceGateway.register_interface(__MODULE__, interface_config) do
      {:ok, interface_id} ->
        # Subscribe to real-time updates
        if connected?(socket) do
          PubSub.subscribe(Aiex.PubSub, "interface:#{interface_id}")
          PubSub.subscribe(Aiex.PubSub, "ai_updates")
        end

        # Start a new conversation
        {:ok, conversation_state} = ConversationManager.start_conversation(
          interface_id,
          :coding_conversation,
          %{interface: :live_view}
        )

        {:ok,
         socket
         |> assign(:interface_id, interface_id)
         |> assign(:conversation_id, conversation_state.conversation_id)
         |> assign(:conversation_state, conversation_state)
         |> assign(:messages, [])
         |> assign(:current_message, "")
         |> assign(:processing, false)
         |> assign(:show_context, true)
         |> assign(:project_context, %{})
         |> assign(:typing_indicator, false)
         |> stream(:messages, [])}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Failed to initialize chat: #{reason}")
         |> assign(:interface_id, nil)
         |> assign(:messages, [])}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "AI Chat")
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) != "" and !socket.assigns.processing do
      # Add user message to chat
      user_message = %{
        id: System.unique_integer([:positive]),
        role: :user,
        content: message,
        timestamp: DateTime.utc_now()
      }

      # Send to conversation manager
      Task.start(fn ->
        case ConversationManager.continue_conversation(
               socket.assigns.conversation_id,
               message
             ) do
          {:ok, response} ->
            send_update(self(), {:ai_response, response})

          {:error, reason} ->
            send_update(self(), {:ai_error, reason})
        end
      end)

      {:noreply,
       socket
       |> stream_insert(:messages, user_message)
       |> assign(:current_message, "")
       |> assign(:processing, true)
       |> assign(:typing_indicator, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_message", %{"value" => value}, socket) do
    {:noreply, assign(socket, :current_message, value)}
  end

  @impl true
  def handle_event("toggle_context", _params, socket) do
    {:noreply, assign(socket, :show_context, !socket.assigns.show_context)}
  end

  @impl true
  def handle_event("clear_chat", _params, socket) do
    # Clear conversation history
    ConversationManager.clear_conversation_history(socket.assigns.conversation_id)
    
    {:noreply,
     socket
     |> assign(:messages, [])
     |> stream(:messages, [], reset: true)
     |> put_flash(:info, "Chat cleared")}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    # End current conversation
    ConversationManager.end_conversation(socket.assigns.conversation_id)
    
    # Start new conversation
    {:ok, conversation_state} = ConversationManager.start_conversation(
      socket.assigns.interface_id,
      :coding_conversation,
      %{interface: :live_view}
    )

    {:noreply,
     socket
     |> assign(:conversation_id, conversation_state.conversation_id)
     |> assign(:conversation_state, conversation_state)
     |> assign(:messages, [])
     |> assign(:current_message, "")
     |> assign(:processing, false)
     |> assign(:typing_indicator, false)
     |> stream(:messages, [], reset: true)
     |> put_flash(:info, "Started new conversation")}
  end

  @impl true
  def handle_info({:ai_response, response}, socket) do
    ai_message = %{
      id: System.unique_integer([:positive]),
      role: :assistant,
      content: response.response,
      timestamp: DateTime.utc_now(),
      metadata: %{
        model: response[:model],
        tokens: response[:tokens_used],
        duration: response[:response_time]
      }
    }

    {:noreply,
     socket
     |> stream_insert(:messages, ai_message)
     |> assign(:processing, false)
     |> assign(:typing_indicator, false)}
  end

  @impl true
  def handle_info({:ai_error, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "AI Error: #{reason}")
     |> assign(:processing, false)
     |> assign(:typing_indicator, false)}
  end

  @impl true
  def handle_info({:pubsub, :ai_updates, update}, socket) do
    # Handle real-time AI updates (streaming responses, etc.)
    case update do
      {:streaming_chunk, chunk} ->
        # Update the last AI message with streaming content
        {:noreply, update_last_ai_message(socket, chunk)}

      {:context_update, context} ->
        {:noreply, assign(socket, :project_context, context)}

      _ ->
        {:noreply, socket}
    end
  end

  defp update_last_ai_message(socket, chunk) do
    # Implementation for updating streaming messages
    socket
  end

  defp get_user_id(_socket) do
    # Get user ID from session or generate anonymous ID
    "anonymous_#{:erlang.unique_integer([:positive])}"
  end

  # Helper function for rendering message content
  def render_message_content(content) do
    Phoenix.HTML.raw(format_message_content(content))
  end

  defp format_message_content(content) do
    content
    |> String.replace(~r/```(\w+)?\n(.*?)\n```/s, "<pre class=\"bg-gray-100 dark:bg-gray-800 p-3 rounded-md overflow-x-auto\"><code>\\2</code></pre>")
    |> String.replace(~r/`([^`]+)`/, "<code class=\"bg-gray-100 dark:bg-gray-800 px-1 rounded\">\\1</code>")
    |> String.replace(~r/\*\*([^*]+)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*([^*]+)\*/, "<em>\\1</em>")
    |> String.replace("\n", "<br>")
  end
end