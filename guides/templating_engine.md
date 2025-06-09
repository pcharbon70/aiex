# Aiex Templating Engine Guide

The Aiex templating engine provides a powerful, flexible system for managing AI prompts and generating consistent, high-quality interactions with language models. This guide covers everything you need to know about using and extending the templating system.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Template Structure](#template-structure)
4. [Built-in Templates](#built-in-templates)
5. [Using Templates](#using-templates)
6. [Creating Custom Templates](#creating-custom-templates)
7. [Template Syntax](#template-syntax)
8. [Context Injection](#context-injection)
9. [Performance & Caching](#performance--caching)
10. [Best Practices](#best-practices)
11. [API Reference](#api-reference)
12. [Troubleshooting](#troubleshooting)

## Overview

The Aiex templating engine is a sophisticated system designed to:

- **Standardize AI prompts** across different operations (code analysis, generation, explanation, etc.)
- **Ensure consistency** in AI assistant interactions
- **Provide flexibility** for customization and extension
- **Optimize performance** through caching and validation
- **Support complex scenarios** with variable substitution and conditional logic

### Key Benefits

- **🎯 Consistency**: All AI operations use standardized, tested prompts
- **🚀 Performance**: Template compilation and caching for fast rendering
- **🔧 Flexibility**: Easy customization and extension of templates
- **📊 Quality**: Built-in validation and quality scoring
- **🎨 Rich Features**: Variable substitution, conditionals, and context injection

## Architecture

The templating system consists of four main components:

```elixir
┌─────────────────┐    ┌─────────────────┐
│ Template        │    │ Template        │
│ Registry        │◄──►│ Engine          │
└─────────────────┘    └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│ Template        │    │ Context         │
│ Compiler        │    │ Injector        │
└─────────────────┘    └─────────────────┘
```

### Components

1. **Template Registry** (`Aiex.LLM.Templates.TemplateRegistry`)
   - Central repository for all templates
   - Template discovery and selection
   - Inheritance and fallback management

2. **Template Engine** (`Aiex.LLM.Templates.TemplateEngine`)
   - Template rendering and variable substitution
   - Performance metrics and caching
   - Error handling and validation

3. **Template Compiler** (`Aiex.LLM.Templates.TemplateCompiler`)
   - Mustache-style template parsing
   - Template validation and optimization
   - AST generation and compilation

4. **Context Injector** (`Aiex.LLM.Templates.ContextInjector`)
   - Smart context management
   - Automatic context compression
   - Multi-layered context extraction

## Template Structure

Every template in Aiex follows a standardized structure:

```elixir
%{
  # Required fields
  name: "template name",
  description: "Template description",
  version: "1.0.0",
  category: :workflow | :operation | :conversation | :system,
  intent: :specific_intent,
  content: "Template content with {{variables}}",
  
  # Optional fields
  variables: [
    %{name: "var_name", type: :string, required: true}
  ],
  conditions: [
    %{name: "condition_name", expression: "var_expr", description: "..."}
  ],
  metadata: %{
    complexity: :low | :medium | :high,
    estimated_tokens: 1500,
    tags: ["coding", "analysis"]
  }
}
```

### Field Descriptions

- **name**: Human-readable template name
- **description**: Detailed description of template purpose
- **version**: Semantic version for template evolution
- **category**: High-level categorization of template type
- **intent**: Specific use case or operation type
- **content**: The actual template text with variable placeholders
- **variables**: List of required and optional variables
- **conditions**: Conditional logic for dynamic content
- **metadata**: Additional information for optimization and discovery

## Built-in Templates

Aiex comes with comprehensive built-in templates for common AI operations:

### Workflow Templates

These templates handle complete AI assistant workflows:

#### Implementation Template (`:workflow_implement_feature`)
```elixir
# Used for implementing new features
variables: [
  %{name: "feature_description", type: :string, required: true},
  %{name: "project_name", type: :string, required: false},
  %{name: "framework", type: :string, required: false},
  %{name: "existing_code", type: :string, required: false}
]
```

#### Bug Fix Template (`:workflow_fix_bug`)
```elixir
# Used for debugging and fixing issues
variables: [
  %{name: "bug_description", type: :string, required: true},
  %{name: "error_info", type: :string, required: false},
  %{name: "code_context", type: :string, required: true}
]
```

#### Refactoring Template (`:workflow_refactor_code`)
```elixir
# Used for code refactoring operations
variables: [
  %{name: "original_code", type: :string, required: true},
  %{name: "refactoring_goals", type: :string, required: true}
]
```

### Operation Templates

These templates handle specific code operations:

#### Code Analysis (`:operation_analyze`)
```elixir
# Analyzes code structure and patterns
variables: [
  %{name: "code_content", type: :string, required: true},
  %{name: "analysis_focus", type: :string, required: false}
]
```

#### Code Generation (`:operation_generate`)
```elixir
# Generates new code from specifications
variables: [
  %{name: "specification", type: :string, required: true},
  %{name: "context_info", type: :string, required: false}
]
```

#### Code Explanation (`:operation_explain`)
```elixir
# Explains existing code
variables: [
  %{name: "code_content", type: :string, required: true},
  %{name: "explanation_level", type: :string, required: false}
]
```

## Using Templates

### Basic Usage

The most common way to use templates is through the Template Engine:

```elixir
# Get a template
{:ok, template} = Aiex.LLM.Templates.TemplateRegistry.get_template(:operation_analyze)

# Prepare variables
variables = %{
  code_content: """
  defmodule Calculator do
    def add(a, b), do: a + b
  end
  """,
  analysis_focus: "performance and best practices"
}

# Render the template
{:ok, rendered_prompt} = Aiex.LLM.Templates.TemplateEngine.render_template(
  :operation_analyze,
  variables,
  %{} # additional context
)
```

### Template Selection

The registry can automatically select appropriate templates based on intent:

```elixir
# Select template by intent
{:ok, template_id} = Aiex.LLM.Templates.TemplateRegistry.select_template(
  :analyze, # intent
  %{language: "elixir", complexity: :medium} # context
)

# Use the selected template
{:ok, rendered} = Aiex.LLM.Templates.TemplateEngine.render_template(
  template_id,
  variables,
  context
)
```

### Integration with AI Engines

Templates are designed to integrate seamlessly with AI engines:

```elixir
defmodule MyAIEngine do
  def analyze_code(code_content, options \\ []) do
    # Select appropriate template
    {:ok, template_id} = TemplateRegistry.select_template(:analyze, %{
      language: detect_language(code_content),
      focus: Keyword.get(options, :focus)
    })
    
    # Prepare variables
    variables = %{
      code_content: code_content,
      analysis_focus: Keyword.get(options, :focus, "general analysis")
    }
    
    # Render template
    {:ok, prompt} = TemplateEngine.render_template(template_id, variables, %{})
    
    # Send to LLM
    LLM.ModelCoordinator.request(%{
      type: :completion,
      content: prompt,
      metadata: %{template_id: template_id}
    })
  end
end
```

## Creating Custom Templates

### Registering New Templates

You can register custom templates at runtime:

```elixir
# Define your custom template
custom_template = %{
  name: "Code Review Template",
  description: "Template for comprehensive code reviews",
  version: "1.0.0",
  category: :operation,
  intent: :code_review,
  content: """
  Please review the following {{language}} code:

  ```{{language}}
  {{code_content}}
  ```

  Focus areas:
  - Code quality and best practices
  - Performance considerations
  - Security implications
  {{#review_focus}}
  - {{review_focus}}
  {{/review_focus}}

  Provide detailed feedback with specific recommendations.
  """,
  variables: [
    %{name: "language", type: :string, required: true},
    %{name: "code_content", type: :string, required: true},
    %{name: "review_focus", type: :string, required: false}
  ],
  conditions: [
    %{name: "review_focus", expression: "review_focus", description: "Additional focus area"}
  ],
  metadata: %{
    complexity: :medium,
    estimated_tokens: 2000,
    tags: ["code-review", "quality"]
  }
}

# Register the template
{:ok, _state} = Aiex.LLM.Templates.TemplateRegistry.register_template(
  :custom_code_review,
  custom_template,
  []
)
```

### Template Files

For more complex templates, you can create template files:

```elixir
# priv/templates/my_template.exs
%{
  name: "Advanced Analysis Template",
  description: "Multi-layered code analysis with context awareness",
  version: "2.0.0",
  category: :operation,
  intent: :advanced_analysis,
  content: """
  # Advanced Code Analysis

  ## Code Under Review
  ```{{language}}
  {{code_content}}
  ```

  ## Analysis Parameters
  - **Language**: {{language}}
  - **Complexity Level**: {{complexity_level}}
  - **Project Context**: {{project_context}}

  ## Analysis Requirements
  {{#performance_focus}}
  ### Performance Analysis
  Focus on performance bottlenecks and optimization opportunities.
  {{/performance_focus}}

  {{#security_focus}}
  ### Security Review
  Identify potential security vulnerabilities and risks.
  {{/security_focus}}

  {{#maintainability_focus}}
  ### Maintainability Assessment
  Evaluate code maintainability and technical debt.
  {{/maintainability_focus}}

  Provide a comprehensive analysis covering all requested aspects.
  """,
  variables: [
    %{name: "language", type: :string, required: true},
    %{name: "code_content", type: :string, required: true},
    %{name: "complexity_level", type: :string, required: false},
    %{name: "project_context", type: :string, required: false}
  ],
  conditions: [
    %{name: "performance_focus", expression: "performance_focus", description: "Include performance analysis"},
    %{name: "security_focus", expression: "security_focus", description: "Include security review"},
    %{name: "maintainability_focus", expression: "maintainability_focus", description: "Include maintainability assessment"}
  ],
  metadata: %{
    complexity: :high,
    estimated_tokens: 3500,
    tags: ["analysis", "comprehensive", "multi-layered"]
  }
}
```

Load template files:

```elixir
# Load from file
{:ok, template} = Aiex.LLM.Templates.TemplateRegistry.load_template_from_file(
  "priv/templates/my_template.exs"
)

# Register loaded template
{:ok, _state} = Aiex.LLM.Templates.TemplateRegistry.register_template(
  :advanced_analysis,
  template,
  []
)
```

## Template Syntax

Aiex uses a Mustache-inspired syntax for variable substitution and conditional logic:

### Variable Substitution

```mustache
{{variable_name}}
```

Variables are replaced with their corresponding values from the variables map.

### Conditional Sections

```mustache
{{#condition_name}}
Content shown when condition is true
{{/condition_name}}
```

Conditional sections are displayed only when the condition evaluates to a truthy value.

### Advanced Examples

```mustache
# Basic variable substitution
Hello {{name}}, welcome to {{platform}}!

# Conditional content
{{#has_errors}}
## Errors Found
The following errors were detected:
{{error_list}}
{{/has_errors}}

{{#no_errors}}
## No Issues Found
The code looks good!
{{/no_errors}}

# Nested structure
{{#project_context}}
## Project Information
- **Name**: {{project_name}}
- **Framework**: {{framework}}
- **Version**: {{version}}
{{/project_context}}
```

### Variable Types

Templates support different variable types:

- **`:string`** - Text content
- **`:integer`** - Numeric values
- **`:boolean`** - True/false values
- **`:list`** - Arrays of items
- **`:map`** - Structured data

```elixir
variables: [
  %{name: "title", type: :string, required: true},
  %{name: "count", type: :integer, required: false},
  %{name: "enabled", type: :boolean, required: false},
  %{name: "items", type: :list, required: false},
  %{name: "config", type: :map, required: false}
]
```

## Context Injection

The Context Injector automatically provides additional context to templates:

### Automatic Context

```elixir
# The system automatically injects:
context = %{
  # Project information
  project_name: "MyApp",
  language: "elixir",
  framework: "phoenix",
  
  # File context
  file_path: "lib/my_app/user.ex",
  file_type: "elixir",
  
  # User preferences
  code_style: "consistent",
  explanation_level: "intermediate",
  
  # Technical context
  testing_framework: "exunit",
  build_tool: "mix"
}
```

### Manual Context

You can also provide explicit context:

```elixir
custom_context = %{
  optimization_level: "aggressive",
  target_audience: "senior_developers",
  include_examples: true,
  max_complexity: :high
}

{:ok, rendered} = TemplateEngine.render_template(
  :operation_analyze,
  variables,
  custom_context
)
```

### Context Layers

Context is organized in layers (highest to lowest priority):

1. **Explicit context** - Manually provided
2. **Request context** - From current request
3. **Session context** - From user session
4. **Project context** - From project analysis
5. **Default context** - System defaults

## Performance & Caching

The templating engine includes several performance optimizations:

### Template Compilation

Templates are compiled once and cached:

```elixir
# First render - compiles template
{:ok, result1} = TemplateEngine.render_template(:my_template, vars1, ctx1)

# Subsequent renders - uses compiled version
{:ok, result2} = TemplateEngine.render_template(:my_template, vars2, ctx2)
```

### Render Caching

Frequently used template + variable combinations are cached:

```elixir
# Configure caching
config :aiex, :template_engine,
  cache_enabled: true,
  cache_ttl: 300_000,  # 5 minutes
  max_cache_size: 1000
```

### Performance Metrics

The engine tracks performance metrics:

```elixir
# Get performance metrics
metrics = Aiex.LLM.Templates.TemplateEngine.get_metrics()

# Example output:
%{
  total_renders: 1543,
  cache_hits: 892,
  cache_hit_rate: 0.578,
  average_render_time: 12.3,
  compilation_count: 45
}
```

## Best Practices

### Template Design

1. **Keep templates focused** - One template per specific operation
2. **Use descriptive names** - Clear, unambiguous template names
3. **Document variables** - Include descriptions for all variables
4. **Test thoroughly** - Validate templates with various inputs

### Variable Management

```elixir
# Good: Clear, typed variables
variables: [
  %{name: "code_content", type: :string, required: true, description: "The code to analyze"},
  %{name: "focus_area", type: :string, required: false, description: "Specific analysis focus"}
]

# Avoid: Unclear, untyped variables
variables: [
  %{name: "input", type: :string, required: true},
  %{name: "opts", type: :string, required: false}
]
```

### Content Guidelines

1. **Be specific** - Clear instructions and requirements
2. **Use structured format** - Headings, lists, code blocks
3. **Include examples** - Show expected output format
4. **Handle edge cases** - Account for missing or invalid data

### Error Handling

```elixir
# Always handle template errors gracefully
case TemplateEngine.render_template(template_id, variables, context) do
  {:ok, rendered} ->
    # Use rendered template
    process_with_llm(rendered)
    
  {:error, :template_not_found} ->
    # Fall back to default template
    render_with_fallback(variables, context)
    
  {:error, :missing_variables} ->
    # Request additional information
    request_missing_variables()
    
  {:error, reason} ->
    # Log error and provide user feedback
    Logger.error("Template rendering failed: #{inspect(reason)}")
    {:error, "Template processing error"}
end
```

## API Reference

### Template Registry

```elixir
# Get template
{:ok, template} = TemplateRegistry.get_template(template_id)

# Register template
{:ok, state} = TemplateRegistry.register_template(id, template_data, opts)

# Select template by intent
{:ok, template_id} = TemplateRegistry.select_template(intent, context)

# List all templates
templates = TemplateRegistry.list_templates()

# List by category
workflow_templates = TemplateRegistry.list_templates(:workflow)
```

### Template Engine

```elixir
# Render template
{:ok, result} = TemplateEngine.render_template(template_id, variables, context)

# Render with options
{:ok, result} = TemplateEngine.render_template(
  template_id,
  variables,
  context,
  cache: false,
  validate: true
)

# Get metrics
metrics = TemplateEngine.get_metrics()

# Clear cache
:ok = TemplateEngine.clear_cache()
```

### Template Compiler

```elixir
# Compile template
{:ok, compiled} = TemplateCompiler.compile(template_data)

# Validate template
{:ok, validation_result} = TemplateCompiler.validate(template_data)

# Parse template content
{:ok, ast} = TemplateCompiler.parse_template_content(content)
```

## Troubleshooting

### Common Issues

#### Template Not Found
```
{:error, :template_not_found}
```
**Solution**: Verify template ID and ensure template is registered.

#### Missing Variables
```
{:error, {:missing_variables, ["variable_name"]}}
```
**Solution**: Provide all required variables in the variables map.

#### Invalid Template Structure
```
{:error, {:invalid_template_structure, errors}}
```
**Solution**: Check template structure matches required fields.

#### Compilation Errors
```
{:error, {:compilation_error, reason}}
```
**Solution**: Validate template syntax, especially Mustache expressions.

### Debugging

Enable debug logging:

```elixir
# In config.exs
config :logger, level: :debug

# Or at runtime
Logger.configure(level: :debug)
```

Check template validation:

```elixir
# Validate template before registration
case TemplateValidator.validate_template(template_data) do
  {:ok, _} -> 
    IO.puts("Template is valid")
  {:error, errors} -> 
    IO.inspect(errors, label: "Validation errors")
end
```

### Performance Issues

If templates are rendering slowly:

1. **Check template complexity** - Simplify overly complex templates
2. **Enable caching** - Ensure template caching is enabled
3. **Monitor metrics** - Use performance metrics to identify bottlenecks
4. **Optimize variables** - Reduce variable processing overhead

### Memory Issues

For high-volume usage:

```elixir
# Configure cache limits
config :aiex, :template_engine,
  max_cache_size: 500,
  cache_cleanup_interval: 60_000
```

## Advanced Features

### Template Inheritance

Templates can extend other templates:

```elixir
base_template = %{
  name: "Base Analysis",
  content: "Base analysis content",
  # ... other fields
}

extended_template = %{
  name: "Extended Analysis", 
  extends: :base_analysis,  # Inherits from base
  content: "{{> base_analysis}}\n\nAdditional analysis...",
  # ... additional fields
}
```

### Dynamic Template Selection

Implement custom selection logic:

```elixir
defmodule CustomTemplateSelector do
  def select_template(intent, context) do
    case {intent, context} do
      {:analyze, %{language: "elixir", complexity: :high}} ->
        {:ok, :advanced_elixir_analysis}
      {:analyze, %{language: "elixir"}} ->
        {:ok, :standard_elixir_analysis}
      {:analyze, _} ->
        {:ok, :generic_analysis}
      _ ->
        {:error, :no_matching_template}
    end
  end
end
```

### Template Versioning

Manage template evolution:

```elixir
# Version 1.0
old_template = %{
  name: "Analysis v1",
  version: "1.0.0",
  # ... template definition
}

# Version 2.0 with migration
new_template = %{
  name: "Analysis v2", 
  version: "2.0.0",
  migration_from: ["1.0.0"],
  # ... updated template definition
}
```

This comprehensive guide covers all aspects of the Aiex templating engine. For additional examples and advanced use cases, check the test files in `test/aiex/llm/templates/` and the built-in templates in the `TemplateRegistry` module.