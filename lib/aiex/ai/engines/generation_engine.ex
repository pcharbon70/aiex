defmodule Aiex.AI.Engines.GenerationEngine do
  @moduledoc """
  Intelligent code generation engine that creates modules, functions, tests,
  and other code artifacts based on specifications and context.
  
  This engine integrates with existing LLM coordination and context management
  to generate contextually appropriate code following project conventions.
  """
  
  use GenServer
  require Logger
  
  @behaviour Aiex.AI.Behaviours.AIEngine
  
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.LLM.Templates.TemplateEngine
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.Events.EventBus
  alias Aiex.Semantic.Chunker
  alias Aiex.Sandbox.PathValidator
  
  # Generation types supported by this engine
  @supported_types [
    :module_generation,      # Complete modules with functions
    :function_generation,    # Individual functions
    :test_generation,        # Test suites and test cases
    :documentation_generation, # Module and function documentation
    :boilerplate_generation, # Common boilerplate patterns
    :refactoring_generation, # Refactored versions of existing code
    :api_generation,         # API endpoint implementations
    :schema_generation       # Database schemas and migrations
  ]
  
  defstruct [
    :session_id,
    :generation_cache,
    :project_conventions,
    :template_registry
  ]
  
  ## Public API
  
  @doc """
  Starts the GenerationEngine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Generates code based on the specification and type.
  
  ## Examples
  
      iex> GenerationEngine.generate_code(:module_generation, "Calculator", "basic arithmetic operations")
      {:ok, %{type: :module_generation, generated_code: "defmodule Calculator do...", metadata: ...}}
      
      iex> GenerationEngine.generate_function("add", "adds two numbers", ["a", "b"])
      {:ok, %{type: :function_generation, generated_code: "def add(a, b) do...", metadata: ...}}
  """
  def generate_code(generation_type, specification, context \\ %{}) do
    GenServer.call(__MODULE__, {:generate_code, generation_type, specification, context})
  end
  
  @doc """
  Generates a complete module with the given name and description.
  """
  def generate_module(module_name, description, options \\ []) do
    context = %{
      module_name: module_name,
      description: description,
      options: options
    }
    generate_code(:module_generation, description, context)
  end
  
  @doc """
  Generates a function with the given signature and description.
  """
  def generate_function(function_name, description, parameters \\ [], options \\ []) do
    context = %{
      function_name: function_name,
      description: description,
      parameters: parameters,
      options: options
    }
    generate_code(:function_generation, description, context)
  end
  
  @doc """
  Generates tests for the given code or module.
  """
  def generate_tests(target_code, test_type \\ :unit_tests, options \\ []) do
    context = %{
      target_code: target_code,
      test_type: test_type,
      options: options
    }
    generate_code(:test_generation, "Generate comprehensive tests", context)
  end
  
  @doc """
  Generates documentation for the given code.
  """
  def generate_documentation(code_content, doc_type \\ :module_docs, options \\ []) do
    context = %{
      code_content: code_content,
      doc_type: doc_type,
      options: options
    }
    generate_code(:documentation_generation, "Generate comprehensive documentation", context)
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
      name: "Generation Engine",
      description: "Intelligent code generation engine for modules, functions, tests, and documentation",
      supported_types: @supported_types,
      version: "1.0.0",
      capabilities: [
        "Context-aware module generation",
        "Function generation with proper signatures",
        "Comprehensive test suite generation",
        "Documentation generation (ExDoc format)",
        "Boilerplate and scaffold generation",
        "Project convention compliance",
        "Refactoring code generation"
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
    
    # Initialize generation cache and template registry
    cache_table = :ets.new(:generation_cache, [:set, :private])
    template_registry = initialize_template_registry()
    
    state = %__MODULE__{
      session_id: session_id,
      generation_cache: cache_table,
      project_conventions: %{},
      template_registry: template_registry
    }
    
    Logger.info("GenerationEngine started with session_id: #{session_id}")
    
    # Load project conventions
    updated_state = load_project_conventions(state)
    
    EventBus.emit("ai.engine.generation_engine.started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, updated_state}
  end
  
  @impl GenServer
  def handle_call({:generate_code, generation_type, specification, context}, _from, state) do
    result = perform_code_generation(generation_type, specification, context, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:process_request, request, context}, _from, state) do
    result = process_generation_request(request, context, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:prepare, options}, _from, state) do
    case prepare_generation_engine(options, state) do
      {:ok, updated_state} -> {:reply, :ok, updated_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:cleanup, _from, state) do
    :ets.delete(state.generation_cache)
    
    EventBus.emit("ai.engine.generation_engine.stopped", %{
      session_id: state.session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:reply, :ok, state}
  end
  
  ## Private Implementation
  
  defp perform_code_generation(generation_type, specification, context, state) do
    start_time = System.monotonic_time(:millisecond)
    
    # Check cache for similar generations
    cache_key = generate_cache_key(generation_type, specification, context)
    
    case :ets.lookup(state.generation_cache, cache_key) do
      [{^cache_key, cached_result}] ->
        Logger.debug("Cache hit for generation: #{generation_type}")
        {:ok, cached_result}
        
      [] ->
        case execute_generation(generation_type, specification, context, state) do
          {:ok, result} ->
            # Cache the result
            :ets.insert(state.generation_cache, {cache_key, result})
            
            # Record metrics
            duration = System.monotonic_time(:millisecond) - start_time
            record_generation_metrics(generation_type, duration, byte_size(result.generated_code))
            
            {:ok, result}
            
          {:error, reason} ->
            Logger.warning("Code generation failed for type #{generation_type}: #{reason}")
            {:error, reason}
        end
    end
  end
  
  defp execute_generation(generation_type, specification, context, state) do
    # Get enhanced project context
    project_context = get_enhanced_project_context(context, state)
    
    # Generate appropriate prompt for the generation type
    prompt = generate_code_prompt(generation_type, specification, context, project_context, state)
    
    # Prepare LLM request
    llm_request = %{
      type: :code_generation,
      generation_type: generation_type,
      prompt: prompt,
      context: project_context,
      options: %{
        temperature: get_temperature_for_type(generation_type),
        max_tokens: get_max_tokens_for_type(generation_type)
      }
    }
    
    case ModelCoordinator.request(llm_request) do
      {:ok, llm_response} ->
        # Post-process and validate the generated code
        case post_process_generated_code(llm_response, generation_type, context, state) do
          {:ok, processed_result} ->
            structured_result = structure_generation_result(processed_result, generation_type, context)
            {:ok, structured_result}
            
          {:error, reason} ->
            {:error, "Post-processing failed: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, "LLM request failed: #{reason}"}
    end
  end
  
  defp generate_code_prompt(generation_type, specification, context, project_context, state) do
    # Use the template system for consistent, structured generation prompts
    template_context = %{
      intent: :generate,
      generation_type: generation_type,
      description: specification,
      requirements: specification,
      project_context: project_context,
      project_conventions: state.project_conventions,
      specific_context: format_specific_context(context, generation_type),
      interface: Map.get(context, :interface, :ai_engine)
    }
    
    case TemplateEngine.render_for_intent(:generate, template_context) do
      {:ok, rendered_prompt} -> 
        rendered_prompt
      {:error, reason} ->
        Logger.warning("Template rendering failed, falling back to legacy prompt: #{reason}")
        generate_legacy_code_prompt(generation_type, specification, context, project_context, state)
    end
  end
  
  # Fallback to legacy prompt generation if template system fails
  defp generate_legacy_code_prompt(generation_type, specification, context, project_context, state) do
    base_prompt = get_base_generation_prompt(generation_type)
    conventions = format_project_conventions(state.project_conventions)
    context_info = format_context_for_prompt(project_context)
    specific_context = format_specific_context(context, generation_type)
    
    """
    #{base_prompt}
    
    Project Context:
    #{context_info}
    
    Project Conventions:
    #{conventions}
    
    Specific Requirements:
    #{specific_context}
    
    Specification:
    #{specification}
    
    Please generate high-quality, idiomatic Elixir code that follows the project conventions and best practices.
    """
  end
  
  defp get_base_generation_prompt(:module_generation) do
    """
    Generate a complete Elixir module with the following requirements:
    - Follow proper module documentation with @moduledoc
    - Include appropriate function documentation with @doc
    - Follow Elixir naming conventions
    - Include proper type specifications where appropriate
    - Follow OTP patterns if applicable
    - Include error handling and validation
    """
  end
  
  defp get_base_generation_prompt(:function_generation) do
    """
    Generate an Elixir function with the following requirements:
    - Proper function documentation with @doc
    - Type specifications with @spec
    - Appropriate guard clauses if needed
    - Pattern matching and error handling
    - Follow functional programming principles
    - Include examples in documentation
    """
  end
  
  defp get_base_generation_prompt(:test_generation) do
    """
    Generate comprehensive ExUnit tests with the following requirements:
    - Use proper test descriptions
    - Include setup and teardown if needed
    - Test both positive and negative cases
    - Use appropriate assertions
    - Follow testing best practices
    - Include property-based tests if applicable
    """
  end
  
  defp get_base_generation_prompt(:documentation_generation) do
    """
    Generate comprehensive documentation with the following requirements:
    - Use proper ExDoc formatting
    - Include clear module and function descriptions
    - Provide usage examples
    - Document parameters and return values
    - Include any relevant notes or warnings
    - Follow documentation best practices
    """
  end
  
  defp get_base_generation_prompt(:boilerplate_generation) do
    """
    Generate appropriate boilerplate code with the following requirements:
    - Follow project structure conventions
    - Include necessary dependencies and imports
    - Set up proper supervision trees if needed
    - Include configuration patterns
    - Follow Elixir/OTP best practices
    """
  end
  
  defp get_base_generation_prompt(_) do
    "Generate high-quality Elixir code following best practices and project conventions."
  end
  
  defp post_process_generated_code(llm_response, generation_type, context, state) do
    # Extract code blocks from the response
    code_blocks = extract_code_blocks(llm_response)
    
    case code_blocks do
      [] ->
        {:error, "No code blocks found in response"}
        
      [code_block | _] ->
        # Validate the generated code
        case validate_generated_code(code_block, generation_type) do
          :ok ->
            # Apply any necessary transformations
            processed_code = apply_code_transformations(code_block, generation_type, context, state)
            {:ok, processed_code}
            
          {:error, validation_error} ->
            {:error, "Code validation failed: #{validation_error}"}
        end
    end
  end
  
  defp extract_code_blocks(response) do
    # Extract Elixir code blocks from markdown-style response
    regex = ~r/```(?:elixir)?\n(.*?)\n```/s
    
    Regex.scan(regex, response, capture: :all_but_first)
    |> Enum.map(fn [code] -> String.trim(code) end)
    |> Enum.filter(fn code -> String.length(code) > 0 end)
  end
  
  defp validate_generated_code(code, generation_type) do
    # Basic syntax validation
    case Code.string_to_quoted(code) do
      {:ok, _ast} ->
        # Type-specific validation
        validate_by_type(code, generation_type)
        
      {:error, {line, error_info, token}} ->
        {:error, "Syntax error at line #{line}: #{format_syntax_error(error_info, token)}"}
    end
  end
  
  defp validate_by_type(code, :module_generation) do
    if String.contains?(code, "defmodule") do
      :ok
    else
      {:error, "Module generation must contain defmodule"}
    end
  end
  
  defp validate_by_type(code, :function_generation) do
    if String.contains?(code, "def ") or String.contains?(code, "defp ") do
      :ok
    else
      {:error, "Function generation must contain def or defp"}
    end
  end
  
  defp validate_by_type(code, :test_generation) do
    if String.contains?(code, "test ") or String.contains?(code, "describe ") do
      :ok
    else
      {:error, "Test generation must contain test cases"}
    end
  end
  
  defp validate_by_type(_code, _type), do: :ok
  
  defp apply_code_transformations(code, generation_type, context, state) do
    code
    |> apply_naming_conventions(context, state)
    |> apply_formatting()
    |> apply_type_specific_transformations(generation_type, context)
  end
  
  defp apply_naming_conventions(code, _context, state) do
    # Apply project-specific naming conventions
    _conventions = state.project_conventions
    
    # This would be more sophisticated in practice
    code
  end
  
  defp apply_formatting(code) do
    # Use Code.format_string! to format the code
    case Code.format_string(code) do
      formatted_code when is_binary(formatted_code) -> formatted_code
      _ -> code  # Fallback if formatting fails
    end
  rescue
    _ -> code  # Fallback if formatting fails
  end
  
  defp apply_type_specific_transformations(code, :module_generation, context) do
    # Add module-specific transformations
    module_name = Map.get(context, :module_name, "GeneratedModule")
    String.replace(code, "GeneratedModule", module_name)
  end
  
  defp apply_type_specific_transformations(code, _type, _context), do: code
  
  defp structure_generation_result(generated_code, generation_type, context) do
    %{
      type: generation_type,
      generated_code: generated_code,
      timestamp: DateTime.utc_now(),
      context: context,
      metadata: %{
        engine: "generation_engine",
        version: "1.0.0",
        lines_of_code: count_lines(generated_code),
        code_size_bytes: byte_size(generated_code)
      }
    }
  end
  
  defp process_generation_request(request, context, state) do
    generation_type = Map.get(request, :generation_type, :module_generation)
    specification = Map.get(request, :specification, "")
    request_context = Map.get(request, :context, %{})
    
    # Merge contexts
    merged_context = Map.merge(request_context, context)
    
    perform_code_generation(generation_type, specification, merged_context, state)
  end
  
  defp get_enhanced_project_context(context, _state) do
    # Get base project context
    base_context = case ContextManager.get_current_context() do
      {:ok, ctx} -> ctx
      {:error, _} -> %{}
    end
    
    # Merge with generation-specific context
    Map.merge(base_context, context)
  end
  
  defp format_project_conventions(conventions) when is_map(conventions) do
    conventions
    |> Enum.map(fn {key, value} -> "#{key}: #{value}" end)
    |> Enum.join("\n")
  end
  
  defp format_project_conventions(_), do: "No specific conventions"
  
  defp format_context_for_prompt(context) when is_map(context) do
    context
    |> Map.take([:project_name, :language, :framework, :dependencies, :patterns])
    |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
    |> Enum.join("\n")
  end
  
  defp format_context_for_prompt(_), do: "No context available"
  
  defp format_specific_context(context, generation_type) do
    case generation_type do
      :module_generation ->
        """
        Module Name: #{Map.get(context, :module_name, "N/A")}
        Description: #{Map.get(context, :description, "N/A")}
        """
        
      :function_generation ->
        """
        Function Name: #{Map.get(context, :function_name, "N/A")}
        Parameters: #{inspect(Map.get(context, :parameters, []))}
        """
        
      :test_generation ->
        """
        Test Type: #{Map.get(context, :test_type, :unit_tests)}
        Target Code: #{Map.get(context, :target_code, "N/A")}
        """
        
      _ ->
        inspect(context)
    end
  end
  
  defp load_project_conventions(state) do
    # Load conventions from project configuration or infer from existing code
    conventions = %{
      naming_style: :snake_case,
      module_prefix: infer_module_prefix(),
      documentation_style: :ex_doc,
      test_framework: :ex_unit
    }
    
    %{state | project_conventions: conventions}
  end
  
  defp infer_module_prefix do
    # Try to infer from existing modules in the project
    case Application.get_env(:aiex, :app_name) do
      nil -> "MyApp"
      app_name -> Macro.camelize(to_string(app_name))
    end
  end
  
  defp initialize_template_registry do
    %{
      module: load_module_templates(),
      function: load_function_templates(),
      test: load_test_templates()
    }
  end
  
  defp load_module_templates do
    %{
      genserver: "GenServer module template",
      supervisor: "Supervisor module template", 
      application: "Application module template"
    }
  end
  
  defp load_function_templates, do: %{}
  defp load_test_templates, do: %{}
  
  defp prepare_generation_engine(options, state) do
    # Validate LLM coordinator readiness
    case ModelCoordinator.health_check() do
      :ok ->
        # Reload project conventions if requested
        updated_state = if Keyword.get(options, :reload_conventions, false) do
          load_project_conventions(state)
        else
          state
        end
        
        {:ok, updated_state}
        
      {:error, reason} ->
        {:error, "LLM coordinator not ready: #{reason}"}
    end
  end
  
  defp get_temperature_for_type(:documentation_generation), do: 0.3
  defp get_temperature_for_type(:test_generation), do: 0.4
  defp get_temperature_for_type(_), do: 0.7
  
  defp get_max_tokens_for_type(:module_generation), do: 2000
  defp get_max_tokens_for_type(:documentation_generation), do: 1000
  defp get_max_tokens_for_type(_), do: 1500
  
  defp generate_cache_key(generation_type, specification, context) do
    content_hash = :crypto.hash(:sha256, specification) |> Base.encode16()
    context_hash = :crypto.hash(:sha256, inspect(context)) |> Base.encode16()
    "#{generation_type}_#{content_hash}_#{context_hash}"
  end
  
  defp record_generation_metrics(generation_type, duration_ms, code_size_bytes) do
    EventBus.emit("ai.engine.generation_engine.metrics", %{
      generation_type: generation_type,
      duration_ms: duration_ms,
      code_size_bytes: code_size_bytes,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp count_lines(code) do
    code |> String.split("\n") |> length()
  end
  
  defp format_syntax_error(error_info, token) do
    "#{error_info} near '#{token}'"
  end
  
  defp generate_session_id do
    "generation_engine_" <> Base.encode16(:crypto.strong_rand_bytes(8))
  end
end