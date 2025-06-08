# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Rust Terminal User Interface (TUI) for the Aiex AI-powered Elixir coding assistant. It's built with Ratatui and async Rust, following The Elm Architecture (TEA) pattern for predictable state management.

## Common Development Commands

### Build and Run
- `cargo build` - Compile the project
- `cargo run` - Run the TUI application
- `cargo run -- --debug` - Run with debug logging enabled
- `cargo run -- --otp-addr 127.0.0.1:9487` - Connect to specific OTP server address
- `cargo run -- --project-dir /path/to/project` - Work with specific project directory

### Testing
- `cargo test` - Run unit tests
- `cargo test --features integration` - Run integration tests (requires OTP server)
- `cargo tarpaulin --out Html` - Run with test coverage

### Code Quality
- `cargo fmt` - Format code according to Rust standards
- `cargo clippy` - Run linting checks

### Environment Variables
- `RUST_LOG=debug cargo run` - Enable debug logging
- `RUST_LOG=aiex_tui::otp_client=trace cargo run` - Enable trace logging for specific modules

## High-Level Architecture

The application follows **The Elm Architecture (TEA)** pattern:

- **Model**: Application state in `src/state.rs` (AppState struct)
- **Update**: Message handling in `src/app.rs` (handle_message methods) 
- **View**: UI rendering in `src/ui.rs` (render_ui function)

### Key Components

1. **App (`src/app.rs`)**: Main application orchestrator with async event loop
2. **AppState (`src/state.rs`)**: Immutable state management with structured updates
3. **OtpClient (`src/otp_client.rs`)**: TCP communication layer with Elixir OTP application
4. **TerminalManager (`src/terminal.rs`)**: Terminal initialization and capability detection
5. **EventHandler (`src/events.rs`)**: Keyboard and terminal event processing
6. **Config (`src/config.rs`)**: TOML-based configuration management
7. **ChatUI (`src/chat_ui.rs`)**: Specialized rendering for conversational interfaces

### Communication Architecture

The TUI communicates with an Elixir OTP application through:
- **Protocol**: Direct TCP connection with MessagePack serialization
- **Default Port**: 9487 (configurable via `--otp-addr`)
- **Message Types**: Commands (TUI → OTP), Events (OTP → TUI), Responses (OTP → TUI)
- **Topics**: `otp.event.pg.context_updates.join` and similar patterns

### State Management

- All state changes flow through the `Message` enum in `src/message.rs`
- State updates are immutable and processed in `App::handle_message()`
- UI re-renders are frame-rate limited (60 FPS) with dirty checking

### UI Layout

Multi-pane interface with:
- **Header Tabs**: Explorer, Search, Git, Extensions, Settings
- **File Tree**: Project navigation with vim-like keybindings
- **Code View**: File content display with syntax highlighting hints
- **Bottom Panel**: Event Log, Build Output, Debug, Performance views
- **Status Bar**: System status with keyboard shortcuts

## Key Implementation Patterns

### Error Handling
- Uses `anyhow::Result` for error propagation
- Graceful error recovery in event loop (continues on non-critical errors)
- Terminal cleanup always happens, even on errors

### Async Programming
- Built on `tokio` async runtime
- Non-blocking UI updates with `tokio::select!`
- Background tasks for OTP communication and terminal events

### Terminal Management
- Cross-platform support via `crossterm`
- Capability detection for fallback on limited terminals
- Proper cleanup on shutdown or resize errors

### Configuration
- TOML-based config with sensible defaults
- Platform-specific config paths (`~/.config/aiex-tui/config.toml`)
- Auto-creation of default config if none exists

## Message Protocol

### Commands (TUI → OTP)
```rust
// File operations: tui.command.file.{action}
{"action": "open", "path": "lib/my_module.ex", "timestamp": 1234567890}

// Project operations: tui.command.project.{action}  
{"action": "build", "target": "test", "timestamp": 1234567890}
```

### Events (OTP → TUI)
```rust
// File changes: otp.event.file.changed
{"file_path": "lib/my_module.ex", "change_type": "Modified", "content": "...", "timestamp": 1234567890}

// Build events: otp.event.build.completed
{"project": "my_app", "status": "Success", "output": "...", "duration_ms": 1500, "timestamp": 1234567890}
```

## Development Notes

- The TUI expects to connect to an OTP server on `127.0.0.1:9487` by default via TCP
- OTP client connection happens in background tasks spawned in `App::start_background_tasks()`
- Language detection is basic file extension matching in `state.rs:detect_language()`
- Event log retention is limited to 1000 entries with automatic cleanup
- Frame rate is capped at 60 FPS to prevent excessive CPU usage
- Architecture migrated from NATS messaging to direct TCP with MessagePack for better performance
- Chat UI module (`src/chat_ui.rs`) provides specialized rendering for conversational interfaces