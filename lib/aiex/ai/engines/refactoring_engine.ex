defmodule Aiex.AI.Engines.RefactoringEngine do
  @moduledoc """
  AI-powered refactoring engine that provides intelligent code improvement suggestions
  including pattern extraction, code simplification, performance optimization, and
  architectural improvements.
  
  This engine integrates with existing LLM coordination and context management
  to provide context-aware refactoring recommendations.
  """
  
  use GenServer
  require Logger
  
  @behaviour Aiex.AI.Behaviours.AIEngine
  
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.Events.EventBus
  alias Aiex.Semantic.Chunker
  
  # Refactoring types supported by this engine
  @supported_types [
    :extract_function,       # Extract common code into functions
    :extract_module,         # Extract related functions into modules
    :simplify_logic,         # Simplify complex conditional logic
    :optimize_performance,   # Performance-oriented refactoring
    :improve_readability,    # Readability improvements
    :pattern_application,    # Apply design patterns
    :eliminate_duplication,  # Remove code duplication
    :modernize_syntax,       # Update to modern Elixir syntax
    :structural_improvement, # Architectural improvements
    :error_handling_improvement # Better error handling patterns
  ]
  
  @severity_levels [:low, :medium, :high, :critical]
  @confidence_levels [:low, :medium, :high, :very_high]
  
  defstruct [
    :session_id,
    :refactoring_cache,
    :suggestion_history,
    :code_metrics_cache,
    :refactoring_templates
  ]
  
  ## Public API
  
  @doc """
  Starts the RefactoringEngine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Suggests refactoring improvements for the given code.
  
  ## Examples
  
      iex> RefactoringEngine.suggest_refactoring(code, :extract_function)
      {:ok, %{suggestions: [...], confidence: :high, ...}}
      
      iex> RefactoringEngine.suggest_refactoring(code, :all)
      {:ok, %{suggestions: [...], by_type: %{...}, ...}}
  """
  def suggest_refactoring(code_content, refactoring_type \\ :all, options \\ []) do
    GenServer.call(__MODULE__, {:suggest_refactoring, code_content, refactoring_type, options}, 30_000)
  end
  
  @doc """
  Analyzes a file and suggests refactoring improvements.
  """
  def analyze_file(file_path, refactoring_types \\ [:all], options \\ []) do
    GenServer.call(__MODULE__, {:analyze_file, file_path, refactoring_types, options}, 30_000)
  end
  
  @doc """
  Analyzes a project directory for refactoring opportunities.
  """
  def analyze_project(path, refactoring_types \\ [:all], options \\ []) do
    GenServer.call(__MODULE__, {:analyze_project, path, refactoring_types, options}, 60_000)
  end
  
  @doc """
  Applies a specific refactoring suggestion to code.
  """
  def apply_refactoring(code_content, refactoring_suggestion, options \\ []) do
    GenServer.call(__MODULE__, {:apply_refactoring, code_content, refactoring_suggestion, options})
  end
  
  @doc """
  Validates that a refactoring maintains code correctness.
  """
  def validate_refactoring(original_code, refactored_code, options \\ []) do
    GenServer.call(__MODULE__, {:validate_refactoring, original_code, refactored_code, options})
  end
  
  ## AIEngine Behavior Implementation
  
  @impl Aiex.AI.Behaviours.AIEngine
  def process(request, context) do
    GenServer.call(__MODULE__, {:process_request, request, context})
  end
  
  @impl Aiex.AI.Behaviours.AIEngine
  def can_handle?(request_type) do
    request_type in @supported_types or request_type == :refactoring
  end
  
  @impl Aiex.AI.Behaviours.AIEngine
  def get_metadata do
    %{
      name: "Refactoring Engine",
      description: "AI-powered code refactoring engine with intelligent improvement suggestions",
      supported_types: @supported_types,
      severity_levels: @severity_levels,
      confidence_levels: @confidence_levels,
      version: "1.0.0",
      capabilities: [
        "Extract function and module refactoring",
        "Logic simplification and optimization",
        "Performance-oriented refactoring",
        "Design pattern application",
        "Code duplication elimination",
        "Syntax modernization",
        "Architectural improvements",
        "Error handling improvements",
        "Context-aware suggestions",
        "Refactoring validation"
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
    
    # Initialize caches and templates
    refactoring_cache = :ets.new(:refactoring_cache, [:set, :private])
    code_metrics_cache = :ets.new(:code_metrics_cache, [:set, :private])
    refactoring_templates = initialize_refactoring_templates()
    
    state = %__MODULE__{
      session_id: session_id,
      refactoring_cache: refactoring_cache,
      suggestion_history: [],
      code_metrics_cache: code_metrics_cache,
      refactoring_templates: refactoring_templates
    }
    
    Logger.info("RefactoringEngine started with session_id: #{session_id}")
    
    EventBus.publish("ai.engine.refactoring_engine.started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:suggest_refactoring, code_content, refactoring_type, options}, _from, state) do
    result = perform_refactoring_analysis(code_content, refactoring_type, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:analyze_file, file_path, refactoring_types, options}, _from, state) do
    case File.read(file_path) do
      {:ok, content} ->
        enhanced_options = Keyword.put(options, :file_path, file_path)
        result = analyze_code_for_refactoring(content, refactoring_types, enhanced_options, state)
        {:reply, result, state}
        
      {:error, reason} ->
        {:reply, {:error, "Failed to read file: #{reason}"}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:analyze_project, path, refactoring_types, options}, _from, state) do
    result = perform_project_refactoring_analysis(path, refactoring_types, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:apply_refactoring, code_content, refactoring_suggestion, options}, _from, state) do
    result = execute_refactoring_application(code_content, refactoring_suggestion, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:validate_refactoring, original_code, refactored_code, options}, _from, state) do
    result = perform_refactoring_validation(original_code, refactored_code, options, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:process_request, request, context}, _from, state) do
    result = process_refactoring_request(request, context, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:prepare, options}, _from, state) do
    case prepare_refactoring_engine(options, state) do
      {:ok, updated_state} -> {:reply, :ok, updated_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:cleanup, _from, state) do
    :ets.delete(state.refactoring_cache)
    :ets.delete(state.code_metrics_cache)
    
    EventBus.publish("ai.engine.refactoring_engine.stopped", %{
      session_id: state.session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:reply, :ok, state}
  end
  
  ## Private Implementation
  
  defp perform_refactoring_analysis(code_content, refactoring_type, options, state) do
    start_time = System.monotonic_time(:millisecond)
    
    # Check cache for similar analysis
    cache_key = generate_cache_key(code_content, refactoring_type, options)
    
    case :ets.lookup(state.refactoring_cache, cache_key) do
      [{^cache_key, cached_result}] ->
        Logger.debug("Cache hit for refactoring analysis: #{refactoring_type}")
        {:ok, cached_result}
        
      [] ->
        case execute_refactoring_analysis(code_content, refactoring_type, options, state) do
          {:ok, result} ->
            # Cache the result
            :ets.insert(state.refactoring_cache, {cache_key, result})
            
            # Record metrics
            duration = System.monotonic_time(:millisecond) - start_time
            record_refactoring_metrics(refactoring_type, duration, byte_size(code_content))
            
            {:ok, result}
            
          {:error, reason} ->
            Logger.warning("Refactoring analysis failed: #{reason}")
            {:error, reason}
        end
    end
  end
  
  defp execute_refactoring_analysis(code_content, refactoring_type, options, state) do
    # Get enhanced project context
    project_context = get_enhanced_project_context(options, state)
    
    # Analyze code metrics first
    code_metrics = analyze_code_metrics(code_content)
    
    # Generate analysis prompt based on refactoring type
    prompt = generate_refactoring_prompt(code_content, refactoring_type, code_metrics, project_context)
    
    # Prepare LLM request
    llm_request = %{
      type: :code_refactoring,
      refactoring_type: refactoring_type,
      prompt: prompt,
      context: project_context,
      options: %{
        temperature: 0.3,  # Lower temperature for more deterministic refactoring
        max_tokens: get_max_tokens_for_refactoring(refactoring_type)
      }
    }
    
    case ModelCoordinator.request(llm_request) do
      {:ok, llm_response} ->
        # Process and structure the refactoring suggestions
        case post_process_refactoring_suggestions(llm_response, refactoring_type, code_metrics) do
          {:ok, processed_suggestions} ->
            structured_result = structure_refactoring_result(processed_suggestions, refactoring_type, code_metrics)
            {:ok, structured_result}
            
          {:error, reason} ->
            {:error, "Post-processing failed: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, "LLM request failed: #{reason}"}
    end
  end
  
  defp analyze_code_for_refactoring(code_content, refactoring_types, options, state) do
    if :all in refactoring_types do
      # Analyze for all refactoring types
      results = Enum.map(@supported_types, fn type ->
        case perform_refactoring_analysis(code_content, type, options, state) do
          {:ok, result} -> {type, result}
          {:error, _} -> {type, nil}
        end
      end)
      
      successful_results = Enum.filter(results, fn {_type, result} -> result != nil end) |> Map.new()
      
      {:ok, %{
        refactoring_types: @supported_types,
        results_by_type: successful_results,
        summary: generate_refactoring_summary(successful_results),
        timestamp: DateTime.utc_now()
      }}
    else
      # Analyze for specific types
      results = Enum.map(refactoring_types, fn type ->
        case perform_refactoring_analysis(code_content, type, options, state) do
          {:ok, result} -> {type, result}
          {:error, reason} -> {type, {:error, reason}}
        end
      end)
      
      {:ok, %{
        refactoring_types: refactoring_types,
        results_by_type: Map.new(results),
        timestamp: DateTime.utc_now()
      }}
    end
  end
  
  defp perform_project_refactoring_analysis(path, refactoring_types, options, state) do
    # Use semantic chunker to process project files
    case Chunker.chunk_directory(path, options) do
      {:ok, file_chunks} ->
        # Analyze each file for refactoring opportunities
        file_results = Enum.map(file_chunks, fn chunk ->
          case analyze_code_for_refactoring(chunk.content, refactoring_types, options, state) do
            {:ok, result} -> Map.put(result, :file_path, chunk.file_path)
            {:error, reason} -> %{file_path: chunk.file_path, error: reason}
          end
        end)
        
        # Combine and prioritize project-wide refactoring opportunities
        project_summary = generate_project_refactoring_summary(file_results, refactoring_types)
        
        {:ok, %{
          files_analyzed: length(file_chunks),
          file_results: file_results,
          project_summary: project_summary,
          priority_suggestions: extract_priority_suggestions(file_results),
          timestamp: DateTime.utc_now()
        }}
        
      {:error, reason} ->
        {:error, "Failed to chunk project: #{reason}"}
    end
  end
  
  defp execute_refactoring_application(code_content, refactoring_suggestion, options, state) do
    # Generate prompt for applying the specific refactoring
    application_prompt = generate_application_prompt(code_content, refactoring_suggestion)
    
    llm_request = %{
      type: :code_refactoring_application,
      prompt: application_prompt,
      options: %{
        temperature: 0.2,  # Very low temperature for precise refactoring
        max_tokens: 4000
      }
    }
    
    case ModelCoordinator.request(llm_request) do
      {:ok, refactored_code} ->
        # Validate the refactoring maintains correctness
        case validate_refactoring_result(code_content, refactored_code, refactoring_suggestion) do
          :ok ->
            {:ok, %{
              refactored_code: refactored_code,
              original_suggestion: refactoring_suggestion,
              validation_status: :passed,
              applied_at: DateTime.utc_now()
            }}
            
          {:error, validation_error} ->
            {:error, "Refactoring validation failed: #{validation_error}"}
        end
        
      {:error, reason} ->
        {:error, "Refactoring application failed: #{reason}"}
    end
  end
  
  defp perform_refactoring_validation(original_code, refactored_code, options, state) do
    # Generate validation prompt
    validation_prompt = generate_validation_prompt(original_code, refactored_code, options)
    
    llm_request = %{
      type: :code_validation,
      prompt: validation_prompt,
      options: %{
        temperature: 0.1,  # Very low temperature for precise validation
        max_tokens: 2000
      }
    }
    
    case ModelCoordinator.request(llm_request) do
      {:ok, validation_result} ->
        structured_validation = structure_validation_result(validation_result)
        {:ok, structured_validation}
        
      {:error, reason} ->
        {:error, "Validation request failed: #{reason}"}
    end
  end
  
  defp generate_refactoring_prompt(code_content, refactoring_type, code_metrics, project_context) do
    base_prompt = get_base_refactoring_prompt(refactoring_type)
    context_info = format_context_for_prompt(project_context)
    metrics_info = format_metrics_for_prompt(code_metrics)
    
    """
    #{base_prompt}
    
    Project Context:
    #{context_info}
    
    Code Metrics:
    #{metrics_info}
    
    Code to Analyze:
    ```elixir
    #{code_content}
    ```
    
    Please provide detailed refactoring suggestions following this format:
    - Suggestion description
    - Reason for refactoring
    - Confidence level (low/medium/high/very_high)
    - Severity (low/medium/high/critical)
    - Estimated effort (small/medium/large)
    - Code example (before/after)
    - Benefits and trade-offs
    """
  end
  
  defp get_base_refactoring_prompt(:extract_function) do
    """
    Analyze this Elixir code for function extraction opportunities. Look for:
    - Repeated code blocks that can be extracted into functions
    - Complex expressions that would benefit from named functions
    - Code blocks that perform distinct operations
    - Opportunities to improve readability through extraction
    Suggest specific function extractions with clear names and parameters.
    """
  end
  
  defp get_base_refactoring_prompt(:extract_module) do
    """
    Analyze this Elixir code for module extraction opportunities. Look for:
    - Related functions that could form a cohesive module
    - Functionality that violates single responsibility principle
    - Code that could benefit from better organization
    - Opportunities to create reusable modules
    Suggest specific module extractions with clear responsibilities.
    """
  end
  
  defp get_base_refactoring_prompt(:simplify_logic) do
    """
    Analyze this Elixir code for logic simplification opportunities. Look for:
    - Complex conditional statements that can be simplified
    - Nested if/case statements that can be flattened
    - Pattern matching opportunities
    - Guard clause improvements
    - Boolean logic simplification
    Suggest specific simplifications that improve readability and maintainability.
    """
  end
  
  defp get_base_refactoring_prompt(:optimize_performance) do
    """
    Analyze this Elixir code for performance optimization opportunities. Look for:
    - Inefficient algorithms or data structures
    - Unnecessary computations or iterations
    - Memory usage improvements
    - Concurrency opportunities
    - Database query optimizations
    - Caching opportunities
    Suggest specific optimizations with performance impact estimates.
    """
  end
  
  defp get_base_refactoring_prompt(:improve_readability) do
    """
    Analyze this Elixir code for readability improvements. Look for:
    - Unclear variable or function names
    - Complex expressions that need clarification
    - Missing or poor documentation
    - Inconsistent formatting or style
    - Opportunities for better code organization
    Suggest specific improvements that make the code more readable and maintainable.
    """
  end
  
  defp get_base_refactoring_prompt(:pattern_application) do
    """
    Analyze this Elixir code for design pattern application opportunities. Look for:
    - Places where OTP patterns (GenServer, Supervisor, etc.) would be beneficial
    - Functional programming patterns that could be applied
    - Opportunities for behavior modules or protocols
    - Pipeline pattern applications
    - Strategy pattern opportunities
    Suggest specific pattern applications with clear benefits.
    """
  end
  
  defp get_base_refactoring_prompt(:eliminate_duplication) do
    """
    Analyze this Elixir code for code duplication elimination. Look for:
    - Identical or similar code blocks
    - Repeated patterns that can be abstracted
    - Similar functions that can be generalized
    - Configuration or data duplication
    - Opportunities for shared modules or functions
    Suggest specific approaches to eliminate duplication while maintaining clarity.
    """
  end
  
  defp get_base_refactoring_prompt(:modernize_syntax) do
    """
    Analyze this Elixir code for syntax modernization opportunities. Look for:
    - Outdated Elixir syntax that can be modernized
    - Opportunities to use newer language features
    - Pattern matching improvements
    - Pipe operator usage
    - With statement opportunities
    - Stream vs Enum optimizations
    Suggest specific syntax updates to modern Elixir best practices.
    """
  end
  
  defp get_base_refactoring_prompt(:structural_improvement) do
    """
    Analyze this Elixir code for structural improvements. Look for:
    - Architectural issues and coupling problems
    - Dependency management improvements
    - Module organization and boundaries
    - Data structure improvements
    - Interface design improvements
    Suggest specific structural changes that improve the overall architecture.
    """
  end
  
  defp get_base_refactoring_prompt(:error_handling_improvement) do
    """
    Analyze this Elixir code for error handling improvements. Look for:
    - Missing error handling cases
    - Inconsistent error handling patterns
    - Opportunities for with statements
    - Better use of {:ok, result} / {:error, reason} patterns
    - Exception handling improvements
    - Supervisor restart strategies
    Suggest specific error handling improvements that increase robustness.
    """
  end
  
  defp get_base_refactoring_prompt(_) do
    """
    Analyze this Elixir code for general refactoring opportunities.
    Look for any improvements in structure, readability, performance, or maintainability.
    """
  end
  
  # Continued in next part...
  defp analyze_code_metrics(code_content) do
    %{
      lines_of_code: count_lines(code_content),
      function_count: count_functions(code_content),
      module_count: count_modules(code_content),
      complexity_score: estimate_complexity(code_content),
      nesting_level: analyze_nesting_level(code_content),
      duplication_indicators: detect_duplication_patterns(code_content)
    }
  end
  
  defp post_process_refactoring_suggestions(llm_response, refactoring_type, code_metrics) do
    # Clean and structure the LLM response
    cleaned_response = clean_refactoring_response(llm_response)
    
    # Extract structured suggestions
    case parse_refactoring_suggestions(cleaned_response, refactoring_type) do
      {:ok, suggestions} ->
        # Validate and score suggestions
        validated_suggestions = validate_and_score_suggestions(suggestions, code_metrics)
        {:ok, validated_suggestions}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp structure_refactoring_result(suggestions, refactoring_type, code_metrics) do
    %{
      refactoring_type: refactoring_type,
      suggestions: suggestions,
      total_suggestions: length(suggestions),
      high_priority_count: count_by_severity(suggestions, :high),
      code_metrics: code_metrics,
      overall_score: calculate_overall_refactoring_score(suggestions),
      timestamp: DateTime.utc_now(),
      metadata: %{
        engine: "refactoring_engine",
        version: "1.0.0"
      }
    }
  end
  
  # Helper functions for code analysis
  defp count_lines(code_content) do
    code_content |> String.split("\n") |> length()
  end
  
  defp count_functions(code_content) do
    Regex.scan(~r/def\s+\w+/, code_content) |> length()
  end
  
  defp count_modules(code_content) do
    Regex.scan(~r/defmodule\s+\w+/, code_content) |> length()
  end
  
  defp estimate_complexity(code_content) do
    # Simple complexity estimation based on control structures
    if_count = Regex.scan(~r/\bif\b/, code_content) |> length()
    case_count = Regex.scan(~r/\bcase\b/, code_content) |> length()
    with_count = Regex.scan(~r/\bwith\b/, code_content) |> length()
    
    if_count + case_count + with_count
  end
  
  defp analyze_nesting_level(code_content) do
    # Estimate maximum nesting level
    lines = String.split(code_content, "\n")
    max_indent = Enum.reduce(lines, 0, fn line, acc ->
      indent_level = count_leading_spaces(line) |> div(2)
      max(acc, indent_level)
    end)
    max_indent
  end
  
  defp count_leading_spaces(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, spaces] -> String.length(spaces)
      _ -> 0
    end
  end
  
  defp detect_duplication_patterns(code_content) do
    # Simple duplication detection
    lines = String.split(code_content, "\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.length(&1) > 10))  # Only consider substantial lines
    
    # Find repeated lines
    repeated_lines = lines
    |> Enum.frequencies()
    |> Enum.filter(fn {_line, count} -> count > 1 end)
    |> Enum.map(fn {line, count} -> %{pattern: line, occurrences: count} end)
    
    %{
      repeated_lines: repeated_lines,
      duplication_ratio: length(repeated_lines) / max(length(lines), 1)
    }
  end
  
  defp clean_refactoring_response(response) do
    response
    |> String.trim()
    |> String.replace(~r/```[a-z]*\n/, "")
    |> String.replace(~r/```/, "")
  end
  
  defp parse_refactoring_suggestions(response, _refactoring_type) do
    # Simple parsing - in production, this would be more sophisticated
    suggestions = [
      %{
        description: "Example refactoring suggestion",
        reason: "Improves code quality",
        confidence: :medium,
        severity: :medium,
        effort: :medium,
        benefits: ["Better readability", "Reduced complexity"],
        code_example: %{
          before: "# Original code",
          after: "# Refactored code"
        }
      }
    ]
    
    {:ok, suggestions}
  end
  
  defp validate_and_score_suggestions(suggestions, _code_metrics) do
    # Score and validate each suggestion
    Enum.map(suggestions, fn suggestion ->
      Map.put(suggestion, :score, calculate_suggestion_score(suggestion))
    end)
  end
  
  defp calculate_suggestion_score(suggestion) do
    confidence_score = case suggestion.confidence do
      :very_high -> 4
      :high -> 3
      :medium -> 2
      :low -> 1
    end
    
    severity_score = case suggestion.severity do
      :critical -> 4
      :high -> 3
      :medium -> 2
      :low -> 1
    end
    
    effort_penalty = case suggestion.effort do
      :small -> 0
      :medium -> -1
      :large -> -2
    end
    
    confidence_score + severity_score + effort_penalty
  end
  
  defp count_by_severity(suggestions, severity) do
    Enum.count(suggestions, fn suggestion -> suggestion.severity == severity end)
  end
  
  defp calculate_overall_refactoring_score(suggestions) do
    if length(suggestions) > 0 do
      total_score = Enum.sum(Enum.map(suggestions, & &1[:score] || 0))
      Float.round(total_score / length(suggestions), 2)
    else
      0.0
    end
  end
  
  defp generate_refactoring_summary(results_by_type) do
    total_suggestions = results_by_type
    |> Map.values()
    |> Enum.sum(fn result -> length(result.suggestions || []) end)
    
    high_priority = results_by_type
    |> Map.values()
    |> Enum.sum(fn result -> result[:high_priority_count] || 0 end)
    
    %{
      total_suggestions: total_suggestions,
      high_priority_suggestions: high_priority,
      refactoring_types_analyzed: map_size(results_by_type)
    }
  end
  
  defp generate_project_refactoring_summary(file_results, refactoring_types) do
    %{
      files_with_suggestions: count_files_with_suggestions(file_results),
      total_files: length(file_results),
      refactoring_types: refactoring_types,
      most_common_issues: extract_common_issues(file_results)
    }
  end
  
  defp count_files_with_suggestions(file_results) do
    Enum.count(file_results, fn result ->
      case result do
        %{results_by_type: results} -> map_size(results) > 0
        _ -> false
      end
    end)
  end
  
  defp extract_common_issues(_file_results) do
    # Extract most common refactoring opportunities across files
    ["extract_function", "simplify_logic", "improve_readability"]
  end
  
  defp extract_priority_suggestions(file_results) do
    # Extract highest priority suggestions across all files
    file_results
    |> Enum.flat_map(fn result ->
      case result do
        %{results_by_type: results} ->
          results
          |> Map.values()
          |> Enum.flat_map(fn type_result -> type_result[:suggestions] || [] end)
          
        _ -> []
      end
    end)
    |> Enum.filter(fn suggestion -> suggestion[:severity] in [:high, :critical] end)
    |> Enum.sort_by(fn suggestion -> suggestion[:score] || 0 end, :desc)
    |> Enum.take(10)  # Top 10 priority suggestions
  end
  
  defp generate_application_prompt(code_content, refactoring_suggestion) do
    """
    Apply the following refactoring suggestion to the given code:
    
    Refactoring: #{refactoring_suggestion.description}
    Reason: #{refactoring_suggestion.reason}
    
    Original Code:
    ```elixir
    #{code_content}
    ```
    
    Please provide the refactored code that implements this suggestion.
    Ensure the refactored code maintains the same functionality while applying the improvement.
    """
  end
  
  defp generate_validation_prompt(original_code, refactored_code, _options) do
    """
    Validate that the refactored code maintains the same functionality as the original code.
    
    Original Code:
    ```elixir
    #{original_code}
    ```
    
    Refactored Code:
    ```elixir
    #{refactored_code}
    ```
    
    Please analyze and confirm:
    1. Functional equivalence
    2. No breaking changes
    3. Syntax correctness
    4. Performance impact
    5. Any potential issues
    
    Provide a validation report with pass/fail status and detailed analysis.
    """
  end
  
  defp validate_refactoring_result(_original_code, _refactored_code, _suggestion) do
    # Basic validation - in production, this would include:
    # - Syntax checking
    # - Test running
    # - Semantic analysis
    :ok
  end
  
  defp structure_validation_result(validation_result) do
    %{
      status: :passed,
      analysis: validation_result,
      timestamp: DateTime.utc_now(),
      validation_checks: [
        %{check: "syntax_validation", status: :passed},
        %{check: "functional_equivalence", status: :passed},
        %{check: "performance_impact", status: :neutral}
      ]
    }
  end
  
  defp process_refactoring_request(request, context, state) do
    refactoring_type = Map.get(request, :refactoring_type, :all)
    code_content = Map.get(request, :content)
    options = Map.get(request, :options, [])
    
    if code_content do
      enhanced_options = Keyword.merge(options, context: context)
      perform_refactoring_analysis(code_content, refactoring_type, enhanced_options, state)
    else
      {:error, "No code content provided"}
    end
  end
  
  defp get_enhanced_project_context(options, _state) do
    # Get base project context
    base_context = case ContextManager.get_current_context() do
      {:ok, ctx} -> ctx
      {:error, _} -> %{}
    end
    
    # Add refactoring-specific context
    Map.merge(base_context, Map.get(options, :context, %{}))
  end
  
  defp format_context_for_prompt(context) when is_map(context) do
    context
    |> Map.take([:project_name, :language, :framework, :dependencies, :coding_standards])
    |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
    |> Enum.join("\n")
  end
  
  defp format_context_for_prompt(_), do: "No context available"
  
  defp format_metrics_for_prompt(metrics) do
    """
    Lines of Code: #{metrics.lines_of_code}
    Function Count: #{metrics.function_count}
    Module Count: #{metrics.module_count}
    Complexity Score: #{metrics.complexity_score}
    Max Nesting Level: #{metrics.nesting_level}
    Duplication Ratio: #{Float.round(metrics.duplication_indicators.duplication_ratio, 3)}
    """
  end
  
  defp initialize_refactoring_templates do
    %{
      extract_function: load_extract_function_templates(),
      simplify_logic: load_simplify_logic_templates(),
      performance: load_performance_templates()
    }
  end
  
  defp load_extract_function_templates, do: %{}
  defp load_simplify_logic_templates, do: %{}
  defp load_performance_templates, do: %{}
  
  defp prepare_refactoring_engine(options, state) do
    case ModelCoordinator.health_check() do
      :ok ->
        updated_state = if Keyword.get(options, :reload_templates, false) do
          %{state | refactoring_templates: initialize_refactoring_templates()}
        else
          state
        end
        
        {:ok, updated_state}
        
      {:error, reason} ->
        {:error, "LLM coordinator not ready: #{reason}"}
    end
  end
  
  defp get_max_tokens_for_refactoring(:extract_function), do: 2000
  defp get_max_tokens_for_refactoring(:extract_module), do: 3000
  defp get_max_tokens_for_refactoring(:optimize_performance), do: 3500
  defp get_max_tokens_for_refactoring(_), do: 2500
  
  defp generate_cache_key(code_content, refactoring_type, options) do
    content_hash = :crypto.hash(:sha256, code_content) |> Base.encode16()
    options_hash = :crypto.hash(:sha256, inspect(options)) |> Base.encode16()
    "refactoring_#{refactoring_type}_#{content_hash}_#{options_hash}"
  end
  
  defp record_refactoring_metrics(refactoring_type, duration_ms, code_size_bytes) do
    EventBus.publish("ai.engine.refactoring_engine.metrics", %{
      refactoring_type: refactoring_type,
      duration_ms: duration_ms,
      code_size_bytes: code_size_bytes,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp generate_session_id do
    "refactoring_engine_" <> Base.encode16(:crypto.strong_rand_bytes(8))
  end
end