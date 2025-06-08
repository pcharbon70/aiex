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
    
    # Load default templates
    {:ok, state} = load_default_templates(state)
    
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
      new_state = case Map.get(opts, :extends) do
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
      category: :workflow,
      intent: type,
      description: "Default #{type} workflow template",
      version: "1.0.0",
      template: get_workflow_template_content(type),
      variables: get_workflow_template_variables(type),
      conditions: [],
      metadata: %{
        complexity: :medium,
        estimated_tokens: 2000
      }
    }
  end
  
  defp get_default_conversation_template(type) do
    %{
      category: :conversation,
      intent: type,
      description: "Default #{type} conversation template",
      version: "1.0.0",
      template: get_conversation_template_content(type),
      variables: get_conversation_template_variables(type),
      conditions: [],
      metadata: %{}
    }
  end
  
  defp get_default_operation_template(type) do
    %{
      category: :operation,
      intent: type,
      description: "Default #{type} operation template",
      version: "1.0.0",
      template: get_operation_template_content(type),
      variables: get_operation_template_variables(type),
      conditions: [],
      metadata: %{}
    }
  end
  
  defp get_default_system_template(type) do
    %{
      category: :system,
      intent: type,
      description: "Default #{type} system template",
      version: "1.0.0",
      template: get_system_template_content(type),
      variables: get_system_template_variables(type),
      conditions: [],
      metadata: %{}
    }
  end
  
  # Template content generators (to be implemented)
  defp get_workflow_template_content(_type), do: "TODO: Implement workflow template content"
  defp get_workflow_template_variables(_type), do: []
  defp get_conversation_template_content(_type), do: "TODO: Implement conversation template content"
  defp get_conversation_template_variables(_type), do: []
  defp get_operation_template_content(_type), do: "TODO: Implement operation template content"
  defp get_operation_template_variables(_type), do: []
  defp get_system_template_content(_type), do: "TODO: Implement system template content"
  defp get_system_template_variables(_type), do: []
end