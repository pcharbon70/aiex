defmodule Aiex.Context.DistributedEngine do
  @moduledoc """
  Distributed context management engine using Mnesia for persistence and 
  pg module for event distribution across cluster nodes.

  Provides distributed context storage with ACID guarantees, cross-node 
  synchronization, and automatic failover.
  """

  use GenServer
  require Logger

  # Mnesia table definitions
  @ai_context_table :ai_context
  @code_analysis_cache_table :code_analysis_cache
  @llm_interaction_table :llm_interaction

  # Context data structures (moved to separate modules would be cleaner,
  # but keeping here for simplicity in this initial implementation)

  ## Client API

  @doc """
  Starts the distributed context engine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates or updates an AI context session.
  """
  def put_context(session_id, context) do
    GenServer.call(__MODULE__, {:put_context, session_id, context})
  end

  @doc """
  Retrieves an AI context by session ID.
  """
  def get_context(session_id) do
    GenServer.call(__MODULE__, {:get_context, session_id})
  end

  @doc """
  Stores code analysis results in the cache.
  """
  def put_analysis(file_path, analysis) do
    GenServer.call(__MODULE__, {:put_analysis, file_path, analysis})
  end

  @doc """
  Retrieves cached code analysis for a file.
  """
  def get_analysis(file_path) do
    GenServer.call(__MODULE__, {:get_analysis, file_path})
  end

  @doc """
  Records an LLM interaction.
  """
  def record_interaction(interaction) do
    GenServer.call(__MODULE__, {:record_interaction, interaction})
  end

  @doc """
  Gets interaction history for a session.
  """
  def get_interactions(session_id) do
    GenServer.call(__MODULE__, {:get_interactions, session_id})
  end

  @doc """
  Analyzes code content and returns structured analysis.
  """
  def analyze_code(content, context \\ %{}) do
    GenServer.call(__MODULE__, {:analyze_code, content, context})
  end

  @doc """
  Get distributed context for a code element across the cluster.
  """
  def get_distributed_context(code_element, opts \\ []) do
    GenServer.call(__MODULE__, {:get_distributed_context, code_element, opts})
  end

  @doc """
  Get related context for a code fragment.
  """
  def get_related_context(code_fragment) do
    GenServer.call(__MODULE__, {:get_related_context, code_fragment})
  end

  @doc """
  Compress context data while preserving important information.
  """
  def compress_context(context, opts \\ []) do
    GenServer.call(__MODULE__, {:compress_context, context, opts})
  end

  @doc """
  Gets distributed context statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Initialize Mnesia if not already done
    case setup_mnesia() do
      :ok ->
        Logger.info("Distributed context engine started successfully")
        {:ok, %{node: node()}}

      {:error, reason} ->
        Logger.error("Failed to setup Mnesia: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:put_context, session_id, context}, _from, state) do
    result =
      mnesia_transaction(fn ->
        context_record = %{
          session_id: session_id,
          user_id: Map.get(context, :user_id),
          conversation_history: Map.get(context, :conversation_history, []),
          active_model: Map.get(context, :active_model),
          embeddings: Map.get(context, :embeddings, %{}),
          created_at: Map.get(context, :created_at, DateTime.utc_now()),
          last_updated: DateTime.utc_now()
        }

        :mnesia.write({@ai_context_table, session_id, context_record})
      end)

    # Broadcast context update via pg (only if available)
    try do
      broadcast_context_update(session_id, :updated)
    catch
      _, _ ->
        Logger.debug("pg not available for broadcasting, skipping")
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_context, session_id}, _from, state) do
    result =
      mnesia_transaction(fn ->
        case :mnesia.read({@ai_context_table, session_id}) do
          [{@ai_context_table, ^session_id, context}] -> {:ok, context}
          [] -> {:error, :not_found}
        end
      end)

    case result do
      {:atomic, inner_result} -> {:reply, inner_result, state}
      {:aborted, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:put_analysis, file_path, analysis}, _from, state) do
    result =
      mnesia_transaction(fn ->
        analysis_record = %{
          file_path: file_path,
          ast: Map.get(analysis, :ast),
          symbols: Map.get(analysis, :symbols, []),
          dependencies: Map.get(analysis, :dependencies, []),
          last_analyzed: DateTime.utc_now()
        }

        :mnesia.write({@code_analysis_cache_table, file_path, analysis_record})
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_analysis, file_path}, _from, state) do
    result =
      mnesia_transaction(fn ->
        case :mnesia.read({@code_analysis_cache_table, file_path}) do
          [{@code_analysis_cache_table, ^file_path, analysis}] -> {:ok, analysis}
          [] -> {:error, :not_found}
        end
      end)

    case result do
      {:atomic, inner_result} -> {:reply, inner_result, state}
      {:aborted, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:record_interaction, interaction}, _from, state) do
    interaction_id = generate_interaction_id()

    result =
      mnesia_transaction(fn ->
        interaction_record = %{
          interaction_id: interaction_id,
          session_id: Map.get(interaction, :session_id),
          prompt: Map.get(interaction, :prompt),
          response: Map.get(interaction, :response),
          model_used: Map.get(interaction, :model_used),
          tokens_used: Map.get(interaction, :tokens_used),
          latency_ms: Map.get(interaction, :latency_ms),
          timestamp: DateTime.utc_now()
        }

        :mnesia.write({@llm_interaction_table, interaction_id, interaction_record})
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_interactions, session_id}, _from, state) do
    result =
      mnesia_transaction(fn ->
        # For now, scan all interactions to find by session_id
        all_interactions =
          :mnesia.select(@llm_interaction_table, [
            {{@llm_interaction_table, :"$1", :"$2"}, [], [:"$2"]}
          ])

        Enum.filter(all_interactions, fn record ->
          Map.get(record, :session_id) == session_id
        end)
      end)

    case result do
      {:atomic, interactions} ->
        {:reply, {:ok, interactions}, state}

      {:aborted, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:analyze_code, content, context}, _from, state) do
    # Basic code analysis - in a real implementation this would use
    # tree-sitter or other parsing tools
    analysis = %{
      timestamp: DateTime.utc_now(),
      content_length: String.length(content),
      lines: String.split(content, "\n") |> length(),
      context: context,
      # Basic heuristics - replace with real analysis
      complexity: estimate_complexity(content),
      language: detect_language(content),
      functions: extract_functions(content)
    }

    {:reply, {:ok, analysis}, state}
  end

  @impl true
  def handle_call({:get_distributed_context, code_element, opts}, _from, state) do
    # Get context from local and remote nodes
    local_context = get_local_context(code_element)
    remote_context = get_remote_context(code_element, opts)
    
    distributed_context = %{
      local: local_context,
      remote: remote_context,
      dependencies: extract_dependencies(code_element),
      dependents: extract_dependents(code_element)
    }
    
    {:reply, {:ok, distributed_context}, state}
  end

  def handle_call({:get_related_context, code_fragment}, _from, state) do
    # Analyze the code fragment and find related context
    related_context = %{
      ast_analysis: analyze_ast_fragment(code_fragment),
      symbol_references: find_symbol_references(code_fragment),
      similar_patterns: find_similar_patterns(code_fragment),
      cluster_context: get_cluster_context_for_fragment(code_fragment)
    }
    
    {:reply, {:ok, related_context}, state}
  end

  def handle_call({:compress_context, context, opts}, _from, state) do
    # Compress context while preserving critical information
    target_size = Keyword.get(opts, :target_size, 1000)
    preserve_critical = Keyword.get(opts, :preserve_critical, true)
    
    compressed_context = compress_context_data(context, target_size, preserve_critical)
    
    {:reply, {:ok, compressed_context}, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      node: node(),
      ai_contexts: table_size(@ai_context_table),
      code_analyses: table_size(@code_analysis_cache_table),
      llm_interactions: table_size(@llm_interaction_table),
      cluster_nodes: [node() | Node.list()],
      mnesia_running: :mnesia.system_info(:is_running)
    }

    {:reply, stats, state}
  end

  ## Private Functions

  defp estimate_complexity(content) do
    # Simple heuristic based on lines and nesting
    lines = String.split(content, "\n")
    line_count = length(lines)

    # Count nesting indicators
    nesting_score =
      Enum.reduce(lines, 0, fn line, acc ->
        cond do
          String.contains?(line, ["if", "case", "cond", "with", "for", "fn"]) -> acc + 1
          String.contains?(line, ["do", "{"]) -> acc + 1
          true -> acc
        end
      end)

    cond do
      line_count < 50 and nesting_score < 5 -> :low
      line_count < 200 and nesting_score < 20 -> :medium
      true -> :high
    end
  end

  defp detect_language(content) do
    cond do
      String.contains?(content, ["defmodule", "defp", "def ", "|>"]) -> :elixir
      String.contains?(content, ["fn ", "use ", "require ", "import "]) -> :elixir
      String.contains?(content, ["function", "const", "let", "var", "=>"]) -> :javascript
      String.contains?(content, ["def ", "class ", "import ", "from "]) -> :python
      String.contains?(content, ["pub fn", "let ", "match", "impl"]) -> :rust
      true -> :unknown
    end
  end

  defp extract_functions(content) do
    # Extract Elixir function definitions
    ~r/def\s+(\w+)/
    |> Regex.scan(content)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end

  defp setup_mnesia do
    nodes = [node() | Node.list()]

    # Create schema if it doesn't exist
    case :mnesia.create_schema(nodes) do
      :ok -> :ok
      {:error, {_, {:already_exists, _}}} -> :ok
      error -> error
    end

    # Start Mnesia
    case :mnesia.start() do
      :ok -> create_tables(nodes)
      error -> error
    end
  end

  defp create_tables(nodes) do
    # AI Context table - use ram_copies for single node development
    table_type = if length(nodes) > 1, do: :disc_copies, else: :ram_copies

    create_table(@ai_context_table, [
      {table_type, nodes},
      {:attributes, [:session_id, :context]},
      {:type, :set}
    ])

    # Code Analysis Cache table
    create_table(@code_analysis_cache_table, [
      {table_type, nodes},
      {:attributes, [:file_path, :analysis]},
      {:type, :set}
    ])

    # LLM Interaction table - simplified for single node development
    create_table(@llm_interaction_table, [
      {table_type, nodes},
      {:attributes, [:interaction_id, :interaction]},
      {:type, :set}
    ])

    :ok
  end

  defp create_table(name, options) do
    case :mnesia.create_table(name, options) do
      {:atomic, :ok} ->
        Logger.info("Created Mnesia table: #{name}")
        :ok

      {:aborted, {:already_exists, ^name}} ->
        Logger.debug("Mnesia table already exists: #{name}")
        :ok

      {:aborted, reason} ->
        Logger.error("Failed to create Mnesia table #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp mnesia_transaction(fun) do
    try do
      :mnesia.transaction(fun)
    catch
      :exit, {:aborted, reason} -> {:aborted, reason}
      :exit, reason -> {:aborted, reason}
    end
  end

  defp table_size(table_name) do
    try do
      :mnesia.table_info(table_name, :size)
    catch
      :exit, _ -> 0
    end
  end

  # Context retrieval helper functions

  defp get_local_context(code_element) do
    # Simplified local context retrieval
    %{
      definitions: find_local_definitions(code_element),
      usages: find_local_usages(code_element),
      node: node()
    }
  end

  defp get_remote_context(code_element, opts) do
    # Get context from remote nodes
    remote_nodes = Keyword.get(opts, :nodes, Node.list())
    
    Enum.reduce(remote_nodes, %{}, fn remote_node, acc ->
      try do
        remote_context = :rpc.call(remote_node, __MODULE__, :get_local_context, [code_element], 5000)
        Map.put(acc, remote_node, remote_context)
      catch
        _, _ -> acc
      end
    end)
  end

  defp extract_dependencies(code_element) do
    # Simplified dependency extraction
    case String.contains?(to_string(code_element), ".") do
      true -> [String.split(to_string(code_element), ".") |> List.first()]
      false -> []
    end
  end

  defp extract_dependents(code_element) do
    # Simplified dependent extraction
    []
  end

  defp analyze_ast_fragment(code_fragment) do
    # Simple AST analysis
    try do
      case Code.string_to_quoted(code_fragment) do
        {:ok, ast} -> %{valid: true, ast_type: element_type(ast)}
        {:error, _} -> %{valid: false, ast_type: :unknown}
      end
    catch
      _, _ -> %{valid: false, ast_type: :unknown}
    end
  end

  defp element_type({:defmodule, _, _}), do: :module
  defp element_type({:def, _, _}), do: :function
  defp element_type({:defp, _, _}), do: :private_function
  defp element_type(_), do: :expression

  defp find_symbol_references(code_fragment) do
    # Simplified symbol reference finding
    symbols = Regex.scan(~r/[A-Z][a-zA-Z0-9_]*/, code_fragment)
    |> Enum.map(fn [symbol] -> symbol end)
    |> Enum.uniq()
    
    %{modules: symbols, functions: []}
  end

  defp find_similar_patterns(code_fragment) do
    # Simplified pattern matching
    %{
      pattern_type: determine_pattern_type(code_fragment),
      confidence: 0.5,
      examples: []
    }
  end

  defp determine_pattern_type(code_fragment) do
    cond do
      String.contains?(code_fragment, "GenServer") -> :genserver_pattern
      String.contains?(code_fragment, "def ") -> :function_definition
      String.contains?(code_fragment, "defmodule") -> :module_definition
      true -> :unknown
    end
  end

  defp get_cluster_context_for_fragment(code_fragment) do
    %{
      cluster_nodes: [node() | Node.list()],
      fragment_hash: :crypto.hash(:sha256, code_fragment) |> Base.encode16(case: :lower),
      analysis_timestamp: DateTime.utc_now()
    }
  end

  defp find_local_definitions(_code_element) do
    # Simplified local definition finding
    []
  end

  defp find_local_usages(_code_element) do
    # Simplified local usage finding
    []
  end

  defp compress_context_data(context, target_size, preserve_critical) do
    original_size = :erlang.external_size(context)
    
    if original_size <= target_size do
      # Already small enough
      context
    else
      # Perform compression
      compressed = case preserve_critical do
        true -> preserve_critical_context(context, target_size)
        false -> simple_compression(context, target_size)
      end
      
      Map.put(compressed, :compression_info, %{
        original_size: original_size,
        compressed_size: :erlang.external_size(compressed),
        compression_ratio: original_size / :erlang.external_size(compressed),
        preserved_critical: preserve_critical
      })
    end
  end

  defp preserve_critical_context(context, target_size) do
    # Preserve the most important parts of the context
    critical_keys = [:modules, :functions, :dependencies, :complexity, :patterns]
    
    critical_context = Map.take(context, critical_keys)
    remaining_budget = target_size - :erlang.external_size(critical_context)
    
    if remaining_budget > 0 do
      # Add non-critical data if budget allows
      non_critical = Map.drop(context, critical_keys)
      additional_data = compress_non_critical(non_critical, remaining_budget)
      Map.merge(critical_context, additional_data)
    else
      # Create summary if critical data is too large
      %{
        summary: summarize_context(context),
        critical_data: compress_critical_data(critical_context, target_size * 0.8)
      }
    end
  end

  defp simple_compression(context, target_size) do
    # Simple compression by truncating less important data
    sorted_keys = context
    |> Map.keys()
    |> Enum.sort_by(fn key -> importance_score(key) end, :desc)
    
    Enum.reduce_while(sorted_keys, %{}, fn key, acc ->
      new_acc = Map.put(acc, key, context[key])
      
      if :erlang.external_size(new_acc) <= target_size do
        {:cont, new_acc}
      else
        {:halt, acc}
      end
    end)
  end

  defp importance_score(key) do
    # Assign importance scores to different context keys
    case key do
      :modules -> 10
      :functions -> 9
      :dependencies -> 8
      :complexity -> 7
      :patterns -> 6
      :metadata -> 5
      :code_analysis -> 8
      _ -> 1
    end
  end

  defp compress_non_critical(data, budget) do
    # Compress non-critical data to fit budget
    if :erlang.external_size(data) <= budget do
      data
    else
      # Summarize or truncate non-critical data
      %{summary: "Non-critical data compressed due to size constraints"}
    end
  end

  defp compress_critical_data(data, budget) do
    # Compress critical data while preserving essential information
    if :erlang.external_size(data) <= budget do
      data
    else
      # Create abbreviated version of critical data
      abbreviated = Enum.reduce(data, %{}, fn {key, value}, acc ->
        case key do
          :modules when is_list(value) ->
            # Keep only module names
            abbreviated_modules = Enum.map(value, fn
              %{name: name} -> name
              module when is_binary(module) -> module
              _ -> "unknown"
            end)
            Map.put(acc, key, abbreviated_modules)
            
          :functions when is_list(value) ->
            # Keep only function names and arities
            abbreviated_functions = Enum.map(value, fn
              %{name: name, arity: arity} -> "#{name}/#{arity}"
              func when is_binary(func) -> func
              _ -> "unknown"
            end)
            Map.put(acc, key, abbreviated_functions)
            
          _ ->
            Map.put(acc, key, value)
        end
      end)
      
      abbreviated
    end
  end

  defp summarize_context(context) do
    module_count = case context[:modules] do
      modules when is_list(modules) -> length(modules)
      _ -> 0
    end
    
    function_count = case context[:functions] do
      functions when is_list(functions) -> length(functions)
      _ -> 0
    end
    
    "Context summary: #{module_count} modules, #{function_count} functions"
  end

  defp generate_interaction_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  defp broadcast_context_update(session_id, action) do
    # Use pg module for distributed event broadcasting
    event = %{
      session_id: session_id,
      action: action,
      node: node(),
      timestamp: DateTime.utc_now()
    }

    # Join the context_updates group if not already joined
    :pg.join(:context_updates, self())

    # Broadcast to all members of the group
    members = :pg.get_members(:context_updates)

    Enum.each(members, fn pid ->
      send(pid, {:context_update, event})
    end)
  end
end
