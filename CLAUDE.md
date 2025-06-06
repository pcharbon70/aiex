# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Aiex is an Elixir-based coding assistant project in early development. The project aims to build a sophisticated AI-powered coding assistant that leverages Elixir's strengths in concurrency, fault tolerance, and distributed computing.

## Common Development Commands

### Build and Dependencies
- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project

### Testing
- `mix test` - Run all tests
- `mix test test/aiex_test.exs` - Run specific test file
- `mix test test/aiex_test.exs:5` - Run test at specific line

### Code Quality
- `mix format` - Format code according to Elixir standards
- `mix format --check-formatted` - Check if code is properly formatted

### Interactive Development
- `iex -S mix` - Start interactive Elixir shell with project loaded

## High-Level Architecture

The planned architecture (see `research/coding_agent_overview.md`) follows a supervision tree design with five main subsystems:

1. **CLI Interface** - Verb-noun command structure with progressive disclosure
2. **Context Management Engine** - Hybrid strategy combining summary-based compression and semantic chunking
3. **LLM Integration Layer** - Multi-provider support with adapter pattern
4. **File Operation Sandbox** - Security-focused file operations with path validation
5. **State Management System** - Event sourcing for auditability and session recovery

Key architectural principles:
- Actor model using GenServers for stateful components
- Process isolation for security boundaries
- Streaming operations for handling large codebases
- Supervision trees for fault tolerance

## Development Phases

The project follows a 20-week roadmap (see `planning/detailed_implementation_plan.md`):

- **Phase 1**: Core infrastructure, CLI framework, basic context engine
- **Phase 2**: Advanced context management, multi-LLM support, IEx integration
- **Phase 3**: State management, ExUnit integration, security features
- **Phase 4**: Performance optimization, distributed deployment, monitoring
- **Phase 5**: AI Response Intelligence & Comparison

## Key Implementation Details

- Uses ETS tables for fast in-memory storage with DETS for persistence
- Implements circuit breakers for LLM API calls
- Plans to use Rustler for Tree-sitter integration (semantic parsing)
- Event sourcing pattern for state management
- Hierarchical configuration system with TOML format

## Git Commit Guidelines

**IMPORTANT**: Do not include any references to coding LLMs or AI assistants in commit messages or merge messages. This includes but is not limited to:
- "Generated with Claude Code" or similar attribution
- "Co-Authored-By: Claude" or AI assistant credits
- Any mention of AI assistance in commit descriptions

Keep commit messages focused on the technical changes and their purpose, without referencing the tools or assistants used to create them.

## README.md Implementation Progress Formatting

When updating the "Implementation Progress" section in README.md, use this specific format:

### Phase Structure:
Each phase should include:
1. **Phase title** with weeks and completion status (e.g., "✅ 80% Complete" or "⏳")
2. **Phase description paragraph** copied from the corresponding phase in `planning/detailed_implementation_plan.md`
3. **Section bullet list** with numbered sections:
   - Use `✅` for completed sections
   - Use `[ ]` (unchecked markdown checkbox) for uncompleted sections
   - Format: `- ✅ **Section X.Y:** Section Name` or `- [ ] **Section X.Y:** Section Name`

### Example Format:
```markdown
### Phase 1: Core Infrastructure (Weeks 1-4) ✅ 80% Complete

This phase establishes the foundational architecture with robust CLI tooling...

- ✅ **Section 1.1:** CLI Framework and Command Structure
- [ ] **Section 1.2:** Context Management Engine Foundation
- [ ] **Section 1.3:** Sandboxed File Operations
- ✅ **Section 1.4:** Basic LLM Integration
- [ ] **Section 1.5:** Mix Task Integration
```

This format provides a clear overview that matches the detailed implementation plan while being readable in the README.