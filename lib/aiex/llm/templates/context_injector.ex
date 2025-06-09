defmodule Aiex.LLM.Templates.ContextInjector do
  @moduledoc """
  Handles context injection into prompt templates.
  
  Features:
  - Multi-layered context management
  - Smart context compression and chunking
  - Context relevance scoring
  - Dynamic context selection
  - Context caching and optimization
  """
  
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.LLM.Templates.{Template, TemplateCompiler}
  
  defstruct [
    :context_layers,
    :compression_config,
    :relevance_weights,
    :cache,
    :performance_metrics
  ]
  
  @type context_layer :: %{
    name: atom(),
    priority: integer(),
    extractor: function(),
    compressor: function() | nil,
    max_size_tokens: integer()
  }
  
  @type injection_config :: %{
    max_total_tokens: integer(),
    compression_threshold: float(),
    relevance_threshold: float(),
    include_metadata: boolean(),
    cache_enabled: boolean()
  }
  
  @type context_result :: %{
    injected_context: map(),
    compression_ratio: float(),
    total_tokens: integer(),
    layers_used: list(atom()),
    performance_ms: float()
  }
  
  # Default context layers with priorities
  @default_context_layers [
    %{
      name: :immediate,
      priority: 10,
      extractor: :extract_immediate_context,
      compressor: nil,
      max_size_tokens: 1000
    },
    %{
      name: :file,
      priority: 9,
      extractor: :extract_file_context,
      compressor: :compress_file_context,
      max_size_tokens: 2000
    },
    %{
      name: :project,
      priority: 8,
      extractor: :extract_project_context,
      compressor: :compress_project_context,
      max_size_tokens: 1500
    },
    %{
      name: :conversation,
      priority: 7,
      extractor: :extract_conversation_context,
      compressor: :compress_conversation_context,
      max_size_tokens: 1000
    },
    %{
      name: :user_preferences,
      priority: 6,
      extractor: :extract_user_preferences,
      compressor: nil,
      max_size_tokens: 500
    },
    %{
      name: :technical,
      priority: 5,
      extractor: :extract_technical_context,
      compressor: :compress_technical_context,
      max_size_tokens: 800
    },
    %{
      name: :historical,
      priority: 4,
      extractor: :extract_historical_context,
      compressor: :compress_historical_context,
      max_size_tokens: 600
    }
  ]
  
  @default_config %{
    max_total_tokens: 6000,
    compression_threshold: 0.8,
    relevance_threshold: 0.3,
    include_metadata: true,
    cache_enabled: true
  }
  
  @doc """
  Initialize the context injector with configuration.
  """
  def init(opts \\ []) do
    %__MODULE__{
      context_layers: Keyword.get(opts, :context_layers, @default_context_layers),
      compression_config: Keyword.get(opts, :compression_config, @default_config),
      relevance_weights: Keyword.get(opts, :relevance_weights, %{}),
      cache: %{},
      performance_metrics: %{}
    }
  end
  
  @doc """
  Inject context into a template with the given request data.
  """
  @spec inject_context(
    %__MODULE__{},
    Template.t() | TemplateCompiler.compiled_template(),
    map(),
    injection_config()
  ) :: {:ok, {String.t() | list(), context_result()}} | {:error, term()}
  def inject_context(injector, template, request_data, config \\ @default_config) do
    start_time = System.monotonic_time(:millisecond)
    
    with {:ok, extracted_contexts} <- extract_all_contexts(injector, request_data),
         {:ok, relevant_contexts} <- filter_relevant_contexts(extracted_contexts, request_data, config),
         {:ok, compressed_contexts} <- compress_contexts(relevant_contexts, config),
         {:ok, final_context} <- merge_contexts(compressed_contexts, config),
         {:ok, injected_template} <- inject_into_template(template, final_context) do
      
      end_time = System.monotonic_time(:millisecond)
      
      result = %{
        injected_context: final_context,
        compression_ratio: calculate_compression_ratio(extracted_contexts, final_context),
        total_tokens: estimate_token_count(final_context),
        layers_used: Map.keys(final_context),
        performance_ms: end_time - start_time
      }
      
      {:ok, {injected_template, result}}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Extract context for a specific layer.
  """
  @spec extract_layer_context(%__MODULE__{}, atom(), map()) :: {:ok, map()} | {:error, term()}
  def extract_layer_context(injector, layer_name, request_data) do
    case Enum.find(injector.context_layers, &(&1.name == layer_name)) do
      nil -> {:error, {:unknown_layer, layer_name}}
      layer -> 
        try do
          context = apply(__MODULE__, layer.extractor, [request_data])
          {:ok, context}
        rescue
          error -> {:error, {:extraction_failed, layer_name, Exception.message(error)}}
        end
    end
  end
  
  @doc """
  Update context layer configuration.
  """
  def update_layer(injector, layer_name, updates) do
    layers = Enum.map(injector.context_layers, fn layer ->
      if layer.name == layer_name do
        Map.merge(layer, updates)
      else
        layer
      end
    end)
    
    %{injector | context_layers: layers}
  end
  
  @doc """
  Get performance metrics for context injection.
  """
  def get_performance_metrics(injector) do
    injector.performance_metrics
  end
  
  ## Private Implementation
  
  defp extract_all_contexts(injector, request_data) do
    contexts = injector.context_layers
    |> Enum.sort_by(& &1.priority, :desc)
    |> Enum.reduce_while({:ok, %{}}, fn layer, {:ok, acc} ->
      case extract_layer_context_with_caching(injector, layer, request_data) do
        {:ok, context} ->
          {:cont, {:ok, Map.put(acc, layer.name, context)}}
        {:error, _reason} ->
          # Log error but continue with other layers
          {:cont, {:ok, acc}}
      end
    end)
    
    contexts
  end
  
  defp extract_layer_context_with_caching(injector, layer, request_data) do
    if injector.compression_config.cache_enabled do
      cache_key = generate_cache_key(layer.name, request_data)
      
      case Map.get(injector.cache, cache_key) do
        nil ->
          case extract_layer_context(injector, layer.name, request_data) do
            {:ok, context} ->
              # Cache the result (in practice, you'd use a proper cache with TTL)
              {:ok, context}
            error -> error
          end
        cached_context ->
          {:ok, cached_context}
      end
    else
      extract_layer_context(injector, layer.name, request_data)
    end
  end
  
  defp filter_relevant_contexts(contexts, request_data, config) do
    relevant = contexts
    |> Enum.filter(fn {layer_name, context} ->
      relevance_score = calculate_relevance_score(layer_name, context, request_data)
      relevance_score >= config.relevance_threshold
    end)
    |> Enum.into(%{})
    
    {:ok, relevant}
  end
  
  defp compress_contexts(contexts, config) do
    total_tokens = contexts
    |> Map.values()
    |> Enum.map(&estimate_token_count/1)
    |> Enum.sum()
    
    if total_tokens > config.max_total_tokens do
      # Apply compression
      compression_ratio = config.max_total_tokens / total_tokens
      
      compressed = contexts
      |> Enum.map(fn {layer_name, context} ->
        compressed_context = compress_layer_context(layer_name, context, compression_ratio)
        {layer_name, compressed_context}
      end)
      |> Enum.into(%{})
      
      {:ok, compressed}
    else
      {:ok, contexts}
    end
  end
  
  defp compress_layer_context(layer_name, context, compression_ratio) do
    layer = Enum.find(@default_context_layers, &(&1.name == layer_name))
    
    case layer && layer.compressor do
      nil -> 
        # No compressor, truncate
        truncate_context(context, compression_ratio)
      compressor ->
        try do
          apply(__MODULE__, compressor, [context, compression_ratio])
        rescue
          _error -> truncate_context(context, compression_ratio)
        end
    end
  end
  
  defp merge_contexts(contexts, config) do
    merged = %{}
    
    # Merge contexts by priority, handling conflicts
    merged = contexts
    |> Enum.reduce(merged, fn {layer_name, context}, acc ->
      merge_layer_context(acc, layer_name, context)
    end)
    
    # Add metadata if requested
    final_merged = if config.include_metadata do
      Map.put(merged, :_metadata, %{
        layers: Map.keys(contexts),
        total_tokens: estimate_token_count(merged),
        compression_applied: true
      })
    else
      merged
    end
    
    {:ok, final_merged}
  end
  
  defp merge_layer_context(merged_context, _layer_name, layer_context) do
    # Merge strategy: later layers override earlier ones for conflicting keys
    # but preserve both if they can be combined
    
    Enum.reduce(layer_context, merged_context, fn {key, value}, acc ->
      case Map.get(acc, key) do
        nil -> 
          Map.put(acc, key, value)
        existing_value ->
          # Try to merge if both are maps or lists
          merged_value = merge_context_values(existing_value, value)
          Map.put(acc, key, merged_value)
      end
    end)
  end
  
  defp merge_context_values(existing, new) when is_map(existing) and is_map(new) do
    Map.merge(existing, new)
  end
  
  defp merge_context_values(existing, new) when is_list(existing) and is_list(new) do
    (existing ++ new) |> Enum.uniq()
  end
  
  defp merge_context_values(_existing, new) do
    # New value takes precedence
    new
  end
  
  defp inject_into_template(%Template{} = template, context) do
    # Convert template to compiled form and inject
    case TemplateCompiler.compile(template) do
      {:ok, compiled_template} -> inject_into_template(compiled_template, context)
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp inject_into_template(compiled_template, context) do
    case TemplateCompiler.render(compiled_template, context) do
      {:ok, rendered} -> {:ok, rendered}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp calculate_relevance_score(layer_name, context, request_data) do
    # Calculate how relevant this context layer is for the current request
    base_score = get_base_relevance_score(layer_name, request_data)
    
    # Adjust based on context content
    content_score = calculate_content_relevance(context, request_data)
    
    # Combine scores
    (base_score * 0.6) + (content_score * 0.4)
  end
  
  defp get_base_relevance_score(layer_name, request_data) do
    intent = Map.get(request_data, :intent, :unknown)
    
    case {layer_name, intent} do
      # Immediate context is always highly relevant
      {:immediate, _} -> 1.0
      
      # File context is relevant for code operations
      {:file, intent} when intent in [:code_review, :refactor_code, :explain_codebase, :generate_tests] -> 0.9
      {:file, _} -> 0.6
      
      # Project context is relevant for larger operations
      {:project, intent} when intent in [:implement_feature, :code_review, :generate_docs] -> 0.8
      {:project, _} -> 0.5
      
      # Conversation context is relevant for interactive operations
      {:conversation, intent} when intent in [:explain_codebase, :generate_docs] -> 0.7
      {:conversation, _} -> 0.4
      
      # Technical context is relevant for complex operations
      {:technical, intent} when intent in [:implement_feature, :fix_bug, :refactor_code] -> 0.8
      {:technical, _} -> 0.5
      
      # Default relevance
      {_, _} -> 0.5
    end
  end
  
  defp calculate_content_relevance(context, request_data) do
    # Simple relevance calculation based on keyword overlap
    request_keywords = extract_keywords(request_data)
    context_keywords = extract_keywords(context)
    
    if Enum.empty?(request_keywords) or Enum.empty?(context_keywords) do
      0.5
    else
      overlap = MapSet.intersection(MapSet.new(request_keywords), MapSet.new(context_keywords))
      MapSet.size(overlap) / max(length(request_keywords), length(context_keywords))
    end
  end
  
  defp extract_keywords(data) when is_map(data) do
    data
    |> Map.values()
    |> Enum.flat_map(&extract_keywords/1)
  end
  
  defp extract_keywords(data) when is_binary(data) do
    data
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.take(20)  # Limit keywords
  end
  
  defp extract_keywords(_data), do: []
  
  defp calculate_compression_ratio(original_contexts, final_context) do
    original_size = original_contexts |> Map.values() |> Enum.map(&estimate_token_count/1) |> Enum.sum()
    final_size = estimate_token_count(final_context)
    
    if original_size > 0 do
      final_size / original_size
    else
      1.0
    end
  end
  
  defp estimate_token_count(data) do
    # Rough token estimation: ~4 characters per token
    data
    |> :erlang.term_to_binary()
    |> byte_size()
    |> div(4)
  end
  
  defp truncate_context(context, compression_ratio) when is_binary(context) do
    max_length = round(String.length(context) * compression_ratio)
    String.slice(context, 0, max_length)
  end
  
  defp truncate_context(context, compression_ratio) when is_list(context) do
    max_items = max(1, round(length(context) * compression_ratio))
    Enum.take(context, max_items)
  end
  
  defp truncate_context(context, _compression_ratio) when is_map(context) do
    # For maps, keep the most important keys (heuristic)
    important_keys = [:code, :description, :intent, :file_path, :requirements]
    
    important_data = Map.take(context, important_keys)
    other_data = Map.drop(context, important_keys)
    
    # Keep all important data, truncate others
    truncated_others = other_data
    |> Enum.take(5)  # Keep only 5 other keys
    |> Enum.into(%{})
    
    Map.merge(important_data, truncated_others)
  end
  
  defp truncate_context(context, _compression_ratio), do: context
  
  defp generate_cache_key(layer_name, request_data) do
    # Generate a cache key based on layer and relevant request data
    relevant_data = Map.take(request_data, [:intent, :file_path, :description])
    :crypto.hash(:md5, :erlang.term_to_binary({layer_name, relevant_data}))
    |> Base.encode16()
  end

  # Context extraction implementations
  
  defp extract_immediate_context(request_data) do
    %{
      intent: Map.get(request_data, :intent, :unknown),
      description: Map.get(request_data, :description, ""),
      code: Map.get(request_data, :code, ""),
      file_path: Map.get(request_data, :file_path),
      requirements: Map.get(request_data, :requirements, []),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp extract_file_context(request_data) do
    case Map.get(request_data, :file_path) do
      nil -> %{}
      file_path when is_binary(file_path) ->
        try do
          case File.read(file_path) do
            {:ok, content} ->
              %{
                file_path: file_path,
                file_name: Path.basename(file_path),
                file_extension: Path.extname(file_path),
                file_content: content,
                file_size: byte_size(content),
                directory: Path.dirname(file_path),
                module_name: extract_module_name(content),
                functions: extract_function_names(content),
                dependencies: extract_dependencies(content)
              }
            {:error, _} ->
              %{file_path: file_path, file_error: "Could not read file"}
          end
        rescue
          _ -> %{file_path: file_path, file_error: "File processing error"}
        end
      _ -> %{}
    end
  end
  
  defp extract_project_context(request_data) do
    project_dir = Map.get(request_data, :project_directory) || System.cwd!()
    
    try do
      # Check if it's an Elixir project
      mix_file = Path.join(project_dir, "mix.exs")
      
      project_info = if File.exists?(mix_file) do
        case File.read(mix_file) do
          {:ok, content} ->
            %{
              type: :elixir,
              name: extract_project_name(content),
              version: extract_project_version(content),
              dependencies: extract_mix_dependencies(content)
            }
          {:error, _} ->
            %{type: :unknown}
        end
      else
        %{type: :unknown}
      end
      
      # Scan for relevant files
      elixir_files = Path.wildcard(Path.join([project_dir, "**", "*.{ex,exs}"]))
      |> Enum.take(50)  # Limit for performance
      
      test_files = Path.wildcard(Path.join([project_dir, "test", "**", "*_test.exs"]))
      |> Enum.take(20)
      
      %{
        project_directory: project_dir,
        project_info: project_info,
        file_count: length(elixir_files),
        test_file_count: length(test_files),
        recent_files: get_recently_modified_files(elixir_files),
        structure: analyze_project_structure(project_dir)
      }
    rescue
      _ -> %{project_directory: project_dir, error: "Could not analyze project"}
    end
  end
  
  defp extract_conversation_context(request_data) do
    session_id = Map.get(request_data, :session_id)
    conversation_id = Map.get(request_data, :conversation_id)
    
    case {session_id, conversation_id} do
      {nil, _} -> %{}
      {_, nil} -> %{session_id: session_id}
      {session_id, conversation_id} ->
        # Get conversation history from ConversationManager if available
        try do
          case Aiex.AI.Coordinators.ConversationManager.get_conversation_history(
                 session_id, 
                 conversation_id, 
                 limit: 5
               ) do
            {:ok, history} ->
              %{
                session_id: session_id,
                conversation_id: conversation_id,
                recent_messages: format_conversation_history(history),
                turn_count: length(history),
                context_summary: summarize_conversation_context(history)
              }
            {:error, _} ->
              %{session_id: session_id, conversation_id: conversation_id}
          end
        rescue
          _ -> %{session_id: session_id, conversation_id: conversation_id}
        end
    end
  end
  
  defp extract_user_preferences(request_data) do
    # Extract user preferences from various sources
    interface = Map.get(request_data, :interface, :unknown)
    
    base_preferences = %{
      interface: interface,
      preferred_detail_level: get_interface_detail_preference(interface),
      preferred_format: get_interface_format_preference(interface),
      code_style: :elixir_standard,
      explanation_style: :technical
    }
    
    # Add any explicit preferences from request
    explicit_prefs = Map.take(request_data, [
      :detail_level, :format, :style, :verbosity, :include_examples
    ])
    
    Map.merge(base_preferences, explicit_prefs)
  end
  
  defp extract_technical_context(request_data) do
    %{
      language: detect_language(request_data),
      frameworks: detect_frameworks(request_data),
      patterns: detect_code_patterns(request_data),
      complexity: estimate_complexity(request_data),
      domain: infer_domain_context(request_data),
      architecture_style: detect_architecture_style(request_data)
    }
  end
  
  defp extract_historical_context(request_data) do
    # Extract patterns from historical interactions
    # This could be enhanced with ML-based pattern detection
    
    %{
      similar_requests: find_similar_requests(request_data),
      user_patterns: analyze_user_patterns(request_data),
      success_patterns: get_successful_patterns(request_data),
      feedback_trends: get_feedback_trends(request_data)
    }
  end

  # Helper functions for context extraction
  
  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([A-Za-z_][A-Za-z0-9_.]*)/m, content) do
      [_, module_name] -> module_name
      nil -> nil
    end
  end
  
  defp extract_function_names(content) do
    Regex.scan(~r/def\s+([a-z_][a-zA-Z0-9_]*)/m, content)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
    |> Enum.take(10)  # Limit for context size
  end
  
  defp extract_dependencies(content) do
    Regex.scan(~r/alias\s+([A-Za-z_][A-Za-z0-9_.]*)/m, content)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
    |> Enum.take(10)
  end
  
  defp extract_project_name(mix_content) do
    case Regex.run(~r/app:\s*:([a-zA-Z_][a-zA-Z0-9_]*)/m, mix_content) do
      [_, name] -> name
      nil -> "unknown"
    end
  end
  
  defp extract_project_version(mix_content) do
    case Regex.run(~r/version:\s*"([^"]+)"/m, mix_content) do
      [_, version] -> version
      nil -> "0.1.0"
    end
  end
  
  defp extract_mix_dependencies(mix_content) do
    # Simple extraction - could be enhanced with proper AST parsing
    case Regex.run(~r/defp deps do\s*\[(.*?)\]/ms, mix_content) do
      [_, deps_content] ->
        Regex.scan(~r/{:([a-zA-Z_][a-zA-Z0-9_]*)/m, deps_content)
        |> Enum.map(fn [_, name] -> name end)
        |> Enum.uniq()
        |> Enum.take(20)
      nil -> []
    end
  end
  
  defp get_recently_modified_files(files) do
    files
    |> Enum.map(fn file ->
      case File.stat(file) do
        {:ok, stat} -> {file, stat.mtime}
        {:error, _} -> {file, {{1970, 1, 1}, {0, 0, 0}}}
      end
    end)
    |> Enum.sort_by(fn {_, mtime} -> mtime end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {file, _} -> file end)
  end
  
  defp analyze_project_structure(project_dir) do
    lib_dir = Path.join(project_dir, "lib")
    test_dir = Path.join(project_dir, "test")
    
    %{
      has_lib: File.dir?(lib_dir),
      has_test: File.dir?(test_dir),
      has_config: File.dir?(Path.join(project_dir, "config")),
      has_priv: File.dir?(Path.join(project_dir, "priv")),
      structure_type: infer_structure_type(project_dir)
    }
  end
  
  defp infer_structure_type(project_dir) do
    cond do
      File.exists?(Path.join(project_dir, "apps")) -> :umbrella
      File.exists?(Path.join(project_dir, "lib")) -> :standard
      true -> :unknown
    end
  end
  
  defp format_conversation_history(history) do
    history
    |> Enum.take(3)  # Last 3 messages for context
    |> Enum.map(fn msg ->
      %{
        role: msg.role,
        content: String.slice(msg.content, 0, 200),  # Truncate for context
        timestamp: msg.timestamp
      }
    end)
  end
  
  defp summarize_conversation_context(history) do
    # Simple keyword extraction - could be enhanced with NLP
    all_content = history
    |> Enum.map(& &1.content)
    |> Enum.join(" ")
    
    keywords = extract_keywords(all_content)
    
    %{
      message_count: length(history),
      keywords: keywords,
      topics: infer_topics_from_keywords(keywords),
      last_intent: get_last_intent(history)
    }
  end
  
  defp extract_keywords(text) do
    # Simple keyword extraction
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(10)
    |> Enum.map(fn {word, _} -> word end)
  end
  
  defp infer_topics_from_keywords(keywords) do
    # Simple topic inference based on common programming keywords
    programming_keywords = ["function", "module", "test", "code", "error", "debug"]
    architecture_keywords = ["design", "pattern", "structure", "architecture"]
    performance_keywords = ["performance", "optimize", "speed", "memory"]
    
    topics = []
    
    topics = if Enum.any?(keywords, &(&1 in programming_keywords)), 
      do: ["programming" | topics], else: topics
    topics = if Enum.any?(keywords, &(&1 in architecture_keywords)), 
      do: ["architecture" | topics], else: topics
    topics = if Enum.any?(keywords, &(&1 in performance_keywords)), 
      do: ["performance" | topics], else: topics
    
    topics
  end
  
  defp get_last_intent(history) do
    case List.last(history) do
      %{intent: intent} -> intent
      _ -> :unknown
    end
  end
  
  defp get_interface_detail_preference(:cli), do: :concise
  defp get_interface_detail_preference(:tui), do: :detailed
  defp get_interface_detail_preference(:liveview), do: :interactive
  defp get_interface_detail_preference(:lsp), do: :minimal
  defp get_interface_detail_preference(_), do: :balanced
  
  defp get_interface_format_preference(:cli), do: :text
  defp get_interface_format_preference(:tui), do: :structured
  defp get_interface_format_preference(:liveview), do: :html
  defp get_interface_format_preference(:lsp), do: :json
  defp get_interface_format_preference(_), do: :markdown
  
  defp detect_language(request_data) do
    code = Map.get(request_data, :code, "")
    file_path = Map.get(request_data, :file_path, "")
    
    cond do
      String.contains?(file_path, ".ex") -> :elixir
      String.contains?(file_path, ".exs") -> :elixir
      String.contains?(code, "defmodule") -> :elixir
      String.contains?(code, "def ") -> :elixir
      true -> :unknown
    end
  end
  
  defp detect_frameworks(request_data) do
    code = Map.get(request_data, :code, "")
    dependencies = Map.get(request_data, :dependencies, [])
    
    frameworks = []
    
    frameworks = if "phoenix" in dependencies or String.contains?(code, "Phoenix"), 
      do: ["phoenix" | frameworks], else: frameworks
    frameworks = if "ecto" in dependencies or String.contains?(code, "Ecto"), 
      do: ["ecto" | frameworks], else: frameworks
    frameworks = if "genserver" in dependencies or String.contains?(code, "GenServer"), 
      do: ["otp" | frameworks], else: frameworks
    
    frameworks
  end
  
  defp detect_code_patterns(request_data) do
    code = Map.get(request_data, :code, "")
    
    patterns = []
    
    patterns = if String.contains?(code, "use GenServer"), 
      do: ["genserver" | patterns], else: patterns
    patterns = if String.contains?(code, "|>"), 
      do: ["pipe_operator" | patterns], else: patterns
    patterns = if String.contains?(code, "with "), 
      do: ["with_statement" | patterns], else: patterns
    patterns = if String.contains?(code, "case "), 
      do: ["pattern_matching" | patterns], else: patterns
    
    patterns
  end
  
  defp estimate_complexity(request_data) do
    code = Map.get(request_data, :code, "")
    lines = String.split(code, "\n") |> length()
    
    cond do
      lines < 10 -> :simple
      lines < 50 -> :moderate
      lines < 200 -> :complex
      true -> :very_complex
    end
  end
  
  defp infer_domain_context(request_data) do
    description = Map.get(request_data, :description, "")
    code = Map.get(request_data, :code, "")
    
    text = "#{description} #{code}" |> String.downcase()
    
    cond do
      String.contains?(text, ["web", "http", "api", "rest"]) -> :web_development
      String.contains?(text, ["database", "sql", "ecto"]) -> :data_persistence
      String.contains?(text, ["test", "spec", "assert"]) -> :testing
      String.contains?(text, ["deploy", "release", "docker"]) -> :devops
      String.contains?(text, ["performance", "optimize", "benchmark"]) -> :performance
      true -> :general
    end
  end
  
  defp detect_architecture_style(request_data) do
    code = Map.get(request_data, :code, "")
    
    cond do
      String.contains?(code, "GenServer") -> :actor_model
      String.contains?(code, "Supervisor") -> :supervision_tree
      String.contains?(code, "Agent") -> :stateful_agents
      String.contains?(code, "Task") -> :task_concurrency
      true -> :functional
    end
  end
  
  # Simplified implementations for historical context
  defp find_similar_requests(_request_data), do: []
  defp analyze_user_patterns(_request_data), do: %{}
  defp get_successful_patterns(_request_data), do: []
  defp get_feedback_trends(_request_data), do: %{}
end