defmodule Aiex.AI.Engines.CodeAnalyzer do
  @moduledoc """
  Deep code analysis engine that provides comprehensive code insights,
  pattern detection, and architectural analysis.
  
  This engine integrates with the existing LLM coordination system
  and context management to provide intelligent code analysis.
  """
  
  use GenServer
  require Logger
  
  @behaviour Aiex.AI.Behaviours.AIEngine
  
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.LLM.Templates.TemplateEngine
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.Events.EventBus
  alias Aiex.Semantic.Chunker
  
  # Analysis types supported by this engine
  @supported_types [
    :structure_analysis,    # Code structure and organization
    :complexity_analysis,   # Cyclomatic complexity and code metrics
    :pattern_analysis,      # Design patterns and anti-patterns
    :dependency_analysis,   # Module dependencies and coupling
    :security_analysis,     # Security vulnerabilities and issues
    :performance_analysis,  # Performance bottlenecks and optimizations
    :quality_analysis       # Code quality and maintainability
  ]
  
  defstruct [
    :session_id,
    :llm_coordinator_pid,
    :context_manager_pid,
    :analysis_cache,
    :metrics_collector
  ]
  
  ## Public API
  
  @doc """
  Starts the CodeAnalyzer engine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Analyzes the given code with specified analysis type.
  
  ## Examples
  
      iex> CodeAnalyzer.analyze_code("defmodule MyModule do ... end", :structure_analysis)
      {:ok, %{analysis_type: :structure_analysis, results: ...}}
      
      iex> CodeAnalyzer.analyze_file("lib/my_module.ex", :complexity_analysis)
      {:ok, %{analysis_type: :complexity_analysis, results: ...}}
  """
  def analyze_code(code_content, analysis_type, options \\ []) do
    GenServer.call(__MODULE__, {:analyze_code, code_content, analysis_type, options})
  end
  
  @doc """
  Analyzes a file at the given path.
  """
  def analyze_file(file_path, analysis_type, options \\ []) do
    GenServer.call(__MODULE__, {:analyze_file, file_path, analysis_type, options})
  end
  
  @doc """
  Analyzes multiple files or a directory.
  """
  def analyze_project(path, analysis_types, options \\ []) do
    GenServer.call(__MODULE__, {:analyze_project, path, analysis_types, options}, 30_000)
  end
  
  ## AIEngine Behavior Implementation
  
  @impl Aiex.AI.Behaviours.AIEngine
  def process(request, context) do
    GenServer.call(__MODULE__, {:process_request, request, context})
  end
  
  @impl Aiex.AI.Behaviours.AIEngine
  def can_handle?(request_type) do
    request_type in @supported_types
  end
  
  @impl Aiex.AI.Behaviours.AIEngine
  def get_metadata do
    %{
      name: "Code Analyzer",
      description: "Deep code analysis engine for structure, complexity, patterns, and quality assessment",
      supported_types: @supported_types,
      version: "1.0.0",
      capabilities: [
        "AST-based code structure analysis",
        "Complexity metrics calculation",
        "Design pattern detection",
        "Security vulnerability scanning",
        "Performance bottleneck identification",
        "Code quality assessment"
      ]
    }
  end
  
  @impl Aiex.AI.Behaviours.AIEngine
  def prepare(options \\ []) do
    GenServer.call(__MODULE__, {:prepare, options})
  end
  
  @impl Aiex.AI.Behaviours.AIEngine
  def cleanup do
    GenServer.call(__MODULE__, :cleanup)
  end
  
  ## GenServer Implementation
  
  @impl GenServer
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    
    # Initialize analysis cache using ETS
    cache_table = :ets.new(:code_analysis_cache, [:set, :private])
    
    state = %__MODULE__{
      session_id: session_id,
      analysis_cache: cache_table,
      metrics_collector: %{}
    }
    
    Logger.info("CodeAnalyzer engine started with session_id: #{session_id}")
    
    # Emit event for engine startup
    EventBus.publish("ai.engine.code_analyzer.started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:analyze_code, code_content, analysis_type, options}, _from, state) do
    result = perform_code_analysis(code_content, analysis_type, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:analyze_file, file_path, analysis_type, options}, _from, state) do
    case File.read(file_path) do
      {:ok, content} ->
        # Add file context to options
        enhanced_options = Keyword.put(options, :file_path, file_path)
        result = perform_code_analysis(content, analysis_type, enhanced_options, state)
        {:reply, result, state}
        
      {:error, reason} ->
        {:reply, {:error, "Failed to read file: #{reason}"}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:analyze_project, path, analysis_types, options}, _from, state) do
    result = perform_project_analysis(path, analysis_types, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:process_request, request, context}, _from, state) do
    result = process_ai_request(request, context, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:prepare, options}, _from, state) do
    # Warm up the LLM connections and prepare analysis models
    case prepare_analysis_engine(options, state) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:cleanup, _from, state) do
    # Clean up cache and resources safely
    if :ets.info(state.analysis_cache) != :undefined do
      :ets.delete(state.analysis_cache)
    end
    
    EventBus.publish("ai.engine.code_analyzer.stopped", %{
      session_id: state.session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:reply, :ok, state}
  end
  
  ## Private Implementation
  
  defp perform_code_analysis(code_content, analysis_type, options, state) do
    start_time = System.monotonic_time(:millisecond)
    
    # Check cache first
    cache_key = generate_cache_key(code_content, analysis_type, options)
    
    case :ets.lookup(state.analysis_cache, cache_key) do
      [{^cache_key, cached_result}] ->
        Logger.debug("Cache hit for analysis: #{analysis_type}")
        {:ok, cached_result}
        
      [] ->
        # Perform fresh analysis
        case execute_analysis(code_content, analysis_type, options, state) do
          {:ok, result} ->
            # Cache the result
            :ets.insert(state.analysis_cache, {cache_key, result})
            
            # Record metrics
            duration = System.monotonic_time(:millisecond) - start_time
            record_analysis_metrics(analysis_type, duration, byte_size(code_content))
            
            {:ok, result}
            
          {:error, reason} ->
            Logger.warning("Analysis failed for type #{analysis_type}: #{reason}")
            {:error, reason}
        end
    end
  end
  
  defp execute_analysis(code_content, analysis_type, options, _state) do
    # Get project context for better analysis
    project_context = get_project_context(options)
    
    # Generate analysis prompt based on type
    prompt = generate_analysis_prompt(analysis_type, code_content, project_context)
    
    # Use existing LLM coordination for processing
    llm_request = %{
      type: :code_analysis,
      analysis_type: analysis_type,
      prompt: prompt,
      context: project_context,
      options: Map.new(options)
    }
    
    case ModelCoordinator.process_request(llm_request) do
      {:ok, llm_response} ->
        # Process and structure the LLM response
        structured_result = structure_analysis_result(llm_response, analysis_type, options)
        {:ok, structured_result}
        
      {:error, reason} ->
        {:error, "LLM request failed: #{reason}"}
    end
  end
  
  defp perform_project_analysis(path, analysis_types, options, _state) do
    # Use existing semantic chunker to process project files
    case Chunker.chunk_directory(path, options) do
      {:ok, file_chunks} ->
        results = Enum.map(analysis_types, fn analysis_type ->
          analyze_project_chunks(file_chunks, analysis_type, options, _state)
        end)
        
        # Combine and summarize results
        combined_results = combine_project_analysis_results(results, analysis_types)
        {:ok, combined_results}
        
      {:error, reason} ->
        {:error, "Failed to chunk project: #{reason}"}
    end
  end
  
  defp analyze_project_chunks(file_chunks, analysis_type, options, _state) do
    chunk_results = Enum.map(file_chunks, fn chunk ->
      case execute_analysis(chunk.content, analysis_type, options, _state) do
        {:ok, result} -> Map.put(result, :file_path, chunk.file_path)
        {:error, _} -> nil
      end
    end)
    
    Enum.filter(chunk_results, & &1)
  end
  
  defp process_ai_request(request, context, state) do
    analysis_type = Map.get(request, :analysis_type, :structure_analysis)
    code_content = Map.get(request, :content)
    options = Map.get(request, :options, [])
    
    if code_content do
      # Merge context into options
      enhanced_options = Keyword.merge(options, context: context)
      
      perform_code_analysis(code_content, analysis_type, enhanced_options, state)
    else
      {:error, "No code content provided"}
    end
  end
  
  defp generate_analysis_prompt(analysis_type, code_content, context) do
    # Use the template system for consistent, structured analysis prompts
    template_context = %{
      intent: :analyze,
      code: code_content,
      analysis_type: analysis_type,
      project_context: context,
      interface: Map.get(context, :interface, :ai_engine)
    }
    
    case TemplateEngine.render_for_intent(:analyze, template_context) do
      {:ok, rendered_prompt} -> 
        rendered_prompt
      {:error, reason} ->
        Logger.warning("Template rendering failed, falling back to legacy prompt: #{reason}")
        generate_legacy_analysis_prompt(analysis_type, code_content, context)
    end
  end
  
  # Fallback to legacy prompt generation if template system fails  
  defp generate_legacy_analysis_prompt(analysis_type, code_content, context) do
    base_prompt = get_base_analysis_prompt(analysis_type)
    context_info = format_context_for_prompt(context)
    
    """
    #{base_prompt}
    
    Project Context:
    #{context_info}
    
    Code to Analyze:
    ```elixir
    #{code_content}
    ```
    
    Please provide a detailed analysis following the requested format.
    """
  end
  
  defp get_base_analysis_prompt(:structure_analysis) do
    """
    Analyze the code structure and organization. Focus on:
    - Module organization and responsibilities
    - Function organization and grouping  
    - Code hierarchy and dependencies
    - Architectural patterns used
    - Suggestions for structural improvements
    """
  end
  
  defp get_base_analysis_prompt(:complexity_analysis) do
    """
    Analyze the code complexity and provide metrics. Focus on:
    - Cyclomatic complexity of functions
    - Cognitive complexity assessment
    - Nesting levels and control flow
    - Function length and parameter counts
    - Suggestions for complexity reduction
    """
  end
  
  defp get_base_analysis_prompt(:pattern_analysis) do
    """
    Analyze design patterns and anti-patterns in the code. Focus on:
    - Design patterns implemented (OTP, functional patterns)
    - Anti-patterns and code smells detected
    - Opportunities for pattern application
    - Elixir/OTP best practices compliance
    - Refactoring suggestions for better patterns
    """
  end
  
  defp get_base_analysis_prompt(:security_analysis) do
    """
    Analyze the code for security vulnerabilities and issues. Focus on:
    - Input validation and sanitization
    - Authentication and authorization concerns
    - Data exposure and privacy issues
    - Injection vulnerabilities
    - Security best practices compliance
    """
  end
  
  defp get_base_analysis_prompt(:performance_analysis) do
    """
    Analyze the code for performance bottlenecks and optimization opportunities. Focus on:
    - Algorithm efficiency and Big O complexity
    - Memory usage patterns
    - Process and concurrency patterns
    - Database query optimization opportunities
    - Caching and optimization strategies
    """
  end
  
  defp get_base_analysis_prompt(:quality_analysis) do
    """
    Analyze the code quality and maintainability. Focus on:
    - Code readability and documentation
    - Naming conventions and consistency
    - Error handling patterns
    - Test coverage and testability
    - Maintainability and extensibility
    """
  end
  
  defp get_base_analysis_prompt(_) do
    "Provide a comprehensive analysis of the given code."
  end
  
  defp structure_analysis_result(llm_response, analysis_type, options) do
    %{
      analysis_type: analysis_type,
      timestamp: DateTime.utc_now(),
      results: llm_response,
      metadata: %{
        engine: "code_analyzer",
        version: "1.0.0",
        options: Map.new(options)
      }
    }
  end
  
  defp combine_project_analysis_results(results, analysis_types) do
    %{
      analysis_types: analysis_types,
      timestamp: DateTime.utc_now(),
      files_analyzed: count_analyzed_files(results),
      results_by_type: Enum.zip(analysis_types, results) |> Map.new(),
      summary: generate_project_summary(results, analysis_types)
    }
  end
  
  defp get_project_context(_options) do
    # Leverage existing context management
    case ContextManager.get_context("default") do
      {:ok, context} -> context
      {:error, _} -> %{}
    end
  end
  
  defp format_context_for_prompt(context) when is_map(context) do
    context
    |> Map.take([:project_name, :language, :framework, :dependencies])
    |> Enum.map(fn {key, value} -> "#{key}: #{value}" end)
    |> Enum.join("\n")
  end
  
  defp format_context_for_prompt(_), do: "No context available"
  
  defp prepare_analysis_engine(_options, _state) do
    # Warm up LLM connections and validate dependencies
    case ModelCoordinator.force_health_check() do
      :ok -> :ok
      {:error, reason} -> {:error, "LLM coordinator not ready: #{reason}"}
    end
  end
  
  defp generate_cache_key(code_content, analysis_type, options) do
    content_hash = :crypto.hash(:sha256, code_content) |> Base.encode16()
    options_hash = :crypto.hash(:sha256, inspect(options)) |> Base.encode16()
    "#{analysis_type}_#{content_hash}_#{options_hash}"
  end
  
  defp record_analysis_metrics(analysis_type, duration_ms, code_size_bytes) do
    EventBus.publish("ai.engine.code_analyzer.metrics", %{
      analysis_type: analysis_type,
      duration_ms: duration_ms,
      code_size_bytes: code_size_bytes,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp count_analyzed_files(results) do
    results
    |> List.flatten()
    |> Enum.map(& Map.get(&1, :file_path))
    |> Enum.filter(& &1)
    |> Enum.uniq()
    |> length()
  end
  
  defp generate_project_summary(results, analysis_types) do
    "Analyzed project with #{length(analysis_types)} analysis types, " <>
    "processing #{count_analyzed_files(results)} files"
  end
  
  defp generate_session_id do
    "code_analyzer_" <> Base.encode16(:crypto.strong_rand_bytes(8))
  end
end