# Phoenix LiveView Patterns for Real-time Chat and AI Coding Assistants

## Executive Summary

This comprehensive guide provides state-of-the-art patterns and best practices for building sophisticated real-time web interfaces using Phoenix LiveView (Phoenix 1.7+), specifically tailored for chat applications and AI coding assistants. The research synthesizes modern architectural patterns, component design strategies, and production-ready implementations that translate terminal interface concepts to powerful web applications.

## 1. Modern Phoenix LiveView Architecture

### Core architectural shifts in Phoenix 1.7+

Phoenix 1.7 introduces fundamental changes that improve developer experience and application consistency. The **unified HTML rendering architecture** eliminates the distinction between controller and LiveView templates, using function components everywhere with the `<.component_name />` syntax. Templates are now co-located with their modules, and the deprecated Phoenix.View is replaced with Phoenix.Template, creating a more cohesive development experience.

The **Phoenix.Component system** provides a powerful foundation with the CoreComponents module shipping with pre-built, customizable UI components using TailwindCSS. These components include tables, modals, forms, buttons, and inputs designed for extension and customization.

### LiveView Streams for efficient data handling

**Streams** represent the most significant performance optimization for handling large, dynamic collections:

```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :messages, list_messages())}
end

def handle_info({:new_message, message}, socket) do
  {:noreply, stream_insert(socket, :messages, message, at: -1)}
end
```

Streams eliminate server-side memory overhead by managing data on the client, support efficient DOM updates with minimal re-rendering, and provide built-in virtualization for large datasets. The `limit` option prevents client-side memory bloat, making them ideal for chat message histories.

### State management best practices

Modern LiveView applications should follow clear patterns for state management. Use `handle_params/3` over `mount/3` for URL-dependent state, keeping mount minimal. Choose function components for markup reuse and simple interactions, LiveComponents only when isolated state management is needed, and nested LiveViews for complete isolation with error boundaries.

The **async operations pattern** enables non-blocking data loading:

```elixir
def mount(%{"id" => id}, _session, socket) do
  {:ok,
   socket
   |> assign(:loading, true)
   |> assign_async(:user, fn -> {:ok, %{user: fetch_user!(id)}} end)}
end
```

## 2. Chat Interface Implementation Patterns

### Real-time message rendering with streams

Chat applications benefit significantly from LiveView's streaming capabilities. The pattern combines efficient server-side message handling with client-side DOM management:

```elixir
def mount(%{"room_id" => room_id}, _session, socket) do
  if connected?(socket), do: Chat.Messages.subscribe_to_room(room_id)
  
  {:ok,
   socket
   |> stream(:messages, get_recent_messages(room_id), limit: 50)
   |> assign(room_id: room_id)}
end

def handle_info({:new_message, message}, socket) do
  {:noreply, stream_insert(socket, :messages, message, at: -1)}
end
```

### Auto-scroll functionality with JavaScript hooks

Smooth scrolling behavior requires client-side JavaScript integration through LiveView hooks:

```javascript
let ScrollToBottom = {
  mounted() {
    this.scrollDown();
  },
  
  updated() {
    if (this.wasAtBottom()) {
      this.scrollDown();
    }
  },
  
  wasAtBottom() {
    return this.el.scrollTop + this.el.clientHeight >= this.el.scrollHeight - 10;
  }
};
```

This pattern preserves user scroll position when viewing history while automatically scrolling for new messages when at the bottom.

### Typing indicators with Phoenix Presence

Real-time typing indicators leverage Phoenix Presence for distributed state management:

```elixir
def handle_event("typing", _params, socket) do
  Presence.update(self(), "room:#{socket.assigns.room_id}", 
    socket.assigns.current_user.id, %{typing: true})
  
  Process.send_after(self(), :clear_typing, 3000)
  {:noreply, socket}
end
```

### File upload handling

LiveView's built-in upload component provides comprehensive file handling:

```elixir
def mount(params, session, socket) do
  {:ok,
   socket
   |> allow_upload(:attachments, 
       accept: ~w(.jpg .jpeg .png .gif .pdf),
       max_entries: 5,
       max_file_size: 10_000_000)}
end
```

## 3. AI Coding Assistant UI Patterns

### Code syntax highlighting integration

Integrating syntax highlighting requires careful coordination between server-side rendering and client-side JavaScript libraries. The hook-based approach with Prism.js or Highlight.js provides optimal performance:

```elixir
# LiveView template
<pre phx-hook="Highlight"><code class="language-elixir"><%= @code_content %></code></pre>

# JavaScript hook
Hooks.Highlight = {
  mounted() { Prism.highlightElement(this.el) },
  updated() { Prism.highlightElement(this.el) }
}
```

### Dynamic panel management

Modern coding assistants require flexible layouts with resizable panels. LiveView's JS commands enable smooth transitions:

```elixir
def toggle_panel(js \\ %JS{}) do
  js
  |> JS.toggle(to: "#code-panel", 
               in: "fade-in-scale", 
               out: "fade-out-scale")
end
```

### Streaming AI responses

Handling streaming responses from AI models requires careful state management and efficient rendering:

```elixir
def handle_event("send_prompt", %{"content" => content}, socket) do
  Task.start(fn ->
    OpenAI.stream_completion(content, fn
      {:chunk, chunk} -> send(self(), {:ai_chunk, chunk})
      {:done} -> send(self(), :ai_done)
    end)
  end)
  
  {:noreply, assign(socket, streaming: true, ai_response: "")}
end

def handle_info({:ai_chunk, chunk}, socket) do
  {:noreply, assign(socket, ai_response: socket.assigns.ai_response <> chunk)}
end
```

### Token usage tracking

Real-time token counting provides transparency for AI usage:

```elixir
def handle_info({:token_usage, %{prompt_tokens: p, completion_tokens: c}}, socket) do
  total_tokens = socket.assigns.total_tokens + p + c
  cost = calculate_cost(p, c, socket.assigns.current_model)
  
  {:noreply, 
   socket
   |> assign(:total_tokens, total_tokens)
   |> assign(:session_cost, socket.assigns.session_cost + cost)}
end
```

## 4. Component Architecture and Design

### Reusable component patterns

Phoenix 1.7's component system enables building sophisticated, reusable UI elements. Function components provide the foundation for stateless UI elements:

```elixir
attr :variant, :string, default: "primary"
attr :size, :string, default: "md"
slot :inner_block, required: true

def button(assigns) do
  ~H"""
  <button class={[
    "inline-flex items-center justify-center",
    variant_classes(@variant),
    size_classes(@size)
  ]}>
    <%= render_slot(@inner_block) %>
  </button>
  """
end
```

### Event handling between components

Parent-child communication follows clear patterns. Child components communicate upward via messages:

```elixir
# Child component
def handle_event("item_selected", %{"id" => id}, socket) do
  send(self(), {:item_selected, id})
  {:noreply, socket}
end

# Parent LiveView
def handle_info({:item_selected, id}, socket) do
  {:noreply, assign(socket, :selected_item, get_item(id))}
end
```

### Tailwind CSS integration

LiveView works seamlessly with Tailwind CSS, supporting dynamic class composition and responsive design patterns. The Phoenix-specific Tailwind plugin adds variants for LiveView states:

```javascript
plugin(({addVariant}) => {
  addVariant('phx-click-loading', ['&.phx-click-loading', '.phx-click-loading &'])
  addVariant('phx-submit-loading', ['&.phx-submit-loading', '.phx-submit-loading &'])
})
```

## 5. Performance Optimization Strategies

### Memory management for long conversations

Long-running chat sessions require careful memory management. **Temporary assigns** reset after each render:

```elixir
def mount(_params, _session, socket) do
  {:ok, assign(socket, messages: [], temporary_assigns: [messages: []])}
end
```

**Process hibernation** compresses memory during idle periods, configurable via `:hibernate_after` in the endpoint.

### Efficient re-rendering

LiveView automatically optimizes re-rendering by splitting templates into static and dynamic parts. Best practices include:

- Minimize dynamic content in templates
- Use LiveComponents for isolated re-rendering contexts
- Keep frequently updating content in separate components
- Leverage CSS classes instead of inline styles

### WebSocket optimization

Configure appropriate connection handling:

```elixir
socket "/live", Phoenix.LiveView.Socket,
  websocket: [
    timeout: 45_000,
    compress: true
  ]
```

Implement custom reconnection strategies:

```javascript
let liveSocket = new LiveSocket("/live", Socket, {
  reconnectAfterMs: (tries) => [1000, 3000, 10000][tries - 1] || 30000
})
```

### Debouncing and throttling

Prevent excessive server communication with built-in modifiers:

```html
<!-- Debounce search input -->
<input phx-change="search" phx-debounce="1000" />

<!-- Throttle scroll events -->
<div phx-window-scroll="handle_scroll" phx-throttle="100">
```

## 6. Modern UI Patterns

### Responsive layouts with CSS Grid

CSS Grid provides powerful layout capabilities for LiveView applications:

```css
.app-layout {
  display: grid;
  grid-template-columns: 250px 1fr;
  grid-template-rows: 60px 1fr;
  height: 100vh;
}

@media (max-width: 768px) {
  .app-layout {
    grid-template-columns: 1fr;
  }
}
```

### Keyboard shortcuts

Implement comprehensive keyboard navigation:

```elixir
def handle_event("keydown", %{"key" => "k", "ctrlKey" => true}, socket) do
  {:noreply, assign(socket, :show_command_palette, true)}
end
```

### Dark/light theme support

Implement theme switching with CSS custom properties and LiveView state:

```css
:root {
  --bg-color: #ffffff;
  --text-color: #000000;
}

.dark {
  --bg-color: #1a1a1a;
  --text-color: #ffffff;
}
```

### Accessibility considerations

Build inclusive interfaces with proper ARIA attributes:

```elixir
def modal(assigns) do
  ~H"""
  <div role="dialog" 
       aria-modal="true" 
       aria-labelledby={"#{@id}-title"}>
    <.focus_wrap id={"#{@id}-focus"}>
      <!-- Modal content -->
    </.focus_wrap>
  </div>
  """
end
```

## 7. Backend Integration Patterns

### GenServer for AI processing

Manage AI interactions with supervised GenServers:

```elixir
defmodule MyApp.AI.ChatServer do
  use GenServer

  def process_message(user_id, message) do
    GenServer.call(via_tuple(user_id), {:process_message, message})
  end

  def handle_call({:process_message, message}, _from, state) do
    Task.start(fn ->
      OpenAI.stream_completion(message, fn chunk ->
        Phoenix.PubSub.broadcast(MyApp.PubSub, "chat:#{state.user_id}", {:ai_chunk, chunk})
      end)
    end)
    
    {:reply, :ok, state}
  end
end
```

### Background job processing with Oban

Handle long-running AI tasks asynchronously:

```elixir
defmodule MyApp.Workers.AIProcessingWorker do
  use Oban.Worker, queue: :ai_processing

  def perform(%Oban.Job{args: %{"user_id" => user_id, "message" => message}}) do
    response = MyApp.AI.process_message(message)
    Phoenix.PubSub.broadcast(MyApp.PubSub, "user:#{user_id}", {:job_complete, response})
    :ok
  end
end
```

### Database patterns for chat history

Optimize database schema for chat applications:

```elixir
schema "messages" do
  field :content, :text
  field :role, Ecto.Enum, values: [:user, :assistant, :system]
  field :token_count, :integer
  field :embedding, {:array, :float}  # For vector search
  
  belongs_to :conversation, Conversation
  belongs_to :user, User
  
  timestamps()
end

# Optimized querying
def list_messages(conversation_id, opts \\ []) do
  from(m in Message,
    where: m.conversation_id == ^conversation_id,
    order_by: [desc: m.inserted_at],
    limit: ^Keyword.get(opts, :limit, 50),
    preload: [:user]
  )
  |> Repo.all()
  |> Enum.reverse()
end
```

### Caching strategies

Implement multi-layer caching with ETS and Cachex:

```elixir
defmodule MyApp.Cache.Cachex do
  def get_conversation(id) do
    Cachex.fetch(:my_app_cache, "conversation:#{id}", fn ->
      case MyApp.Chat.get_conversation(id) do
        nil -> {:ignore, nil}
        conversation -> {:commit, conversation, ttl: :timer.hours(1)}
      end
    end)
  end
end
```

## Key Implementation Insights

### Architecture decisions

1. **Use Streams for all message lists** - They provide the best balance of performance and functionality
2. **Implement proper supervision trees** - Ensure AI processes are supervised and can recover from failures
3. **Leverage PubSub extensively** - It's the backbone of real-time features in distributed systems
4. **Cache aggressively but invalidate properly** - Critical for performance at scale

### Performance considerations

1. **Memory management is critical** - Use temporary assigns and process hibernation
2. **Debounce user input** - Prevent excessive server load from rapid updates
3. **Optimize database queries** - Proper indexes and query patterns are essential
4. **Stream large responses** - Don't accumulate entire AI responses in memory

### Security best practices

1. **Validate all inputs** - Use Ecto changesets even for non-database operations
2. **Implement rate limiting** - Especially important for AI endpoints
3. **Use proper authentication hooks** - LiveView's on_mount callbacks provide security boundaries
4. **Sanitize file uploads** - Validate types and scan for malicious content

## Conclusion

Phoenix LiveView provides an exceptional foundation for building sophisticated real-time chat and AI coding assistant interfaces. By leveraging streams for efficient data handling, implementing proper component architecture, optimizing performance through strategic state management, and following security best practices, developers can create powerful web applications that rival desktop experiences while maintaining the simplicity of server-rendered HTML.

The patterns presented in this guide represent production-tested approaches that scale from prototype to enterprise deployment, providing a clear path from terminal-based interfaces to modern, responsive web applications.
