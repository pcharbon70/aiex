defmodule Aiex.LLM.Templates.TemplateRegistry do
  @moduledoc """
  Central registry for managing and discovering prompt templates.
  
  Provides functionality for:
  - Template registration and discovery
  - Template versioning and inheritance
  - Dynamic template selection based on context
  - Template caching and performance optimization
  """
  
  use GenServer
  require Logger
  
  alias Aiex.LLM.Templates.{Template, TemplateCompiler, TemplateValidator}
  
  @registry_name __MODULE__
  
  # Template categories
  @template_categories [
    :workflow,        # For AI coordinators workflows
    :conversation,    # For conversation management
    :engine,         # For AI engines
    :operation,      # For CLI operations
    :system          # For system-level templates
  ]
  
  # Template inheritance levels
  @inheritance_levels [
    :base,           # Base templates
    :category,       # Category-specific templates
    :specialized,    # Specialized implementations
    :custom         # User-defined customizations
  ]
  
  defstruct [
    :templates,           # Map of template_id -> template_metadata
    :compiled_cache,      # Map of template_id -> compiled_template
    :inheritance_tree,    # Template inheritance relationships
    :selection_rules,     # Rules for dynamic template selection
    :performance_metrics  # Template performance tracking
  ]
  
  ## Public API
  
  @doc """
  Start the template registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @registry_name)
  end
  
  @doc """
  Register a new template in the registry.
  """
  def register_template(template_id, template_data, opts \\ []) do
    GenServer.call(@registry_name, {:register_template, template_id, template_data, opts})
  end
  
  @doc """
  Get a template by ID with optional context for dynamic selection.
  """
  def get_template(template_id, context \\ %{}) do
    GenServer.call(@registry_name, {:get_template, template_id, context})
  end
  
  @doc """
  Find templates by category, intent, or other criteria.
  """
  def find_templates(criteria) do
    GenServer.call(@registry_name, {:find_templates, criteria})
  end
  
  @doc """
  Select the best template for a given context using selection rules.
  """
  def select_template(intent, context) do
    GenServer.call(@registry_name, {:select_template, intent, context})
  end
  
  @doc """
  Get all available template categories.
  """
  def get_categories, do: @template_categories
  
  @doc """
  Get template inheritance levels.
  """
  def get_inheritance_levels, do: @inheritance_levels
  
  @doc """
  Reload templates from configured sources.
  """
  def reload_templates do
    GenServer.call(@registry_name, :reload_templates)
  end
  
  @doc """
  Get performance metrics for templates.
  """
  def get_metrics do
    GenServer.call(@registry_name, :get_metrics)
  end
  
  @doc """
  Validate a template before registration.
  """
  def validate_template(template_data) do
    TemplateValidator.validate(template_data)
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      templates: %{},
      compiled_cache: %{},
      inheritance_tree: %{},
      selection_rules: [],
      performance_metrics: %{}
    }
    
    # Load default templates unless skipped
    state = case Keyword.get(opts, :skip_defaults, false) do
      true -> state
      false -> 
        case load_default_templates(state) do
          {:ok, loaded_state} -> loaded_state
          {:error, _reason} -> state
        end
    end
    
    # Load custom templates if specified
    case Keyword.get(opts, :custom_templates_path) do
      nil -> {:ok, state}
      path -> load_custom_templates(state, path)
    end
  end
  
  @impl true
  def handle_call({:register_template, template_id, template_data, opts}, _from, state) do
    case register_template_impl(state, template_id, template_data, opts) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:get_template, template_id, context}, _from, state) do
    case get_template_impl(state, template_id, context) do
      {:ok, template} ->
        {:reply, {:ok, template}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:find_templates, criteria}, _from, state) do
    templates = find_templates_impl(state, criteria)
    {:reply, {:ok, templates}, state}
  end
  
  @impl true
  def handle_call({:select_template, intent, context}, _from, state) do
    case select_template_impl(state, intent, context) do
      {:ok, template_id} ->
        {:reply, {:ok, template_id}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:reload_templates, _from, state) do
    case reload_templates_impl(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, {:ok, state.performance_metrics}, state}
  end
  
  ## Private Implementation
  
  defp register_template_impl(state, template_id, template_data, opts) do
    with {:ok, validated_template} <- TemplateValidator.validate(template_data),
         {:ok, compiled_template} <- TemplateCompiler.compile(validated_template),
         {:ok, metadata} <- extract_template_metadata(validated_template, opts) do
      
      new_state = %{state |
        templates: Map.put(state.templates, template_id, metadata),
        compiled_cache: Map.put(state.compiled_cache, template_id, compiled_template)
      }
      
      # Update inheritance tree if template has parent
      opts_map = if is_list(opts), do: Enum.into(opts, %{}), else: opts
      new_state = case Map.get(opts_map, :extends) do
        nil -> new_state
        parent_id -> update_inheritance_tree(new_state, template_id, parent_id)
      end
      
      Logger.info("Registered template: #{template_id}")
      {:ok, new_state}
    else
      {:error, reason} ->
        Logger.error("Failed to register template #{template_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp get_template_impl(state, template_id, context) do
    case Map.get(state.compiled_cache, template_id) do
      nil ->
        {:error, :template_not_found}
      compiled_template ->
        # Apply context and inheritance
        resolved_template = resolve_template_inheritance(state, template_id, compiled_template, context)
        {:ok, resolved_template}
    end
  end
  
  defp find_templates_impl(state, criteria) do
    state.templates
    |> Enum.filter(fn {_id, metadata} ->
      matches_criteria?(metadata, criteria)
    end)
    |> Enum.map(fn {id, metadata} -> {id, metadata} end)
  end
  
  defp select_template_impl(state, intent, context) do
    # Apply selection rules to find best template
    case apply_selection_rules(state.selection_rules, intent, context) do
      {:ok, template_id} ->
        if Map.has_key?(state.templates, template_id) do
          {:ok, template_id}
        else
          {:error, :selected_template_not_found}
        end
      {:error, :no_match} ->
        # Fallback to default template for intent
        fallback_template_id = get_fallback_template(intent)
        if Map.has_key?(state.templates, fallback_template_id) do
          {:ok, fallback_template_id}
        else
          {:error, :no_suitable_template}
        end
    end
  end
  
  defp load_default_templates(state) do
    default_templates = [
      # Workflow templates
      {:workflow_implement_feature, get_default_workflow_template(:implement_feature)},
      {:workflow_fix_bug, get_default_workflow_template(:fix_bug)},
      {:workflow_refactor_code, get_default_workflow_template(:refactor_code)},
      {:workflow_explain_codebase, get_default_workflow_template(:explain_codebase)},
      {:workflow_generate_tests, get_default_workflow_template(:generate_tests)},
      {:workflow_code_review, get_default_workflow_template(:code_review)},
      {:workflow_generate_docs, get_default_workflow_template(:generate_docs)},
      
      # Conversation templates
      {:conversation_intent_classification, get_default_conversation_template(:intent_classification)},
      {:conversation_continuation, get_default_conversation_template(:continuation)},
      {:conversation_summarization, get_default_conversation_template(:summarization)},
      
      # Operation templates
      {:operation_analyze, get_default_operation_template(:analyze)},
      {:operation_generate, get_default_operation_template(:generate)},
      {:operation_explain, get_default_operation_template(:explain)},
      {:operation_refactor, get_default_operation_template(:refactor)},
      
      # System templates
      {:system_error_handling, get_default_system_template(:error_handling)},
      {:system_context_compression, get_default_system_template(:context_compression)}
    ]
    
    register_templates(state, default_templates)
  end
  
  defp register_templates(state, templates) do
    Enum.reduce_while(templates, {:ok, state}, fn {template_id, template_data}, {:ok, acc_state} ->
      case register_template_impl(acc_state, template_id, template_data, []) do
        {:ok, new_state} -> {:cont, {:ok, new_state}}
        {:error, reason} -> {:halt, {:error, {template_id, reason}}}
      end
    end)
  end
  
  defp load_custom_templates(state, path) do
    case File.exists?(path) do
      true ->
        case File.ls(path) do
          {:ok, files} ->
            template_files = Enum.filter(files, &String.ends_with?(&1, [".exs", ".ex"]))
            
            Enum.reduce(template_files, {:ok, state}, fn file, {:ok, acc_state} ->
              file_path = Path.join(path, file)
              case load_template_from_file(file_path) do
                {:ok, template} ->
                  case register_template(template.id, template, []) do
                    {:ok, new_state} -> {:ok, new_state}
                    {:error, reason} -> {:error, reason}
                  end
                {:error, _reason} ->
                  # Skip invalid template files
                  {:ok, acc_state}
              end
            end)
            
          {:error, reason} ->
            {:error, "Failed to read custom templates directory: #{reason}"}
        end
        
      false ->
        {:error, "Custom templates path does not exist: #{path}"}
    end
  end

  defp load_template_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Code.eval_string(content) do
          {template_data, _bindings} when is_map(template_data) ->
            Template.from_map(template_data)
          _ ->
            {:error, "Invalid template format"}
        end
      {:error, reason} ->
        {:error, "Failed to read template file: #{reason}"}
    end
  end

  defp extract_template_metadata(template_data, opts) do
    metadata = %{
      category: Map.get(template_data, :category, :custom),
      intent: Map.get(template_data, :intent),
      description: Map.get(template_data, :description, ""),
      version: Map.get(template_data, :version, "1.0.0"),
      author: Map.get(template_data, :author, "system"),
      tags: Map.get(template_data, :tags, []),
      extends: Keyword.get(opts, :extends),
      created_at: DateTime.utc_now(),
      usage_count: 0,
      performance_score: 0.0
    }
    {:ok, metadata}
  end
  
  defp update_inheritance_tree(state, child_id, parent_id) do
    inheritance_tree = Map.update(state.inheritance_tree, parent_id, [child_id], fn children ->
      [child_id | children] |> Enum.uniq()
    end)
    %{state | inheritance_tree: inheritance_tree}
  end
  
  defp resolve_template_inheritance(state, template_id, compiled_template, context) do
    # TODO: Implement template inheritance resolution
    # For now, return the compiled template as-is
    compiled_template
  end
  
  defp matches_criteria?(metadata, criteria) do
    Enum.all?(criteria, fn {key, value} ->
      case Map.get(metadata, key) do
        ^value -> true
        list when is_list(list) -> value in list
        _ -> false
      end
    end)
  end
  
  defp apply_selection_rules(rules, intent, context) do
    # TODO: Implement sophisticated template selection rules
    # For now, use simple intent-based selection
    template_id = String.to_atom("workflow_#{intent}")
    {:ok, template_id}
  end
  
  defp get_fallback_template(intent) do
    case intent do
      :implement_feature -> :workflow_implement_feature
      :fix_bug -> :workflow_fix_bug
      :refactor_code -> :workflow_refactor_code
      :explain_codebase -> :workflow_explain_codebase
      :generate_tests -> :workflow_generate_tests
      :code_review -> :workflow_code_review
      :generate_docs -> :workflow_generate_docs
      _ -> :workflow_implement_feature  # Default fallback
    end
  end
  
  defp reload_templates_impl(state) do
    # Clear caches and reload
    cleared_state = %{state |
      templates: %{},
      compiled_cache: %{},
      inheritance_tree: %{}
    }
    load_default_templates(cleared_state)
  end
  
  # Default template generators
  defp get_default_workflow_template(type) do
    %{
      name: "#{type} workflow",
      description: "Default #{type} workflow template",
      version: "1.0.0",
      category: :workflow,
      intent: type,
      content: get_workflow_template_content(type),
      variables: get_workflow_template_variables(type),
      conditions: get_workflow_template_conditions(type),
      metadata: %{
        complexity: :medium,
        estimated_tokens: 2000
      }
    }
  end
  
  defp get_default_conversation_template(type) do
    %{
      name: "#{type} conversation",
      description: "Default #{type} conversation template",
      version: "1.0.0",
      category: :conversation,
      intent: type,
      content: get_conversation_template_content(type),
      variables: get_conversation_template_variables(type),
      conditions: [],
      metadata: %{}
    }
  end
  
  defp get_default_operation_template(type) do
    %{
      name: "#{type} operation",
      description: "Default #{type} operation template",
      version: "1.0.0",
      category: :operation,
      intent: type,
      content: get_operation_template_content(type),
      variables: get_operation_template_variables(type),
      conditions: get_operation_template_conditions(type),
      metadata: %{}
    }
  end
  
  defp get_default_system_template(type) do
    %{
      name: "#{type} system",
      description: "Default #{type} system template",
      version: "1.0.0",
      category: :system,
      intent: type,
      content: get_system_template_content(type),
      variables: get_system_template_variables(type),
      conditions: [],
      metadata: %{}
    }
  end
  
  # Template content generators
  defp get_workflow_template_content(type) do
    case type do
      :implement_feature ->
        """
        You are an expert Elixir developer working on a distributed OTP application.
        
        ## Task
        Implement the feature: {{feature_description}}
        
        ## Context
        Project: {{project_name}}
        Framework: {{framework}}
        
        ## Requirements
        - Follow OTP design patterns and supervision trees
        - Write comprehensive documentation and typespecs
        - Include unit tests using ExUnit
        - Ensure code follows Elixir formatting standards
        
        ## Existing Code Context
        {{existing_code}}
        
        Provide a complete implementation with explanations.
        """
      
      :fix_bug ->
        """
        You are an expert Elixir developer debugging a distributed OTP application.
        
        ## Bug Report
        {{bug_description}}
        
        ## Error Information
        ```
        {{error_info}}
        ```
        
        ## Code Context
        {{code_context}}
        
        ## Requirements
        - Identify the root cause of the issue
        - Provide a minimal fix that preserves existing functionality
        - Explain the fix and why it resolves the issue
        - Suggest tests to prevent regression
        
        Provide a detailed analysis and fix.
        """
      
      :refactor_code ->
        """
        You are an expert Elixir developer refactoring code for better maintainability.
        
        ## Original Code
        ```elixir
        {{original_code}}
        ```
        
        ## Refactoring Goals
        {{refactoring_goals}}
        
        ## Requirements
        - Preserve existing functionality
        - Improve code structure and readability
        - Follow Elixir and OTP best practices
        - Provide clear explanations for all changes
        
        Provide the refactored code with detailed explanations.
        """
      
      :explain_codebase ->
        """
        You are an expert Elixir developer explaining a codebase structure.
        
        ## Codebase Path
        {{codebase_path}}
        
        ## Explanation Level
        {{explanation_level}}
        
        ## Requirements
        - Explain the overall architecture and structure
        - Identify key modules and their responsibilities
        - Highlight important patterns and design decisions
        - Provide clear guidance for new developers
        
        Provide a comprehensive codebase explanation.
        """
      
      :generate_tests ->
        """
        You are an expert Elixir developer writing comprehensive tests.
        
        ## Code to Test
        ```elixir
        {{code_to_test}}
        ```
        
        ## Test Framework
        {{test_framework}}
        
        ## Requirements
        - Write comprehensive unit tests using ExUnit
        - Cover edge cases and error conditions
        - Include property-based tests where appropriate
        - Follow testing best practices
        
        Provide complete test suite with explanations.
        """
      
      :code_review ->
        """
        You are an expert Elixir developer performing a code review.
        
        ## Code to Review
        ```elixir
        {{code_content}}
        ```
        
        ## Review Focus
        {{review_focus}}
        
        ## Requirements
        - Identify potential issues and improvements
        - Check for OTP patterns and best practices
        - Evaluate performance and security considerations
        - Provide constructive feedback with examples
        
        Provide a detailed code review with recommendations.
        """
      
      :generate_docs ->
        """
        You are an expert Elixir developer writing documentation.
        
        ## Code to Document
        ```elixir
        {{code_content}}
        ```
        
        ## Documentation Type
        {{documentation_type}}
        
        ## Requirements
        - Write clear and comprehensive documentation
        - Include usage examples and API reference
        - Follow Elixir documentation conventions
        - Provide helpful explanations for complex concepts
        
        Provide complete documentation with examples.
        """
      
      _ -> "TODO: Implement #{type} workflow template"
    end
  end
  
  defp get_workflow_template_variables(type) do
    case type do
      :implement_feature ->
        [
          %{name: "feature_description", type: :string, required: true},
          %{name: "project_name", type: :string, required: false},
          %{name: "framework", type: :string, required: false},
          %{name: "existing_code", type: :string, required: false}
        ]
      
      :fix_bug ->
        [
          %{name: "bug_description", type: :string, required: true},
          %{name: "error_info", type: :string, required: false},
          %{name: "code_context", type: :string, required: true}
        ]
      
      :refactor_code ->
        [
          %{name: "original_code", type: :string, required: true},
          %{name: "refactoring_goals", type: :string, required: true}
        ]
      
      :explain_codebase ->
        [
          %{name: "codebase_path", type: :string, required: true},
          %{name: "explanation_level", type: :string, required: false}
        ]
      
      :generate_tests ->
        [
          %{name: "code_to_test", type: :string, required: true},
          %{name: "test_framework", type: :string, required: false}
        ]
      
      :code_review ->
        [
          %{name: "code_content", type: :string, required: true},
          %{name: "review_focus", type: :string, required: false}
        ]
      
      :generate_docs ->
        [
          %{name: "code_content", type: :string, required: true},
          %{name: "documentation_type", type: :string, required: false}
        ]
      
      _ -> []
    end
  end
  
  defp get_workflow_template_conditions(_type), do: []
  
  defp get_conversation_template_content(_type), do: "You are a helpful AI assistant."
  defp get_conversation_template_variables(_type), do: []
  
  defp get_operation_template_content(type) do
    case type do
      :analyze ->
        """
        Analyze the following Elixir code and provide insights:
        
        ## Code to Analyze
        ```elixir
        {{code_content}}
        ```
        
        ## Focus Areas
        {{analysis_focus}}
        
        Provide analysis covering:
        - Code structure and organization
        - OTP patterns and best practices
        - Potential improvements
        - Performance considerations
        """
      
      :generate ->
        """
        Generate Elixir code for the following specification:
        
        ## Specification
        {{specification}}
        
        ## Context
        {{context_info}}
        
        ## Requirements
        - Follow Elixir and OTP best practices
        - Include comprehensive documentation
        - Add appropriate typespecs
        - Ensure code is production-ready
        
        Provide complete, working code with explanations.
        """
      
      :explain ->
        """
        Explain the following Elixir code in detail:
        
        ## Code
        ```elixir
        {{code_content}}
        ```
        
        ## Detail Level: {{explanation_level}}
        
        Provide a clear explanation covering:
        - What the code does
        - How it works
        - Key concepts and patterns used
        - Any notable design decisions
        """
      
      :refactor ->
        """
        Refactor the following Elixir code to improve:
        
        ## Original Code
        ```elixir
        {{original_code}}
        ```
        
        ## Refactoring Goals
        {{refactoring_goals}}
        
        ## Requirements
        - Maintain existing functionality
        - Improve code quality and maintainability
        - Follow Elixir best practices
        - Provide clear explanations for changes
        
        Provide the refactored code with detailed explanations.
        """
      
      _ -> "TODO: Implement #{type} operation template"
    end
  end
  
  defp get_operation_template_variables(type) do
    case type do
      :analyze ->
        [
          %{name: "code_content", type: :string, required: true},
          %{name: "analysis_focus", type: :string, required: false}
        ]
      
      :generate ->
        [
          %{name: "specification", type: :string, required: true},
          %{name: "context_info", type: :string, required: false}
        ]
      
      :explain ->
        [
          %{name: "code_content", type: :string, required: true},
          %{name: "explanation_level", type: :string, required: false}
        ]
      
      :refactor ->
        [
          %{name: "original_code", type: :string, required: true},
          %{name: "refactoring_goals", type: :string, required: true}
        ]
      
      _ -> []
    end
  end
  
  defp get_operation_template_conditions(_type), do: []
  
  defp get_system_template_content(_type), do: "System template placeholder."
  defp get_system_template_variables(_type), do: []
end