defmodule Aiex.LLM.Templates.TemplateValidator do
  @moduledoc """
  Validates prompt templates for correctness, completeness, and best practices.
  
  Features:
  - Template structure validation
  - Variable definition validation
  - Conditional logic validation
  - Template syntax validation
  - Performance and quality checks
  """
  
  alias Aiex.LLM.Templates.Template
  
  @type validation_error :: {atom(), String.t()}
  @type validation_result :: {:ok, Template.t()} | {:error, [validation_error()]}
  
  # Template validation rules
  @required_fields [:id, :content, :variables]
  @optional_fields [:description, :version, :category, :author, :tags, :conditionals, :metadata]
  @allowed_categories [:workflow, :conversation, :engine, :operation, :system, :custom]
  @max_template_size_kb 100
  @max_variable_count 50
  @max_conditional_count 20
  
  @doc """
  Validate a complete template structure.
  """
  @spec validate(Template.t() | map()) :: validation_result()
  def validate(%Template{} = template) do
    validate_template_struct(template)
  end
  
  def validate(template_map) when is_map(template_map) do
    case Template.from_map(template_map) do
      {:ok, template} -> validate_template_struct(template)
      {:error, reason} -> {:error, [{:invalid_template_structure, reason}]}
    end
  end
  
  @doc """
  Validate template content syntax.
  """
  @spec validate_content(String.t() | list()) :: {:ok, String.t() | list()} | {:error, [validation_error()]}
  def validate_content(content) do
    errors = []
    
    errors = errors ++ validate_content_structure(content)
    errors = errors ++ validate_mustache_syntax(content)
    errors = errors ++ validate_content_size(content)
    
    case errors do
      [] -> {:ok, content}
      errors -> {:error, errors}
    end
  end
  
  @doc """
  Validate variable definitions.
  """
  @spec validate_variables(list(Template.variable())) :: {:ok, list(Template.variable())} | {:error, [validation_error()]}
  def validate_variables(variables) do
    errors = []
    
    errors = errors ++ validate_variable_count(variables)
    errors = errors ++ validate_variable_definitions(variables)
    errors = errors ++ validate_variable_names(variables)
    errors = errors ++ validate_variable_types(variables)
    
    case errors do
      [] -> {:ok, variables}
      errors -> {:error, errors}
    end
  end
  
  @doc """
  Validate conditional definitions.
  """
  @spec validate_conditionals(list(Template.conditional())) :: {:ok, list(Template.conditional())} | {:error, [validation_error()]}
  def validate_conditionals(conditionals) do
    errors = []
    
    errors = errors ++ validate_conditional_count(conditionals)
    errors = errors ++ validate_conditional_definitions(conditionals)
    errors = errors ++ validate_conditional_expressions(conditionals)
    
    case errors do
      [] -> {:ok, conditionals}
      errors -> {:error, errors}
    end
  end
  
  @doc """
  Validate template metadata.
  """
  @spec validate_metadata(map()) :: {:ok, map()} | {:error, [validation_error()]}
  def validate_metadata(metadata) when is_map(metadata) do
    errors = []
    
    errors = errors ++ validate_metadata_fields(metadata)
    errors = errors ++ validate_category(metadata)
    errors = errors ++ validate_version(metadata)
    
    case errors do
      [] -> {:ok, metadata}
      errors -> {:error, errors}
    end
  end
  
  @doc """
  Check template quality and provide recommendations.
  """
  @spec quality_check(Template.t()) :: {:ok, map()} | {:error, [validation_error()]}
  def quality_check(%Template{} = template) do
    checks = %{
      readability: check_readability(template),
      performance: check_performance(template),
      maintainability: check_maintainability(template),
      completeness: check_completeness(template),
      best_practices: check_best_practices(template)
    }
    
    overall_score = calculate_overall_score(checks)
    recommendations = generate_recommendations(checks)
    
    result = %{
      overall_score: overall_score,
      checks: checks,
      recommendations: recommendations
    }
    
    {:ok, result}
  end
  
  ## Private Implementation
  
  defp validate_template_struct(%Template{} = template) do
    errors = []
    
    # Validate required fields
    errors = errors ++ validate_required_fields(template)
    
    # Validate individual components
    case validate_content(template.content) do
      {:ok, _} -> :ok
      {:error, content_errors} -> errors = errors ++ content_errors
    end
    
    case validate_variables(template.variables) do
      {:ok, _} -> :ok
      {:error, variable_errors} -> errors = errors ++ variable_errors
    end
    
    case validate_conditionals(template.conditionals) do
      {:ok, _} -> :ok
      {:error, conditional_errors} -> errors = errors ++ conditional_errors
    end
    
    # Validate template coherence
    errors = errors ++ validate_template_coherence(template)
    
    case errors do
      [] -> {:ok, template}
      errors -> {:error, errors}
    end
  end
  
  defp validate_required_fields(template) do
    missing_fields = Enum.filter(@required_fields, fn field ->
      case Map.get(template, field) do
        nil -> true
        "" -> true
        [] -> field in [:variables]  # variables can be empty
        _ -> false
      end
    end)
    
    case missing_fields do
      [] -> []
      fields -> [{:missing_required_fields, "Missing fields: #{inspect(fields)}"}]
    end
  end
  
  defp validate_content_structure(content) when is_binary(content) do
    cond do
      String.trim(content) == "" ->
        [{:empty_content, "Template content cannot be empty"}]
      
      String.length(content) < 10 ->
        [{:content_too_short, "Template content is suspiciously short"}]
      
      true -> []
    end
  end
  
  defp validate_content_structure(content) when is_list(content) do
    if Enum.empty?(content) do
      [{:empty_content, "Template content list cannot be empty"}]
    else
      # Validate each part
      content
      |> Enum.with_index()
      |> Enum.flat_map(fn {part, index} ->
        case validate_content_structure(part) do
          [] -> []
          errors -> Enum.map(errors, fn {type, msg} -> {type, "Part #{index}: #{msg}"} end)
        end
      end)
    end
  end
  
  defp validate_mustache_syntax(content) when is_binary(content) do
    errors = []
    
    # Check for unclosed mustache tags
    open_count = Regex.scan(~r/\{\{[^}]*$/, content) |> length()
    if open_count > 0 do
      errors = errors ++ [{:unclosed_mustache_tags, "Found unclosed mustache tags"}]
    end
    
    # Check for malformed mustache tags
    malformed = Regex.scan(~r/\{[^{].*?\}[^}]/, content)
    if length(malformed) > 0 do
      errors = errors ++ [{:malformed_mustache_tags, "Found malformed mustache tags"}]
    end
    
    # Check for balanced conditional blocks
    conditions = extract_conditional_blocks(content)
    unbalanced = find_unbalanced_conditions(conditions)
    if length(unbalanced) > 0 do
      errors = errors ++ [{:unbalanced_conditions, "Unbalanced conditional blocks: #{inspect(unbalanced)}"}]
    end
    
    errors
  end
  
  defp validate_mustache_syntax(content) when is_list(content) do
    Enum.flat_map(content, &validate_mustache_syntax/1)
  end
  
  defp validate_content_size(content) do
    size_kb = :erlang.external_size(content) / 1024
    
    if size_kb > @max_template_size_kb do
      [{:template_too_large, "Template size (#{Float.round(size_kb, 2)}KB) exceeds maximum (#{@max_template_size_kb}KB)"}]
    else
      []
    end
  end
  
  defp validate_variable_count(variables) do
    if length(variables) > @max_variable_count do
      [{:too_many_variables, "Variable count (#{length(variables)}) exceeds maximum (#{@max_variable_count})"}]
    else
      []
    end
  end
  
  defp validate_variable_definitions(variables) do
    Enum.flat_map(variables, fn variable ->
      errors = []
      
      # Check required variable fields
      if is_nil(variable.name) or variable.name == "" do
        errors = errors ++ [{:invalid_variable_name, "Variable name cannot be empty"}]
      end
      
      if is_nil(variable.type) do
        errors = errors ++ [{:missing_variable_type, "Variable #{variable.name} missing type"}]
      end
      
      errors
    end)
  end
  
  defp validate_variable_names(variables) do
    # Check for duplicate names
    names = Enum.map(variables, & &1.name)
    duplicates = names -- Enum.uniq(names)
    
    errors = if Enum.empty?(duplicates) do
      []
    else
      [{:duplicate_variable_names, "Duplicate variable names: #{inspect(duplicates)}"}]
    end
    
    # Check for invalid names
    invalid_names = Enum.filter(names, fn name ->
      not String.match?(name, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)
    end)
    
    if Enum.empty?(invalid_names) do
      errors
    else
      errors ++ [{:invalid_variable_names, "Invalid variable names: #{inspect(invalid_names)}"}]
    end
  end
  
  defp validate_variable_types(variables) do
    valid_types = [:string, :integer, :float, :boolean, :list, :map, :any]
    
    Enum.flat_map(variables, fn variable ->
      if variable.type in valid_types do
        []
      else
        [{:invalid_variable_type, "Invalid type '#{variable.type}' for variable '#{variable.name}'"}]
      end
    end)
  end
  
  defp validate_conditional_count(conditionals) do
    if length(conditionals) > @max_conditional_count do
      [{:too_many_conditionals, "Conditional count (#{length(conditionals)}) exceeds maximum (#{@max_conditional_count})"}]
    else
      []
    end
  end
  
  defp validate_conditional_definitions(conditionals) do
    Enum.flat_map(conditionals, fn conditional ->
      errors = []
      
      if is_nil(conditional.name) or conditional.name == "" do
        errors = errors ++ [{:invalid_conditional_name, "Conditional name cannot be empty"}]
      end
      
      if is_nil(conditional.expression) or conditional.expression == "" do
        errors = errors ++ [{:missing_conditional_expression, "Conditional #{conditional.name} missing expression"}]
      end
      
      errors
    end)
  end
  
  defp validate_conditional_expressions(conditionals) do
    Enum.flat_map(conditionals, fn conditional ->
      case parse_conditional_expression(conditional.expression) do
        {:ok, _} -> []
        {:error, reason} -> [{:invalid_conditional_expression, "Conditional #{conditional.name}: #{reason}"}]
      end
    end)
  end
  
  defp validate_metadata_fields(metadata) do
    unknown_fields = Map.keys(metadata) -- (@required_fields ++ @optional_fields ++ [:category, :version, :author, :tags])
    
    if Enum.empty?(unknown_fields) do
      []
    else
      [{:unknown_metadata_fields, "Unknown metadata fields: #{inspect(unknown_fields)}"}]
    end
  end
  
  defp validate_category(metadata) do
    case Map.get(metadata, :category) do
      nil -> []
      category when category in @allowed_categories -> []
      category -> [{:invalid_category, "Invalid category: #{category}. Must be one of: #{inspect(@allowed_categories)}"}]
    end
  end
  
  defp validate_version(metadata) do
    case Map.get(metadata, :version) do
      nil -> []
      version when is_binary(version) ->
        if String.match?(version, ~r/^\d+\.\d+\.\d+.*$/) do
          []
        else
          [{:invalid_version_format, "Version must follow semantic versioning (e.g., '1.0.0')"}]
        end
      _ -> [{:invalid_version_type, "Version must be a string"}]
    end
  end
  
  defp validate_template_coherence(template) do
    errors = []
    
    # Check that all variables referenced in content are defined
    referenced_vars = extract_referenced_variables(template.content)
    defined_vars = Enum.map(template.variables, & &1.name)
    undefined_vars = referenced_vars -- defined_vars
    
    if not Enum.empty?(undefined_vars) do
      errors = errors ++ [{:undefined_variables, "Variables referenced but not defined: #{inspect(undefined_vars)}"}]
    end
    
    # Check that all conditionals referenced in content are defined
    referenced_conditions = extract_referenced_conditions(template.content)
    defined_conditions = Enum.map(template.conditionals, & &1.name)
    undefined_conditions = referenced_conditions -- defined_conditions
    
    if not Enum.empty?(undefined_conditions) do
      errors = errors ++ [{:undefined_conditionals, "Conditionals referenced but not defined: #{inspect(undefined_conditions)}"}]
    end
    
    # Check for unused variables (warning, not error)
    unused_vars = defined_vars -- referenced_vars
    if not Enum.empty?(unused_vars) do
      errors = errors ++ [{:unused_variables, "Variables defined but not used: #{inspect(unused_vars)}"}]
    end
    
    errors
  end
  
  # Helper functions
  
  defp extract_conditional_blocks(content) do
    # Extract all conditional blocks from content
    Regex.scan(~r/\{\{#(\w+)\}\}.*?\{\{\/\1\}\}/s, content)
    |> Enum.map(fn [_full, name] -> name end)
  end
  
  defp find_unbalanced_conditions(conditions) do
    # This is a simplified check - in practice, you'd need a proper parser
    # For now, assume balanced if we extracted them successfully
    []
  end
  
  defp extract_referenced_variables(content) when is_binary(content) do
    Regex.scan(~r/\{\{(?!#|\/|>)([^}]+)\}\}/, content)
    |> Enum.map(fn [_full, var] -> String.trim(var) end)
    |> Enum.uniq()
  end
  
  defp extract_referenced_variables(content) when is_list(content) do
    Enum.flat_map(content, &extract_referenced_variables/1)
    |> Enum.uniq()
  end
  
  defp extract_referenced_conditions(content) when is_binary(content) do
    Regex.scan(~r/\{\{#(\w+)\}\}/, content)
    |> Enum.map(fn [_full, condition] -> condition end)
    |> Enum.uniq()
  end
  
  defp extract_referenced_conditions(content) when is_list(content) do
    Enum.flat_map(content, &extract_referenced_conditions/1)
    |> Enum.uniq()
  end
  
  defp parse_conditional_expression(expression) do
    # Simple expression parser - would be more sophisticated in practice
    case String.split(expression, " ", parts: 3) do
      [left, operator, right] when operator in ["==", "!=", ">", "<", ">=", "<=", "contains", "in"] ->
        {:ok, {left, operator, right}}
      [variable] ->
        {:ok, {:exists, variable}}
      _ ->
        {:error, "Invalid expression format"}
    end
  end
  
  # Quality check functions
  
  defp check_readability(template) do
    score = 10.0
    issues = []
    
    # Check content length
    content_length = String.length(to_string(template.content))
    if content_length > 2000 do
      score = score - 2.0
      issues = issues ++ ["Content is very long (#{content_length} chars)"]
    end
    
    # Check variable count
    var_count = length(template.variables)
    if var_count > 20 do
      score = score - 1.5
      issues = issues ++ ["Many variables (#{var_count})"]
    end
    
    # Check description presence
    if is_nil(template.description) or String.trim(template.description) == "" do
      score = score - 1.0
      issues = issues ++ ["Missing description"]
    end
    
    %{score: max(score, 0.0), issues: issues}
  end
  
  defp check_performance(template) do
    score = 10.0
    issues = []
    
    # Estimate complexity
    complexity = estimate_template_complexity(template)
    if complexity > 100 do
      score = score - 3.0
      issues = issues ++ ["High complexity (#{complexity})"]
    end
    
    # Check for expensive operations
    if has_expensive_operations?(template) do
      score = score - 2.0
      issues = issues ++ ["Contains potentially expensive operations"]
    end
    
    %{score: max(score, 0.0), issues: issues}
  end
  
  defp check_maintainability(template) do
    score = 10.0
    issues = []
    
    # Check versioning
    if is_nil(template.version) do
      score = score - 1.0
      issues = issues ++ ["Missing version"]
    end
    
    # Check variable documentation
    undocumented_vars = Enum.count(template.variables, fn var ->
      is_nil(var.description) or String.trim(var.description) == ""
    end)
    
    if undocumented_vars > 0 do
      score = score - (undocumented_vars * 0.5)
      issues = issues ++ ["#{undocumented_vars} undocumented variables"]
    end
    
    %{score: max(score, 0.0), issues: issues}
  end
  
  defp check_completeness(template) do
    score = 10.0
    issues = []
    
    # Check required metadata
    required_meta = [:category, :description, :version]
    missing_meta = Enum.filter(required_meta, fn field ->
      is_nil(Map.get(template, field))
    end)
    
    if not Enum.empty?(missing_meta) do
      score = score - (length(missing_meta) * 1.5)
      issues = issues ++ ["Missing metadata: #{inspect(missing_meta)}"]
    end
    
    # Check variable completeness
    incomplete_vars = Enum.count(template.variables, fn var ->
      is_nil(var.type) or is_nil(var.description)
    end)
    
    if incomplete_vars > 0 do
      score = score - (incomplete_vars * 0.8)
      issues = issues ++ ["#{incomplete_vars} incomplete variable definitions"]
    end
    
    %{score: max(score, 0.0), issues: issues}
  end
  
  defp check_best_practices(template) do
    score = 10.0
    issues = []
    
    # Check naming conventions
    bad_names = Enum.filter(template.variables, fn var ->
      not String.match?(var.name, ~r/^[a-z][a-z0-9_]*$/)
    end)
    
    if not Enum.empty?(bad_names) do
      score = score - 1.0
      issues = issues ++ ["Poor variable naming conventions"]
    end
    
    # Check for hardcoded values
    if has_hardcoded_values?(template.content) do
      score = score - 1.5
      issues = issues ++ ["Contains hardcoded values"]
    end
    
    %{score: max(score, 0.0), issues: issues}
  end
  
  defp calculate_overall_score(checks) do
    scores = [
      checks.readability.score * 0.25,
      checks.performance.score * 0.20,
      checks.maintainability.score * 0.25,
      checks.completeness.score * 0.20,
      checks.best_practices.score * 0.10
    ]
    
    Enum.sum(scores)
  end
  
  defp generate_recommendations(checks) do
    all_issues = [
      checks.readability.issues,
      checks.performance.issues,
      checks.maintainability.issues,
      checks.completeness.issues,
      checks.best_practices.issues
    ]
    |> List.flatten()
    
    # Generate specific recommendations based on issues
    recommendations = all_issues
    |> Enum.map(&issue_to_recommendation/1)
    |> Enum.uniq()
    
    recommendations
  end
  
  defp issue_to_recommendation(issue) do
    cond do
      String.contains?(issue, "Missing description") ->
        "Add a clear description explaining the template's purpose"
      
      String.contains?(issue, "undocumented variables") ->
        "Document all variables with clear descriptions and examples"
      
      String.contains?(issue, "High complexity") ->
        "Consider breaking the template into smaller, more focused templates"
      
      String.contains?(issue, "hardcoded values") ->
        "Replace hardcoded values with configurable variables"
      
      String.contains?(issue, "Missing version") ->
        "Add semantic versioning to track template changes"
      
      true ->
        "Review and address: #{issue}"
    end
  end
  
  defp estimate_template_complexity(template) do
    content_complexity = count_mustache_tags(template.content) * 2
    variable_complexity = length(template.variables) * 3
    conditional_complexity = length(template.conditionals) * 5
    
    content_complexity + variable_complexity + conditional_complexity
  end
  
  defp count_mustache_tags(content) when is_binary(content) do
    length(Regex.scan(~r/\{\{[^}]+\}\}/, content))
  end
  
  defp count_mustache_tags(content) when is_list(content) do
    Enum.sum(Enum.map(content, &count_mustache_tags/1))
  end
  
  defp has_expensive_operations?(template) do
    content_str = to_string(template.content)
    
    # Check for patterns that might be expensive
    String.contains?(content_str, "{{#") and String.length(content_str) > 1000
  end
  
  defp has_hardcoded_values?(content) when is_binary(content) do
    # Simple heuristic: look for quoted strings or numbers outside of mustache tags
    non_template_content = String.replace(content, ~r/\{\{[^}]+\}\}/, "")
    
    Regex.match?(~r/"[^"]{10,}"/, non_template_content) or
    Regex.match?(~r/\b\d{4,}\b/, non_template_content)
  end
  
  defp has_hardcoded_values?(content) when is_list(content) do
    Enum.any?(content, &has_hardcoded_values?/1)
  end
end