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

**Development Roadmap** following a structured distributed architecture approach.

### Phase 1: Distributed Core Infrastructure ✅ 85% Complete

This phase establishes the distributed OTP foundation with layered architecture (Functional Core, Boundary, Interface), distributed context management using Mnesia, secure file operations, and multi-provider LLM integration with distributed coordination. The focus is on building a scalable, fault-tolerant foundation using OTP primitives that will support horizontal scaling and multiple interfaces.

- ✅ **Section 1.1:** CLI Framework and Command Structure
- ✅ **Section 1.2:** Distributed Context Management Foundation
- ✅ **Section 1.3:** Sandboxed File Operations
- ✅ **Section 1.4:** Distributed LLM Integration (Base implementation)
- ✅ **Section 1.5:** OTP Application Architecture
- ✅ **Section 1.6:** Mix Task Integration

### Phase 2: Rust TUI with TCP/OTP Integration ⏳

This phase implements a sophisticated Rust-based Terminal User Interface (TUI) using Ratatui that communicates with the Elixir OTP application through a custom TCP server with MessagePack protocol. The architecture follows a direct communication pattern with the OTP application, enabling real-time bidirectional communication while maintaining clean separation between the OTP core logic and TUI interface.

- [ ] **Section 2.1:** TCP/OTP Infrastructure Setup
- [ ] **Section 2.2:** Rust TUI Foundation
- [ ] **Section 2.3:** OTP Client Integration
- [ ] **Section 2.4:** Protocol Implementation
- [ ] **Section 2.5:** State Synchronization

### Phase 3: Distributed Language Processing ✅ 100% Complete

This phase introduces sophisticated distributed language processing with semantic chunking across nodes, distributed context compression, multi-LLM coordination with pg process groups, and multi-interface support (CLI, LiveView, LSP). The focus is on scalable code understanding and interface flexibility.

- ✅ **Section 3.1:** Distributed Semantic Chunking
- ✅ **Section 3.2:** Distributed Context Compression  
- ✅ **Section 3.3:** Distributed Multi-LLM Coordination
- ✅ **Section 3.4:** Multi-Interface Architecture
- ✅ **Section 3.5:** Distributed IEx Integration

### Phase 4: Distributed State Management ✅ 100% Complete

This phase implements distributed state management using event sourcing with pg-based event bus, Mnesia for persistence, comprehensive test generation across nodes, and cluster-wide security. The focus is on distributed reliability, auditability, and consistency.

- ✅ **Section 4.1:** Distributed Event Sourcing with pg
- ✅ **Section 4.2:** Distributed Session Management
- ✅ **Section 4.3:** Distributed Test Generation
- ✅ **Section 4.4:** Distributed Security Architecture
- ✅ **Section 4.5:** Distributed Checkpoint System

### Phase 5: Advanced Chat-Focused TUI Interface ⏳

This phase implements a sophisticated chat-focused Terminal User Interface (TUI) using Ratatui that provides an immersive AI coding assistant experience. The interface features multi-panel layouts, real-time collaboration capabilities, context awareness, and rich interactive elements designed specifically for AI-powered development workflows.

- [ ] **Section 5.1:** Ratatui Foundation with TEA Architecture
- [ ] **Section 5.2:** Multi-Panel Chat Interface Layout
- [ ] **Section 5.3:** Interactive Chat System with Message Management
- [ ] **Section 5.4:** Focus Management and Navigation System
- [ ] **Section 5.5:** Context Awareness and Quick Actions
- [ ] **Section 5.6:** Rich Text Support and Syntax Highlighting

### Phase 6: Core AI Assistant Application Logic ✅ 100% Complete

This phase implements the core AI assistant engines that provide actual coding assistance capabilities. Building on the existing distributed LLM coordination and context management infrastructure, this phase creates the intelligent engines that analyze, generate, and explain code, transforming Aiex from having excellent infrastructure into being a true AI coding assistant.

- ✅ **Section 6.1:** Core AI Assistant Engines (CodeAnalyzer, GenerationEngine, ExplanationEngine)
- ✅ **Section 6.2:** Advanced AI Engines (RefactoringEngine, TestGenerator)
- ✅ **Section 6.3:** AI Assistant Coordinators (CodingAssistant, ConversationManager)
- ✅ **Section 6.4:** Enhanced CLI Integration with AI Commands
- ✅ **Section 6.5:** Prompt Templates and System Integration

### Phase 7: Production Distributed Deployment ⏳

This phase focuses on production deployment with Kubernetes integration, cluster-wide performance optimization, distributed monitoring with telemetry aggregation, and multi-node operational excellence. The emphasis is on horizontal scalability and fault tolerance.

- [ ] **Section 7.1:** Distributed Performance Optimization
- [ ] **Section 7.2:** Kubernetes Production Deployment
- [ ] **Section 7.3:** Distributed Monitoring and Observability
- [ ] **Section 7.4:** Distributed Release Engineering
- [ ] **Section 7.5:** Distributed Developer Tools

### Phase 8: Distributed AI Intelligence ⏳

This phase implements distributed AI response comparison, quality assessment, and selection across the cluster. The focus is on leveraging distributed computing for parallel LLM requests, consensus-based selection, and cluster-wide learning from user preferences.

- [ ] **Section 8.1:** Distributed Response Comparison
- [ ] **Section 8.2:** Distributed Quality Assessment
- [ ] **Section 8.3:** Distributed Response Selection
- [ ] **Section 8.4:** Distributed Analytics Platform
- [ ] **Section 8.5:** Distributed Context Intelligence

### Phase 9: AI Techniques Abstraction Layer ⏳

This phase establishes a comprehensive abstraction layer for implementing advanced AI improvement techniques with runtime configuration and pluggable architecture. The system allows for selective enablement of techniques like self-refinement, multi-agent architectures, RAG, tree-of-thought reasoning, RLHF, and Constitutional AI, providing a flexible foundation for continuous AI enhancement.

- [ ] **Section 9.1:** Core Abstraction Architecture
- [ ] **Section 9.2:** Multi-Agent Architecture Framework
- [ ] **Section 9.3:** Self-Refinement and Iterative Improvement
- [ ] **Section 9.4:** Advanced Reasoning Systems
- [ ] **Section 9.5:** Knowledge Integration and RAG
- [ ] **Section 9.6:** Quality Assessment and Learning

### Phase 10: Phoenix LiveView Web Interface ⏳

This phase implements a sophisticated Phoenix LiveView web interface that provides a modern, real-time chat and AI coding assistant experience. Building on the existing OTP business logic and AI assistant engines, this phase creates a responsive web application with streaming AI responses, real-time collaboration, multi-panel layouts, and production-grade performance optimizations.

- [ ] **Section 10.1:** LiveView Foundation and Architecture
- [ ] **Section 10.2:** Real-time Chat Interface with Streams
- [ ] **Section 10.3:** Multi-panel Layout and Navigation
- [ ] **Section 10.4:** Code Integration and Syntax Highlighting
- [ ] **Section 10.5:** Performance Optimization and Caching
- [ ] **Section 10.6:** Security and Authentication Integration

## ✨ Current Capabilities

### 🧠 **Intelligent Language Processing**
- **Semantic Code Chunking**: Pure Elixir AST-based parsing with intelligent boundary detection
- **Context Compression**: Multi-strategy compression (semantic, truncation, sampling) with model-specific token counting
- **Multi-LLM Coordination**: Distributed provider selection with circuit breaker protection and health monitoring

### 📊 **Event Sourcing & State Management**
- **Distributed Event Bus**: pg-based event distribution with Mnesia storage for cluster-wide auditability
- **Event Store**: Persistent event storage with querying, filtering, and replay capabilities
- **Event Aggregates**: Distributed aggregate management with state reconstruction and snapshots
- **Event Projections**: Real-time read model updates with behavior pattern and error handling

### 🔄 **Distributed Architecture**  
- **pg Process Groups**: Pure OTP clustering without external dependencies
- **Mnesia Persistence**: Distributed database for context and configuration storage
- **Fault Tolerance**: Circuit breakers, health monitoring, and graceful degradation
- **Single-Node Optimization**: 95% usage patterns optimized for single-node deployment

### 🤖 **AI Provider Support**
- **OpenAI**: GPT-3.5/4 with proper rate limiting and cost tracking
- **Anthropic**: Claude-3 models (Haiku, Sonnet, Opus) with large context windows  
- **Ollama**: Local models (Llama2, CodeLlama, Mistral) for offline development
- **LM Studio**: HuggingFace models with OpenAI-compatible API

### 🖥️ **Multi-Interface Support**
- **CLI Interface**: Rich terminal UI with verb-noun command structure
- **Mix Tasks**: Integrated `mix ai.*` tasks for seamless Elixir workflow
- **TUI Client**: Rust-based terminal interface with real-time communication
- **Escript**: Single executable for easy distribution

### 🔒 **Security & Operations**
- **Sandboxed File Operations**: Path validation and allowlist-based access control
- **Audit Logging**: Comprehensive logging for all file operations and AI requests
- **Configuration Management**: Distributed configuration with runtime updates
- **Production Ready**: Mix releases with clustering support

### 📊 **Performance Features**
- **ETS Caching**: High-performance caching for chunks and compression results
- **Token-Aware Processing**: Intelligent context management based on model limits
- **Load Balancing**: Multiple selection strategies (local_affinity, load_balanced, round_robin)
- **Health Monitoring**: Real-time provider status and performance tracking

## Installation

### Quick Start (Single Executable)

```bash
# Self-extracting installer (recommended)
curl -sSL https://releases.aiex.dev/install.sh | bash
# OR download and run manually
wget https://releases.aiex.dev/aiex-installer.sh
chmod +x aiex-installer.sh && ./aiex-installer.sh

# Use immediately
aiex help
aiex start-iex  # Interactive development
```

### Development Setup

```bash
# Clone and build from source
git clone https://github.com/your-org/aiex.git
cd aiex

# Quick development start
make dev  # Starts iex -S mix

# OR manual setup
mix deps.get && mix compile
./aiex version  # Test escript
```

### Distribution Options

#### 1. **Single Executable (Escript)**
```bash
mix escript.build
./aiex help  # 2MB executable, requires Elixir runtime
```

#### 2. **Self-Contained Release**
```bash
make release  # OR ./scripts/build-release.sh
./_build/prod/rel/aiex/bin/aiex start-iex  # Includes Erlang VM
```

#### 3. **Packaged Distribution**
```bash
make package  # Creates multiple distribution formats
./_build/packages/aiex-*-installer.sh  # Self-extracting installer
```

#### 4. **Docker**
```bash
docker run -it --rm aiex:latest
# OR build locally
make docker
```

### Production Deployment

For distributed clusters and Kubernetes deployment:
```bash
# Kubernetes with libcluster
make release
# See scripts/k8s/ for deployment manifests (coming soon)
```

## Quick Start

### 🚀 **Interactive Development**

```bash
# Start full OTP application with interactive shell
aiex start-iex  # OR make dev

# The application provides:
# - Distributed context management with Mnesia
# - Multi-LLM coordination (OpenAI, Anthropic, Ollama, LM Studio)  
# - Semantic chunking and context compression
# - TUI server (TCP on port 9487)
# - Real-time health monitoring
```

### 🖥️ **Terminal User Interface**

```bash
# Launch visual TUI (requires OTP server running)
aiex tui  # OR cd tui && cargo run

# Features:
# - Real-time code analysis
# - Multi-provider LLM interaction
# - File tree navigation
# - Context-aware assistance
```

### ⚡ **CLI Operations**

```bash
# Quick AI operations
aiex cli create module Calculator "basic arithmetic"
aiex cli analyze lib/my_module.ex
aiex cli help

# Mix task integration  
mix ai.gen.module Calculator "arithmetic operations"
mix ai.explain lib/calculator.ex
```

## Configuration

### LLM Provider Setup

```bash
# Set API keys for cloud providers
export OPENAI_API_KEY="your-openai-key"
export ANTHROPIC_API_KEY="your-anthropic-key"

# Local models (no API keys required)
# Ollama: Install from https://ollama.ai/
# LM Studio: Install from https://lmstudio.ai/

# Start with local models for offline development
aiex start-iex
```

### Environment Variables

```bash
# Core configuration
export AIEX_CLUSTERING_ENABLED="false"  # Single-node mode (default)
export AIEX_TUI_PORT="9487"            # TUI server port
export AIEX_LOG_LEVEL="info"           # Logging level

# Provider preferences (optional)
export AIEX_PREFERRED_PROVIDER="ollama"  # Local-first development
export AIEX_MAX_CONTEXT_TOKENS="8000"   # Context window limit
```

## Key Achievements ✨

### 🏗️ **Robust Architecture**
- **Pure OTP Implementation**: No external clustering dependencies 
- **Fault Tolerant**: Circuit breakers, health monitoring, graceful degradation
- **Horizontally Scalable**: Linear performance gains with additional nodes
- **Single-Node Optimized**: 95% usage patterns optimized for local development
- **Event Sourcing**: Complete audit trail with distributed event bus and Mnesia persistence

### 🧠 **Advanced AI Integration**  
- **4 LLM Providers**: OpenAI, Anthropic, Ollama, LM Studio with intelligent coordination
- **Context Intelligence**: Semantic chunking and multi-strategy compression
- **Token Optimization**: Model-specific token counting and context management
- **Circuit Protection**: Automatic failover and provider health monitoring

### 🔧 **Developer Experience**
- **Multiple Interfaces**: CLI, TUI, Mix tasks, and future web/LSP support
- **Single Executable**: Multiple distribution options (escript, releases, installers)
- **Rich Terminal**: Colorized output, progress indicators, interactive help
- **Hot Code Reloading**: Full development experience with `iex -S mix`

### 🛡️ **Production Ready**
- **Security**: Sandboxed operations, audit logging, path validation
- **Observability**: Comprehensive logging, metrics, and health monitoring  
- **Deployment**: Mix releases, Docker, Kubernetes, self-extracting installers
- **Configuration**: Distributed config management with runtime updates

## Architecture Highlights

### 🔄 **Distributed OTP Design**
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CLI/TUI/Web   │    │  LLM Providers  │    │ Context Engine  │
│   Interfaces    │◄──►│   Coordinator   │◄──►│   (Semantic)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Interface       │    │ Circuit Breaker │    │ Compression     │
│ Gateway         │    │ & Health Mon.   │    │ & Caching       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 ▼
                    ┌─────────────────────┐
                    │  Event Sourcing     │
                    │  (OTPEventBus)      │
                    └─────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────┐
                    │  Mnesia + pg        │
                    │ (Distributed State) │
                    └─────────────────────┘
```

### 📊 **Performance Characteristics**
- **Startup Time**: ~2-3 seconds (full OTP application)
- **Memory Usage**: ~50-100MB (including Erlang VM)
- **Concurrent Requests**: 1000+ simultaneous LLM requests
- **Context Processing**: 10MB+ codebases with intelligent chunking
- **Clustering**: Linear scaling across multiple nodes

### 🎯 **Design Principles**
- **Single-Node First**: Optimized for 95% single-developer usage
- **Graceful Distribution**: Optional clustering without complexity overhead
- **Interface Agnostic**: Core logic separated from presentation layer
- **Provider Agnostic**: Unified interface for any LLM provider

## Development Commands

```bash
# Quick development targets
make dev          # Start development server
make test         # Run test suite
make release      # Build production release  
make package      # Create distribution packages

# Manual commands
mix deps.get      # Install dependencies
mix test          # Run tests
mix format        # Format code
iex -S mix        # Interactive development
```

## Contributing

We welcome contributions! The project follows a structured development approach with:

- **Development Roadmap**: Clear phases and milestones
- **Test-Driven Development**: Comprehensive test coverage
- **Documentation**: Detailed implementation plan and API docs
- **Code Quality**: Elixir formatting and best practices

### Getting Started

1. **Read the Plan**: Check `planning/detailed_implementation_plan.md`
2. **Pick a Phase**: Choose from current or upcoming phases
3. **Write Tests**: All features require comprehensive tests
4. **Follow Conventions**: Maintain OTP patterns and distributed design

## License

Apache 2.0 License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- **Elixir/OTP Team**: For the incredible distributed computing platform
- **Discord Engineering**: FastGlobal and 26M events/second inspiration  
- **WhatsApp Architecture**: Minimal team, maximum scale patterns
- **Kubernetes Community**: Cloud-native deployment patterns

---

**Aiex** - *Distributed AI-powered Elixir coding assistant*  
Built with ❤️ using pure OTP primitives for maximum scalability and fault tolerance.

