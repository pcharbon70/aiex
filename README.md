# Aiex

**Distributed AI-powered Elixir coding assistant** leveraging Erlang/OTP's distributed computing capabilities with multiple interfaces (CLI, Phoenix LiveView, VS Code LSP) to enhance your development workflow.

Aiex is a sophisticated distributed coding assistant that combines Elixir's strengths in concurrency, fault tolerance, and distributed computing with modern AI capabilities. Built using pure OTP primitives, it provides horizontal scalability, multi-interface support, and production-grade reliability.

## Architecture Overview

Aiex follows a **distributed OTP architecture** with layered design:

- **Functional Core Layer** - Pure business logic for AI operations and code analysis
- **Boundary Layer** - OTP processes (GenServers, Supervisors) managing distributed state
- **Interface Layer** - Multiple interfaces (CLI, LiveView, LSP) with unified business logic

### Key Components

1. **Distributed Context Management** - Mnesia-based persistence with cross-node synchronization
2. **Multi-Provider LLM Integration** - OpenAI, Anthropic, Ollama, LM Studio with distributed coordination
3. **Multi-Interface Support** - CLI, Phoenix LiveView web UI, VS Code LSP server
4. **Event Distribution** - pg module for pure OTP pub/sub (no Phoenix dependency)
5. **Kubernetes Native** - Horizontal scaling with libcluster and Horde

### Distributed Features

- **Horizontal Scaling** - Linear performance gains across cluster nodes
- **Fault Tolerance** - Network partition handling with degraded mode operation
- **Interface Flexibility** - Switch between CLI, web UI, and VS Code seamlessly
- **Production Ready** - Kubernetes deployment with monitoring and observability

## Implementation Progress

**20-Week Development Roadmap** following a structured distributed architecture approach.

### Phase 1: Distributed Core Infrastructure (Weeks 1-4) ✅ 80% Complete

This phase establishes the distributed OTP foundation with layered architecture (Functional Core, Boundary, Interface), distributed context management using Mnesia, secure file operations, and multi-provider LLM integration with distributed coordination. The focus is on building a scalable, fault-tolerant foundation using OTP primitives that will support horizontal scaling and multiple interfaces.

- ✅ **Section 1.1:** CLI Framework and Command Structure
- [ ] **Section 1.2:** Distributed Context Management Foundation
- [ ] **Section 1.3:** Sandboxed File Operations
- ✅ **Section 1.4:** Distributed LLM Integration (Base implementation)
- [ ] **Section 1.5:** OTP Application Architecture
- [ ] **Section 1.6:** Mix Task Integration

### Phase 2: Distributed Language Processing (Weeks 5-8) ⏳

This phase introduces sophisticated distributed language processing with semantic chunking across nodes, distributed context compression, multi-LLM coordination with pg process groups, and multi-interface support (CLI, LiveView, LSP). The focus is on scalable code understanding and interface flexibility.

- [ ] **Section 2.1:** Distributed Semantic Chunking
- [ ] **Section 2.2:** Distributed Context Compression
- [ ] **Section 2.3:** Distributed Multi-LLM Coordination
- [ ] **Section 2.4:** Multi-Interface Architecture
- [ ] **Section 2.5:** Distributed IEx Integration

### Phase 3: Distributed State Management (Weeks 9-12) ⏳

This phase implements distributed state management using event sourcing with pg-based event bus, Mnesia for persistence, comprehensive test generation across nodes, and cluster-wide security. The focus is on distributed reliability, auditability, and consistency.

- [ ] **Section 3.1:** Distributed Event Sourcing with pg
- [ ] **Section 3.2:** Distributed Session Management
- [ ] **Section 3.3:** Distributed Test Generation
- [ ] **Section 3.4:** Distributed Security Architecture
- [ ] **Section 3.5:** Distributed Checkpoint System

### Phase 4: Production Distributed Deployment (Weeks 13-16) ⏳

This phase focuses on production deployment with Kubernetes integration, cluster-wide performance optimization, distributed monitoring with telemetry aggregation, and multi-node operational excellence. The emphasis is on horizontal scalability and fault tolerance.

- [ ] **Section 4.1:** Distributed Performance Optimization
- [ ] **Section 4.2:** Kubernetes Production Deployment
- [ ] **Section 4.3:** Distributed Monitoring and Observability
- [ ] **Section 4.4:** Distributed Release Engineering
- [ ] **Section 4.5:** Distributed Developer Tools

### Phase 5: Distributed AI Intelligence (Weeks 17-20) ⏳

This phase implements distributed AI response comparison, quality assessment, and selection across the cluster. The focus is on leveraging distributed computing for parallel LLM requests, consensus-based selection, and cluster-wide learning from user preferences.

- [ ] **Section 5.1:** Distributed Response Comparison
- [ ] **Section 5.2:** Distributed Quality Assessment
- [ ] **Section 5.3:** Distributed Response Selection
- [ ] **Section 5.4:** Distributed Analytics Platform
- [ ] **Section 5.5:** Distributed Context Intelligence

## Installation

### Development Setup

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

4. Run Aiex CLI:
```bash
./aiex --help
```

### Distributed Deployment

For production distributed deployment, see [Kubernetes deployment guide](docs/deployment.md) (coming soon).

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

### CLI Interface

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

### Web Interface (Coming Soon)

Access the Phoenix LiveView interface at `http://localhost:4000` for real-time collaborative AI assistance.

### VS Code Extension (Coming Soon)

Install the Aiex VS Code extension for integrated AI assistance directly in your editor.

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

# Start distributed cluster (development)
iex --name aiex@127.0.0.1 -S mix
```

## Distributed Architecture

### Core Technologies

- **Pure OTP** - No external dependencies for core functionality
- **pg module** - Distributed pub/sub replacing Phoenix.PubSub
- **Mnesia** - Distributed database for persistent state
- **Horde** - Distributed process registry and supervision
- **libcluster** - Automatic cluster formation

### Production Insights

Architecture incorporates patterns from proven distributed systems:
- **Discord** - 26M events/second with FastGlobal optimization
- **WhatsApp** - 50B messages/day with minimal engineering team
- **Kubernetes Native** - Cloud-native deployment and scaling

### Key Design Principles

- **Distributed First** - Every component designed for multi-node operation
- **Interface Independence** - Business logic separated from interface concerns
- **Process Isolation** - Fault boundaries through OTP supervision trees
- **Eventual Consistency** - Using pg and CRDTs for collaborative features
- **Horizontal Scaling** - Linear performance gains with additional nodes

See [distributed architecture design](research/distributed_coding_agent.md) and [detailed implementation plan](planning/detailed_implementation_plan.md) for complete specifications.

## Development

### Requirements
- Elixir 1.18+
- OTP 27+
- Mix build tool
- For distributed development: Multiple nodes or Kubernetes cluster

### Testing
```bash
# Run all tests
mix test

# Run specific test files
mix test test/aiex/cli/pipeline_test.exs

# Run with coverage
mix test --cover

# Run distributed tests (coming soon)
mix test.distributed
```

### Cluster Development

```bash
# Start first node
iex --name aiex1@127.0.0.1 -S mix

# Start second node (in another terminal)
iex --name aiex2@127.0.0.1 -S mix

# Connect nodes
Node.connect(:"aiex1@127.0.0.1")
```

### Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with tests
4. Run the test suite (`mix test`)
5. Format your code (`mix format`)
6. Test distributed scenarios if applicable
7. Commit your changes (`git commit -am 'Add amazing feature'`)
8. Push to the branch (`git push origin feature/amazing-feature`)
9. Open a Pull Request

## Interfaces

### CLI Interface ✅
- Rich terminal UI with progress indicators
- Verb-noun command structure
- Interactive prompts and confirmations

### Phoenix LiveView Interface ⏳
- Real-time collaborative AI assistance
- Multi-user sessions with shared context
- Interactive chat interface

### VS Code LSP Interface ⏳
- Language server protocol integration
- AI-powered code completions
- In-editor chat and explanations

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Elixir](https://elixir-lang.org/) and the OTP platform
- CLI powered by [Owl](https://github.com/fuelen/owl) and [Optimus](https://github.com/funbox/optimus)
- Distributed architecture inspired by Discord, WhatsApp, and other large-scale OTP systems
- Multi-interface design enabling flexible user experiences

---

**Note**: Aiex is currently in active development with a focus on distributed architecture. The CLI interface is functional, while web and LSP interfaces are planned for Phase 2. Features and APIs may change as we work toward the first stable release.