# AI Provider Support Guide

## Overview

Aiex implements a sophisticated multi-provider LLM integration system that supports both cloud-based and local AI providers. The system provides intelligent coordination, automatic failover, rate limiting, and unified response processing across different providers. This architecture ensures high availability, cost optimization, and flexibility for diverse deployment scenarios.

## Table of Contents

1. [Supported Providers](#supported-providers)
2. [Architecture Overview](#architecture-overview)
3. [ModelCoordinator](#modelcoordinator)
4. [Provider Adapters](#provider-adapters)
5. [Rate Limiting](#rate-limiting)
6. [Template System](#template-system)
7. [Response Processing](#response-processing)
8. [Configuration Management](#configuration-management)
9. [Health Monitoring](#health-monitoring)
10. [Development Patterns](#development-patterns)
11. [Testing Strategies](#testing-strategies)
12. [Troubleshooting](#troubleshooting)

## Supported Providers

Aiex supports four different LLM providers, each optimized for specific use cases:

### Cloud Providers

**Anthropic (Claude)**
- **Models**: Claude-3 (Opus, Sonnet, Haiku), Claude-2.1, Claude-2.0, Claude-instant-1.2
- **Best For**: Code analysis, explanation, high-quality reasoning
- **Rate Limits**: 50 requests/minute, 100,000 tokens/minute
- **Features**: System message support, cost estimation, streaming responses

**OpenAI (GPT)**
- **Models**: GPT-4 variants, GPT-3.5-turbo variants
- **Best For**: Code generation, general purpose tasks
- **Rate Limits**: 60 requests/minute, 90,000 tokens/minute
- **Features**: Function calling, extensive model selection, robust API

### Local Providers

**Ollama**
- **Models**: Dynamic discovery of locally installed models
- **Best For**: Privacy-focused deployment, offline operation
- **Rate Limits**: None (local processing)
- **Features**: No API costs, full control, extended inference time

**LM Studio**
- **Models**: HuggingFace models with OpenAI-compatible API
- **Best For**: Custom model deployment, development testing
- **Rate Limits**: None (local processing)
- **Features**: Quantization support, model metadata extraction

## Architecture Overview

### System Design

```
┌─────────────────────────────────────────────────────────────┐
│                   Interface Layer                           │
│         (CLI, TUI, LSP, Future LiveView)                   │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│                  LLM Client                                │
│           (Unified Request Interface)                       │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│                ModelCoordinator                             │
│        (Distributed Provider Selection)                     │
└─────────────────────────────────────────────────────────────┘
                            │
    ┌───────────────────────┼───────────────────────┐
    │                       │                       │
┌───▼────┐ ┌──────▼─────┐ ┌─▼──────┐ ┌─────▼─────┐
│Anthropic│ │   OpenAI   │ │ Ollama │ │ LM Studio │
│Adapter  │ │  Adapter   │ │Adapter │ │ Adapter   │
└────────┘ └────────────┘ └────────┘ └───────────┘
```

### Key Components

1. **LLM Client**: Unified interface for all provider interactions
2. **ModelCoordinator**: Intelligent provider selection and load balancing
3. **Rate Limiter**: Per-provider rate limiting and token management
4. **Template Engine**: Prompt template management and context injection
5. **Response Parser**: Structured response processing across providers
6. **Health Monitor**: Circuit breakers and provider health tracking

## ModelCoordinator

The `Aiex.LLM.ModelCoordinator` serves as the central orchestrator for all LLM interactions:

### Provider Selection Strategies

```elixir
# Random selection for load distribution
ModelCoordinator.request_completion(prompt, %{strategy: :random})

# Round-robin for balanced usage
ModelCoordinator.request_completion(prompt, %{strategy: :round_robin})

# Load-balanced selection based on performance metrics
ModelCoordinator.request_completion(prompt, %{strategy: :load_balanced})

# Local affinity for privacy-focused scenarios
ModelCoordinator.request_completion(prompt, %{strategy: :local_affinity})

# Specific provider selection
ModelCoordinator.request_completion(prompt, %{provider: :anthropic})
```

### Distributed Coordination

The ModelCoordinator uses OTP process groups for cluster-wide coordination:

```elixir
defmodule Aiex.LLM.ModelCoordinator do
  use GenServer

  @coordinator_group :llm_coordinators

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Join coordinator process group
    :pg.join(@coordinator_group, self())
    
    # Subscribe to health events
    EventBus.subscribe(:llm_health)
    
    # Initialize provider tracking
    providers = load_configured_providers()
    
    state = %{
      providers: providers,
      health_status: %{},
      request_count: 0,
      last_selection: nil
    }

    {:ok, state}
  end

  def request_completion(prompt, opts \\ %{}) do
    case get_coordinator() do
      {:ok, coordinator} ->
        GenServer.call(coordinator, {:completion, prompt, opts})
      
      {:error, :no_coordinator} ->
        # Fall back to direct provider call
        direct_provider_request(prompt, opts)
    end
  end

  defp get_coordinator do
    case :pg.get_members(@coordinator_group) do
      [] -> {:error, :no_coordinator}
      [coordinator | _] -> {:ok, coordinator}
      coordinators -> {:ok, select_coordinator(coordinators)}
    end
  end
end
```

### Context Integration

The coordinator integrates with the context system for intelligent provider selection:

```elixir
def handle_call({:completion, prompt, opts}, _from, state) do
  # Get context for enhanced provider selection
  context = get_request_context(opts)
  
  # Select optimal provider based on context
  provider = select_provider(state.providers, context, opts)
  
  # Compress context if needed
  compressed_context = Context.Compressor.compress_for_llm(context)
  
  # Execute request with selected provider
  result = execute_with_provider(provider, prompt, compressed_context, opts)
  
  # Update provider statistics
  new_state = update_provider_stats(state, provider, result)
  
  {:reply, result, new_state}
end

defp select_provider(providers, context, opts) do
  strategy = Map.get(opts, :strategy, :load_balanced)
  
  case strategy do
    :load_balanced ->
      select_by_performance(providers, context)
    
    :local_affinity ->
      select_local_first(providers)
    
    :cost_optimized ->
      select_by_cost(providers, context)
    
    :round_robin ->
      select_round_robin(providers)
    
    :random ->
      Enum.random(healthy_providers(providers))
  end
end
```

## Provider Adapters

Each provider adapter implements a common behavior while handling provider-specific details:

### Adapter Behavior

```elixir
defmodule Aiex.LLM.Adapter do
  @callback completion(prompt :: String.t(), opts :: map()) :: 
    {:ok, map()} | {:error, term()}
  
  @callback health_check() :: :healthy | :unhealthy | {:error, term()}
  
  @callback get_models() :: {:ok, [String.t()]} | {:error, term()}
  
  @callback estimate_cost(prompt :: String.t(), response :: String.t()) :: 
    {:ok, float()} | {:error, term()}
  
  @callback rate_limits() :: %{requests_per_minute: integer(), tokens_per_minute: integer()}
end
```

### Anthropic Adapter Implementation

```elixir
defmodule Aiex.LLM.Adapters.Anthropic do
  @behaviour Aiex.LLM.Adapter

  @base_url "https://api.anthropic.com/v1"
  @models %{
    "claude-3-opus-20240229" => %{cost_per_1k_tokens: %{input: 0.015, output: 0.075}},
    "claude-3-sonnet-20240229" => %{cost_per_1k_tokens: %{input: 0.003, output: 0.015}},
    "claude-3-haiku-20240307" => %{cost_per_1k_tokens: %{input: 0.00025, output: 0.00125}}
  }

  def completion(prompt, opts \\ %{}) do
    model = Map.get(opts, :model, "claude-3-sonnet-20240229")
    max_tokens = Map.get(opts, :max_tokens, 1000)
    
    # Handle system message separately (Anthropic requirement)
    {system_message, user_message} = extract_system_message(prompt)
    
    request_body = %{
      model: model,
      max_tokens: max_tokens,
      system: system_message,
      messages: [%{role: "user", content: user_message}]
    }

    case make_api_request("/messages", request_body) do
      {:ok, response} ->
        parse_anthropic_response(response)
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  def health_check do
    case make_api_request("/messages", %{
      model: "claude-3-haiku-20240307",
      max_tokens: 1,
      messages: [%{role: "user", content: "Hi"}]
    }) do
      {:ok, _} -> :healthy
      {:error, _} -> :unhealthy
    end
  end

  def estimate_cost(prompt, response) do
    model = get_current_model()
    input_tokens = count_tokens(prompt)
    output_tokens = count_tokens(response)
    
    pricing = @models[model][:cost_per_1k_tokens]
    
    input_cost = (input_tokens / 1000) * pricing.input
    output_cost = (output_tokens / 1000) * pricing.output
    
    {:ok, input_cost + output_cost}
  end

  def rate_limits do
    %{requests_per_minute: 50, tokens_per_minute: 100_000}
  end

  defp make_api_request(endpoint, body) do
    headers = [
      {"Content-Type", "application/json"},
      {"x-api-key", get_api_key()},
      {"anthropic-version", "2023-06-01"}
    ]

    url = @base_url <> endpoint
    json_body = Jason.encode!(body)

    case HTTPoison.post(url, json_body, headers, timeout: 30_000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}
      
      {:ok, %{status_code: status, body: body}} ->
        {:error, %{status: status, body: Jason.decode!(body)}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### OpenAI Adapter Implementation

```elixir
defmodule Aiex.LLM.Adapters.OpenAI do
  @behaviour Aiex.LLM.Adapter

  @base_url "https://api.openai.com/v1"
  @models %{
    "gpt-4" => %{cost_per_1k_tokens: %{input: 0.03, output: 0.06}},
    "gpt-4-turbo" => %{cost_per_1k_tokens: %{input: 0.01, output: 0.03}},
    "gpt-3.5-turbo" => %{cost_per_1k_tokens: %{input: 0.0015, output: 0.002}}
  }

  def completion(prompt, opts \\ %{}) do
    model = Map.get(opts, :model, "gpt-4-turbo")
    max_tokens = Map.get(opts, :max_tokens, 1000)
    temperature = Map.get(opts, :temperature, 0.7)
    
    messages = format_messages(prompt, opts)
    
    request_body = %{
      model: model,
      messages: messages,
      max_tokens: max_tokens,
      temperature: temperature
    }

    case make_api_request("/chat/completions", request_body) do
      {:ok, response} ->
        parse_openai_response(response)
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  def health_check do
    case make_api_request("/models", %{}) do
      {:ok, _} -> :healthy
      {:error, _} -> :unhealthy
    end
  end

  defp format_messages(prompt, opts) do
    case Map.get(opts, :system_message) do
      nil ->
        [%{role: "user", content: prompt}]
      
      system_message ->
        [
          %{role: "system", content: system_message},
          %{role: "user", content: prompt}
        ]
    end
  end

  defp make_api_request(endpoint, body) do
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{get_api_key()}"}
    ]

    url = @base_url <> endpoint
    json_body = Jason.encode!(body)

    case HTTPoison.post(url, json_body, headers, timeout: 30_000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}
      
      {:ok, %{status_code: 429, headers: headers}} ->
        # Handle rate limiting with retry-after
        retry_after = get_retry_after(headers)
        {:error, {:rate_limited, retry_after}}
      
      {:ok, %{status_code: status, body: body}} ->
        {:error, %{status: status, body: Jason.decode!(body)}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### Local Provider Adapters

**Ollama Adapter** for local model support:

```elixir
defmodule Aiex.LLM.Adapters.Ollama do
  @behaviour Aiex.LLM.Adapter

  @base_url Application.get_env(:aiex, :ollama_url, "http://localhost:11434")

  def completion(prompt, opts \\ %{}) do
    model = Map.get(opts, :model, get_default_model())
    
    request_body = %{
      model: model,
      prompt: prompt,
      stream: false,
      options: %{
        temperature: Map.get(opts, :temperature, 0.7),
        num_predict: Map.get(opts, :max_tokens, 1000)
      }
    }

    case make_api_request("/api/generate", request_body) do
      {:ok, response} ->
        {:ok, %{content: response["response"], model: model}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_models do
    case make_api_request("/api/tags", %{}) do
      {:ok, %{"models" => models}} ->
        model_names = Enum.map(models, & &1["name"])
        {:ok, model_names}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  def health_check do
    case make_api_request("/api/tags", %{}) do
      {:ok, _} -> :healthy
      {:error, _} -> :unhealthy
    end
  end

  def estimate_cost(_prompt, _response) do
    # Local models have no API cost
    {:ok, 0.0}
  end

  def rate_limits do
    # No rate limits for local models
    %{requests_per_minute: :unlimited, tokens_per_minute: :unlimited}
  end

  defp get_default_model do
    case get_models() do
      {:ok, [model | _]} -> model
      _ -> "llama2"  # Fallback
    end
  end
end
```

## Rate Limiting

The `Aiex.LLM.RateLimiter` provides per-provider rate limiting using the Hammer library:

### Implementation

```elixir
defmodule Aiex.LLM.RateLimiter do
  use GenServer

  @provider_limits %{
    anthropic: %{requests_per_minute: 50, tokens_per_minute: 100_000},
    openai: %{requests_per_minute: 60, tokens_per_minute: 90_000},
    ollama: %{requests_per_minute: :unlimited, tokens_per_minute: :unlimited},
    lm_studio: %{requests_per_minute: :unlimited, tokens_per_minute: :unlimited}
  }

  def check_rate_limit(provider, tokens \\ 0) do
    GenServer.call(__MODULE__, {:check_rate_limit, provider, tokens})
  end

  def get_rate_limit_status(provider) do
    GenServer.call(__MODULE__, {:get_status, provider})
  end

  def handle_call({:check_rate_limit, provider, tokens}, _from, state) do
    limits = get_provider_limits(provider)
    
    case limits do
      %{requests_per_minute: :unlimited} ->
        {:reply, :ok, state}
      
      %{requests_per_minute: rpm, tokens_per_minute: tpm} ->
        # Check request rate limit
        case check_request_limit(provider, rpm) do
          :ok ->
            # Check token rate limit
            case check_token_limit(provider, tokens, tpm) do
              :ok -> {:reply, :ok, state}
              {:error, reason} -> {:reply, {:error, reason}, state}
            end
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  defp check_request_limit(provider, rpm) do
    bucket_id = "requests:#{provider}"
    
    case Hammer.check_rate(bucket_id, 60_000, rpm) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :request_rate_exceeded}
    end
  end

  defp check_token_limit(provider, tokens, tpm) do
    bucket_id = "tokens:#{provider}"
    
    case Hammer.check_rate(bucket_id, 60_000, tpm) do
      {:allow, current_count} ->
        if current_count + tokens <= tpm do
          # Record token usage
          Hammer.check_rate(bucket_id, 60_000, tpm, tokens)
          :ok
        else
          {:error, :token_rate_exceeded}
        end
      
      {:deny, _limit} ->
        {:error, :token_rate_exceeded}
    end
  end

  def get_rate_limit_status(provider) do
    limits = get_provider_limits(provider)
    
    case limits do
      %{requests_per_minute: :unlimited} ->
        %{
          requests: %{current: 0, limit: :unlimited, remaining: :unlimited},
          tokens: %{current: 0, limit: :unlimited, remaining: :unlimited}
        }
      
      %{requests_per_minute: rpm, tokens_per_minute: tpm} ->
        request_bucket = "requests:#{provider}"
        token_bucket = "tokens:#{provider}"
        
        {:ok, {request_count, _}} = Hammer.inspect_bucket(request_bucket, 60_000, rpm)
        {:ok, {token_count, _}} = Hammer.inspect_bucket(token_bucket, 60_000, tpm)
        
        %{
          requests: %{
            current: request_count,
            limit: rpm,
            remaining: max(0, rpm - request_count)
          },
          tokens: %{
            current: token_count,
            limit: tpm,
            remaining: max(0, tpm - token_count)
          }
        }
    end
  end
end
```

### Usage Patterns

```elixir
# Check before making request
case RateLimiter.check_rate_limit(:anthropic, estimated_tokens) do
  :ok ->
    # Proceed with request
    make_llm_request(provider, prompt)
  
  {:error, :request_rate_exceeded} ->
    # Handle request rate limit
    schedule_retry_after_cooldown()
  
  {:error, :token_rate_exceeded} ->
    # Handle token rate limit
    reduce_prompt_size_or_retry()
end

# Monitor current usage
status = RateLimiter.get_rate_limit_status(:openai)
# %{
#   requests: %{current: 45, limit: 60, remaining: 15},
#   tokens: %{current: 75000, limit: 90000, remaining: 15000}
# }
```

## Template System

The template system provides structured prompt management with context injection:

### Template Definition

```elixir
defmodule Aiex.LLM.Templates.CodeAnalysisTemplate do
  use Aiex.LLM.Templates.Template

  def template do
    %Template{
      id: :code_analysis,
      name: "Code Analysis Template",
      category: :engine,
      variables: [
        variable("code", :string, required: true, description: "The code to analyze"),
        variable("language", :string, default: "elixir", description: "Programming language"),
        variable("context", :map, description: "Additional context information"),
        variable("analysis_type", :string, default: "general", 
               enum: ["general", "performance", "security", "maintainability"])
      ],
      conditionals: [
        conditional("has_tests", "length(get_in(context, [:test_files]) || []) > 0"),
        conditional("large_file", "String.length(code) > 1000")
      ],
      content: """
      {{#system}}
      You are an expert {{language}} developer. Analyze the provided code with focus on {{analysis_type}} aspects.
      {{#has_tests}}The codebase includes test files for reference.{{/has_tests}}
      {{#large_file}}This is a large file, focus on the most critical issues.{{/large_file}}
      {{/system}}

      Please analyze this {{language}} code:

      ```{{language}}
      {{code}}
      ```

      {{#context}}
      Additional context:
      {{#context.project_structure}}Project structure: {{context.project_structure}}{{/context.project_structure}}
      {{#context.dependencies}}Dependencies: {{context.dependencies}}{{/context.dependencies}}
      {{/context}}

      Provide analysis focusing on:
      1. Code quality and structure
      2. Potential issues or improvements
      3. Best practices compliance
      {{#has_tests}}4. Test coverage insights{{/has_tests}}
      """
    }
  end
end
```

### Template Engine Usage

```elixir
# Register template
TemplateEngine.register_template(CodeAnalysisTemplate.template())

# Render with context
result = TemplateEngine.render(:code_analysis, %{
  code: file_content,
  language: "elixir",
  analysis_type: "performance",
  context: %{
    project_structure: project_info,
    test_files: test_file_list
  }
})

case result do
  {:ok, rendered_prompt} ->
    # Use rendered prompt with LLM
    LLM.Client.completion(rendered_prompt)
  
  {:error, reason} ->
    # Handle template error
    Logger.error("Template rendering failed: #{inspect(reason)}")
end
```

### Context Injection

The `ContextInjector` automatically enriches templates with project context:

```elixir
defmodule Aiex.LLM.Templates.ContextInjector do
  def inject_context(template, user_variables, session_id) do
    # Get project context
    project_context = Context.Manager.get_project_context(session_id)
    
    # Get code analysis cache
    analysis_cache = Context.DistributedEngine.get_analysis_cache(session_id)
    
    # Merge contexts
    enhanced_variables = Map.merge(user_variables, %{
      project_context: project_context,
      recent_analysis: analysis_cache,
      session_info: get_session_info(session_id)
    })
    
    # Apply context-aware variable transformations
    transformed_variables = transform_variables(enhanced_variables, template)
    
    {:ok, transformed_variables}
  end

  defp transform_variables(variables, template) do
    Enum.reduce(template.variables, variables, fn var, acc ->
      case var.context_injection do
        nil -> acc
        injection_rule -> apply_injection_rule(acc, var.name, injection_rule)
      end
    end)
  end
end
```

## Response Processing

The `ResponseParser` provides structured parsing for different response types:

### Parser Implementation

```elixir
defmodule Aiex.LLM.ResponseParser do
  def parse_response(content, type \\ :general) do
    case type do
      :code_generation -> parse_code_generation(content)
      :code_explanation -> parse_code_explanation(content)
      :test_generation -> parse_test_generation(content)
      :documentation -> parse_documentation(content)
      :general -> parse_general(content)
    end
  end

  defp parse_code_generation(content) do
    # Extract code blocks with language detection
    code_blocks = extract_code_blocks(content)
    
    # Validate syntax for known languages
    validated_blocks = Enum.map(code_blocks, &validate_code_block/1)
    
    # Extract explanatory text
    explanation = extract_explanation(content, code_blocks)
    
    %{
      type: :code_generation,
      code_blocks: validated_blocks,
      explanation: explanation,
      language: detect_primary_language(code_blocks)
    }
  end

  defp parse_code_explanation(content) do
    # Parse sections and subsections
    sections = parse_markdown_sections(content)
    
    # Extract code references
    code_references = extract_code_references(content)
    
    # Identify key concepts
    concepts = extract_concepts(content)
    
    %{
      type: :code_explanation,
      sections: sections,
      code_references: code_references,
      concepts: concepts,
      summary: extract_summary(sections)
    }
  end

  defp extract_code_blocks(content) do
    ~r/```(\w+)?\n(.*?)\n```/s
    |> Regex.scan(content, capture: :all_but_first)
    |> Enum.map(fn
      [language, code] -> %{language: language, code: String.trim(code)}
      [code] -> %{language: "text", code: String.trim(code)}
    end)
  end

  defp validate_code_block(%{language: "elixir", code: code} = block) do
    case Code.string_to_quoted(code) do
      {:ok, _ast} -> 
        Map.put(block, :valid, true)
      {:error, reason} -> 
        Map.merge(block, %{valid: false, error: reason})
    end
  end

  defp validate_code_block(block) do
    # For non-Elixir code, perform basic validation
    Map.put(block, :valid, String.length(block.code) > 0)
  end

  defp parse_markdown_sections(content) do
    ~r/^(#{1,6})\s+(.+)$/m
    |> Regex.scan(content, capture: :all_but_first)
    |> Enum.map(fn [level, title] ->
      %{
        level: String.length(level),
        title: String.trim(title),
        content: extract_section_content(content, title)
      }
    end)
  end
end
```

### Usage Examples

```elixir
# Parse code generation response
{:ok, llm_response} = LLM.Client.completion(generation_prompt)
parsed = ResponseParser.parse_response(llm_response.content, :code_generation)

case parsed do
  %{code_blocks: [%{code: code, valid: true, language: "elixir"}]} ->
    # Use generated code
    File.write!("generated_module.ex", code)
  
  %{code_blocks: blocks} ->
    # Handle validation errors
    invalid_blocks = Enum.filter(blocks, &(!&1.valid))
    Logger.warn("Generated code has validation errors: #{inspect(invalid_blocks)}")
end

# Parse explanation response
{:ok, explanation_response} = LLM.Client.completion(explanation_prompt)
parsed = ResponseParser.parse_response(explanation_response.content, :code_explanation)

%{
  sections: sections,
  concepts: concepts,
  summary: summary
} = parsed

# Display structured explanation
Enum.each(sections, fn section ->
  IO.puts("#{String.duplicate("#", section.level)} #{section.title}")
  IO.puts(section.content)
end)
```

## Configuration Management

Secure configuration management with encryption for sensitive data:

### Configuration Structure

```elixir
defmodule Aiex.LLM.Config do
  use GenServer

  @default_config %{
    anthropic: %{
      api_key: nil,
      base_url: "https://api.anthropic.com/v1",
      default_model: "claude-3-sonnet-20240229",
      rate_limits: %{requests_per_minute: 50, tokens_per_minute: 100_000}
    },
    openai: %{
      api_key: nil,
      base_url: "https://api.openai.com/v1",
      default_model: "gpt-4-turbo",
      rate_limits: %{requests_per_minute: 60, tokens_per_minute: 90_000}
    },
    ollama: %{
      base_url: "http://localhost:11434",
      default_model: nil,  # Auto-detected
      rate_limits: %{requests_per_minute: :unlimited, tokens_per_minute: :unlimited}
    },
    lm_studio: %{
      base_url: "http://localhost:1234/v1",
      default_model: nil,  # Auto-detected
      rate_limits: %{requests_per_minute: :unlimited, tokens_per_minute: :unlimited}
    }
  }

  def get_provider_config(provider) do
    GenServer.call(__MODULE__, {:get_config, provider})
  end

  def set_provider_config(provider, config) do
    GenServer.call(__MODULE__, {:set_config, provider, config})
  end

  def validate_config(provider, config) do
    case provider do
      :anthropic -> validate_anthropic_config(config)
      :openai -> validate_openai_config(config)
      :ollama -> validate_ollama_config(config)
      :lm_studio -> validate_lm_studio_config(config)
    end
  end

  defp validate_anthropic_config(config) do
    with {:ok, _} <- validate_api_key(config.api_key, "sk-ant-"),
         {:ok, _} <- validate_url(config.base_url),
         {:ok, _} <- validate_model(config.default_model, :anthropic) do
      :ok
    else
      error -> error
    end
  end

  defp validate_api_key(nil, _prefix), do: {:error, :missing_api_key}
  defp validate_api_key(key, prefix) when is_binary(key) do
    if String.starts_with?(key, prefix) do
      :ok
    else
      {:error, {:invalid_api_key_format, prefix}}
    end
  end

  # Secure API key storage with encryption
  defp encrypt_api_key(api_key) when is_binary(api_key) do
    key = get_encryption_key()
    :crypto.crypto_one_time(:aes_256_gcm, key, generate_iv(), api_key, true)
  end

  defp decrypt_api_key(encrypted_key) do
    key = get_encryption_key()
    :crypto.crypto_one_time(:aes_256_gcm, key, extract_iv(encrypted_key), encrypted_key, false)
  end
end
```

### Environment Integration

```elixir
# config/config.exs
config :aiex, :llm,
  providers: [
    anthropic: [
      api_key: {:system, "ANTHROPIC_API_KEY"},
      default_model: "claude-3-sonnet-20240229"
    ],
    openai: [
      api_key: {:system, "OPENAI_API_KEY"},
      default_model: "gpt-4-turbo"
    ],
    ollama: [
      base_url: {:system, "OLLAMA_URL", "http://localhost:11434"}
    ],
    lm_studio: [
      base_url: {:system, "LM_STUDIO_URL", "http://localhost:1234/v1"}
    ]
  ],
  default_provider: :anthropic,
  fallback_providers: [:openai, :ollama],
  request_timeout: 30_000

# Load configuration with environment variable resolution
defmodule Aiex.LLM.ConfigLoader do
  def load_config do
    base_config = Application.get_env(:aiex, :llm, %{})
    
    resolved_config = resolve_environment_variables(base_config)
    
    # Validate all provider configurations
    validated_config = validate_all_providers(resolved_config)
    
    {:ok, validated_config}
  end

  defp resolve_environment_variables(config) do
    Enum.into(config, %{}, fn {key, value} ->
      {key, resolve_value(value)}
    end)
  end

  defp resolve_value({:system, env_var}), do: System.get_env(env_var)
  defp resolve_value({:system, env_var, default}), do: System.get_env(env_var, default)
  defp resolve_value(value), do: value
end
```

## Health Monitoring

Comprehensive health monitoring with circuit breakers:

### Health Monitor Implementation

```elixir
defmodule Aiex.LLM.HealthMonitor do
  use GenServer

  @health_check_interval 30_000  # 30 seconds
  @circuit_breaker_threshold 5    # failures before opening circuit
  @circuit_breaker_timeout 60_000 # 1 minute

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_provider_health(provider) do
    GenServer.call(__MODULE__, {:get_health, provider})
  end

  def get_cluster_health do
    GenServer.call(__MODULE__, :get_cluster_health)
  end

  def init(_opts) do
    # Schedule initial health check
    Process.send_after(self(), :health_check, 1000)
    
    # Subscribe to LLM events for real-time monitoring
    EventBus.subscribe(:llm_request)
    EventBus.subscribe(:llm_response)
    EventBus.subscribe(:llm_error)

    state = %{
      provider_health: %{},
      circuit_breakers: %{},
      metrics: %{},
      last_check: DateTime.utc_now()
    }

    {:ok, state}
  end

  def handle_info(:health_check, state) do
    # Check all configured providers
    providers = get_configured_providers()
    
    health_results = check_all_providers(providers)
    
    # Update circuit breaker states
    updated_circuit_breakers = update_circuit_breakers(
      state.circuit_breakers, 
      health_results
    )
    
    # Broadcast health updates
    broadcast_health_updates(health_results)
    
    # Schedule next check
    Process.send_after(self(), :health_check, @health_check_interval)
    
    new_state = %{state |
      provider_health: health_results,
      circuit_breakers: updated_circuit_breakers,
      last_check: DateTime.utc_now()
    }

    {:noreply, new_state}
  end

  def handle_info({:event, %{type: :llm_error, provider: provider, error: error}}, state) do
    # Track errors for circuit breaker logic
    updated_state = record_provider_error(state, provider, error)
    {:noreply, updated_state}
  end

  def handle_info({:event, %{type: :llm_response, provider: provider, duration: duration}}, state) do
    # Track successful responses and performance metrics
    updated_state = record_provider_success(state, provider, duration)
    {:noreply, updated_state}
  end

  defp check_all_providers(providers) do
    providers
    |> Task.async_stream(fn provider ->
      {provider, check_provider_health(provider)}
    end, timeout: 10_000)
    |> Enum.into(%{}, fn {:ok, {provider, health}} -> {provider, health} end)
  end

  defp check_provider_health(provider) do
    adapter = get_provider_adapter(provider)
    
    start_time = System.monotonic_time(:millisecond)
    
    case adapter.health_check() do
      :healthy ->
        response_time = System.monotonic_time(:millisecond) - start_time
        %{
          status: :healthy,
          response_time: response_time,
          last_check: DateTime.utc_now(),
          error: nil
        }
      
      :unhealthy ->
        %{
          status: :unhealthy,
          response_time: nil,
          last_check: DateTime.utc_now(),
          error: :health_check_failed
        }
      
      {:error, reason} ->
        %{
          status: :error,
          response_time: nil,
          last_check: DateTime.utc_now(),
          error: reason
        }
    end
  end

  defp update_circuit_breakers(circuit_breakers, health_results) do
    Enum.into(health_results, circuit_breakers, fn {provider, health} ->
      current_state = Map.get(circuit_breakers, provider, %{
        state: :closed,
        failure_count: 0,
        last_failure: nil
      })

      new_state = case health.status do
        :healthy ->
          # Reset circuit breaker on successful health check
          %{current_state | state: :closed, failure_count: 0}
        
        status when status in [:unhealthy, :error] ->
          new_failure_count = current_state.failure_count + 1
          
          if new_failure_count >= @circuit_breaker_threshold do
            %{current_state | 
              state: :open,
              failure_count: new_failure_count,
              last_failure: DateTime.utc_now()
            }
          else
            %{current_state | 
              failure_count: new_failure_count,
              last_failure: DateTime.utc_now()
            }
          end
      end

      {provider, new_state}
    end)
  end

  def is_circuit_open?(provider) do
    case GenServer.call(__MODULE__, {:get_circuit_state, provider}) do
      %{state: :open, last_failure: last_failure} ->
        # Check if circuit should transition to half-open
        time_since_failure = DateTime.diff(DateTime.utc_now(), last_failure, :millisecond)
        
        if time_since_failure >= @circuit_breaker_timeout do
          # Transition to half-open
          GenServer.cast(__MODULE__, {:set_circuit_state, provider, :half_open})
          false
        else
          true
        end
      
      %{state: state} ->
        state == :open
      
      nil ->
        false
    end
  end
end
```

### Circuit Breaker Usage

```elixir
defmodule Aiex.LLM.Client do
  def completion(prompt, opts \\ %{}) do
    provider = get_provider(opts)
    
    # Check circuit breaker before making request
    case HealthMonitor.is_circuit_open?(provider) do
      true ->
        # Circuit is open, try fallback provider
        try_fallback_provider(prompt, opts, provider)
      
      false ->
        # Circuit is closed or half-open, proceed with request
        make_request_with_monitoring(provider, prompt, opts)
    end
  end

  defp make_request_with_monitoring(provider, prompt, opts) do
    start_time = System.monotonic_time(:millisecond)
    
    # Publish request start event
    EventBus.publish(:llm_request, %{
      provider: provider,
      prompt_length: String.length(prompt),
      timestamp: DateTime.utc_now()
    })

    case make_provider_request(provider, prompt, opts) do
      {:ok, response} ->
        # Record successful request
        duration = System.monotonic_time(:millisecond) - start_time
        
        EventBus.publish(:llm_response, %{
          provider: provider,
          duration: duration,
          response_length: String.length(response.content),
          timestamp: DateTime.utc_now()
        })
        
        {:ok, response}
      
      {:error, reason} ->
        # Record failed request
        EventBus.publish(:llm_error, %{
          provider: provider,
          error: reason,
          timestamp: DateTime.utc_now()
        })
        
        {:error, reason}
    end
  end

  defp try_fallback_provider(prompt, opts, failed_provider) do
    fallback_providers = get_fallback_providers(failed_provider)
    
    case fallback_providers do
      [] ->
        {:error, {:no_providers_available, failed_provider}}
      
      [fallback | remaining] ->
        case completion(prompt, Map.put(opts, :provider, fallback)) do
          {:ok, response} ->
            Logger.info("Successfully used fallback provider #{fallback} after #{failed_provider} failure")
            {:ok, response}
          
          {:error, _reason} ->
            # Try next fallback
            try_fallback_provider(prompt, opts, fallback_providers: remaining)
        end
    end
  end
end
```

## Development Patterns

### Adding a New Provider

To add support for a new LLM provider:

1. **Create the Adapter Module**:

```elixir
defmodule Aiex.LLM.Adapters.NewProvider do
  @behaviour Aiex.LLM.Adapter

  def completion(prompt, opts \\ %{}) do
    # Implement provider-specific completion logic
  end

  def health_check do
    # Implement health check
  end

  def get_models do
    # Return available models
  end

  def estimate_cost(prompt, response) do
    # Calculate cost based on provider pricing
  end

  def rate_limits do
    # Return provider rate limits
  end
end
```

2. **Register the Provider**:

```elixir
# In ModelCoordinator initialization
defp load_configured_providers do
  %{
    anthropic: Aiex.LLM.Adapters.Anthropic,
    openai: Aiex.LLM.Adapters.OpenAI,
    ollama: Aiex.LLM.Adapters.Ollama,
    lm_studio: Aiex.LLM.Adapters.LMStudio,
    new_provider: Aiex.LLM.Adapters.NewProvider  # Add here
  }
end
```

3. **Add Configuration**:

```elixir
# config/config.exs
config :aiex, :llm,
  providers: [
    # ... existing providers
    new_provider: [
      api_key: {:system, "NEW_PROVIDER_API_KEY"},
      base_url: "https://api.newprovider.com/v1",
      default_model: "new-provider-model"
    ]
  ]
```

4. **Add Rate Limiting**:

```elixir
# In RateLimiter
@provider_limits %{
  # ... existing limits
  new_provider: %{requests_per_minute: 100, tokens_per_minute: 200_000}
}
```

### Custom Selection Strategies

Implement custom provider selection logic:

```elixir
defmodule Aiex.LLM.SelectionStrategies.CustomStrategy do
  def select_provider(providers, context, opts) do
    cond do
      # Prefer local providers for sensitive code
      contains_sensitive_data?(context) ->
        select_local_provider(providers)
      
      # Use fastest provider for quick tasks
      is_quick_task?(opts) ->
        select_fastest_provider(providers)
      
      # Use cost-effective provider for large tasks
      is_large_task?(context) ->
        select_cheapest_provider(providers)
      
      true ->
        select_default_provider(providers)
    end
  end

  defp contains_sensitive_data?(context) do
    # Check for API keys, passwords, etc.
    content = get_context_content(context)
    Regex.match?(~r/(api[_-]?key|password|secret|token)/i, content)
  end

  defp is_quick_task?(opts) do
    Map.get(opts, :max_tokens, 1000) < 500
  end

  defp is_large_task?(context) do
    content_size = get_context_size(context)
    content_size > 10_000  # Large context
  end
end

# Register custom strategy
defmodule Aiex.LLM.ModelCoordinator do
  @selection_strategies %{
    random: &select_random/3,
    round_robin: &select_round_robin/3,
    load_balanced: &select_load_balanced/3,
    local_affinity: &select_local_affinity/3,
    custom: &Aiex.LLM.SelectionStrategies.CustomStrategy.select_provider/3
  }
end
```

## Testing Strategies

### Provider Adapter Testing

```elixir
defmodule Aiex.LLM.Adapters.AnthropicTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  test "successful completion request" do
    # Mock HTTP response
    expect(HTTPoison.Mock, :post, fn _url, _body, _headers, _opts ->
      {:ok, %{
        status_code: 200,
        body: Jason.encode!(%{
          content: [%{text: "Test response"}],
          model: "claude-3-sonnet-20240229",
          usage: %{input_tokens: 10, output_tokens: 5}
        })
      }}
    end)

    # Test completion
    result = Anthropic.completion("Test prompt", %{model: "claude-3-sonnet-20240229"})
    
    assert {:ok, %{content: "Test response"}} = result
  end

  test "rate limit handling" do
    expect(HTTPoison.Mock, :post, fn _url, _body, _headers, _opts ->
      {:ok, %{
        status_code: 429,
        headers: [{"retry-after", "60"}],
        body: Jason.encode!(%{error: %{message: "Rate limit exceeded"}})
      }}
    end)

    result = Anthropic.completion("Test prompt")
    
    assert {:error, {:rate_limited, 60}} = result
  end

  test "health check" do
    expect(HTTPoison.Mock, :post, fn _url, _body, _headers, _opts ->
      {:ok, %{status_code: 200, body: Jason.encode!(%{content: [%{text: "Hi"}]})}}
    end)

    assert :healthy = Anthropic.health_check()
  end
end
```

### ModelCoordinator Testing

```elixir
defmodule Aiex.LLM.ModelCoordinatorTest do
  use ExUnit.Case

  setup do
    # Start test coordinator with mock providers
    {:ok, _} = start_supervised({ModelCoordinator, test_mode: true})
    
    # Mock provider responses
    Mox.stub_with(MockAnthropicAdapter, MockProviderBehavior)
    Mox.stub_with(MockOpenAIAdapter, MockProviderBehavior)
    
    :ok
  end

  test "provider selection strategies" do
    # Test random selection
    result1 = ModelCoordinator.request_completion("test", %{strategy: :random})
    assert {:ok, _} = result1

    # Test load balanced selection
    result2 = ModelCoordinator.request_completion("test", %{strategy: :load_balanced})
    assert {:ok, _} = result2

    # Test local affinity
    result3 = ModelCoordinator.request_completion("test", %{strategy: :local_affinity})
    assert {:ok, _} = result3
  end

  test "fallback on provider failure" do
    # Mock first provider to fail
    expect(MockAnthropicAdapter, :completion, fn _prompt, _opts ->
      {:error, :service_unavailable}
    end)

    # Mock second provider to succeed
    expect(MockOpenAIAdapter, :completion, fn _prompt, _opts ->
      {:ok, %{content: "Fallback response"}}
    end)

    result = ModelCoordinator.request_completion("test", %{
      provider: :anthropic,
      fallback_providers: [:openai]
    })

    assert {:ok, %{content: "Fallback response"}} = result
  end
end
```

### Integration Testing

```elixir
defmodule Aiex.LLM.IntegrationTest do
  use ExUnit.Case

  @tag :integration
  test "end-to-end LLM request flow" do
    # This test requires actual API keys for real providers
    prompt = "Write a simple hello world function in Elixir"
    
    result = Aiex.LLM.Client.completion(prompt, %{
      provider: :anthropic,
      max_tokens: 100
    })

    case result do
      {:ok, response} ->
        assert is_binary(response.content)
        assert String.contains?(response.content, "def")
        
        # Test response parsing
        parsed = ResponseParser.parse_response(response.content, :code_generation)
        assert %{code_blocks: [%{language: "elixir", valid: true}]} = parsed
      
      {:error, reason} ->
        # Log error for debugging but don't fail test if API is unavailable
        Logger.warn("Integration test skipped due to: #{inspect(reason)}")
    end
  end

  @tag :integration
  test "provider failover in real scenario" do
    # Test with invalid API key to trigger failover
    old_config = Application.get_env(:aiex, :llm)
    
    # Set invalid config for primary provider
    Application.put_env(:aiex, :llm, %{
      providers: %{
        anthropic: %{api_key: "invalid-key"},
        openai: %{api_key: System.get_env("OPENAI_API_KEY")}
      },
      fallback_providers: [:openai]
    })

    try do
      result = Aiex.LLM.Client.completion("Hello world", %{provider: :anthropic})
      
      # Should succeed with fallback provider
      assert {:ok, _response} = result
    after
      # Restore original config
      Application.put_env(:aiex, :llm, old_config)
    end
  end
end
```

## Troubleshooting

### Common Issues and Solutions

#### Rate Limiting Issues

**Problem**: Requests failing with rate limit errors

```elixir
# Check current rate limit status
status = RateLimiter.get_rate_limit_status(:anthropic)
IO.inspect(status)
# %{
#   requests: %{current: 50, limit: 50, remaining: 0},
#   tokens: %{current: 95000, limit: 100000, remaining: 5000}
# }

# Solution: Implement exponential backoff
defmodule RateLimitHandler do
  def with_backoff(provider, request_fn, max_retries \\ 3) do
    do_with_backoff(provider, request_fn, max_retries, 1)
  end

  defp do_with_backoff(_provider, _request_fn, 0, _attempt) do
    {:error, :max_retries_exceeded}
  end

  defp do_with_backoff(provider, request_fn, retries_left, attempt) do
    case request_fn.() do
      {:error, :rate_limited} ->
        delay = calculate_backoff_delay(attempt)
        Logger.info("Rate limited, backing off for #{delay}ms")
        Process.sleep(delay)
        do_with_backoff(provider, request_fn, retries_left - 1, attempt + 1)
      
      result ->
        result
    end
  end

  defp calculate_backoff_delay(attempt) do
    # Exponential backoff with jitter
    base_delay = :math.pow(2, attempt) * 1000
    jitter = :rand.uniform(1000)
    trunc(base_delay + jitter)
  end
end
```

#### Provider Health Issues

**Problem**: Provider showing as unhealthy

```elixir
# Check provider health
health = HealthMonitor.get_provider_health(:anthropic)
IO.inspect(health)

case health.status do
  :unhealthy ->
    # Check network connectivity
    case :httpc.request(:get, {'https://api.anthropic.com', []}, [], []) do
      {:ok, {{_version, 200, _reason_phrase}, _headers, _body}} ->
        Logger.info("Network connectivity OK, check API key")
      
      {:error, reason} ->
        Logger.error("Network connectivity issue: #{inspect(reason)}")
    end
  
  :error ->
    Logger.error("Provider error: #{inspect(health.error)}")
    
    # Try manual health check
    case Anthropic.health_check() do
      :healthy -> Logger.info("Manual health check passed")
      error -> Logger.error("Manual health check failed: #{inspect(error)}")
    end
end
```

#### Circuit Breaker Issues

**Problem**: Circuit breaker stuck in open state

```elixir
# Check circuit breaker status
circuit_state = HealthMonitor.get_circuit_state(:anthropic)
IO.inspect(circuit_state)

# Force circuit reset if needed
defmodule CircuitBreakerUtils do
  def force_reset_circuit(provider) do
    GenServer.cast(HealthMonitor, {:force_reset_circuit, provider})
    Logger.info("Forced circuit reset for #{provider}")
  end

  def get_circuit_diagnostics(provider) do
    health = HealthMonitor.get_provider_health(provider)
    circuit = HealthMonitor.get_circuit_state(provider)
    
    %{
      health_status: health.status,
      circuit_state: circuit.state,
      failure_count: circuit.failure_count,
      last_failure: circuit.last_failure,
      time_since_failure: time_since_failure(circuit.last_failure)
    }
  end

  defp time_since_failure(nil), do: :never
  defp time_since_failure(timestamp) do
    DateTime.diff(DateTime.utc_now(), timestamp, :millisecond)
  end
end
```

#### Configuration Issues

**Problem**: Provider configuration errors

```elixir
# Validate all provider configurations
defmodule ConfigDiagnostics do
  def diagnose_provider_configs do
    providers = [:anthropic, :openai, :ollama, :lm_studio]
    
    Enum.map(providers, fn provider ->
      config = Config.get_provider_config(provider)
      validation_result = Config.validate_config(provider, config)
      
      %{
        provider: provider,
        config: config,
        valid: validation_result == :ok,
        error: if(validation_result != :ok, do: validation_result)
      }
    end)
  end

  def fix_common_issues(provider) do
    case provider do
      :anthropic ->
        check_anthropic_config()
      
      :openai ->
        check_openai_config()
      
      provider when provider in [:ollama, :lm_studio] ->
        check_local_provider(provider)
    end
  end

  defp check_anthropic_config do
    api_key = System.get_env("ANTHROPIC_API_KEY")
    
    cond do
      is_nil(api_key) ->
        "ANTHROPIC_API_KEY environment variable not set"
      
      not String.starts_with?(api_key, "sk-ant-") ->
        "Invalid Anthropic API key format (should start with 'sk-ant-')"
      
      true ->
        "Configuration appears valid"
    end
  end

  defp check_local_provider(provider) do
    config = Config.get_provider_config(provider)
    
    case :httpc.request(:get, {config.base_url, []}, [], []) do
      {:ok, _} ->
        "Local provider is running and accessible"
      
      {:error, reason} ->
        "Cannot connect to local provider: #{inspect(reason)}"
    end
  end
end
```

### Debugging Tools

**Provider Performance Analysis**:

```elixir
defmodule ProviderAnalytics do
  def analyze_provider_performance(days \\ 7) do
    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -days * 24 * 3600, :second)
    
    # Gather metrics from event store
    events = EventStore.get_events_by_time_range(start_time, end_time)
    
    events
    |> Enum.filter(fn event -> event.type in [:llm_request, :llm_response, :llm_error] end)
    |> Enum.group_by(fn event -> event.data.provider end)
    |> Enum.map(fn {provider, provider_events} ->
      analyze_provider_events(provider, provider_events)
    end)
  end

  defp analyze_provider_events(provider, events) do
    requests = Enum.filter(events, &(&1.type == :llm_request))
    responses = Enum.filter(events, &(&1.type == :llm_response))
    errors = Enum.filter(events, &(&1.type == :llm_error))
    
    total_requests = length(requests)
    successful_requests = length(responses)
    failed_requests = length(errors)
    
    avg_response_time = if successful_requests > 0 do
      total_time = responses |> Enum.map(& &1.data.duration) |> Enum.sum()
      total_time / successful_requests
    else
      0
    end

    %{
      provider: provider,
      total_requests: total_requests,
      successful_requests: successful_requests,
      failed_requests: failed_requests,
      success_rate: if(total_requests > 0, do: successful_requests / total_requests, else: 0),
      average_response_time: avg_response_time,
      error_types: Enum.frequencies_by(errors, & &1.data.error)
    }
  end
end
```

## Best Practices Summary

### Provider Integration Guidelines

1. **Implement the Adapter Behavior**: Always implement all required callbacks
2. **Handle Rate Limits Gracefully**: Respect provider rate limits and implement retry logic
3. **Validate Configurations**: Ensure proper validation for all provider settings
4. **Monitor Health Continuously**: Implement comprehensive health checking
5. **Plan for Failures**: Design fallback strategies for provider outages

### Performance Guidelines

1. **Use Circuit Breakers**: Protect against cascading failures
2. **Implement Caching**: Cache responses where appropriate to reduce API calls
3. **Optimize Context Size**: Compress context to stay within token limits
4. **Monitor Costs**: Track token usage and costs across providers
5. **Load Balance Intelligently**: Consider provider capabilities for task assignment

### Security Guidelines

1. **Encrypt API Keys**: Never store API keys in plaintext
2. **Validate Inputs**: Sanitize prompts and responses
3. **Use Local Providers for Sensitive Code**: Keep sensitive data on-premises
4. **Audit All Requests**: Log all LLM interactions for security analysis
5. **Implement Access Controls**: Restrict provider access based on user roles

The Aiex AI Provider Support system provides a robust, scalable foundation for multi-provider LLM integration. By following these patterns and practices, you can build reliable AI applications that gracefully handle provider failures, optimize costs, and maintain high performance across diverse deployment scenarios.