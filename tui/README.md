# Aiex TUI - Rust Terminal User Interface

A sophisticated Terminal User Interface (TUI) for the Aiex AI-powered Elixir coding assistant, built with Ratatui and async Rust.

## Architecture Overview

The TUI follows **The Elm Architecture (TEA)** pattern for predictable state management:

- **Model**: Application state in `src/state.rs`
- **Update**: Message handling in `src/app.rs` 
- **View**: UI rendering in `src/ui.rs`

### Communication with Elixir OTP

The TUI communicates with the Elixir OTP application through **NATS messaging** using **MessagePack** serialization:

```
┌─────────────────┐    NATS Cluster    ┌─────────────────┐
│   Rust TUI      │◄──────────────────►│  Elixir OTP     │
│                 │                    │                 │
│ - Ratatui UI    │  Commands/Queries  │ - GenServers    │
│ - async-nats    │  ←────────────→   │ - Gnat client   │
│ - MessagePack   │                    │ - pg groups     │
│ - Local state   │  Events/Streaming  │ - Supervisors   │
└─────────────────┘  ←────────────    └─────────────────┘
```

## Features

### Multi-Pane Layout
- **File Tree**: Navigate project structure with vim-like keybindings
- **Code View**: Display file contents with syntax highlighting hints
- **Diff View**: Show code changes and modifications
- **Event Log**: Real-time updates from OTP application

### Real-Time Communication
- **Command/Response**: Send file operations, build requests to OTP
- **Event Streaming**: Receive file changes, build updates in real-time
- **State Queries**: Query project state, configuration from OTP

### Production-Ready Patterns
- **Circuit Breakers**: Resilient communication with fallback
- **Connection Management**: Automatic reconnection with exponential backoff
- **Message Batching**: Efficient data transfer optimization
- **Offline Capability**: Command queuing when disconnected

## Usage

### Prerequisites

1. **Rust**: Install from [rustup.rs](https://rustup.rs/)
2. **NATS Server**: Running on `localhost:4222`
3. **Aiex OTP Application**: Running and connected to same NATS server

### Building and Running

```bash
# Navigate to TUI directory
cd tui/

# Install dependencies and build
cargo build

# Run the TUI
cargo run

# Run with debug logging
cargo run -- --debug

# Connect to different NATS server
cargo run -- --nats-url nats://remote:4222

# Work with specific project directory
cargo run -- --project-dir /path/to/project
```

### Key Bindings

| Key | Action |
|-----|--------|
| `q`, `Esc`, `Ctrl+C` | Quit application |
| `↑`/`k`, `↓`/`j` | Navigate up/down |
| `Enter` | Select/Open file |
| `Tab` | Switch between panes |
| `r`, `F5` | Refresh project |
| `b`, `F6` | Build project |
| `t`, `F7` | Run tests |
| `f`, `F8` | Format code |

## Configuration

The TUI creates a configuration file at:
- Linux: `~/.config/aiex-tui/config.toml`
- macOS: `~/Library/Application Support/aiex-tui/config.toml`
- Windows: `%APPDATA%\aiex-tui\config.toml`

### Example Configuration

```toml
[nats]
server_url = "nats://localhost:4222"
connection_timeout = 10
message_timeout = 5
reconnect_interval = 1000

[ui]
fps_limit = 60
show_line_numbers = true
show_status_bar = true
file_tree_width = 25

[ui.theme]
primary = "#61afef"
secondary = "#c678dd"
background = "#282c34"
foreground = "#abb2bf"

[editor]
tab_size = 2
use_spaces = true
word_wrap = true
auto_save_interval = 0

[project]
auto_refresh = true
refresh_interval = 5
ignore_patterns = ["_build", "deps", ".git", "node_modules"]
watch_files = true
```

## NATS Message Protocol

### Commands (TUI → OTP)

File operations:
```rust
// Subject: tui.command.file.{action}
{
  "action": "open",
  "path": "lib/my_module.ex",
  "timestamp": 1234567890
}
```

Project operations:
```rust
// Subject: tui.command.project.{action}
{
  "action": "build",
  "target": "test",
  "timestamp": 1234567890
}
```

### Events (OTP → TUI)

File changes:
```rust
// Subject: otp.event.file.changed
{
  "file_path": "lib/my_module.ex",
  "change_type": "Modified",
  "content": "defmodule MyModule do...",
  "timestamp": 1234567890
}
```

Build events:
```rust
// Subject: otp.event.build.completed
{
  "project": "my_app",
  "status": "Success",
  "output": "Compiled successfully",
  "duration_ms": 1500,
  "timestamp": 1234567890
}
```

### Responses (OTP → TUI)

Success responses:
```rust
// Subject: otp.response.{request_id}
{
  "status": "success",
  "data": { /* response data */ },
  "timestamp": 1234567890
}
```

Error responses:
```rust
{
  "status": "error",
  "message": "File not found",
  "code": "ENOENT",
  "timestamp": 1234567890
}
```

## Development

### Project Structure

```
tui/
├── Cargo.toml              # Dependencies and metadata
├── src/
│   ├── main.rs             # Application entry point
│   ├── app.rs              # Main application (TEA Update)
│   ├── state.rs            # Application state (TEA Model)
│   ├── ui.rs               # UI rendering (TEA View)
│   ├── config.rs           # Configuration management
│   ├── nats_client.rs      # NATS client and connection management
│   ├── events.rs           # Terminal event handling
│   ├── message.rs          # Message types and protocol
│   └── tui.rs              # TUI utilities
└── README.md
```

### Testing

```bash
# Run unit tests
cargo test

# Run integration tests (requires NATS server)
cargo test --features integration

# Run with test coverage
cargo tarpaulin --out Html
```

### Logging

The TUI uses `tracing` for structured logging:

```bash
# Enable debug logging
RUST_LOG=debug cargo run

# Enable trace logging for specific modules
RUST_LOG=aiex_tui::nats_client=trace cargo run
```

## Architecture Decisions

### Why Ratatui + crossterm?
- **Cross-platform**: Works on Windows, macOS, Linux
- **Performance**: Efficient terminal rendering with minimal screen updates
- **Async-first**: Integrates well with tokio async runtime

### Why The Elm Architecture?
- **Predictable State**: All state changes flow through messages
- **Testable**: Pure functions for state updates
- **Maintainable**: Clear separation of concerns

### Why NATS + MessagePack?
- **Performance**: MessagePack is 10-15% faster than Protocol Buffers
- **Flexibility**: Schema-less, works well with dynamic Elixir data
- **Reliability**: NATS provides delivery guarantees and clustering

### Why async/await?
- **Responsiveness**: Non-blocking UI updates
- **Concurrency**: Handle multiple NATS subscriptions simultaneously  
- **Resource Efficiency**: Single-threaded event loop model

## Troubleshooting

### Connection Issues

1. **NATS server not running**:
   ```bash
   # Start NATS server
   nats-server
   ```

2. **Connection refused**:
   ```bash
   # Check NATS server address
   cargo run -- --nats-url nats://127.0.0.1:4222
   ```

3. **Authentication errors**: Ensure NATS server allows anonymous connections

### Performance Issues

1. **High CPU usage**: Reduce FPS limit in config
2. **Memory leaks**: Check event log retention settings
3. **Slow rendering**: Disable syntax highlighting for large files

### Integration Issues

1. **Messages not received**: Check NATS subject patterns
2. **Serialization errors**: Verify MessagePack compatibility
3. **State synchronization**: Check event ordering and timestamps

## Contributing

1. Follow Rust standard formatting: `cargo fmt`
2. Run clippy for linting: `cargo clippy`
3. Add tests for new features
4. Update documentation for API changes

## License

Licensed under the Apache License, Version 2.0.