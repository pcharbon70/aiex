defmodule Aiex.Context.Compressor do
  @moduledoc """
  Intelligent context compression using semantic chunks and token-aware strategies.

  Single-node-first design with optional distribution:
  - Fast local compression for most use cases
  - Model-specific token counting and limits
  - Intelligent priority-based selection
  - Graceful fallback and caching
  """

  use GenServer
  require Logger
  alias Aiex.Semantic.Chunker

  @compression_cache_table :context_compression_cache
  @default_token_limits %{
    "gpt-3.5-turbo" => 4_096,
    "gpt-4" => 8_192,
    "gpt-4-32k" => 32_768,
    "claude-3-haiku" => 200_000,
    "claude-3-sonnet" => 200_000,
    "claude-3-opus" => 200_000,
    # Conservative default for local models
    "ollama" => 4_096,
    # Conservative default
    "lm-studio" => 4_096
  }

  defstruct [
    :node,
    token_limits: @default_token_limits,
    compression_stats: %{
      compressions: 0,
      cache_hits: 0,
      cache_misses: 0,
      tokens_saved: 0,
      avg_compression_ratio: 0.0
    }
  ]

  ## Client API

  @doc """
  Starts the context compressor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Compresses context for a specific model and prompt.

  Options:
  - `model`: Target LLM model (affects token limits)
  - `priority_context`: High-priority content (always included)
  - `strategy`: Compression strategy (:semantic, :size, :relevance)
  - `max_tokens`: Override default model token limit
  - `force_local`: Never distribute compression work
  """
  def compress_context(context_items, opts \\ []) do
    GenServer.call(__MODULE__, {:compress_context, context_items, opts}, 30_000)
  end

  @doc """
  Estimates token count for given content using model-specific tokenizer.
  """
  def estimate_tokens(content, model \\ "gpt-4") do
    GenServer.call(__MODULE__, {:estimate_tokens, content, model})
  end

  @doc """
  Gets compression statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clears compression cache.
  """
  def clear_cache do
    GenServer.call(__MODULE__, :clear_cache)
  end

  @doc """
  Updates token limits for models.
  """
  def update_token_limits(limits) when is_map(limits) do
    GenServer.call(__MODULE__, {:update_token_limits, limits})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for compression caching
    :ets.new(@compression_cache_table, [:named_table, :public, :set])

    state = %__MODULE__{
      node: node()
    }

    Logger.info("Context compressor started on #{node()}")
    {:ok, state}
  end

  @impl true
  def handle_call({:compress_context, context_items, opts}, _from, state) do
    try do
      {compressed_context, new_state} = do_compress_context(context_items, opts, state)
      {:reply, {:ok, compressed_context}, new_state}
    rescue
      e ->
        Logger.error("Context compression failed: #{inspect(e)}")
        {:reply, {:error, :compression_failed}, state}
    end
  end

  def handle_call({:estimate_tokens, content, model}, _from, state) do
    token_count = estimate_token_count(content, model)
    {:reply, token_count, state}
  end

  def handle_call(:get_stats, _from, state) do
    stats =
      Map.merge(state.compression_stats, %{
        cache_size: :ets.info(@compression_cache_table, :size),
        token_limits: state.token_limits
      })

    {:reply, stats, state}
  end

  def handle_call(:clear_cache, _from, state) do
    :ets.delete_all_objects(@compression_cache_table)
    Logger.info("Context compression cache cleared")
    {:reply, :ok, state}
  end

  def handle_call({:update_token_limits, limits}, _from, state) do
    new_limits = Map.merge(state.token_limits, limits)
    new_state = %{state | token_limits: new_limits}
    Logger.info("Updated token limits: #{inspect(limits)}")
    {:reply, :ok, new_state}
  end

  ## Private Functions

  defp do_compress_context(context_items, opts, state) do
    model = Keyword.get(opts, :model, "gpt-4")
    strategy = Keyword.get(opts, :strategy, :semantic)
    max_tokens = Keyword.get(opts, :max_tokens) || Map.get(state.token_limits, model, 8192)
    priority_context = Keyword.get(opts, :priority_context, [])
    force_local = Keyword.get(opts, :force_local, false)

    # Create cache key
    cache_key = create_cache_key(context_items, opts)

    case :ets.lookup(@compression_cache_table, cache_key) do
      [{^cache_key, cached_result}] ->
        # Cache hit
        new_stats = update_stats(state.compression_stats, :cache_hit)
        new_state = %{state | compression_stats: new_stats}
        {cached_result, new_state}

      [] ->
        # Cache miss - perform compression
        compressed =
          perform_compression(
            context_items,
            %{
              model: model,
              strategy: strategy,
              max_tokens: max_tokens,
              priority_context: priority_context,
              force_local: force_local
            },
            state
          )

        # Cache the result
        :ets.insert(@compression_cache_table, {cache_key, compressed})

        # Update stats
        new_stats = update_stats(state.compression_stats, :cache_miss, compressed)
        new_state = %{state | compression_stats: new_stats}

        {compressed, new_state}
    end
  end

  defp perform_compression(context_items, config, state) do
    %{
      model: model,
      strategy: strategy,
      max_tokens: max_tokens,
      priority_context: priority_context,
      force_local: force_local
    } = config

    # Step 1: Chunk all context items using semantic chunker
    chunked_items = chunk_context_items(context_items)

    # Step 2: Add priority context (always included)
    priority_chunks = chunk_priority_context(priority_context)

    # Step 3: Calculate available tokens after priority content
    priority_tokens = calculate_total_tokens(priority_chunks, model)
    # Reserve 200 for prompt overhead
    available_tokens = max_tokens - priority_tokens - 200

    if available_tokens <= 0 do
      Logger.warning("Priority context exceeds token limit for model #{model}")

      %{
        chunks: priority_chunks,
        total_tokens: priority_tokens,
        compression_ratio: 1.0,
        strategy_used: :priority_only,
        model: model
      }
    else
      # Step 4: Apply compression strategy
      selected_chunks =
        apply_compression_strategy(
          chunked_items,
          strategy,
          available_tokens,
          model,
          force_local,
          state
        )

      # Step 5: Combine with priority content
      final_chunks = priority_chunks ++ selected_chunks
      total_tokens = calculate_total_tokens(final_chunks, model)
      original_tokens = calculate_total_tokens(chunked_items ++ priority_chunks, model)

      compression_ratio = if original_tokens > 0, do: total_tokens / original_tokens, else: 1.0

      %{
        chunks: final_chunks,
        total_tokens: total_tokens,
        compression_ratio: compression_ratio,
        strategy_used: strategy,
        model: model,
        available_tokens: available_tokens,
        original_tokens: original_tokens
      }
    end
  end

  defp chunk_context_items(context_items) do
    Enum.flat_map(context_items, fn item ->
      case item do
        %{content: content, type: type} when is_binary(content) ->
          case Chunker.chunk_code(content) do
            {:ok, chunks} ->
              Enum.map(chunks, fn chunk ->
                Map.merge(chunk, %{
                  context_type: type,
                  priority: Map.get(item, :priority, 0),
                  metadata: Map.get(item, :metadata, %{})
                })
              end)

            {:error, _} ->
              # Fallback to simple chunk
              [
                %{
                  content: content,
                  context_type: type,
                  priority: Map.get(item, :priority, 0),
                  token_count: estimate_token_count(content, "gpt-4"),
                  type: :fallback
                }
              ]
          end

        %{content: content} when is_binary(content) ->
          # Simple content without type
          case Chunker.chunk_code(content) do
            {:ok, chunks} ->
              chunks

            {:error, _} ->
              [
                %{
                  content: content,
                  token_count: estimate_token_count(content, "gpt-4"),
                  type: :fallback
                }
              ]
          end

        _ ->
          Logger.warning("Invalid context item format: #{inspect(item)}")
          []
      end
    end)
  end

  defp chunk_priority_context([]), do: []

  defp chunk_priority_context(priority_content) when is_list(priority_content) do
    chunk_context_items(priority_content)
  end

  defp chunk_priority_context(priority_content) when is_binary(priority_content) do
    chunk_context_items([%{content: priority_content, type: :priority}])
  end

  defp apply_compression_strategy(chunks, strategy, available_tokens, model, force_local, state) do
    case strategy do
      :semantic ->
        compress_semantic(chunks, available_tokens, model)

      :size ->
        compress_by_size(chunks, available_tokens, model)

      :relevance ->
        compress_by_relevance(chunks, available_tokens, model)

      :priority ->
        compress_by_priority(chunks, available_tokens, model)

      :distributed ->
        if not force_local and cluster_available?() do
          compress_distributed(chunks, available_tokens, model, state)
        else
          compress_semantic(chunks, available_tokens, model)
        end

      _ ->
        # Fallback to semantic compression
        compress_semantic(chunks, available_tokens, model)
    end
  end

  defp compress_semantic(chunks, available_tokens, model) do
    # Prioritize complete semantic units (modules, functions)
    chunks
    |> Enum.sort_by(fn chunk ->
      semantic_priority =
        case chunk.type do
          :semantic -> 3
          :merged -> 2
          :split -> 1
          _ -> 0
        end

      # Higher priority for smaller, complete chunks
      size_factor = 1000 / max(chunk.token_count, 1)

      -(semantic_priority * 100 + size_factor)
    end)
    |> select_chunks_within_limit(available_tokens, model)
  end

  defp compress_by_size(chunks, available_tokens, model) do
    # Select smallest chunks first to maximize content variety
    chunks
    |> Enum.sort_by(& &1.token_count)
    |> select_chunks_within_limit(available_tokens, model)
  end

  defp compress_by_relevance(chunks, available_tokens, model) do
    # Prioritize by context priority and recency
    chunks
    |> Enum.sort_by(fn chunk ->
      priority = Map.get(chunk, :priority, 0)

      # Boost priority for certain context types
      context_boost =
        case Map.get(chunk, :context_type) do
          :current_file -> 10
          :related_file -> 5
          :documentation -> 3
          _ -> 0
        end

      -(priority + context_boost)
    end)
    |> select_chunks_within_limit(available_tokens, model)
  end

  defp compress_by_priority(chunks, available_tokens, model) do
    # Simple priority-based selection
    chunks
    |> Enum.sort_by(&Map.get(&1, :priority, 0), :desc)
    |> select_chunks_within_limit(available_tokens, model)
  end

  defp compress_distributed(chunks, available_tokens, model, _state) do
    # TODO: Implement distributed compression using pg process groups
    # For now, fallback to local semantic compression
    Logger.info("Distributed compression not yet implemented, using semantic fallback")
    compress_semantic(chunks, available_tokens, model)
  end

  defp select_chunks_within_limit(sorted_chunks, available_tokens, _model) do
    {selected, _remaining_tokens} =
      Enum.reduce_while(sorted_chunks, {[], available_tokens}, fn chunk, {acc, remaining} ->
        chunk_tokens = chunk.token_count

        if chunk_tokens <= remaining do
          {:cont, {[chunk | acc], remaining - chunk_tokens}}
        else
          {:halt, {acc, remaining}}
        end
      end)

    Enum.reverse(selected)
  end

  defp calculate_total_tokens(chunks, model) do
    Enum.reduce(chunks, 0, fn chunk, acc ->
      acc + Map.get(chunk, :token_count, estimate_token_count(chunk.content || "", model))
    end)
  end

  defp estimate_token_count(content, model) when is_binary(content) do
    # Model-specific token estimation
    base_estimate = estimate_tokens_simple(content)

    # Apply model-specific adjustments
    case model do
      "claude-" <> _ ->
        # Claude tends to use fewer tokens per word
        trunc(base_estimate * 0.85)

      "gpt-" <> _ ->
        # GPT models are close to our base estimate
        base_estimate

      "ollama" <> _ ->
        # Local models might vary, use conservative estimate
        trunc(base_estimate * 1.1)

      _ ->
        base_estimate
    end
  end

  defp estimate_token_count(_, _), do: 0

  defp estimate_tokens_simple(content) do
    # Simple but reasonably accurate token estimation
    # Roughly 4 characters per token for English text
    # Code tends to have more tokens per character

    char_count = String.length(content)
    word_count = content |> String.split(~r/\s+/) |> length()

    # Heuristic: mix of character and word based counting
    char_based = div(char_count, 4)
    # Code words tend to be more tokens
    word_based = trunc(word_count * 1.3)

    # Take the higher estimate for safety
    max(char_based, word_based)
  end

  defp create_cache_key(context_items, opts) do
    # Create a deterministic cache key
    content_hash =
      context_items
      |> Enum.map(&inspect/1)
      |> Enum.join("|")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16()

    opts_hash =
      opts
      |> Keyword.take([:model, :strategy, :max_tokens])
      |> inspect()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16()

    "#{content_hash}_#{opts_hash}"
  end

  defp update_stats(stats, :cache_hit) do
    %{stats | cache_hits: stats.cache_hits + 1}
  end

  defp update_stats(stats, :cache_miss, compressed) do
    new_compressions = stats.compressions + 1
    compression_ratio = Map.get(compressed, :compression_ratio, 1.0)

    # Update running average
    new_avg =
      (stats.avg_compression_ratio * stats.compressions + compression_ratio) / new_compressions

    tokens_saved =
      max(0, Map.get(compressed, :original_tokens, 0) - Map.get(compressed, :total_tokens, 0))

    %{
      stats
      | cache_misses: stats.cache_misses + 1,
        compressions: new_compressions,
        avg_compression_ratio: new_avg,
        tokens_saved: stats.tokens_saved + tokens_saved
    }
  end

  defp cluster_available? do
    case Node.list() do
      [] -> false
      _nodes -> true
    end
  end
end
