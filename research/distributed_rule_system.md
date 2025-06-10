# Design patterns and implementation approaches for distributed rule system in Elixir/OTP AI code assistant

This research provides concrete design recommendations for integrating a distributed rule system into your Elixir/OTP-based AI code assistant, addressing all specified requirements while leveraging existing distributed architecture components.

## Rule organization and markdown structure

The system should adopt a hierarchical directory structure inspired by successful implementations from Cursor and GitHub Copilot:

```
.ai-rules/                          # Configurable root directory
├── 00-global/                      # Global project rules (highest priority)
│   ├── coding-standards.md
│   └── security-guidelines.md
├── 10-languages/                   # Language-specific rules
│   ├── elixir/
│   │   ├── general.md
│   │   ├── otp-patterns.md
│   │   └── phoenix.md
│   └── sql/
│       └── postgres.md
├── 20-frameworks/                  # Framework-specific rules
│   ├── phoenix/
│   └── ecto/
└── 30-contexts/                    # Context-specific rules
    ├── api-development.md
    └── liveview-components.md
```

Each rule file should use **YAML frontmatter** for metadata:

```yaml
---
description: "Phoenix LiveView component standards"
version: "1.0"
priority: 8                         # Higher number = higher priority
scope: ["project", "framework"]     # Rule application scope
language: ["elixir"]
tags: ["phoenix", "liveview", "components"]
globs: ["lib/**/live/**/*.ex"]      # File pattern matching
alwaysApply: false                  # Auto-inclusion behavior
created: 2025-01-01
updated: 2025-06-10
---
```

## Mnesia schema design for distributed storage

The system should implement a **multi-table architecture** optimized for the 95% single-node, 5% distributed usage pattern:

### Core tables structure

```elixir
# Main rules table with comprehensive indexing
:mnesia.create_table(:rules, [
  {:attributes, [:id, :scope, :language, :priority, :metadata, 
                 :content, :version, :created_at, :updated_at, :status]},
  {:disc_copies, [node()]},         # RAM + disk for performance
  {:type, :set},                    # Unique keys
  {:index, [:scope, :language, :priority, :status]}  # Secondary indexes
])

# Event sourcing table for rule changes
:mnesia.create_table(:rule_events, [
  {:attributes, [:event_id, :rule_id, :event_type, :data, :version, 
                 :timestamp, :causation_id, :correlation_id]},
  {:disc_only_copies, [node()]},    # Append-only, disk storage
  {:type, :ordered_set},            # Ordered by event_id
  {:index, [:rule_id, :timestamp, :event_type]}
])

# High-performance cache table
:mnesia.create_table(:rule_cache, [
  {:ram_copies, all_nodes()},       # Memory-only for speed
  {:attributes, [:key, :value, :ttl]},
  {:type, :set}
])
```

For distributed scenarios, the system should implement **adaptive replication**:

```elixir
defmodule RuleStore do
  def setup_adaptive_storage do
    case get_cluster_size() do
      1 -> create_single_node_tables()
      size when size <= 3 -> create_replicated_tables(all_nodes())
      _ -> create_selective_replication()
    end
  end
end
```

## Rule discovery and aggregation patterns

The system should leverage the emerging **usage_rules** tool pattern combined with a **GenServer-based aggregation architecture**:

```elixir
defmodule RuleAggregator do
  use GenServer
  
  def aggregate_rules(sources) do
    sources
    |> Enum.map(&load_rules_from_source/1)
    |> merge_rules_with_priority()
    |> cache_in_ets()
  end
  
  defp merge_rules_with_priority(rule_sets) do
    # Priority order (highest to lowest):
    # 1. User rules
    # 2. Project rules  
    # 3. Framework rules
    # 4. Dependency rules
    # 5. Default rules
  end
end
```

## Context injection strategies for LLM prompts

The system should implement a **pipeline-based context builder** with intelligent rule prioritization:

```elixir
defmodule PromptContextBuilder do
  def build_context(request, opts \\ []) do
    %{
      system_rules: load_system_rules(),
      project_context: extract_project_context(request),
      file_context: get_file_context(request.file_path),
      dependency_rules: get_dependency_rules(),
      user_preferences: load_user_rules()
    }
    |> filter_relevant_rules(request)
    |> prioritize_rules()
    |> compress_for_token_limit(opts[:max_tokens])
    |> format_for_llm()
  end
end
```

### Template-based injection pattern

```elixir
defmodule PromptTemplate do
  def render(rules, context) do
    """
    You are an expert Elixir developer working on a #{context.project_type} project.
    
    ## Project Rules
    #{format_rules(rules.project)}
    
    ## Framework Guidelines  
    #{format_rules(rules.framework)}
    
    ## Code Context
    Current file: #{context.file_path}
    #{context.surrounding_code}
    
    ## Task
    #{context.user_request}
    """
  end
end
```

## Performance optimization with caching

The system should implement a **multi-layer caching strategy**:

### ETS-based primary cache
```elixir
defmodule RuleCache do
  def start_link do
    :ets.new(:rule_cache, [:set, :protected, :named_table, 
                          {:read_concurrency, true}])
  end
  
  def get_rules(scope) do
    case :ets.lookup(:rule_cache, scope) do
      [{^scope, rules}] -> rules
      [] -> load_and_cache_rules(scope)
    end
  end
end
```

### Performance characteristics
- ETS lookups: ~0.1-1 microseconds
- Mnesia transactions: ~1-10 milliseconds
- Distributed calls via :pg: ~100-1000 microseconds

## Integration with existing architecture

### Context.Manager integration
```elixir
defmodule Context.Manager.RuleExtension do
  def enrich_context(context) do
    relevant_rules = RuleSystem.get_relevant_rules(context)
    
    context
    |> Map.put(:rules, relevant_rules)
    |> Map.update(:metadata, %{}, &Map.put(&1, :rule_version, get_rule_version()))
  end
end
```

### Semantic chunker compatibility
```elixir
defmodule RuleAwareChunker do
  def chunk_with_rules(content, rules) do
    chunking_strategy = determine_strategy_from_rules(rules)
    
    content
    |> TextChunker.chunk(chunking_strategy)
    |> enrich_chunks_with_rule_metadata(rules)
  end
end
```

### Multi-LLM coordination with pg process groups
```elixir
defmodule LLMPool.RuleAwareCoordinator do
  def route_request_with_rules(request, rules) do
    llm_type = determine_llm_type(request, rules)
    
    case :pg.get_local_members({:llm_pool, llm_type}) do
      [] -> :pg.get_members({:llm_pool, llm_type}) |> List.first()
      local_members -> select_by_rule_affinity(local_members, rules)
    end
    |> send_request(request)
  end
end
```

## Configuration system for enabling/disabling features

Implement a **runtime configuration system** with feature flags:

```elixir
# config/runtime.exs
config :rule_system,
  enabled: System.get_env("RULE_SYSTEM_ENABLED", "true") == "true",
  sources: [
    {:file, ".ai-rules"},
    {:dependency, :usage_rules},
    {:mnesia, :rules_table}
  ],
  cache_ttl: 300,
  auto_reload: true

# Feature flag implementation
defmodule RuleSystem.FeatureFlags do
  def rule_enabled?(rule_id) do
    case :ets.lookup(:feature_flags, {:rule, rule_id}) do
      [{_, enabled}] -> enabled
      [] -> Application.get_env(:rule_system, :enabled, true)
    end
  end
end
```

## Rule validation and testing approaches

### Property-based testing with StreamData
```elixir
property "rule transformations preserve semantics" do
  check all original_rule <- rule_generator() do
    transformed = RuleTransformer.apply(original_rule)
    assert semantically_equivalent?(original_rule, transformed)
  end
end
```

### Integration testing pattern
```elixir
defmodule RuleSystemIntegrationTest do
  use ExUnit.Case
  
  setup do
    # Start supervised rule system
    start_supervised!(RuleSystem.Supervisor)
    :ok
  end
  
  test "distributed rule synchronization" do
    # Test Mnesia replication
    rule = create_test_rule()
    assert {:ok, _} = RuleStore.write(rule)
    assert {:ok, ^rule} = RuleStore.read(rule.id)
  end
end
```

## Supervision tree structure

```elixir
defmodule RuleSystem.Supervisor do
  use Supervisor
  
  def init(_init_arg) do
    children = [
      {RuleCache, []},                              # ETS cache manager
      {RuleStore, []},                              # Mnesia interface
      {RuleAggregator, []},                         # Rule aggregation
      {RuleEventProcessor, []},                     # Event sourcing
      {DynamicSupervisor, 
       strategy: :one_for_one, 
       name: RuleSystem.DynamicSupervisor}         # Dynamic rule workers
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## Key implementation recommendations

1. **Start with single-node Mnesia** using `disc_copies` and add distribution features incrementally
2. **Use ETS for hot path caching** with Mnesia as the persistent store
3. **Implement rule versioning** using event sourcing for auditability
4. **Leverage the usage_rules package** for dependency rule management
5. **Design for graceful degradation** - system should work without rules
6. **Monitor performance metrics** - track cache hit rates, rule evaluation times
7. **Use property-based testing** for rule validation logic
8. **Implement circuit breakers** for rule evaluation failures

This architecture provides a robust, scalable foundation that integrates seamlessly with your existing distributed OTP application while maintaining flexibility for future enhancements.
