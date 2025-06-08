defmodule Aiex.AI.Engines.ExplanationEngine do
  @moduledoc """
  Structured code explanation engine that provides natural language explanations
  of code functionality, patterns, and architecture at different detail levels.
  
  This engine integrates with existing LLM coordination and context management
  to provide educational and informative code explanations.
  """
  
  use GenServer
  require Logger
  
  @behaviour Aiex.AI.Behaviours.AIEngine
  
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.Events.EventBus
  alias Aiex.Semantic.Chunker
  
  # Explanation types and detail levels supported
  @supported_types [
    :code_explanation,        # General code explanation
    :function_explanation,    # Specific function explanation
    :module_explanation,      # Module structure and purpose
    :pattern_explanation,     # Design pattern explanation
    :architecture_explanation, # High-level architecture explanation
    :tutorial_explanation,    # Step-by-step tutorial format
    :concept_explanation      # Concept and principle explanation
  ]
  
  @detail_levels [:brief, :detailed, :comprehensive, :tutorial]
  @audience_levels [:beginner, :intermediate, :advanced, :expert]
  
  defstruct [
    :session_id,
    :explanation_cache,
    :learning_preferences,
    :explanation_templates
  ]
  
  ## Public API
  
  @doc """
  Starts the ExplanationEngine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Explains the given code with specified detail level and audience.
  
  ## Examples
  
      iex> ExplanationEngine.explain_code("def add(a, b), do: a + b", :detailed, :beginner)
      {:ok, %{explanation_type: :code_explanation, content: "...", metadata: ...}}
      
      iex> ExplanationEngine.explain_module(MyModule, :comprehensive, :intermediate)
      {:ok, %{explanation_type: :module_explanation, content: "...", metadata: ...}}
  """
  def explain_code(code_content, detail_level \\ :detailed, audience \\ :intermediate, options \\ []) do
    GenServer.call(__MODULE__, {:explain_code, code_content, detail_level, audience, options})
  end
  
  @doc """
  Explains a specific function including its purpose, parameters, and usage.
  """
  def explain_function(function_code, function_name, detail_level \\ :detailed, options \\ []) do
    context = %{
      function_name: function_name,
      explanation_type: :function_explanation,
      detail_level: detail_level,
      options: options
    }
    GenServer.call(__MODULE__, {:explain_with_context, function_code, context})
  end
  
  @doc """
  Explains a module's structure, purpose, and usage patterns.
  """
  def explain_module(module_code, detail_level \\ :detailed, audience \\ :intermediate) do
    context = %{
      explanation_type: :module_explanation,
      detail_level: detail_level,
      audience: audience
    }
    GenServer.call(__MODULE__, {:explain_with_context, module_code, context})
  end
  
  @doc """
  Explains design patterns and architectural concepts in the code.
  """
  def explain_patterns(code_content, pattern_focus \\ nil, detail_level \\ :detailed) do
    context = %{
      explanation_type: :pattern_explanation,
      pattern_focus: pattern_focus,
      detail_level: detail_level
    }
    GenServer.call(__MODULE__, {:explain_with_context, code_content, context})
  end
  
  @doc """
  Creates a tutorial-style explanation walking through code step by step.
  """
  def create_tutorial(code_content, tutorial_title, audience \\ :beginner) do
    context = %{
      explanation_type: :tutorial_explanation,
      tutorial_title: tutorial_title,
      audience: audience,
      detail_level: :comprehensive
    }
    GenServer.call(__MODULE__, {:explain_with_context, code_content, context})
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
      name: "Explanation Engine",
      description: "Structured code explanation engine with multiple detail levels and audience targeting",
      supported_types: @supported_types,
      detail_levels: @detail_levels,
      audience_levels: @audience_levels,
      version: "1.0.0",
      capabilities: [
        "Multi-level code explanations (brief to comprehensive)",
        "Audience-specific explanations (beginner to expert)",
        "Tutorial-style step-by-step explanations",
        "Pattern and architecture explanations",
        "Context-aware explanations with project knowledge",
        "Interactive learning formats"
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
    
    # Initialize explanation cache and templates
    cache_table = :ets.new(:explanation_cache, [:set, :private])
    explanation_templates = initialize_explanation_templates()
    
    state = %__MODULE__{
      session_id: session_id,
      explanation_cache: cache_table,
      learning_preferences: %{},
      explanation_templates: explanation_templates
    }
    
    Logger.info("ExplanationEngine started with session_id: #{session_id}")
    
    EventBus.emit("ai.engine.explanation_engine.started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:explain_code, code_content, detail_level, audience, options}, _from, state) do
    context = %{
      explanation_type: :code_explanation,
      detail_level: detail_level,
      audience: audience,
      options: options
    }
    result = perform_code_explanation(code_content, context, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:explain_with_context, code_content, context}, _from, state) do
    result = perform_code_explanation(code_content, context, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:process_request, request, context}, _from, state) do
    result = process_explanation_request(request, context, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:prepare, options}, _from, state) do
    case prepare_explanation_engine(options, state) do
      {:ok, updated_state} -> {:reply, :ok, updated_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:cleanup, _from, state) do
    :ets.delete(state.explanation_cache)
    
    EventBus.emit("ai.engine.explanation_engine.stopped", %{
      session_id: state.session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:reply, :ok, state}
  end
  
  ## Private Implementation
  
  defp perform_code_explanation(code_content, context, state) do
    start_time = System.monotonic_time(:millisecond)
    
    # Validate context parameters
    case validate_explanation_context(context) do
      :ok ->
        # Check cache for similar explanations
        cache_key = generate_cache_key(code_content, context)
        
        case :ets.lookup(state.explanation_cache, cache_key) do
          [{^cache_key, cached_result}] ->
            Logger.debug("Cache hit for explanation: #{context.explanation_type}")
            {:ok, cached_result}
            
          [] ->
            case execute_explanation(code_content, context, state) do
              {:ok, result} ->
                # Cache the result
                :ets.insert(state.explanation_cache, {cache_key, result})
                
                # Record metrics
                duration = System.monotonic_time(:millisecond) - start_time
                record_explanation_metrics(context, duration, byte_size(code_content))
                
                {:ok, result}
                
              {:error, reason} ->
                Logger.warning("Code explanation failed: #{reason}")
                {:error, reason}
            end
        end
        
      {:error, validation_error} ->
        {:error, validation_error}
    end
  end
  
  defp execute_explanation(code_content, context, state) do
    # Get enhanced project context
    project_context = get_enhanced_project_context(context, state)
    
    # Generate explanation prompt based on type and detail level
    prompt = generate_explanation_prompt(code_content, context, project_context, state)
    
    # Prepare LLM request with appropriate parameters
    llm_request = %{
      type: :code_explanation,
      explanation_type: context.explanation_type,
      prompt: prompt,
      context: project_context,
      options: %{
        temperature: get_temperature_for_explanation(context),
        max_tokens: get_max_tokens_for_explanation(context)
      }
    }
    
    case ModelCoordinator.request(llm_request) do
      {:ok, llm_response} ->
        # Post-process and structure the explanation
        case post_process_explanation(llm_response, context, state) do
          {:ok, processed_explanation} ->
            structured_result = structure_explanation_result(processed_explanation, context)
            {:ok, structured_result}
            
          {:error, reason} ->
            {:error, "Post-processing failed: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, "LLM request failed: #{reason}"}
    end
  end
  
  defp generate_explanation_prompt(code_content, context, project_context, state) do
    explanation_type = Map.get(context, :explanation_type, :code_explanation)
    detail_level = Map.get(context, :detail_level, :detailed)
    audience = Map.get(context, :audience, :intermediate)
    
    base_prompt = get_base_explanation_prompt(explanation_type, detail_level, audience)
    context_info = format_context_for_prompt(project_context)
    specific_instructions = get_specific_instructions(context)
    formatting_guide = get_formatting_guide(detail_level)
    
    """
    #{base_prompt}
    
    Project Context:
    #{context_info}
    
    Specific Instructions:
    #{specific_instructions}
    
    Formatting Guide:
    #{formatting_guide}
    
    Code to Explain:
    ```elixir
    #{code_content}
    ```
    
    Please provide a clear, #{detail_level} explanation suitable for a #{audience} audience.
    """
  end
  
  defp get_base_explanation_prompt(:code_explanation, :brief, audience) do
    """
    Provide a brief explanation of this Elixir code for a #{audience} developer.
    Focus on:
    - What the code does (main purpose)
    - Key concepts used
    - Important details relevant to #{audience} level
    Keep it concise but informative.
    """
  end
  
  defp get_base_explanation_prompt(:code_explanation, :detailed, audience) do
    """
    Provide a detailed explanation of this Elixir code for a #{audience} developer.
    Cover:
    - Purpose and functionality
    - How it works (step by step)
    - Key Elixir concepts and patterns used
    - Important implementation details
    - Potential use cases
    - Any notable aspects for #{audience} level understanding
    """
  end
  
  defp get_base_explanation_prompt(:code_explanation, :comprehensive, audience) do
    """
    Provide a comprehensive explanation of this Elixir code for a #{audience} developer.
    Include:
    - Complete functional breakdown
    - Detailed step-by-step analysis
    - All Elixir concepts, patterns, and idioms used
    - Design decisions and trade-offs
    - Alternative approaches and comparisons
    - Performance considerations
    - Best practices demonstrated
    - Integration with larger systems
    - Learning opportunities for #{audience} developers
    """
  end
  
  defp get_base_explanation_prompt(:function_explanation, detail_level, audience) do
    """
    Explain this Elixir function in #{detail_level} detail for #{audience} developers.
    Cover:
    - Function purpose and behavior
    - Parameter descriptions and types
    - Return value and possible outcomes
    - Implementation approach
    - Usage examples
    - Edge cases and error handling
    """
  end
  
  defp get_base_explanation_prompt(:module_explanation, detail_level, audience) do
    """
    Explain this Elixir module in #{detail_level} detail for #{audience} developers.
    Cover:
    - Module purpose and responsibility
    - Public API and main functions
    - Internal structure and organization
    - Dependencies and relationships
    - Usage patterns and examples
    - Design patterns employed
    """
  end
  
  defp get_base_explanation_prompt(:pattern_explanation, detail_level, audience) do
    """
    Explain the design patterns and architectural concepts in this code for #{audience} developers.
    Focus on:
    - Design patterns used (OTP, functional patterns, etc.)
    - Architectural decisions and principles
    - Why these patterns were chosen
    - Benefits and trade-offs
    - How patterns work together
    - Alternative patterns that could be used
    """
  end
  
  defp get_base_explanation_prompt(:tutorial_explanation, detail_level, audience) do
    """
    Create a step-by-step tutorial explanation of this code for #{audience} developers.
    Structure as:
    - Introduction and learning objectives
    - Prerequisite knowledge
    - Step-by-step code breakdown
    - Hands-on examples and exercises
    - Common mistakes to avoid
    - Next steps and further learning
    """
  end
  
  defp get_base_explanation_prompt(:architecture_explanation, detail_level, audience) do
    """
    Explain the high-level architecture and design of this code for #{audience} developers.
    Cover:
    - Overall architecture and design approach
    - Component relationships and interactions
    - Data flow and control flow
    - Scalability and maintainability aspects
    - Integration points and boundaries
    - Architectural patterns and principles
    """
  end
  
  defp get_base_explanation_prompt(_, detail_level, audience) do
    """
    Explain this Elixir code in #{detail_level} detail for #{audience} developers.
    Provide clear, educational content appropriate for the specified audience level.
    """
  end
  
  defp get_specific_instructions(context) do
    instructions = []
    
    instructions = 
      if function_name = Map.get(context, :function_name) do
        ["Focus on the function: #{function_name}" | instructions]
      else
        instructions
      end
    
    instructions =
      if pattern_focus = Map.get(context, :pattern_focus) do
        ["Pay special attention to: #{pattern_focus}" | instructions]
      else
        instructions
      end
    
    instructions =
      if tutorial_title = Map.get(context, :tutorial_title) do
        ["Structure as tutorial: #{tutorial_title}" | instructions]
      else
        instructions
      end
    
    case instructions do
      [] -> "No specific instructions"
      list -> Enum.join(list, "\n")
    end
  end
  
  defp get_formatting_guide(:brief) do
    """
    Use concise formatting:
    - 2-3 short paragraphs maximum
    - Bullet points for key concepts
    - Minimal code examples
    """
  end
  
  defp get_formatting_guide(:detailed) do
    """
    Use structured formatting:
    - Clear section headers
    - Numbered or bulleted lists for steps
    - Code examples with explanations
    - Summary at the end
    """
  end
  
  defp get_formatting_guide(:comprehensive) do
    """
    Use comprehensive formatting:
    - Multiple sections with clear headers
    - Detailed explanations with examples
    - Code snippets with line-by-line breakdown
    - Diagrams or flowcharts if helpful (text-based)
    - Related concepts and further reading
    """
  end
  
  defp get_formatting_guide(:tutorial) do
    """
    Use tutorial formatting:
    - Step-by-step numbered sections
    - "Try this" hands-on examples
    - Common pitfalls and solutions
    - Progress checkpoints
    - Summary and next steps
    """
  end
  
  defp post_process_explanation(llm_response, context, state) do
    # Clean up and structure the explanation
    cleaned_explanation = clean_explanation_text(llm_response)
    
    # Add interactive elements if appropriate
    enhanced_explanation = add_interactive_elements(cleaned_explanation, context)
    
    # Validate explanation quality
    case validate_explanation_quality(enhanced_explanation, context) do
      :ok -> {:ok, enhanced_explanation}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp clean_explanation_text(text) do
    text
    |> String.trim()
    |> String.replace(~r/\n{3,}/, "\n\n")  # Remove excessive newlines
    |> String.replace(~r/ {2,}/, " ")      # Remove excessive spaces
  end
  
  defp add_interactive_elements(explanation, context) do
    case Map.get(context, :explanation_type) do
      :tutorial_explanation ->
        add_tutorial_elements(explanation)
        
      :function_explanation ->
        add_function_examples(explanation, context)
        
      _ ->
        explanation
    end
  end
  
  defp add_tutorial_elements(explanation) do
    # Add interactive tutorial elements
    explanation <> "\n\n## Try It Yourself\n" <>
    "Copy the code examples and experiment with different inputs to deepen your understanding."
  end
  
  defp add_function_examples(explanation, context) do
    # Add usage examples for function explanations
    if function_name = Map.get(context, :function_name) do
      explanation <> "\n\n## Usage Examples\n" <>
      "Try calling `#{function_name}()` with different parameters to see how it behaves."
    else
      explanation
    end
  end
  
  defp validate_explanation_quality(explanation, context) do
    min_length = get_minimum_length(Map.get(context, :detail_level, :detailed))
    
    cond do
      String.length(explanation) < min_length ->
        {:error, "Explanation too short for detail level"}
        
      not String.contains?(explanation, "Elixir") ->
        {:error, "Explanation should mention Elixir concepts"}
        
      true ->
        :ok
    end
  end
  
  defp get_minimum_length(:brief), do: 100
  defp get_minimum_length(:detailed), do: 300
  defp get_minimum_length(:comprehensive), do: 800
  defp get_minimum_length(:tutorial), do: 500
  
  defp structure_explanation_result(explanation_content, context) do
    %{
      explanation_type: Map.get(context, :explanation_type, :code_explanation),
      detail_level: Map.get(context, :detail_level, :detailed),
      audience: Map.get(context, :audience, :intermediate),
      content: explanation_content,
      timestamp: DateTime.utc_now(),
      metadata: %{
        engine: "explanation_engine",
        version: "1.0.0",
        word_count: count_words(explanation_content),
        estimated_reading_time: estimate_reading_time(explanation_content)
      }
    }
  end
  
  defp validate_explanation_context(context) do
    required_fields = [:explanation_type]
    
    case Enum.find(required_fields, fn field -> not Map.has_key?(context, field) end) do
      nil ->
        # Validate field values
        explanation_type = Map.get(context, :explanation_type)
        detail_level = Map.get(context, :detail_level, :detailed)
        audience = Map.get(context, :audience, :intermediate)
        
        cond do
          explanation_type not in @supported_types ->
            {:error, "Unsupported explanation type: #{explanation_type}"}
            
          detail_level not in @detail_levels ->
            {:error, "Invalid detail level: #{detail_level}"}
            
          audience not in @audience_levels ->
            {:error, "Invalid audience level: #{audience}"}
            
          true ->
            :ok
        end
        
      missing_field ->
        {:error, "Missing required field: #{missing_field}"}
    end
  end
  
  defp process_explanation_request(request, context, state) do
    code_content = Map.get(request, :content)
    explanation_type = Map.get(request, :explanation_type, :code_explanation)
    detail_level = Map.get(request, :detail_level, :detailed)
    audience = Map.get(request, :audience, :intermediate)
    
    if code_content do
      explanation_context = %{
        explanation_type: explanation_type,
        detail_level: detail_level,
        audience: audience,
        project_context: context
      }
      
      perform_code_explanation(code_content, explanation_context, state)
    else
      {:error, "No code content provided"}
    end
  end
  
  defp get_enhanced_project_context(context, state) do
    # Get base project context
    base_context = case ContextManager.get_current_context() do
      {:ok, ctx} -> ctx
      {:error, _} -> %{}
    end
    
    # Add explanation-specific context
    Map.merge(base_context, Map.get(context, :project_context, %{}))
  end
  
  defp format_context_for_prompt(context) when is_map(context) do
    context
    |> Map.take([:project_name, :language, :framework, :dependencies, :conventions])
    |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
    |> Enum.join("\n")
  end
  
  defp format_context_for_prompt(_), do: "No context available"
  
  defp initialize_explanation_templates do
    %{
      code_explanation: load_code_explanation_templates(),
      function_explanation: load_function_explanation_templates(),
      tutorial_explanation: load_tutorial_explanation_templates()
    }
  end
  
  defp load_code_explanation_templates, do: %{}
  defp load_function_explanation_templates, do: %{}
  defp load_tutorial_explanation_templates, do: %{}
  
  defp prepare_explanation_engine(options, state) do
    case ModelCoordinator.health_check() do
      :ok ->
        # Load any custom templates or preferences
        updated_state = if Keyword.get(options, :reload_templates, false) do
          %{state | explanation_templates: initialize_explanation_templates()}
        else
          state
        end
        
        {:ok, updated_state}
        
      {:error, reason} ->
        {:error, "LLM coordinator not ready: #{reason}"}
    end
  end
  
  defp get_temperature_for_explanation(context) do
    case Map.get(context, :explanation_type) do
      :tutorial_explanation -> 0.8  # More creative for tutorials
      :pattern_explanation -> 0.6   # Moderate creativity for patterns
      _ -> 0.4                       # Lower for factual explanations
    end
  end
  
  defp get_max_tokens_for_explanation(context) do
    case Map.get(context, :detail_level) do
      :brief -> 500
      :detailed -> 1500
      :comprehensive -> 3000
      :tutorial -> 2500
      _ -> 1500
    end
  end
  
  defp generate_cache_key(code_content, context) do
    content_hash = :crypto.hash(:sha256, code_content) |> Base.encode16()
    context_hash = :crypto.hash(:sha256, inspect(context)) |> Base.encode16()
    "explanation_#{content_hash}_#{context_hash}"
  end
  
  defp record_explanation_metrics(context, duration_ms, code_size_bytes) do
    EventBus.emit("ai.engine.explanation_engine.metrics", %{
      explanation_type: Map.get(context, :explanation_type),
      detail_level: Map.get(context, :detail_level),
      audience: Map.get(context, :audience),
      duration_ms: duration_ms,
      code_size_bytes: code_size_bytes,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp count_words(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end
  
  defp estimate_reading_time(text) do
    word_count = count_words(text)
    # Assume 200 words per minute reading speed
    reading_time_minutes = Float.ceil(word_count / 200.0)
    "#{trunc(reading_time_minutes)} min"
  end
  
  defp generate_session_id do
    "explanation_engine_" <> Base.encode16(:crypto.strong_rand_bytes(8))
  end
end