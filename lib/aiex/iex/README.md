# Enhanced IEx Integration with AI

This directory contains modules that provide seamless AI integration within Elixir's Interactive Shell (IEx).

## Overview

The enhanced IEx integration brings AI-powered assistance directly into your development workflow, making it easy to get help, generate code, analyze patterns, and debug issues without leaving your IEx session.

## Quick Start

### 1. Setup IEx Configuration

Copy the provided template to your home directory:

```bash
cp priv/templates/iex.exs ~/.iex.exs
```

### 2. Start IEx with Aiex

```bash
iex -S mix
```

### 3. Use AI helpers

```elixir
# Quick AI assistance
iex> ai("explain GenServer.call")

# Start interactive AI shell
iex> ai_shell()

# Get code completions
iex> ai_complete("defmodule MyMod")

# Enhanced documentation
iex> ai_doc(GenServer)
```

## Available Modules

### Core Modules

- **`Aiex.IEx.Commands`** - Enhanced IEx commands with AI integration
- **`Aiex.IEx.Helpers`** - Distributed AI helpers for development
- **`Aiex.IEx.EnhancedHelpers`** - Advanced AI helpers with quick access
- **`Aiex.IEx.Integration`** - Integration utilities and setup

### Key Features

#### 1. Enhanced Commands

Standard IEx commands extended with AI capabilities:

```elixir
# AI-enhanced help
iex> h GenServer, :ai
# Shows standard docs + AI explanations + usage patterns

# Smart compilation with analysis
iex> c "lib/my_module.ex", :analyze
# Compiles + provides AI code quality insights

# AI-powered testing
iex> test MyModule, :generate
# Runs tests + generates missing test cases
```

#### 2. Quick AI Helpers

Convenient functions for immediate AI assistance:

```elixir
# General AI queries
iex> ai("how do I handle timeouts in GenServer?")

# Code completion
iex> ai_complete("def handle_call")

# Smart code evaluation
iex> ai_eval("Enum.map([1,2,3], &(&1 * 2))", explain: true)

# Debugging assistance
iex> ai_debug(pid)
iex> ai_debug({:error, :timeout}, context: "during API call")

# Project analysis
iex> ai_project(focus: :performance)
```

#### 3. Interactive AI Shell

Launch a full-featured AI shell from within IEx:

```elixir
iex> ai_shell()
# Enters interactive AI shell with enhanced capabilities

iex> ai_shell(project_dir: "/path/to/project")
# Shell with specific project context
```

#### 4. Enhanced Documentation

AI-powered documentation with insights:

```elixir
iex> ai_doc(GenServer)
# Standard docs + AI explanations + best practices

iex> ai_doc(MyModule.function)
# Function docs + usage patterns + examples
```

## Integration Modes

### 1. Standard IEx Session

Works in any IEx session when Aiex is available:

```elixir
iex> Aiex.IEx.Integration.load_helpers()
# Loads AI helpers into current session
```

### 2. Project-Specific IEx

Best experience when starting IEx with your project:

```bash
cd your_project
iex -S mix
# AI helpers automatically available with project context
```

### 3. Distributed IEx

Full cluster-aware AI assistance:

```bash
iex --name node1@localhost -S mix
# Connect additional nodes for distributed AI
```

## Configuration

### Environment Variables

```bash
# Enable debug logging for AI helpers
export RUST_LOG=debug

# Configure default AI model
export AIEX_DEFAULT_MODEL=gpt-4

# Set custom project directory
export AIEX_PROJECT_DIR=/path/to/project
```

### Application Configuration

In your `config/config.exs`:

```elixir
config :aiex, Aiex.IEx.Helpers,
  default_model: "gpt-4",
  max_completion_length: 200,
  distributed_timeout: 30_000,
  prefer_local_node: true

config :aiex, Aiex.CLI.InteractiveShell,
  auto_save: true,
  max_history: 100,
  show_context: true
```

## Advanced Usage

### Custom AI Workflows

```elixir
# Execute custom workflows from IEx
iex> ai("workflow code_review file:lib/my_module.ex")

# Chain AI operations
iex> ai_eval("""
  "lib/important.ex"
  |> ai_analyze()
  |> ai_refactor()
  |> ai_test_generate()
""")
```

### Cluster-Wide Analysis

```elixir
# Search across cluster nodes
iex> search("GenServer.call", :semantic)

# Analyze distributed patterns
iex> debug_cluster(:analyze)

# Find similar code across nodes
iex> search(MyModule, :similar)
```

### AI-Powered Debugging

```elixir
# Process debugging with AI
iex> ai_debug(pid, context: "user registration process")

# Error analysis
iex> ai_debug({:error, :noproc}, context: "after supervisor restart")

# Performance analysis
iex> debug_performance(:bottlenecks)
```

## Shortcuts and Aliases

When using the provided `.iex.exs` template, these shortcuts are available:

```elixir
# Quick access functions (from H module)
ai("query")           # -> EnhancedHelpers.ai("query")
shell()               # -> EnhancedHelpers.ai_shell()
complete("code")      # -> EnhancedHelpers.ai_complete("code")
eval("code")          # -> EnhancedHelpers.ai_eval("code")
debug(target)         # -> EnhancedHelpers.ai_debug(target)
status()              # -> Integration.check_ai_status()
help()                # -> Integration.show_ai_help()
```

## Troubleshooting

### Check AI System Status

```elixir
iex> Aiex.IEx.Integration.check_ai_status()
# Shows status of all AI components
```

### Common Issues

1. **AI helpers not available**
   ```elixir
   # Check if Aiex is loaded
   iex> Code.ensure_loaded?(Aiex)
   
   # Try manual loading
   iex> Aiex.IEx.Integration.load_helpers()
   ```

2. **Slow AI responses**
   ```elixir
   # Check cluster status
   iex> cluster_status()
   
   # Select optimal node
   iex> select_optimal_node(:completion)
   ```

3. **Context not available**
   ```elixir
   # Refresh distributed context
   iex> distributed_context("MyModule")
   
   # Check file context
   iex> ai_project()
   ```

## Examples

### Daily Development Workflow

```elixir
# Start your day
iex> ai_project()  # Get project overview
iex> status()      # Check AI systems

# During development
iex> ai("explain this pattern: with {:ok, data} <- fetch()")
iex> ai_complete("def process_payment")
iex> c "lib/payments.ex", :analyze

# Debugging issues
iex> ai_debug(pid, context: "payment processing")
iex> ai("why might GenServer.call timeout?")

# Before committing
iex> ai("workflow code_review")
iex> test MyModule, :analyze
```

### Learning Elixir

```elixir
# Understanding concepts
iex> ai("explain OTP supervision trees")
iex> ai_doc(GenServer, examples: true)

# Exploring patterns
iex> ai("show me different ways to handle errors in Elixir")
iex> search("error handling", :pattern)

# Getting examples
iex> ai("generate a simple GenServer example")
iex> ai_complete("defmodule MyServer")
```

## Integration with External Tools

The IEx helpers integrate seamlessly with:

- **Language Servers** - AI insights available in editors
- **CI/CD** - AI analysis in build pipelines  
- **Documentation** - AI-generated docs and examples
- **Testing** - AI-powered test generation and analysis

## Contributing

To extend the IEx integration:

1. Add new helper functions to `EnhancedHelpers`
2. Extend command capabilities in `Commands`
3. Update the integration module for new features
4. Add examples and documentation

The modular design makes it easy to add new AI-powered capabilities while maintaining backward compatibility.