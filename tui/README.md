# Aiex Go TUI

A sophisticated Terminal User Interface (TUI) built with Bubble Tea that communicates with the Elixir OTP distributed AI coding assistant.

## Architecture

This TUI follows the Bubble Tea framework's Elm-inspired Model-Update-View pattern with the following key components:

### Core Components

- **AIAssistantModel**: Main application model with hierarchical component composition
- **JSON-RPC Client**: Bidirectional communication with Elixir backend over WebSocket
- **Event Stream Manager**: Handles high-frequency events with adaptive rate limiting
- **State Manager**: Centralized state management with optimistic updates and rollback
- **Multi-Panel Layout**: Claude-inspired interface with file explorer, editor, and chat

### Project Structure

```
tui/
├── cmd/
│   └── main.go                 # Application entry point
├── internal/
│   ├── ui/
│   │   ├── app.go             # Main application model
│   │   ├── components.go      # UI components (panels)
│   │   └── render.go          # Rendering logic
│   ├── rpc/
│   │   ├── client.go          # JSON-RPC client
│   │   └── websocket.go       # WebSocket transport
│   └── state/
│       └── manager.go         # State management
└── pkg/
    └── types/
        └── messages.go        # Message type definitions
```

## Features

### Current Implementation (Phase 5.5.1)

- ✅ Go module initialization with Bubble Tea dependencies
- ✅ Main AIAssistantModel struct with hierarchical component composition
- ✅ JSON-RPC 2.0 client with WebSocket transport
- ✅ Bidirectional communication infrastructure
- ✅ Multi-panel layout system (file explorer, editor, chat, context)
- ✅ Event-driven architecture with state management
- ✅ Circuit breaker and reconnection logic
- ✅ Centralized state management with optimistic updates

### Planned Features

- [ ] Syntax highlighting with Chroma library
- [ ] Real-time collaborative editing
- [ ] File system integration
- [ ] Chat interface with streaming responses
- [ ] Performance optimizations (virtual scrolling, render caching)
- [ ] Context awareness and quick actions

## Dependencies

```go
require (
    github.com/charmbracelet/bubbletea v0.25.0
    github.com/charmbracelet/bubbles v0.18.0
    github.com/charmbracelet/lipgloss v0.9.1
    github.com/gorilla/websocket v1.5.1
    github.com/creachadair/jrpc2 v1.1.2
    github.com/alecthomas/chroma/v2 v2.12.0
)
```

## Usage

Once Go is installed, you can run the TUI with:

```bash
cd tui
go mod tidy
go run cmd/main.go
```

## Communication Protocol

The TUI communicates with the Elixir backend using JSON-RPC 2.0 over WebSocket connections. Key message types include:

- **AI Responses**: Streaming and complete AI assistant responses
- **Code Suggestions**: Real-time code completion and refactoring suggestions
- **State Updates**: Project context and file system changes
- **File Operations**: Secure file operations through the Elixir sandbox

## Design Patterns

### Event-Driven Architecture
- Uses Bubble Tea's command pattern for asynchronous operations
- Implements event buffering and adaptive rate limiting
- Supports backpressure handling for UI responsiveness

### State Management
- Optimistic updates with rollback capabilities
- Event sourcing for audit trail and replay
- Eventual consistency with distributed backend

### Error Handling
- Circuit breaker pattern for fault tolerance
- Automatic reconnection with exponential backoff
- Graceful degradation on communication failures

## Development Status

This is part of **Phase 5.5: Go Bubble Tea Terminal Interface** in the Aiex development roadmap. The current implementation provides the foundation for a sophisticated TUI that integrates seamlessly with the Elixir OTP distributed AI coding assistant.

For more information about the overall Aiex project, see the main project documentation.