# Aiex

**AI-powered Elixir coding assistant** leveraging the power of artificial intelligence to enhance your Elixir development workflow.

Aiex is a sophisticated coding assistant that combines Elixir's strengths in concurrency, fault tolerance, and distributed computing with modern AI capabilities to help developers write better code faster.

## Features

### 🚀 Current (Phase 1)
- **Rich CLI Interface** - Beautiful terminal UI with Owl and robust command parsing with Optimus
- **Verb-Noun Commands** - Intuitive git/docker-style command structure (`aiex create project`, `aiex analyze code`)
- **Interactive Terminal** - Progress bars, colorized output, and responsive feedback
- **Comprehensive Help** - Context-sensitive help system with progressive disclosure
- **Modular Architecture** - Clean pipeline design with proper error handling

### 🏗️ Planned Features
- **Context Management** - Intelligent code context tracking and compression
- **Multi-LLM Support** - Support for OpenAI, Anthropic, Google, and local models
- **Code Analysis** - Deep code analysis with suggestions and improvements
- **Project Generation** - AI-assisted project and module scaffolding
- **Test Generation** - Automated test creation with property-based testing
- **IEx Integration** - Interactive helpers for the Elixir shell
- **Session Management** - Persistent sessions with recovery and time-travel debugging

## Installation

### From Source (Development)

1. Clone the repository:
```bash
git clone https://github.com/your-org/aiex.git
cd aiex
```

2. Install dependencies:
```bash
mix deps.get
```

3. Build the executable:
```bash
mix escript.build
```

4. Run Aiex:
```bash
./aiex --help
```

### System Installation (Coming Soon)
Aiex will be available on Hex for easy installation:

```elixir
def deps do
  [
    {:aiex, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Basic Commands

```bash
# Show help
./aiex --help

# Show version information  
./aiex version

# Get help for specific commands
./aiex help create
./aiex help analyze

# Create new projects (coming soon)
./aiex create project --name my_app --template web

# Analyze code (coming soon)
./aiex analyze code --path ./lib --depth 3
```

### Development Commands

```bash
# Install dependencies
mix deps.get

# Compile the project
mix compile

# Run tests
mix test

# Format code
mix format

# Start interactive shell
iex -S mix

# Build executable
mix escript.build
```

## Architecture

Aiex follows a clean architectural design with five main subsystems:

1. **CLI Interface** - Verb-noun command structure with rich terminal UI
2. **Context Management Engine** - Hybrid compression and semantic chunking
3. **LLM Integration Layer** - Multi-provider support with failover
4. **File Operation Sandbox** - Security-focused file operations
5. **State Management System** - Event sourcing for auditability

### Key Design Principles
- **Actor Model** - GenServers for stateful components
- **Process Isolation** - Security boundaries through process separation  
- **Supervision Trees** - Fault tolerance and automatic recovery
- **Streaming Operations** - Handle large codebases efficiently
- **Event Sourcing** - Complete audit trail and time-travel debugging

## Project Status

**Current Phase: Phase 1 - Core Infrastructure (Week 1/16)** ✅

- [x] **CLI Framework** - Complete with Owl + Optimus integration
- [ ] **Context Management Engine** - In progress
- [ ] **File Operation Sandbox** - Planned
- [ ] **Basic LLM Integration** - Planned
- [ ] **Mix Task Integration** - Planned

See [detailed implementation plan](planning/detailed_implementation_plan.md) for complete roadmap.

## Development

### Requirements
- Elixir 1.18+
- OTP 27+
- Mix build tool

### Testing
```bash
# Run all tests
mix test

# Run specific test files
mix test test/aiex/cli/pipeline_test.exs

# Run with coverage
mix test --cover
```

### Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with tests
4. Run the test suite (`mix test`)
5. Format your code (`mix format`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Elixir](https://elixir-lang.org/) and the OTP platform
- CLI powered by [Owl](https://github.com/fuelen/owl) and [Optimus](https://github.com/funbox/optimus)
- Inspired by modern AI coding assistants and Elixir's actor model philosophy

---

**Note**: Aiex is currently in active development. Features and APIs may change as we work toward the first stable release.