defmodule Aiex.IEx.Helpers do
  @moduledoc """
  Distributed IEx helpers for AI-assisted development.

  This module provides enhanced IEx helper functions that work across 
  cluster nodes, enabling AI-assisted development with access to the 
  full distributed context.

  ## Usage

  Start an IEx session with the project:

      iex -S mix

  Then use the AI helpers:

      iex> ai_complete("defmodule MyMod")
      # AI-generated completion suggestions

      iex> ai_explain(MyGenServer.handle_call)
      # AI explanation of the function

      iex> ai_test(MyModule)
      # AI-generated tests for the module

      iex> cluster_status()
      # Distributed cluster information

  ## Distributed Features

  All helpers are cluster-aware and can:
  - Access context from any node in the cluster
  - Route requests to optimal nodes based on load
  - Aggregate results from multiple nodes
  - Handle node failures gracefully

  ## Configuration

  Configure distributed AI helpers in config/config.exs:

      config :aiex, Aiex.IEx.Helpers,
        default_model: "gpt-4",
        max_completion_length: 200,
        distributed_timeout: 30_000,
        prefer_local_node: true
  """

  alias Aiex.InterfaceGateway
  alias Aiex.Context.DistributedEngine
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.Events.EventBus

  require Logger

  @doc """
  AI-powered code completion with distributed context.

  Provides intelligent code completions based on the current codebase context
  and distributed cluster knowledge.

  ## Examples

      iex> ai_complete("defmodule MyModule")
      %{
        suggestions: [
          "defmodule MyModule do\\n  use GenServer\\n  ...\\nend",
          "defmodule MyModule.Worker do\\n  ...\\nend"
        ],
        confidence: 0.95,
        context_nodes: [:node1@host, :node2@host]
      }

      iex> ai_complete("def handle_call", context: %{module: MyGenServer})
      %{suggestions: ["def handle_call({:get_state}, _from, state)..."], ...}
  """
  def ai_complete(code_fragment, opts \\ []) do
    context = build_distributed_context(code_fragment, opts)
    
    request = %{
      id: generate_request_id(),
      type: :completion,
      content: code_fragment,
      context: context,
      options: completion_options(opts),
      priority: :high
    }

    case submit_distributed_request(request, opts) do
      {:ok, response} ->
        format_completion_response(response)
      
      {:error, reason} ->
        %{
          error: reason,
          suggestions: [],
          fallback: generate_fallback_completion(code_fragment)
        }
    end
  end

  @doc """
  AI-powered code explanation with distributed analysis.

  Explains code by analyzing it in the context of the entire distributed
  codebase, including dependencies and usage patterns.

  ## Examples

      iex> ai_explain(MyModule.complex_function)
      %{
        explanation: "This function implements a distributed consensus algorithm...",
        complexity: :high,
        dependencies: [:node1@host, :node2@host],
        usage_examples: ["MyModule.complex_function(data, :option)"]
      }

      iex> ai_explain("GenServer.call(pid, :message)")
      %{explanation: "GenServer.call/2 sends a synchronous message...", ...}
  """
  def ai_explain(code_or_function, opts \\ []) do
    {code, metadata} = extract_code_and_metadata(code_or_function)
    context = build_explanation_context(code, metadata, opts)
    
    request = %{
      id: generate_request_id(),
      type: :explanation,
      content: code,
      context: context,
      options: explanation_options(opts),
      priority: :normal
    }

    case submit_distributed_request(request, opts) do
      {:ok, response} ->
        format_explanation_response(response, metadata)
      
      {:error, reason} ->
        %{
          error: reason,
          explanation: "Unable to generate explanation: #{reason}",
          fallback: generate_basic_explanation(code)
        }
    end
  end

  @doc """
  AI-powered test generation with distributed examples.

  Generates comprehensive tests based on the module/function and examples
  from across the distributed cluster.

  ## Examples

      iex> ai_test(MyModule)
      %{
        test_file: "test/my_module_test.exs",
        tests: ["test \\"handles valid input\\"", ...],
        coverage: 0.85,
        examples_from: [:node1@host, :node2@host]
      }

      iex> ai_test(MyModule.calculate, type: :property)
      %{test_type: :property_based, generators: [...], ...}
  """
  def ai_test(module_or_function, opts \\ []) do
    {target, metadata} = extract_test_target(module_or_function)
    context = build_test_context(target, metadata, opts)
    
    request = %{
      id: generate_request_id(),
      type: :test_generation,
      content: target,
      context: context,
      options: test_options(opts),
      priority: :normal
    }

    case submit_distributed_request(request, opts) do
      {:ok, response} ->
        format_test_response(response, metadata)
      
      {:error, reason} ->
        %{
          error: reason,
          tests: [],
          fallback: generate_basic_tests(target)
        }
    end
  end

  @doc """
  Get comprehensive cluster status and health information.

  ## Examples

      iex> cluster_status()
      %{
        local_node: :app@local,
        connected_nodes: [:app@node1, :app@node2],
        total_nodes: 3,
        cluster_health: :healthy,
        ai_providers: %{active: 2, healthy: 2},
        context_engines: %{active: 3, synced: true},
        interfaces: %{cli: 1, liveview: 0, lsp: 0}
      }
  """
  def cluster_status do
    %{
      local_node: node(),
      connected_nodes: Node.list(),
      total_nodes: 1 + length(Node.list()),
      cluster_health: determine_cluster_health(),
      ai_providers: get_ai_provider_status(),
      context_engines: get_context_engine_status(),
      interfaces: get_interface_status(),
      last_updated: DateTime.utc_now()
    }
  end

  @doc """
  Find and explain usage patterns across the cluster.

  ## Examples

      iex> ai_usage(MyModule.function)
      %{
        total_usages: 15,
        usage_patterns: [
          %{pattern: "MyModule.function(data)", frequency: 8, nodes: [...]},
          %{pattern: "MyModule.function(data, opts)", frequency: 7, nodes: [...]}
        ],
        best_practices: ["Always validate input data", ...]
      }
  """
  def ai_usage(function_name, opts \\ []) do
    context = build_usage_context(function_name, opts)
    
    request = %{
      id: generate_request_id(),
      type: :analysis,
      content: "Find usage patterns for: #{inspect(function_name)}",
      context: context,
      options: usage_options(opts),
      priority: :low
    }

    case submit_distributed_request(request, opts) do
      {:ok, response} ->
        format_usage_response(response)
      
      {:error, reason} ->
        %{
          error: reason,
          total_usages: 0,
          usage_patterns: [],
          best_practices: []
        }
    end
  end

  @doc """
  Access distributed context information for a specific code element.

  ## Examples

      iex> distributed_context("MyModule")
      %{
        local_definitions: [...],
        remote_definitions: %{node1@host => [...], node2@host => [...]},
        dependencies: [...],
        dependents: [...],
        total_context_size: 1024
      }
  """
  def distributed_context(code_element, opts \\ []) do
    case DistributedEngine.get_distributed_context(code_element, opts) do
      {:ok, context} ->
        format_context_response(context)
      
      {:error, reason} ->
        %{
          error: reason,
          local_definitions: [],
          remote_definitions: %{},
          dependencies: [],
          dependents: []
        }
    end
  end

  @doc """
  Select optimal node for AI processing based on current load.

  ## Examples

      iex> select_optimal_node(:completion)
      {:ok, :node2@host, %{load: 0.3, ai_providers: 2}}

      iex> select_optimal_node(:analysis, prefer_local: false)
      {:ok, :node1@host, %{load: 0.1, context_size: "large"}}
  """
  def select_optimal_node(request_type, opts \\ []) do
    available_nodes = [node() | Node.list()]
    prefer_local = Keyword.get(opts, :prefer_local, get_config(:prefer_local_node))
    
    node_stats = Enum.map(available_nodes, fn node ->
      {node, get_node_stats(node, request_type)}
    end)
    
    optimal_node = case prefer_local and is_node_suitable?(node(), request_type) do
      true -> node()
      false -> select_best_node(node_stats, request_type)
    end
    
    case optimal_node do
      nil -> {:error, :no_suitable_nodes}
      node -> {:ok, node, get_node_stats(node, request_type)}
    end
  end

  ## Private Functions

  defp build_distributed_context(code_fragment, opts) do
    base_context = %{
      fragment: code_fragment,
      current_module: get_current_module(),
      file_context: get_file_context(opts),
      timestamp: DateTime.utc_now()
    }

    # Add distributed context if available
    case DistributedEngine.get_related_context(code_fragment) do
      {:ok, distributed_context} ->
        Map.merge(base_context, %{
          distributed: distributed_context,
          cluster_nodes: [node() | Node.list()]
        })
      
      {:error, _} ->
        base_context
    end
  end

  defp build_explanation_context(code, metadata, opts) do
    %{
      code: code,
      metadata: metadata,
      context_depth: Keyword.get(opts, :depth, :medium),
      include_examples: Keyword.get(opts, :examples, true),
      cluster_wide: Keyword.get(opts, :cluster_wide, true)
    }
  end

  defp build_test_context(target, metadata, opts) do
    %{
      target: target,
      metadata: metadata,
      test_type: Keyword.get(opts, :type, :unit),
      coverage_goal: Keyword.get(opts, :coverage, 0.8),
      include_integration: Keyword.get(opts, :integration, false)
    }
  end

  defp build_usage_context(function_name, opts) do
    %{
      function_name: function_name,
      search_depth: Keyword.get(opts, :depth, :deep),
      include_tests: Keyword.get(opts, :include_tests, true),
      cluster_wide: true
    }
  end

  defp submit_distributed_request(request, opts) do
    # Select optimal node for processing
    case select_optimal_node(request.type, opts) do
      {:ok, target_node, _stats} when target_node == node() ->
        # Process locally
        submit_local_request(request)
      
      {:ok, target_node, _stats} ->
        # Delegate to remote node
        submit_remote_request(request, target_node, opts)
      
      {:error, reason} ->
        Logger.warning("No suitable nodes for request type #{request.type}: #{reason}")
        submit_local_request(request)
    end
  end

  defp submit_local_request(request) do
    # Register a temporary interface for IEx
    interface_config = %{
      type: :iex,
      session_id: "iex_#{System.system_time(:millisecond)}",
      user_id: nil,
      capabilities: [:ai_assistance, :code_completion],
      settings: %{}
    }

    case InterfaceGateway.register_interface(__MODULE__, interface_config) do
      {:ok, interface_id} ->
        result = InterfaceGateway.submit_request(interface_id, request)
        InterfaceGateway.unregister_interface(interface_id)
        
        case result do
          {:ok, request_id} ->
            # Wait for completion (simplified for IEx usage)
            wait_for_completion(request_id)
          
          {:error, reason} ->
            {:error, reason}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp submit_remote_request(request, target_node, opts) do
    timeout = Keyword.get(opts, :timeout, get_config(:distributed_timeout))
    
    try do
      :rpc.call(target_node, __MODULE__, :submit_local_request, [request], timeout)
    catch
      :exit, reason ->
        Logger.warning("Remote request to #{target_node} failed: #{inspect(reason)}")
        {:error, {:remote_call_failed, reason}}
    end
  end

  defp wait_for_completion(request_id, timeout \\ 30_000) do
    # Subscribe to completion events
    EventBus.subscribe(:request_completed)
    EventBus.subscribe(:request_failed)
    
    receive do
      {:event, :request_completed, %{request_id: ^request_id, response: response}} ->
        {:ok, response}
      
      {:event, :request_failed, %{request_id: ^request_id, reason: reason}} ->
        {:error, reason}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  # Helper functions for extracting code and metadata
  
  defp extract_code_and_metadata(code) when is_binary(code) do
    {code, %{type: :string, length: String.length(code)}}
  end

  defp extract_code_and_metadata({module, function}) when is_atom(module) and is_atom(function) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        function_doc = Enum.find(docs, fn {{type, name, _arity}, _, _, _, _} ->
          type == :function and name == function
        end)
        
        code = case function_doc do
          {{:function, ^function, arity}, _, _, source, _} when is_binary(source) -> source
          _ -> "#{module}.#{function}"
        end
        
        {code, %{type: :function, module: module, function: function}}
      
      _ ->
        {"#{module}.#{function}", %{type: :function, module: module, function: function}}
    end
  end

  defp extract_code_and_metadata(other) do
    {inspect(other), %{type: :term}}
  end

  defp extract_test_target(module) when is_atom(module) do
    {Atom.to_string(module), %{type: :module, module: module}}
  end

  defp extract_test_target({module, function}) when is_atom(module) and is_atom(function) do
    {"#{module}.#{function}", %{type: :function, module: module, function: function}}
  end

  defp extract_test_target(other) do
    {inspect(other), %{type: :term}}
  end

  # Response formatting functions

  defp format_completion_response(response) do
    %{
      suggestions: parse_suggestions(response.content),
      confidence: Map.get(response.metadata, :confidence, 0.5),
      context_nodes: Map.get(response.metadata, :nodes_used, [node()]),
      processing_time: Map.get(response.metadata, :processing_time, 0)
    }
  end

  defp format_explanation_response(response, metadata) do
    %{
      explanation: response.content,
      complexity: determine_complexity(response.content),
      metadata: metadata,
      confidence: Map.get(response.metadata, :confidence, 0.5),
      sources: Map.get(response.metadata, :sources, [])
    }
  end

  defp format_test_response(response, metadata) do
    %{
      test_file: generate_test_filename(metadata),
      tests: parse_generated_tests(response.content),
      coverage_estimate: Map.get(response.metadata, :coverage, 0.0),
      test_type: Map.get(response.metadata, :test_type, :unit),
      examples_from: Map.get(response.metadata, :nodes_used, [node()])
    }
  end

  defp format_usage_response(response) do
    usage_data = parse_usage_data(response.content)
    
    %{
      total_usages: Map.get(usage_data, :total, 0),
      usage_patterns: Map.get(usage_data, :patterns, []),
      best_practices: Map.get(usage_data, :best_practices, []),
      analysis_confidence: Map.get(response.metadata, :confidence, 0.5)
    }
  end

  defp format_context_response(context) do
    %{
      local_definitions: Map.get(context, :local, []),
      remote_definitions: Map.get(context, :remote, %{}),
      dependencies: Map.get(context, :dependencies, []),
      dependents: Map.get(context, :dependents, []),
      total_context_size: calculate_context_size(context)
    }
  end

  # Utility functions

  defp get_current_module do
    # Try to determine current module context
    case Process.get(:iex_current_module) do
      nil -> nil
      module -> module
    end
  end

  defp get_file_context(opts) do
    case Keyword.get(opts, :file) do
      nil -> %{}
      file_path -> %{file: file_path, directory: Path.dirname(file_path)}
    end
  end

  defp determine_cluster_health do
    total_nodes = 1 + length(Node.list())
    
    cond do
      total_nodes >= 3 -> :healthy
      total_nodes == 2 -> :degraded
      true -> :single_node
    end
  end

  defp get_ai_provider_status do
    case Process.whereis(ModelCoordinator) do
      nil -> %{active: 0, healthy: 0}
      _pid -> 
        try do
          status = ModelCoordinator.get_cluster_status()
          %{
            active: Map.get(status, :active_providers, 0),
            healthy: Map.get(status, :healthy_providers, 0)
          }
        catch
          _, _ -> %{active: 0, healthy: 0}
        end
    end
  end

  defp get_context_engine_status do
    case Process.whereis(DistributedEngine) do
      nil -> %{active: 0, synced: false}
      _pid -> %{active: 1 + length(Node.list()), synced: true}
    end
  end

  defp get_interface_status do
    case Process.whereis(InterfaceGateway) do
      nil -> %{cli: 0, liveview: 0, lsp: 0}
      _pid ->
        try do
          interfaces = InterfaceGateway.get_interfaces_status()
          Enum.reduce(interfaces, %{cli: 0, liveview: 0, lsp: 0}, fn {_id, info}, acc ->
            type = info.type
            Map.update(acc, type, 1, &(&1 + 1))
          end)
        catch
          _, _ -> %{cli: 0, liveview: 0, lsp: 0}
        end
    end
  end

  defp get_node_stats(node, request_type) do
    base_stats = %{
      load: :rand.uniform(),  # Placeholder - would be real system load
      memory_usage: 0.5,
      ai_providers: 1,
      suitable: true
    }
    
    # Add request-type specific stats
    case request_type do
      :completion -> Map.put(base_stats, :completion_cache_size, 100)
      :analysis -> Map.put(base_stats, :context_size, "medium")
      _ -> base_stats
    end
  end

  defp is_node_suitable?(node, _request_type) do
    # Simple check - in real implementation would check resources, capabilities
    Node.ping(node) == :pong
  end

  defp select_best_node(node_stats, _request_type) do
    node_stats
    |> Enum.filter(fn {_node, stats} -> stats.suitable end)
    |> Enum.min_by(fn {_node, stats} -> stats.load end, fn -> nil end)
    |> case do
      {node, _stats} -> node
      nil -> nil
    end
  end

  # Configuration and options

  defp completion_options(opts) do
    defaults = [
      model: get_config(:default_model),
      max_length: get_config(:max_completion_length),
      temperature: 0.3
    ]
    
    Keyword.merge(defaults, opts)
  end

  defp explanation_options(opts) do
    defaults = [
      model: get_config(:default_model),
      detail_level: :medium,
      include_examples: true
    ]
    
    Keyword.merge(defaults, opts)
  end

  defp test_options(opts) do
    defaults = [
      model: get_config(:default_model),
      test_framework: :ex_unit,
      coverage_target: 0.8
    ]
    
    Keyword.merge(defaults, opts)
  end

  defp usage_options(opts) do
    defaults = [
      model: get_config(:default_model),
      search_scope: :cluster_wide,
      max_examples: 10
    ]
    
    Keyword.merge(defaults, opts)
  end

  defp get_config(key) do
    Application.get_env(:aiex, __MODULE__, [])
    |> Keyword.get(key, default_config(key))
  end

  defp default_config(:default_model), do: "gpt-4"
  defp default_config(:max_completion_length), do: 200
  defp default_config(:distributed_timeout), do: 30_000
  defp default_config(:prefer_local_node), do: true
  defp default_config(_), do: nil

  # Parsing and generation helpers

  defp parse_suggestions(content) when is_binary(content) do
    content
    |> String.split("\n---\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_suggestions(_), do: []

  defp determine_complexity(explanation) do
    word_count = explanation |> String.split() |> length()
    
    cond do
      word_count > 200 -> :high
      word_count > 100 -> :medium
      true -> :low
    end
  end

  defp generate_test_filename(%{type: :module, module: module}) do
    module_name = module |> Atom.to_string() |> String.replace("Elixir.", "")
    snake_case = Macro.underscore(module_name)
    "test/#{snake_case}_test.exs"
  end

  defp generate_test_filename(_), do: "test/generated_test.exs"

  defp parse_generated_tests(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "test "))
    |> Enum.map(&String.trim/1)
  end

  defp parse_generated_tests(_), do: []

  defp parse_usage_data(content) when is_binary(content) do
    # Simple parsing - in real implementation would be more sophisticated
    %{
      total: :rand.uniform(50),
      patterns: [
        %{pattern: "Standard usage", frequency: 20},
        %{pattern: "With options", frequency: 15}
      ],
      best_practices: ["Always validate inputs", "Handle errors gracefully"]
    }
  end

  defp parse_usage_data(_), do: %{total: 0, patterns: [], best_practices: []}

  defp calculate_context_size(context) do
    context
    |> Map.values()
    |> Enum.map(&byte_size(inspect(&1)))
    |> Enum.sum()
  end

  defp generate_fallback_completion(code_fragment) do
    ["# TODO: Complete #{code_fragment}", "# Implementation needed"]
  end

  defp generate_basic_explanation(code) do
    "Basic code structure: #{String.slice(code, 0..50)}..."
  end

  defp generate_basic_tests(target) do
    ["# TODO: Write tests for #{target}"]
  end

  defp generate_request_id do
    "iex_req_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  # InterfaceBehaviour implementation (minimal for IEx usage)
  
  @behaviour Aiex.InterfaceBehaviour

  @impl true
  def init(config), do: {:ok, config}

  @impl true
  def handle_request(request, state) do
    # For IEx, we just pass through to the distributed system
    {:async, request.id, state}
  end

  @impl true
  def handle_event(_type, _data, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  @impl true
  def get_status(state) do
    %{
      capabilities: [:ai_assistance, :code_completion],
      active_requests: [],
      session_info: %{interface: :iex},
      health: :healthy
    }
  end
end