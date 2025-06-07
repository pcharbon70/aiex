defmodule Aiex.Semantic.Chunker do
  @moduledoc """
  Semantic code chunking with Tree-sitter integration.

  Single-node-first design with optional distribution capabilities:
  - Fast local processing as default
  - Distribute only for large files or when cluster available
  - Intelligent caching for performance
  - Graceful fallback to simpler chunking
  """

  use GenServer
  require Logger

  @chunk_cache_table :semantic_chunks
  # 1MB - distribute larger files
  @max_local_file_size 1_000_000
  # tokens
  @default_chunk_size 2000

  defstruct [
    :node,
    :parser_available,
    cache_hits: 0,
    cache_misses: 0,
    local_chunks: 0,
    distributed_chunks: 0
  ]

  ## Client API

  @doc """
  Starts the semantic chunker.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Chunks code semantically, preferring local processing.

  Options:
  - `force_local: true` - Never distribute, even for large files
  - `max_chunk_size: integer` - Override default chunk size
  - `language: atom` - Specify language for better parsing
  """
  def chunk_code(content, opts \\ []) do
    GenServer.call(__MODULE__, {:chunk_code, content, opts})
  end

  @doc """
  Gets chunking statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clears the chunk cache.
  """
  def clear_cache do
    GenServer.call(__MODULE__, :clear_cache)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast local caching
    :ets.new(@chunk_cache_table, [:named_table, :public, :set])

    # Check if Tree-sitter parser is available
    parser_available = check_parser_availability()

    state = %__MODULE__{
      node: node(),
      parser_available: parser_available
    }

    Logger.info("Semantic chunker started on #{node()} (parser: #{parser_available})")
    {:ok, state}
  end

  @impl true
  def handle_call({:chunk_code, content, opts}, _from, state) do
    try do
      {chunks, new_state} = do_chunk_code(content, opts, state)
      {:reply, {:ok, chunks}, new_state}
    rescue
      e ->
        Logger.error("Failed to chunk code: #{inspect(e)}")
        {:reply, {:error, :chunking_failed}, state}
    end
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      cache_hits: state.cache_hits,
      cache_misses: state.cache_misses,
      local_chunks: state.local_chunks,
      distributed_chunks: state.distributed_chunks,
      parser_available: state.parser_available,
      cache_size: :ets.info(@chunk_cache_table, :size)
    }

    {:reply, stats, state}
  end

  def handle_call(:clear_cache, _from, state) do
    :ets.delete_all_objects(@chunk_cache_table)
    Logger.info("Semantic chunk cache cleared")
    {:reply, :ok, state}
  end

  ## Private Functions

  defp do_chunk_code(content, opts, state) do
    content_hash = :crypto.hash(:sha256, content) |> Base.encode16()

    case :ets.lookup(@chunk_cache_table, content_hash) do
      [{^content_hash, cached_chunks}] ->
        # Cache hit - return cached chunks
        new_state = %{state | cache_hits: state.cache_hits + 1}
        {cached_chunks, new_state}

      [] ->
        # Cache miss - need to chunk
        chunks = chunk_content(content, opts, state)
        :ets.insert(@chunk_cache_table, {content_hash, chunks})

        new_state = %{
          state
          | cache_misses: state.cache_misses + 1,
            local_chunks: state.local_chunks + length(chunks)
        }

        {chunks, new_state}
    end
  end

  defp chunk_content(content, opts, state) do
    force_local = Keyword.get(opts, :force_local, false)
    content_size = byte_size(content)

    cond do
      # Always use local processing if forced or parser unavailable
      force_local or not state.parser_available ->
        chunk_locally(content, opts)

      # Use local processing for small files
      content_size <= @max_local_file_size ->
        chunk_locally(content, opts)

      # Consider distribution for large files
      content_size > @max_local_file_size and cluster_available?() ->
        chunk_distributed(content, opts)

      # Fallback to local for large files if no cluster
      true ->
        Logger.info("Large file (#{content_size} bytes) chunked locally - no cluster available")
        chunk_locally(content, opts)
    end
  end

  defp chunk_locally(content, opts) do
    language = Keyword.get(opts, :language, :elixir)
    max_chunk_size = Keyword.get(opts, :max_chunk_size, @default_chunk_size)

    if Code.ensure_loaded?(Aiex.Semantic.TreeSitter) do
      # Use Tree-sitter semantic chunking
      chunk_with_treesitter(content, language, max_chunk_size)
    else
      # Fallback to simple line-based chunking
      chunk_simple(content, max_chunk_size)
    end
  end

  defp chunk_distributed(content, opts) do
    # TODO: Implement distributed chunking using pg process groups
    # For now, fallback to local chunking
    Logger.info("Distributed chunking not yet implemented, using local")
    chunk_locally(content, opts)
  end

  defp chunk_with_treesitter(content, language, max_chunk_size) do
    try do
      # TODO: Call Tree-sitter NIF
      # For now, use semantic-aware simple chunking
      chunk_semantic_aware(content, max_chunk_size)
    rescue
      e ->
        Logger.warning("Tree-sitter failed: #{inspect(e)}, falling back to simple chunking")
        chunk_simple(content, max_chunk_size)
    end
  end

  defp chunk_semantic_aware(content, max_chunk_size) do
    # Handle empty content
    if String.trim(content) == "" do
      []
    else
      # Smart chunking that respects Elixir structure
      lines = String.split(content, "\n")

      lines
      |> group_by_semantic_boundaries()
      |> merge_small_chunks(max_chunk_size)
      |> split_large_chunks(max_chunk_size)
    end
  end

  defp group_by_semantic_boundaries(lines) do
    # Group lines by functions, modules, etc.
    lines
    |> Enum.with_index()
    |> Enum.reduce([], fn {line, idx}, acc ->
      cond do
        # Start of module
        String.match?(line, ~r/^\s*defmodule\s/) ->
          [{:module_start, idx, line} | acc]

        # Start of function
        String.match?(line, ~r/^\s*def\s/) ->
          [{:function_start, idx, line} | acc]

        # Regular line
        true ->
          [{:line, idx, line} | acc]
      end
    end)
    |> Enum.reverse()
    |> group_into_chunks()
  end

  defp group_into_chunks(annotated_lines) do
    # Group lines into logical chunks based on semantic boundaries
    annotated_lines
    |> Enum.chunk_while(
      [],
      fn {type, idx, line}, acc ->
        case type do
          :module_start when acc != [] ->
            # Start new chunk for module
            {:cont, Enum.reverse(acc), [{type, idx, line}]}

          :function_start when length(acc) > 20 ->
            # Start new chunk for function if current chunk is getting large
            {:cont, Enum.reverse(acc), [{type, idx, line}]}

          _ ->
            {:cont, [{type, idx, line} | acc]}
        end
      end,
      fn acc -> {:cont, Enum.reverse(acc), []} end
    )
    |> Enum.map(fn chunk ->
      content = chunk |> Enum.map(fn {_, _, line} -> line end) |> Enum.join("\n")
      start_line = chunk |> List.first() |> elem(1)
      end_line = chunk |> List.last() |> elem(1)

      %{
        content: content,
        start_line: start_line,
        end_line: end_line,
        type: :semantic,
        token_count: estimate_tokens(content)
      }
    end)
  end

  defp merge_small_chunks(chunks, max_chunk_size) do
    # Merge adjacent small chunks to improve efficiency
    chunks
    |> Enum.reduce([], fn chunk, acc ->
      case acc do
        [] ->
          [chunk]

        [last | rest] when last.token_count + chunk.token_count <= max_chunk_size ->
          merged = %{
            content: last.content <> "\n" <> chunk.content,
            start_line: last.start_line,
            end_line: chunk.end_line,
            type: :merged,
            token_count: last.token_count + chunk.token_count
          }

          [merged | rest]

        _ ->
          [chunk | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp split_large_chunks(chunks, max_chunk_size) do
    # Split chunks that are too large
    Enum.flat_map(chunks, fn chunk ->
      if chunk.token_count > max_chunk_size do
        split_chunk(chunk, max_chunk_size)
      else
        [chunk]
      end
    end)
  end

  defp split_chunk(chunk, max_chunk_size) do
    lines = String.split(chunk.content, "\n")
    target_lines_per_chunk = div(length(lines) * max_chunk_size, chunk.token_count)

    lines
    |> Enum.chunk_every(max(target_lines_per_chunk, 10))
    |> Enum.with_index()
    |> Enum.map(fn {chunk_lines, idx} ->
      content = Enum.join(chunk_lines, "\n")

      %{
        content: content,
        start_line: chunk.start_line + idx * target_lines_per_chunk,
        end_line: chunk.start_line + (idx + 1) * target_lines_per_chunk - 1,
        type: :split,
        token_count: estimate_tokens(content)
      }
    end)
  end

  defp chunk_simple(content, max_chunk_size) do
    # Simple fallback chunking
    lines = String.split(content, "\n")
    # Rough estimate: 4 tokens per line
    lines_per_chunk = max(div(max_chunk_size, 4), 10)

    lines
    |> Enum.chunk_every(lines_per_chunk)
    |> Enum.with_index()
    |> Enum.map(fn {chunk_lines, idx} ->
      content = Enum.join(chunk_lines, "\n")
      start_line = idx * lines_per_chunk
      end_line = start_line + length(chunk_lines) - 1

      %{
        content: content,
        start_line: start_line,
        end_line: end_line,
        type: :simple,
        token_count: estimate_tokens(content)
      }
    end)
  end

  defp estimate_tokens(content) do
    # Rough token estimation: split by spaces and common separators
    content
    |> String.split(~r/\s+|[,\.\(\)\[\]\{\}]/)
    |> length()
  end

  defp check_parser_availability do
    # Check if Rustler and Tree-sitter are available
    Code.ensure_loaded?(Aiex.Semantic.TreeSitter)
  end

  defp cluster_available? do
    # Check if we have multiple nodes available for distribution
    case Node.list() do
      [] -> false
      _nodes -> true
    end
  end
end
