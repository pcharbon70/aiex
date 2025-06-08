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
        {:error, reason} ->
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
  
  defp merge_layer_context(merged_context, layer_name, layer_context) do
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
  
  ## Context Extractors
  
  defp extract_immediate_context(request_data) do
    # Extract immediate context from the request
    %{
      intent: Map.get(request_data, :intent),
      description: Map.get(request_data, :description),
      code: Map.get(request_data, :code),
      file_path: Map.get(request_data, :file_path),
      requirements: Map.get(request_data, :requirements),
      user_input: Map.get(request_data, :user_input)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end
  
  defp extract_file_context(request_data) do
    case Map.get(request_data, :file_path) do
      nil -> %{}
      file_path ->
        case File.read(file_path) do
          {:ok, content} ->
            %{
              file_content: content,
              file_extension: Path.extname(file_path),
              file_size: byte_size(content),
              line_count: length(String.split(content, "\n"))
            }
          {:error, _} -> %{}
        end
    end
  end
  
  defp extract_project_context(request_data) do
    # Get project context from context manager
    case ContextManager.get_current_context() do
      {:ok, context} ->
        %{
          project_name: context.project_name,
          project_structure: context.project_structure,
          dependencies: context.dependencies,
          coding_patterns: context.coding_patterns
        }
      {:error, _} -> %{}
    end
  end
  
  defp extract_conversation_context(request_data) do
    # Extract recent conversation history
    case Map.get(request_data, :conversation_id) do
      nil -> %{}
      conversation_id ->
        # Get conversation history (simplified)
        %{
          conversation_id: conversation_id,
          recent_messages: [],  # Would get from conversation manager
          conversation_summary: "Recent discussion about code improvements"
        }
    end
  end
  
  defp extract_user_preferences(request_data) do
    # Extract user preferences (would come from user profile)
    %{
      code_style: "consistent",
      explanation_level: "intermediate",
      preferred_patterns: ["OTP", "functional"],
      output_format: Map.get(request_data, :output_format, "text")
    }
  end
  
  defp extract_technical_context(request_data) do
    # Extract technical context based on file/project
    file_path = Map.get(request_data, :file_path)
    
    context = %{
      language: detect_language(file_path),
      framework: detect_framework(file_path),
      testing_framework: detect_testing_framework(file_path)
    }
    
    # Add Elixir-specific context
    if context.language == "elixir" do
      Map.merge(context, %{
        otp_version: System.otp_release(),
        elixir_version: System.version(),
        mix_project: detect_mix_project()
      })
    else
      context
    end
  end
  
  defp extract_historical_context(_request_data) do
    # Extract historical patterns and learnings
    %{
      common_patterns: ["GenServer for state", "Supervisor for fault tolerance"],
      recent_decisions: [],
      performance_insights: []
    }
  end
  
  ## Context Compressors
  
  defp compress_file_context(context, compression_ratio) do
    # Compress file content by summarizing
    case Map.get(context, :file_content) do
      nil -> context
      content when byte_size(content) > 5000 ->
        # Compress large files
        compressed_content = summarize_code(content, compression_ratio)
        Map.put(context, :file_content, compressed_content)
      _small_content -> context
    end
  end
  
  defp compress_project_context(context, compression_ratio) do
    # Keep essential project info, compress detailed structure
    essential_keys = [:project_name, :dependencies]
    essential = Map.take(context, essential_keys)
    
    other_keys = Map.keys(context) -- essential_keys
    compressed_others = other_keys
    |> Enum.take(round(length(other_keys) * compression_ratio))
    |> Enum.map(fn key -> {key, Map.get(context, key)} end)
    |> Enum.into(%{})
    
    Map.merge(essential, compressed_others)
  end
  
  defp compress_conversation_context(context, compression_ratio) do
    # Keep recent messages but compress older ones
    case Map.get(context, :recent_messages) do
      messages when is_list(messages) ->
        keep_count = max(1, round(length(messages) * compression_ratio))
        compressed_messages = Enum.take(messages, keep_count)
        Map.put(context, :recent_messages, compressed_messages)
      _ -> context
    end
  end
  
  defp compress_technical_context(context, _compression_ratio) do
    # Technical context is usually small, keep as-is
    context
  end
  
  defp compress_historical_context(context, compression_ratio) do
    # Keep most relevant historical data
    %{
      common_patterns: Map.get(context, :common_patterns, []) |> Enum.take(round(10 * compression_ratio)),
      recent_decisions: Map.get(context, :recent_decisions, []) |> Enum.take(round(5 * compression_ratio)),
      performance_insights: Map.get(context, :performance_insights, []) |> Enum.take(round(3 * compression_ratio))
    }
  end
  
  ## Helper Functions
  
  defp detect_language(nil), do: "unknown"
  defp detect_language(file_path) do
    case Path.extname(file_path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".py" -> "python"
      ".js" -> "javascript"
      ".rb" -> "ruby"
      ".rs" -> "rust"
      _ -> "unknown"
    end
  end
  
  defp detect_framework(nil), do: "unknown"
  defp detect_framework(file_path) do
    cond do
      String.contains?(file_path, "phoenix") -> "phoenix"
      String.contains?(file_path, "plug") -> "plug"
      String.contains?(file_path, "nerves") -> "nerves"
      true -> "unknown"
    end
  end
  
  defp detect_testing_framework(nil), do: "unknown"
  defp detect_testing_framework(file_path) do
    cond do
      String.contains?(file_path, "test") and String.ends_with?(file_path, ".exs") -> "exunit"
      String.contains?(file_path, "spec") -> "spec"
      true -> "unknown"
    end
  end
  
  defp detect_mix_project do
    if File.exists?("mix.exs") do
      case File.read("mix.exs") do
        {:ok, content} ->
          # Extract project name from mix.exs
          case Regex.run(~r/def project.*?app:\s*:(\w+)/s, content) do
            [_, app_name] -> app_name
            _ -> "unknown"
          end
        _ -> "unknown"
      end
    else
      "unknown"
    end
  end
  
  defp summarize_code(content, compression_ratio) do
    # Simple code summarization - keep key parts
    lines = String.split(content, "\n")
    target_lines = round(length(lines) * compression_ratio)
    
    # Keep important lines (module definitions, function signatures, etc.)
    important_lines = Enum.filter(lines, fn line ->
      String.match?(line, ~r/(defmodule|def |@doc|@spec|# )/)
    end)
    
    # Fill remaining with other lines
    remaining_count = target_lines - length(important_lines)
    other_lines = (lines -- important_lines) |> Enum.take(max(0, remaining_count))
    
    (important_lines ++ other_lines)
    |> Enum.join("\n")
  end
end