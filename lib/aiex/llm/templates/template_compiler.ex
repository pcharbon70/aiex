defmodule Aiex.LLM.Templates.TemplateCompiler do
  @moduledoc """
  Compiles prompt templates into optimized, executable forms.
  
  Features:
  - Pre-compilation for performance
  - Variable validation and type checking
  - Conditional logic compilation
  - Template inheritance resolution
  - Context injection optimization
  """
  
  alias Aiex.LLM.Templates.{Template, TemplateValidator}
  
  defstruct [
    :template_id,
    :compiled_content,
    :variables,
    :conditionals,
    :inheritance_chain,
    :performance_metadata
  ]
  
  @type compiled_template :: %__MODULE__{
    template_id: atom(),
    compiled_content: String.t() | list(),
    variables: list(Template.variable()),
    conditionals: list(Template.conditional()),
    inheritance_chain: list(atom()),
    performance_metadata: map()
  }
  
  @doc """
  Compile a template into an optimized executable form.
  """
  @spec compile(Template.t()) :: {:ok, compiled_template()} | {:error, term()}
  def compile(%Template{} = template) do
    with {:ok, validated_template} <- TemplateValidator.validate(template),
         {:ok, parsed_content} <- parse_template_content(validated_template.content),
         {:ok, compiled_content} <- compile_content(parsed_content),
         {:ok, compiled_variables} <- compile_variables(validated_template.variables),
         {:ok, compiled_conditionals} <- compile_conditionals(validated_template.conditionals) do
      
      compiled = %__MODULE__{
        template_id: validated_template.id,
        compiled_content: compiled_content,
        variables: compiled_variables,
        conditionals: compiled_conditionals,
        inheritance_chain: [],
        performance_metadata: %{
          compilation_time: DateTime.utc_now(),
          estimated_render_time_ms: estimate_render_time(compiled_content),
          memory_usage_kb: estimate_memory_usage(compiled_content),
          complexity_score: calculate_complexity_score(compiled_content)
        }
      }
      
      {:ok, compiled}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Render a compiled template with the given context.
  """
  @spec render(compiled_template(), map()) :: {:ok, String.t()} | {:error, term()}
  def render(%__MODULE__{} = compiled_template, context \\ %{}) do
    with {:ok, validated_context} <- validate_context(compiled_template, context),
         {:ok, resolved_conditionals} <- resolve_conditionals(compiled_template, validated_context),
         {:ok, rendered_content} <- render_content(compiled_template.compiled_content, validated_context, resolved_conditionals) do
      {:ok, rendered_content}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Get template performance metrics.
  """
  @spec get_performance_metrics(compiled_template()) :: map()
  def get_performance_metrics(%__MODULE__{performance_metadata: metadata}), do: metadata
  
  ## Private Implementation
  
  defp parse_template_content(content) when is_binary(content) do
    # Parse template content into structured format
    case parse_mustache_template(content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, {:template_parse_error, reason}}
    end
  end
  
  defp parse_template_content(content) when is_list(content) do
    # Handle multi-part templates (e.g., system + user messages)
    parsed_parts = Enum.map(content, fn part ->
      case parse_mustache_template(part) do
        {:ok, parsed} -> parsed
        {:error, reason} -> {:error, reason}
      end
    end)
    
    case Enum.find(parsed_parts, &match?({:error, _}, &1)) do
      nil -> {:ok, parsed_parts}
      {:error, reason} -> {:error, {:template_parse_error, reason}}
    end
  end
  
  defp parse_mustache_template(content) do
    # Simple mustache-style template parser
    # Supports: {{variable}}, {{#condition}}...{{/condition}}, {{>include}}
    
    try do
      tokens = tokenize_template(content)
      ast = parse_tokens(tokens)
      {:ok, ast}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end
  
  defp tokenize_template(content) do
    # Tokenize template content
    # Regex to match mustache patterns
    pattern = ~r/(\{\{[\#\/\>]?[^}]+\}\})/
    
    String.split(content, pattern, include_captures: true, trim: false)
    |> Enum.map(&classify_token/1)
    |> Enum.reject(&(&1 == {:text, ""}))
  end
  
  defp classify_token(token) do
    cond do
      String.starts_with?(token, "{{#") ->
        condition_name = String.slice(token, 3..-3//1)
        {:condition_start, String.trim(condition_name)}
      
      String.starts_with?(token, "{{/") ->
        condition_name = String.slice(token, 3..-3//1)
        {:condition_end, String.trim(condition_name)}
      
      String.starts_with?(token, "{{>") ->
        include_name = String.slice(token, 3..-3//1)
        {:include, String.trim(include_name)}
      
      String.starts_with?(token, "{{") and String.ends_with?(token, "}}") ->
        variable_name = String.slice(token, 2..-3//1)
        {:variable, String.trim(variable_name)}
      
      true ->
        {:text, token}
    end
  end
  
  defp parse_tokens(tokens) do
    {ast, _stack} = parse_tokens_recursive(tokens, [], [])
    ast
  end
  
  defp parse_tokens_recursive([], acc, _stack) do
    {Enum.reverse(acc), []}
  end
  
  defp parse_tokens_recursive([{:condition_start, name} | rest], acc, stack) do
    {condition_content, remaining_tokens} = parse_condition_block(rest, name, [])
    condition_node = {:condition, name, condition_content}
    parse_tokens_recursive(remaining_tokens, [condition_node | acc], stack)
  end
  
  defp parse_tokens_recursive([{:condition_end, _name} | rest], acc, _stack) do
    {Enum.reverse(acc), rest}
  end
  
  defp parse_tokens_recursive([token | rest], acc, stack) do
    parse_tokens_recursive(rest, [token | acc], stack)
  end
  
  defp parse_condition_block([{:condition_end, name} | rest], name, acc) do
    {Enum.reverse(acc), rest}
  end
  
  defp parse_condition_block([{:condition_start, nested_name} | rest], target_name, acc) do
    {nested_content, remaining} = parse_condition_block(rest, nested_name, [])
    nested_condition = {:condition, nested_name, nested_content}
    parse_condition_block(remaining, target_name, [nested_condition | acc])
  end
  
  defp parse_condition_block([token | rest], target_name, acc) do
    parse_condition_block(rest, target_name, [token | acc])
  end
  
  defp parse_condition_block([], _target_name, _acc) do
    raise "Unclosed condition block"
  end
  
  defp compile_content(parsed_content) when is_list(parsed_content) do
    # Compile each part of multi-part template
    compiled_parts = Enum.map(parsed_content, &compile_content_part/1)
    {:ok, compiled_parts}
  end
  
  defp compile_content(parsed_content) do
    compiled = compile_content_part(parsed_content)
    {:ok, compiled}
  end
  
  defp compile_content_part(ast) when is_list(ast) do
    Enum.map(ast, &compile_ast_node/1)
  end
  
  defp compile_content_part(ast) do
    compile_ast_node(ast)
  end
  
  defp compile_ast_node({:text, text}), do: {:static, text}
  defp compile_ast_node({:variable, name}), do: {:variable, name}
  defp compile_ast_node({:condition, name, content}) do
    compiled_content = Enum.map(content, &compile_ast_node/1)
    {:condition, name, compiled_content}
  end
  defp compile_ast_node({:include, name}), do: {:include, name}
  
  defp compile_variables(variables) do
    compiled = Enum.map(variables, fn variable ->
      %{
        name: variable.name,
        type: variable.type,
        required: variable.required,
        default: variable.default,
        validator: compile_validator(variable.validator),
        transformer: compile_transformer(variable.transformer)
      }
    end)
    {:ok, compiled}
  end
  
  defp compile_conditionals(conditionals) do
    compiled = Enum.map(conditionals, fn conditional ->
      %{
        name: conditional.name,
        expression: compile_expression(conditional.expression),
        description: conditional.description
      }
    end)
    {:ok, compiled}
  end
  
  defp compile_validator(nil), do: nil
  defp compile_validator(validator_fn) when is_function(validator_fn), do: validator_fn
  defp compile_validator(validator_spec) when is_map(validator_spec) do
    # Compile validator specification into function
    case validator_spec do
      %{type: :regex, pattern: pattern} ->
        compiled_regex = Regex.compile!(pattern)
        fn value -> Regex.match?(compiled_regex, to_string(value)) end
      
      %{type: :length, min: min, max: max} ->
        fn value -> 
          len = String.length(to_string(value))
          len >= min and len <= max
        end
      
      %{type: :enum, values: values} ->
        fn value -> value in values end
      
      _ ->
        fn _value -> true end
    end
  end
  
  defp compile_transformer(nil), do: nil
  defp compile_transformer(transformer_fn) when is_function(transformer_fn), do: transformer_fn
  defp compile_transformer(transformer_spec) when is_map(transformer_spec) do
    # Compile transformer specification into function
    case transformer_spec do
      %{type: :trim} ->
        fn value -> String.trim(to_string(value)) end
      
      %{type: :upcase} ->
        fn value -> String.upcase(to_string(value)) end
      
      %{type: :downcase} ->
        fn value -> String.downcase(to_string(value)) end
      
      %{type: :format, template: template} ->
        fn value -> String.replace(template, "{value}", to_string(value)) end
      
      _ ->
        fn value -> value end
    end
  end
  
  defp compile_expression(expression) when is_binary(expression) do
    # Compile conditional expressions
    # Support basic operations: ==, !=, >, <, >=, <=, contains, in
    case String.split(expression, " ", parts: 3) do
      [left, operator, right] ->
        {
          :binary_op,
          String.trim(left),
          String.to_atom(operator),
          parse_value(String.trim(right))
        }
      
      [variable] ->
        {:variable_exists, String.trim(variable)}
      
      _ ->
        {:invalid_expression, expression}
    end
  end
  
  defp parse_value("true"), do: true
  defp parse_value("false"), do: false
  defp parse_value("nil"), do: nil
  defp parse_value(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> 
            # Remove quotes if present
            if String.starts_with?(value, "\"") and String.ends_with?(value, "\"") do
              String.slice(value, 1..-2//-1)
            else
              value
            end
        end
    end
  end
  
  defp validate_context(compiled_template, context) do
    # Validate that all required variables are present and valid
    missing_vars = Enum.filter(compiled_template.variables, fn var ->
      var.required and not Map.has_key?(context, var.name)
    end)
    
    case missing_vars do
      [] ->
        # Validate individual variable values
        validate_variable_values(compiled_template.variables, context)
      
      missing ->
        missing_names = Enum.map(missing, & &1.name)
        {:error, {:missing_required_variables, missing_names}}
    end
  end
  
  defp validate_variable_values(variables, context) do
    Enum.reduce_while(variables, {:ok, context}, fn var, {:ok, acc_context} ->
      value = Map.get(context, var.name, var.default)
      
      case validate_variable_value(var, value) do
        {:ok, validated_value} ->
          new_context = Map.put(acc_context, var.name, validated_value)
          {:cont, {:ok, new_context}}
        
        {:error, reason} ->
          {:halt, {:error, {:variable_validation_failed, var.name, reason}}}
      end
    end)
  end
  
  defp validate_variable_value(var, value) do
    with {:ok, value} <- apply_variable_transformer(var, value),
         {:ok, value} <- apply_variable_validator(var, value) do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp apply_variable_transformer(var, value) do
    case var.transformer do
      nil -> {:ok, value}
      transformer when is_function(transformer, 1) ->
        try do
          {:ok, transformer.(value)}
        rescue
          error -> {:error, {:transformer_error, Exception.message(error)}}
        end
    end
  end
  
  defp apply_variable_validator(var, value) do
    case var.validator do
      nil -> {:ok, value}
      validator when is_function(validator, 1) ->
        try do
          case validator.(value) do
            true -> {:ok, value}
            false -> {:error, :validation_failed}
            {:error, reason} -> {:error, reason}
          end
        rescue
          error -> {:error, {:validator_error, Exception.message(error)}}
        end
    end
  end
  
  defp resolve_conditionals(compiled_template, context) do
    resolved = Enum.reduce(compiled_template.conditionals, %{}, fn conditional, acc ->
      result = evaluate_conditional_expression(conditional.expression, context)
      Map.put(acc, conditional.name, result)
    end)
    {:ok, resolved}
  end
  
  defp evaluate_conditional_expression({:variable_exists, var_name}, context) do
    Map.has_key?(context, var_name) and not is_nil(Map.get(context, var_name))
  end
  
  defp evaluate_conditional_expression({:binary_op, left, operator, right}, context) do
    left_value = get_context_value(left, context)
    
    case operator do
      :"==" -> left_value == right
      :"!=" -> left_value != right
      :">" -> compare_values(left_value, right) == :gt
      :"<" -> compare_values(left_value, right) == :lt
      :">=" -> compare_values(left_value, right) in [:gt, :eq]
      :"<=" -> compare_values(left_value, right) in [:lt, :eq]
      :contains -> String.contains?(to_string(left_value), to_string(right))
      :in -> left_value in (if is_list(right), do: right, else: [right])
      _ -> false
    end
  end
  
  defp evaluate_conditional_expression({:invalid_expression, _}, _context), do: false
  
  defp get_context_value(var_name, context) do
    # Support nested access like "user.name"
    case String.split(var_name, ".") do
      [single_key] -> Map.get(context, single_key)
      keys -> get_nested_value(context, keys)
    end
  end
  
  defp get_nested_value(map, [key]) when is_map(map) do
    Map.get(map, key)
  end
  
  defp get_nested_value(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      nil -> nil
      nested_map -> get_nested_value(nested_map, rest)
    end
  end
  
  defp get_nested_value(_value, _keys), do: nil
  
  defp compare_values(left, right) when is_number(left) and is_number(right) do
    cond do
      left > right -> :gt
      left < right -> :lt
      true -> :eq
    end
  end
  
  defp compare_values(left, right) do
    case String.compare(to_string(left), to_string(right)) do
      :gt -> :gt
      :lt -> :lt
      :eq -> :eq
    end
  end
  
  defp render_content(compiled_content, context, conditionals) when is_list(compiled_content) do
    rendered_parts = Enum.map(compiled_content, fn part ->
      render_content_part(part, context, conditionals)
    end)
    {:ok, rendered_parts}
  end
  
  defp render_content(compiled_content, context, conditionals) do
    rendered = render_content_part(compiled_content, context, conditionals)
    {:ok, rendered}
  end
  
  defp render_content_part(content_nodes, context, conditionals) when is_list(content_nodes) do
    content_nodes
    |> Enum.map(&render_content_node(&1, context, conditionals))
    |> Enum.join("")
  end
  
  defp render_content_node({:static, text}, _context, _conditionals), do: text
  
  defp render_content_node({:variable, name}, context, _conditionals) do
    value = get_context_value(name, context)
    to_string(value || "")
  end
  
  defp render_content_node({:condition, name, content}, context, conditionals) do
    case Map.get(conditionals, name, false) do
      true -> render_content_part(content, context, conditionals)
      false -> ""
    end
  end
  
  defp render_content_node({:include, _name}, _context, _conditionals) do
    # TODO: Implement template includes
    ""
  end
  
  # Performance estimation functions
  defp estimate_render_time(compiled_content) do
    # Rough estimation based on content complexity
    node_count = count_nodes(compiled_content)
    base_time_ms = 1.0
    node_time_ms = 0.1
    base_time_ms + (node_count * node_time_ms)
  end
  
  defp estimate_memory_usage(compiled_content) do
    # Rough estimation based on content size
    content_size = :erlang.external_size(compiled_content)
    div(content_size, 1024)  # Convert to KB
  end
  
  defp calculate_complexity_score(compiled_content) do
    # Calculate complexity based on structure
    node_count = count_nodes(compiled_content)
    condition_count = count_conditions(compiled_content)
    variable_count = count_variables(compiled_content)
    
    # Simple complexity formula
    (node_count * 1) + (condition_count * 3) + (variable_count * 2)
  end
  
  defp count_nodes(content) when is_list(content) do
    Enum.reduce(content, 0, fn node, acc ->
      acc + count_nodes(node)
    end)
  end
  
  defp count_nodes({:condition, _name, content}), do: 1 + count_nodes(content)
  defp count_nodes(_node), do: 1
  
  defp count_conditions(content) when is_list(content) do
    Enum.reduce(content, 0, fn node, acc ->
      acc + count_conditions(node)
    end)
  end
  
  defp count_conditions({:condition, _name, content}), do: 1 + count_conditions(content)
  defp count_conditions(_node), do: 0
  
  defp count_variables(content) when is_list(content) do
    Enum.reduce(content, 0, fn node, acc ->
      acc + count_variables(node)
    end)
  end
  
  defp count_variables({:variable, _name}), do: 1
  defp count_variables({:condition, _name, content}), do: count_variables(content)
  defp count_variables(_node), do: 0
end