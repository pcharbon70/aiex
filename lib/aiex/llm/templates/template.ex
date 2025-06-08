defmodule Aiex.LLM.Templates.Template do
  @moduledoc """
  Enhanced template structure for the new prompt template system.
  
  This module defines the core template structure and provides utilities
  for creating, validating, and working with templates in the Aiex system.
  """
  
  @type variable :: %{
    name: String.t(),
    type: atom(),
    required: boolean(),
    default: any(),
    description: String.t(),
    validator: function() | map() | nil,
    transformer: function() | map() | nil
  }
  
  @type conditional :: %{
    name: String.t(),
    expression: String.t(),
    description: String.t()
  }
  
  @type template :: %__MODULE__{
    id: atom(),
    name: String.t(),
    description: String.t(),
    version: String.t(),
    category: atom(),
    author: String.t(),
    tags: [String.t()],
    content: String.t() | list(),
    variables: [variable()],
    conditionals: [conditional()],
    metadata: map(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  
  defstruct [
    :id,
    :name,
    :description,
    :version,
    :category,
    :author,
    :tags,
    :content,
    :variables,
    :conditionals,
    :metadata,
    :created_at,
    :updated_at
  ]
  
  @valid_categories [:workflow, :conversation, :engine, :operation, :system, :custom]
  @valid_variable_types [:string, :integer, :float, :boolean, :list, :map, :any]
  
  @doc """
  Create a new template with the given attributes.
  """
  @spec new(map()) :: {:ok, template()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()
    
    template = %__MODULE__{
      id: Map.get(attrs, :id) || generate_id(Map.get(attrs, :name, "")),
      name: Map.get(attrs, :name, ""),
      description: Map.get(attrs, :description, ""),
      version: Map.get(attrs, :version, "1.0.0"),
      category: Map.get(attrs, :category, :custom),
      author: Map.get(attrs, :author, "system"),
      tags: Map.get(attrs, :tags, []),
      content: Map.get(attrs, :content, ""),
      variables: normalize_variables(Map.get(attrs, :variables, [])),
      conditionals: normalize_conditionals(Map.get(attrs, :conditionals, [])),
      metadata: Map.get(attrs, :metadata, %{}),
      created_at: Map.get(attrs, :created_at, now),
      updated_at: Map.get(attrs, :updated_at, now)
    }
    
    case validate_template(template) do
      :ok -> {:ok, template}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Create a template from a map (for loading from external sources).
  """
  @spec from_map(map()) :: {:ok, template()} | {:error, term()}
  def from_map(map) when is_map(map) do
    # Convert string keys to atoms where appropriate
    normalized_map = normalize_map_keys(map)
    new(normalized_map)
  end
  
  @doc """
  Convert a template to a map (for serialization).
  """
  @spec to_map(template()) :: map()
  def to_map(%__MODULE__{} = template) do
    Map.from_struct(template)
  end
  
  @doc """
  Update a template with new attributes.
  """
  @spec update(template(), map()) :: {:ok, template()} | {:error, term()}
  def update(%__MODULE__{} = template, updates) when is_map(updates) do
    updated_template = %{template |
      updated_at: DateTime.utc_now()
    }
    |> struct!(updates)
    
    case validate_template(updated_template) do
      :ok -> {:ok, updated_template}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Create a variable definition.
  """
  @spec variable(String.t(), atom(), keyword()) :: variable()
  def variable(name, type, opts \\ []) do
    %{
      name: name,
      type: type,
      required: Keyword.get(opts, :required, false),
      default: Keyword.get(opts, :default),
      description: Keyword.get(opts, :description, ""),
      validator: Keyword.get(opts, :validator),
      transformer: Keyword.get(opts, :transformer)
    }
  end
  
  @doc """
  Create a conditional definition.
  """
  @spec conditional(String.t(), String.t(), String.t()) :: conditional()
  def conditional(name, expression, description \\ "") do
    %{
      name: name,
      expression: expression,
      description: description
    }
  end
  
  @doc """
  Get all variables referenced in the template content.
  """
  @spec extract_referenced_variables(String.t() | list()) :: [String.t()]
  def extract_referenced_variables(content) when is_binary(content) do
    Regex.scan(~r/\{\{(?!#|\/|>)([^}]+)\}\}/, content)
    |> Enum.map(fn [_full, var] -> String.trim(var) end)
    |> Enum.uniq()
  end
  
  def extract_referenced_variables(content) when is_list(content) do
    Enum.flat_map(content, &extract_referenced_variables/1)
    |> Enum.uniq()
  end
  
  @doc """
  Get all conditionals referenced in the template content.
  """
  @spec extract_referenced_conditionals(String.t() | list()) :: [String.t()]
  def extract_referenced_conditionals(content) when is_binary(content) do
    Regex.scan(~r/\{\{#(\w+)\}\}/, content)
    |> Enum.map(fn [_full, condition] -> condition end)
    |> Enum.uniq()
  end
  
  def extract_referenced_conditionals(content) when is_list(content) do
    Enum.flat_map(content, &extract_referenced_conditionals/1)
    |> Enum.uniq()
  end
  
  @doc """
  Check if a template is valid.
  """
  @spec valid?(template()) :: boolean()
  def valid?(%__MODULE__{} = template) do
    case validate_template(template) do
      :ok -> true
      {:error, _} -> false
    end
  end
  
  @doc """
  Get valid categories.
  """
  def valid_categories, do: @valid_categories
  
  @doc """
  Get valid variable types.
  """
  def valid_variable_types, do: @valid_variable_types
  
  ## Private Implementation
  
  defp generate_id(name) do
    # Generate a unique ID based on name and timestamp
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    base = name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
    
    case base do
      "" -> String.to_atom("template_#{timestamp}")
      base -> String.to_atom("#{base}_#{timestamp}")
    end
  end
  
  defp normalize_map_keys(map) do
    map
    |> Enum.map(fn
      {key, value} when is_binary(key) ->
        # Convert known string keys to atoms
        atom_key = case key do
          "id" -> :id
          "name" -> :name
          "description" -> :description
          "version" -> :version
          "category" -> :category
          "author" -> :author
          "tags" -> :tags
          "content" -> :content
          "variables" -> :variables
          "conditionals" -> :conditionals
          "metadata" -> :metadata
          "created_at" -> :created_at
          "updated_at" -> :updated_at
          _ -> key
        end
        {atom_key, value}
      
      {key, value} -> {key, value}
    end)
    |> Enum.into(%{})
  end
  
  defp normalize_variables(variables) when is_list(variables) do
    Enum.map(variables, &normalize_variable/1)
  end
  
  defp normalize_variable(var) when is_map(var) do
    %{
      name: Map.get(var, :name) || Map.get(var, "name", ""),
      type: normalize_variable_type(Map.get(var, :type) || Map.get(var, "type", :string)),
      required: Map.get(var, :required) || Map.get(var, "required", false),
      default: Map.get(var, :default) || Map.get(var, "default"),
      description: Map.get(var, :description) || Map.get(var, "description", ""),
      validator: Map.get(var, :validator) || Map.get(var, "validator"),
      transformer: Map.get(var, :transformer) || Map.get(var, "transformer")
    }
  end
  
  defp normalize_variable_type(type) when is_binary(type) do
    String.to_atom(type)
  end
  
  defp normalize_variable_type(type) when is_atom(type) do
    type
  end
  
  defp normalize_conditionals(conditionals) when is_list(conditionals) do
    Enum.map(conditionals, &normalize_conditional/1)
  end
  
  defp normalize_conditional(cond) when is_map(cond) do
    %{
      name: Map.get(cond, :name) || Map.get(cond, "name", ""),
      expression: Map.get(cond, :expression) || Map.get(cond, "expression", ""),
      description: Map.get(cond, :description) || Map.get(cond, "description", "")
    }
  end
  
  defp validate_template(template) do
    errors = []
    
    # Validate required fields
    errors = if is_nil(template.id) or template.id == "", do: errors ++ [:missing_id], else: errors
    errors = if is_nil(template.name) or template.name == "", do: errors ++ [:missing_name], else: errors
    errors = if is_nil(template.content) or template.content == "", do: errors ++ [:missing_content], else: errors
    
    # Validate category
    errors = if template.category not in @valid_categories, do: errors ++ [:invalid_category], else: errors
    
    # Validate variables
    case validate_variables_list(template.variables) do
      :ok -> :ok
      {:error, var_errors} -> errors = errors ++ var_errors
    end
    
    # Validate conditionals
    case validate_conditionals_list(template.conditionals) do
      :ok -> :ok
      {:error, cond_errors} -> errors = errors ++ cond_errors
    end
    
    # Validate template coherence
    errors = errors ++ validate_template_coherence(template)
    
    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
  
  defp validate_variables_list(variables) do
    errors = Enum.flat_map(variables, &validate_variable/1)
    
    # Check for duplicate names
    names = Enum.map(variables, & &1.name)
    duplicates = names -- Enum.uniq(names)
    
    errors = if Enum.empty?(duplicates), do: errors, else: errors ++ [{:duplicate_variable_names, duplicates}]
    
    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
  
  defp validate_variable(var) do
    errors = []
    
    # Validate name
    errors = if is_nil(var.name) or var.name == "", do: errors ++ [:invalid_variable_name], else: errors
    
    # Validate type
    errors = if var.type not in @valid_variable_types, do: errors ++ [:invalid_variable_type], else: errors
    
    # Validate required field
    errors = if not is_boolean(var.required), do: errors ++ [:invalid_required_field], else: errors
    
    errors
  end
  
  defp validate_conditionals_list(conditionals) do
    errors = Enum.flat_map(conditionals, &validate_conditional_def/1)
    
    # Check for duplicate names
    names = Enum.map(conditionals, & &1.name)
    duplicates = names -- Enum.uniq(names)
    
    errors = if Enum.empty?(duplicates), do: errors, else: errors ++ [{:duplicate_conditional_names, duplicates}]
    
    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
  
  defp validate_conditional_def(cond) do
    errors = []
    
    # Validate name
    errors = if is_nil(cond.name) or cond.name == "", do: errors ++ [:invalid_conditional_name], else: errors
    
    # Validate expression
    errors = if is_nil(cond.expression) or cond.expression == "", do: errors ++ [:missing_conditional_expression], else: errors
    
    errors
  end
  
  defp validate_template_coherence(template) do
    errors = []
    
    # Check that all variables referenced in content are defined
    referenced_vars = extract_referenced_variables(template.content)
    defined_vars = Enum.map(template.variables, & &1.name)
    undefined_vars = referenced_vars -- defined_vars
    
    errors = if Enum.empty?(undefined_vars), do: errors, else: errors ++ [{:undefined_variables, undefined_vars}]
    
    # Check that all conditionals referenced in content are defined
    referenced_conditions = extract_referenced_conditionals(template.content)
    defined_conditions = Enum.map(template.conditionals, & &1.name)
    undefined_conditions = referenced_conditions -- defined_conditions
    
    errors = if Enum.empty?(undefined_conditions), do: errors, else: errors ++ [{:undefined_conditionals, undefined_conditions}]
    
    errors
  end
end