# Aiex

**AI-powered Elixir coding assistant** leveraging the power of artificial intelligence to enhance your Elixir development workflow.

Aiex is a sophisticated coding assistant that combines Elixir's strengths in concurrency, fault tolerance, and distributed computing with modern AI capabilities to help developers write better code faster.

## Implementation Progress

**20-Week Development Roadmap** following a structured approach with five major phases.

### Phase 1: Core Infrastructure (Weeks 1-4) ✅ 80% Complete

This phase establishes the foundational architecture with robust CLI tooling, basic context management, file operation sandbox, and single-model LLM integration. The focus is on building a solid, secure foundation with proper supervision trees and process isolation that will support all future development.

- ✅ **Section 1.1:** CLI Framework and Command Structure
- [ ] **Section 1.2:** Context Management Engine Foundation
- [ ] **Section 1.3:** Sandboxed File Operations
- ✅ **Section 1.4:** Basic LLM Integration
- [ ] **Section 1.5:** Mix Task Integration

### Phase 2: Advanced Language Processing (Weeks 5-8) ⏳

This phase introduces sophisticated language processing capabilities including semantic chunking, context compression, multi-LLM support with failover, and interactive features. The focus is on intelligent code understanding and reliable AI interactions.

- [ ] **Section 2.1:** Semantic Chunking Implementation
- [ ] **Section 2.2:** Context Compression Strategies
- [ ] **Section 2.3:** Multi-LLM Adapter System
- [ ] **Section 2.4:** Interactive Features
- [ ] **Section 2.5:** IEx Integration Helpers

### Phase 3: State Management and Testing (Weeks 9-12) ⏳

This phase implements production-grade state management using event sourcing, comprehensive test generation capabilities, and enhanced security features. The focus is on reliability, auditability, and developer productivity.

- [ ] **Section 3.1:** Event Sourcing Implementation
- [ ] **Section 3.2:** Session Persistence and Recovery
- [ ] **Section 3.3:** AI-Powered Test Generation
- [ ] **Section 3.4:** Security and Audit System
- [ ] **Section 3.5:** Checkpoint and Version Management

### Phase 4: Production Optimization (Weeks 13-16) ⏳

This final phase focuses on operational excellence with performance optimization, distributed deployment capabilities, comprehensive monitoring, and developer tooling. The emphasis is on production readiness and maintainability.

- [ ] **Section 4.1:** Performance Profiling and Optimization
- [ ] **Section 4.2:** Distributed Deployment Support
- [ ] **Section 4.3:** Monitoring and Observability
- [ ] **Section 4.4:** Release Engineering
- [ ] **Section 4.5:** Developer Tools and Documentation

### Phase 5: AI Response Intelligence & Comparison (Weeks 17-20) ⏳

This phase introduces advanced AI capabilities for comparing, evaluating, and optimizing LLM responses across multiple providers. The focus is on building intelligent response selection, quality assessment, and continuous learning systems that enhance the overall AI assistant experience through context-aware evaluation and user preference adaptation.

- [ ] **Section 5.1:** Multi-Provider Response Comparison Engine
- [ ] **Section 5.2:** Response Quality Assessment System
- [ ] **Section 5.3:** Intelligent Response Selection
- [ ] **Section 5.4:** Response Analytics and Insights
- [ ] **Section 5.5:** Advanced Context Integration

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
3. **LLM Integration Layer** - Four-provider architecture (OpenAI, Anthropic, Ollama, LM Studio) with intelligent failover
4. **File Operation Sandbox** - Security-focused file operations
5. **State Management System** - Event sourcing for auditability

### Key Design Principles
- **Actor Model** - GenServers for stateful components
- **Process Isolation** - Security boundaries through process separation  
- **Supervision Trees** - Fault tolerance and automatic recovery
- **Streaming Operations** - Handle large codebases efficiently
- **Event Sourcing** - Complete audit trail and time-travel debugging

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