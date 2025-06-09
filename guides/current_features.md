# Aiex Current Features Guide

**Version 0.1.0** - Documentation of currently implemented and working features in Aiex.

## What's Actually Working

This guide documents only the features that are currently implemented and functional. For planned features, see `planned_features.md`.

---

## Installation & Setup

### Prerequisites
- **Elixir 1.15+** and **OTP 26+**
- **Rust 1.70+** (for TUI interface, work in progress)
- At least one AI provider account (OpenAI, Anthropic, etc.)

### Installation Steps

```bash
# Clone the repository
git clone https://github.com/pcharbon70/aiex.git
cd aiex

# Install Elixir dependencies
mix deps.get

# Compile the project
mix compile

# Build the CLI executable
mix escript.build
```

### Verification

```bash
# Test CLI (should show help)
./aiex --help

# Test compilation and start interactive session
iex -S mix
```

---

## Configuration

### Current Configuration System

The project uses standard Elixir configuration files:
- `config/config.exs` - Base configuration
- `config/dev.exs` - Development overrides  
- `config/prod.exs` - Production overrides
- `config/test.exs` - Test environment

### Environment Variables

Currently supported environment variables:

```bash
# LLM Provider API Keys (required for AI functionality)
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"

# Optional: Set logging level
export LOG_LEVEL="info"
```

---

## CLI Commands (Currently Working)

### Basic Commands

```bash
# Show help
./aiex --help

# Show version
./aiex --version

# Show help for specific command
./aiex help create
./aiex help analyze
```

### Available Subcommands

1. **create** - Create new projects, modules, or code structures
2. **analyze** - Analyze code for improvements, patterns, and issues  
3. **help** - Show help information for commands
4. **version** - Show version information

### Command Details

#### Create Command
```bash
# Show create command help
./aiex help create
```
*Note: Implementation is basic - creates project scaffolding*

#### Analyze Command  
```bash
# Show analyze command help
./aiex help analyze
```
*Note: Basic code analysis functionality*

---

## IEx Integration (Available but Limited)

### What's Implemented

The project includes IEx helper modules, but functionality is limited:

```elixir
# Start IEx with project
iex -S mix

# Available modules (but functions may not be fully implemented):
# - Aiex.IEx.Helpers
# - Aiex.IEx.Commands
# - Aiex.IEx.EnhancedHelpers
```

### Current IEx Capabilities

Most IEx helpers are implemented as placeholder functions. The infrastructure exists but core AI functionality is not yet connected.

---

## LLM Integration Status

### Adapter Architecture

The project has adapter modules for multiple LLM providers:

- **OpenAI** (`lib/aiex/llm/adapters/openai.ex`)
- **Anthropic** (`lib/aiex/llm/adapters/anthropic.ex`) 
- **Ollama** (`lib/aiex/llm/adapters/ollama.ex`)
- **LM Studio** (`lib/aiex/llm/adapters/lm_studio.ex`)

### Current Status

- ✅ Adapter architecture implemented
- ✅ Configuration system in place
- ⚠️ API integration needs testing/completion
- ⚠️ Rate limiting and error handling partially implemented

---

## Core Infrastructure (Working)

### What's Operational

1. **Application Supervision Tree** - OTP application starts successfully
2. **Event System** - Event bus and projections working
3. **Context Management** - Basic context engine operational
4. **Distributed Architecture** - Horde-based distribution layer functional
5. **Configuration System** - Environment-based configuration working
6. **CLI Framework** - Basic Optimus-based CLI working

### Logging and Monitoring

```bash
# Application logs show successful startup:
# - Event bus initialization
# - Mnesia table creation
# - Context manager startup
# - Distributed supervisor startup
```

---

## Project Structure

### Working Modules

```
lib/aiex/
├── cli/                    # ✅ CLI framework working
│   ├── commands/          # ⚠️ Basic commands implemented
│   └── presenter.ex       # ✅ Output formatting
├── context/               # ✅ Context management working  
├── events/                # ✅ Event sourcing working
├── llm/                   # ⚠️ Adapters exist, integration partial
└── sandbox/               # ✅ Security framework in place
```

### Test Coverage

Basic test framework in place:
```bash
# Run tests
mix test

# Tests exist for:
# - Context management
# - Event systems  
# - CLI components
# - LLM adapters (unit tests)
```

---

## TUI Interface Status

### Current State

- ✅ Rust project structure in `tui/` directory
- ⚠️ Basic TUI skeleton implemented
- ❌ Integration with Elixir backend incomplete

```bash
# TUI can be built but functionality is limited
cd tui
cargo build
cargo run  # Shows basic interface
```

---

## What You Can Actually Do Right Now

### 1. Explore the CLI

```bash
# See what commands are available
./aiex --help

# Get help for specific commands
./aiex help create
./aiex help analyze
```

### 2. Run in Development Mode

```bash
# Start the full application
iex -S mix

# Observe the system starting up:
# - Distributed components
# - Event system
# - Context management
```

### 3. Examine the Code

The codebase demonstrates solid Elixir/OTP architecture:
- Supervision trees
- GenServer-based services
- Event sourcing patterns
- Distributed system design

### 4. Run Tests

```bash
# Execute the test suite
mix test

# Run specific test files
mix test test/aiex/context/
mix test test/aiex/events/
```

---

## Known Limitations

### What's NOT Working Yet

1. **AI Operations** - Analysis, generation, explanation commands don't work
2. **Pipeline System** - Command chaining not functional  
3. **Interactive Shell** - AI shell exists but lacks AI integration
4. **IEx Helpers** - Functions exist but don't connect to AI services
5. **Workflow Templates** - Not implemented
6. **TUI Integration** - Frontend exists but backend integration incomplete

### Configuration Gaps

- LLM provider integration needs completion
- Distributed clustering configuration incomplete
- Security sandbox needs testing

---

## Development Status

### Recent Progress

✅ **Phase 6.3 Completed**: AI Assistant Coordinators
- Coding Assistant coordinator
- Conversation Manager  
- Workflow Orchestrator

✅ **Phase 6.4 In Progress**: Enhanced CLI Integration
- AI command structure
- Interactive shell framework
- Pipeline system foundation

### Next Steps

The system has a solid foundation but needs:
1. LLM integration completion
2. AI command implementations
3. Pipeline execution engine
4. TUI backend integration

---

## Getting Help

### Resources

- Source code: Core functionality in `lib/aiex/`
- Tests: Examples of expected behavior in `test/`
- Configuration: Examples in `config/` files

### Troubleshooting

#### Common Issues

1. **Application won't start**
   ```bash
   # Check dependencies
   mix deps.get
   mix compile
   ```

2. **CLI shows errors**
   ```bash
   # Rebuild executable
   mix escript.build
   ```

3. **Tests failing**
   ```bash
   # Clean and recompile
   mix clean
   mix compile
   mix test
   ```

### Contributing

The project is actively developed. The core architecture is solid and ready for feature implementation.

---

This guide reflects the actual current state of the Aiex project as of version 0.1.0. For planned features and full system capabilities, refer to `planned_features.md`.