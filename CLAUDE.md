# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Aiex is a sophisticated distributed AI-powered Elixir coding assistant currently in Phase 4 of an 11-phase development roadmap. The project has built extensive distributed infrastructure using pure OTP primitives and core AI assistant logic, and is now implementing a modern Zig/Libvaxis terminal interface. Aiex leverages Elixir's strengths in concurrency, fault tolerance, and distributed computing to create a production-ready AI coding assistant.

## Current State (Phase 4 Active, Phase 5 Complete)

Aiex has completed the distributed infrastructure and core AI assistant logic, and is now implementing the Zig/Libvaxis terminal interface:

- **Distributed OTP Architecture**: Complete with pg process group coordination, Mnesia persistence, and event sourcing
- **Multi-LLM Integration**: 4 providers (OpenAI, Anthropic, Ollama, LM Studio) with intelligent coordination, circuit breakers, and health monitoring
- **Advanced Context Management**: Semantic chunking, context compression, and distributed synchronization across nodes
- **Core AI Engines**: Complete implementation of CodeAnalyzer, GenerationEngine, ExplanationEngine, RefactoringEngine, and TestGenerator
- **AI Coordinators**: CodingAssistant and ConversationManager fully integrated with distributed infrastructure
- **Event Sourcing System**: Complete audit trail with distributed event bus using pg module
- **Multiple Interfaces**: CLI, Mix tasks with unified business logic through InterfaceGateway
- **Security & Sandboxing**: Path validation, audit logging, and secure file operations
- **Rich Terminal Features**: Syntax highlighting, real-time context awareness, and multi-panel layouts

**Current Work**: Implementing the Zig/Libvaxis TUI with direct BEAM integration using Zigler NIFs (Phase 4, 20% complete).

## Common Development Commands

### Build and Dependencies
- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project
- `make dev` - Quick development start (runs `iex -S mix`)
- `make release` - Build production release
- `make test` - Run test suite

### Testing
- `mix test` - Run all tests
- `mix test test/aiex_test.exs` - Run specific test file
- `mix test test/aiex_test.exs:5` - Run test at specific line
- `mix test --only integration` - Run integration tests only
- `mix test --exclude integration` - Skip integration tests

### Code Quality
- `mix format` - Format code according to Elixir standards
- `mix format --check-formatted` - Check if code is properly formatted
- `mix dialyzer` - Run static analysis (if configured)

### Interactive Development
- `iex -S mix` - Start interactive Elixir shell with project loaded
- `aiex start-iex` - Start OTP application with interactive shell
- `./aiex help` - Test escript CLI interface

### TUI Development
- `iex -S mix` then `Aiex.Tui.LibvaxisTui.start()` - Start TUI interface
- `./aiex tui` - Launch TUI from CLI (when implemented)
- `elixir test_tui_display.exs` - Test TUI layout without full app
- `mix test test/aiex/tui/` - Run TUI-related tests

### AI Assistant Testing
- `mix ai.explain lib/aiex.ex` - Test AI explanation functionality
- `mix ai.gen.module Calculator "arithmetic operations"` - Test AI module generation
- `./aiex cli analyze lib/` - Test CLI analysis command
- `./aiex cli create module TestModule "description"` - Test CLI creation

### Performance and Monitoring
- `RUST_LOG=debug ./aiex start-iex` - Enable debug logging
- `:observer.start()` - Launch Erlang Observer for monitoring (in IEx)
- `:recon.proc_count(:memory, 10)` - Show top memory processes (in IEx)

## Working Method

We use a structured approach combining todo tracking with documentation for implementing AI assistant features.

### Dependency Management Rule

**IMPORTANT**: Never modify or replace code to work around missing dependencies. If a dependency is not installed or there's a version mismatch:
1. **Stop and inform the user** about the missing dependency
2. **Provide clear installation instructions** for the dependency
3. **Wait for the user to install it** before proceeding
4. **Do NOT create mock implementations** or workarounds to bypass the dependency

This ensures the codebase remains consistent and dependencies are properly managed.

### Current Phase 4 Workflow:

1. **Todo Tracking**: Use TodoWrite/TodoRead tools to track TUI implementation progress
2. **Plan Before Implementation**: Always create and review plans before coding (NO EXCEPTIONS!)
3. **Test-Driven Development**: Write comprehensive tests for all Zig/Elixir integration
4. **Integration Testing**: Ensure TUI works with existing distributed infrastructure
5. **Documentation**: Document Zigler patterns and BEAM integration points

### Feature Implementation Workflow:

1. **Plan Phase**: Collaborate on design, save plan in `/notes/features/<number>-<name>.md` under `## Plan` heading
2. **Implementation Phase**: Store notes, findings, issues in `/notes/features/<number>-<name>.md` under `## Log` heading  
3. **Testing & Finalization**: Document final design in `/notes/features/<number>-<name>.md` under `## Conclusion` heading

### Bug Fix Workflow:

1. **Issue Documentation**: Document in `/notes/fixes/<number>-<name>.md` under `## Issue` heading
2. **Fix Implementation**: Store technical details in `/notes/fixes/<number>-<name>.md` under `## Fix` heading
3. **Resolution Summary**: Document learnings in `/notes/fixes/<number>-<name>.md` under `## Conclusion` heading

### AI Assistant Development Rules:

- **Always plan first**: Refuse to implement until plan is created and reviewed
- **Use existing infrastructure**: Leverage LLM coordination, context management, event sourcing
- **Follow OTP patterns**: Maintain supervision tree and distributed architecture
- **Comprehensive testing**: Test AI functionality, performance, and integration
- **Never commit without approval**: Wait for explicit commit instructions

**IMPORTANT**: For Phase 4 TUI work, always integrate with existing `InterfaceGateway`, `Context.Manager`, and event sourcing system.


## Phase 5: AI Assistant Development Guidelines (Completed)

These guidelines were used when implementing the AI engines for core assistant functionality:

### Integration with Existing Infrastructure:
- **Use `LLM.ModelCoordinator`**: For distributed AI processing across nodes with circuit breakers
- **Leverage `Context.Manager`**: For project understanding and session-aware context
- **Integrate with Event Sourcing**: Track all AI interactions for audit and learning
- **Follow Supervision Tree Patterns**: Maintain fault tolerance and process isolation
- **Use `InterfaceGateway`**: Route AI requests through existing unified interface

### AI Engine Development Patterns:
```elixir
# Example AI engine structure
defmodule Aiex.AI.CodeAnalyzer do
  use GenServer
  
  # Integrate with existing LLM coordination
  def analyze_code(file_path, options \\ []) do
    context = Context.Manager.get_project_context()
    LLM.ModelCoordinator.request(%{
      type: :code_analysis,
      content: file_content,
      context: context,
      options: options
    })
  end
end
```

### Prompt Template Development:
- Create structured, reusable prompt templates
- Include context injection points for project-specific information
- Support multiple detail levels (brief, detailed, tutorial)
- Implement template validation and testing

### Testing AI Functionality:
- Test AI engine logic separately from LLM responses
- Mock LLM responses for consistent testing
- Test integration with existing distributed infrastructure
- Include performance and memory usage tests
- Test error handling and graceful degradation

## High-Level Architecture

The architecture follows a distributed OTP design with six main subsystems:

1. **AI Assistant Engines** - Core logic for analysis, generation, explanation, refactoring (Phase 5 complete)
2. **Multi-Interface Layer** - CLI, TUI, Mix tasks, future LiveView with unified business logic
3. **LLM Integration Layer** - 4 providers with intelligent coordination and circuit breakers
4. **Context Management Engine** - Semantic chunking, compression, distributed synchronization
5. **File Operation Sandbox** - Security-focused operations with path validation and audit logging
6. **Event Sourcing System** - Distributed event bus with Mnesia persistence for auditability

Key architectural principles:
- **Distributed-first design**: Pure OTP with pg coordination for horizontal scaling
- **Actor model**: GenServers for stateful components with supervision trees
- **Interface abstraction**: Core business logic separated from presentation layer
- **Fault tolerance**: Circuit breakers, health monitoring, graceful degradation
- **Event-driven**: All state changes flow through event sourcing system

## Development Phases

The project follows a 32-week roadmap (see `planning/detailed_implementation_plan.md`):

- **Phase 1-3**: ✅ **Completed** - Distributed infrastructure, context management, event sourcing
- **Phase 4**: ⏳ **Current** - Zig/Libvaxis terminal interface with BEAM integration  
- **Phase 5**: ✅ **Completed** - Core AI assistant application logic (analysis, generation, explanation)
- **Phase 6**: Advanced multi-LLM coordination and optimization
- **Phase 7**: Production distributed deployment and Kubernetes integration
- **Phase 8**: Distributed AI intelligence and response comparison
- **Phase 9**: AI techniques abstraction layer (self-refinement, multi-agent, RAG)

## Key Implementation Details

### Current Infrastructure (Completed):
- **ETS/DETS Storage**: Fast in-memory caching with persistent storage for context and configuration
- **Circuit Breakers**: Implemented for all LLM API calls with health monitoring and failover
- **Event Sourcing**: Complete audit trail using pg-based event bus with Mnesia persistence
- **Semantic Processing**: Pure Elixir AST-based chunking with Tree-sitter integration ready
- **Multi-LLM Coordination**: Intelligent provider selection with load balancing and circuit protection
- **Distributed Architecture**: pg process groups for pure OTP clustering without external dependencies
- **Rich TUI**: Zig/Libvaxis terminal interface with direct BEAM integration via Zigler NIFs
- **Security**: Comprehensive path validation, audit logging, and sandboxed file operations

### Phase 4 Implementation Focus:
- **Zigler NIF Integration**: Building robust Zig-Elixir bridge for terminal UI
- **Libvaxis Event Loop**: Integrating terminal events with BEAM scheduler
- **Multi-Panel Layout**: Implementing chat interface using Libvaxis widgets
- **Virtual Scrolling**: Efficient rendering for large message histories
- **Testing Strategy**: Comprehensive testing of NIF reliability and UI responsiveness

## Git Commit Guidelines

**CRITICAL REQUIREMENT**: NEVER allow any AI tool to take authorship or co-authorship in commit messages or merge messages. This is a strict project policy.

**PROHIBITED in ALL commits and merges**:
- "Generated with Claude Code" or any AI tool attribution
- "Co-Authored-By: Claude" or any AI assistant credits  
- "🤖 Generated with [AI Tool]" or similar AI attribution
- Any mention of AI assistance, AI tools, or AI collaboration in commit descriptions
- Any form of AI authorship claim or credit

**REQUIRED**: All commits and merges must reflect human authorship only. Keep commit messages focused on the technical changes and their purpose, without referencing any tools or assistants used to create them.

**Why this matters**: This project maintains human authorship integrity and avoids any implication that AI tools are co-authors or contributors to the codebase.

## README.md Implementation Progress Formatting

When updating the "Implementation Progress" section in README.md, use this specific format:

### Phase Structure:
Each phase should include:
1. **Phase title** with weeks and completion status (e.g., "✅ 100% Complete", "⏳ 20%", or "⏳")
2. **Phase description paragraph** copied from the corresponding phase in `planning/detailed_implementation_plan.md`
3. **Section bullet list** with numbered sections:
   - Use `✅` for completed sections
   - Use `[ ]` (unchecked markdown checkbox) for uncompleted sections
   - Format: `- ✅ **Section X.Y:** Section Name` or `- [ ] **Section X.Y:** Section Name`

### Example Format for Current State:
```markdown
### Phase 5: Advanced Chat-Focused TUI Interface (Weeks 15-17) ✅ 100% Complete

This phase implements a sophisticated chat-focused Terminal User Interface (TUI)...

- ✅ **Section 5.1:** Ratatui Foundation with TEA Architecture
- ✅ **Section 5.2:** Multi-Panel Chat Interface Layout
- ✅ **Section 5.3:** Interactive Chat System with Message Management
- ✅ **Section 5.4:** Focus Management and Navigation System
- ✅ **Section 5.5:** Context Awareness and Quick Actions
- ✅ **Section 5.6:** Rich Text Support and Syntax Highlighting

### Phase 6: Core AI Assistant Application Logic (Weeks 18-20) ⏳

This phase implements the core AI assistant engines that provide actual coding assistance...

- [ ] **Section 6.1:** Core AI Assistant Engines (CodeAnalyzer, GenerationEngine, ExplanationEngine)
- [ ] **Section 6.2:** Advanced AI Engines (RefactoringEngine, TestGenerator)
- [ ] **Section 6.3:** AI Assistant Coordinators (CodingAssistant, ConversationManager)
- [ ] **Section 6.4:** Enhanced CLI Integration with AI Commands
- [ ] **Section 6.5:** Prompt Templates and System Integration
```

### Special Notes for Phase 6:
- **Focus on Application Logic**: Phase 6 implements AI assistant engines, not UI components
- **Leverage Existing Infrastructure**: All AI engines should integrate with existing LLM coordination and context management
- **Document AI Capabilities**: Include specific examples of AI assistant functionality in progress updates
