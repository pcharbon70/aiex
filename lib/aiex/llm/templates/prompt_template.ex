defmodule Aiex.LLM.Templates.PromptTemplate do
  @moduledoc """
  Legacy prompt templating system for backward compatibility.
  
  This module provides backward compatibility with the old template system
  while delegating to the new enhanced template engine for actual functionality.
  
  For new code, use Aiex.LLM.Templates.TemplateEngine directly.
  """

  alias Aiex.LLM.Templates.{Template, TemplateEngine}

  @type template :: %__MODULE__{
          name: String.t(),
          system_prompt: String.t() | nil,
          user_template: String.t(),
          variables: [atom()],
          metadata: map()
        }

  defstruct name: "",
            system_prompt: nil,
            user_template: "",
            variables: [],
            metadata: %{}

  @deprecated "Use Aiex.LLM.Templates.TemplateEngine instead"

  @doc """
  Create a new prompt template.
  """
  @spec new(String.t(), String.t(), keyword()) :: template()
  def new(name, user_template, opts \\ []) do
    %__MODULE__{
      name: name,
      system_prompt: Keyword.get(opts, :system_prompt),
      user_template: user_template,
      variables: extract_variables(user_template),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Render a template with the given variables.
  
  This function provides backward compatibility by converting the legacy
  template to the new format and using the enhanced template engine.
  """
  @spec render(template(), map()) :: {:ok, [Aiex.LLM.Adapter.message()]} | {:error, String.t()}
  def render(template, variables \\ %{}) do
    # Convert legacy template to new format
    case convert_to_new_template(template) do
      {:ok, new_template} ->
        case TemplateEngine.render_template_struct(new_template, variables) do
          {:ok, result} -> {:ok, format_as_messages(result.rendered_content, template.system_prompt)}
          {:error, reason} -> {:error, inspect(reason)}
        end
      {:error, reason} ->
        {:error, "Failed to convert template: #{inspect(reason)}"}
    end
  end

  defp convert_to_new_template(legacy_template) do
    # Convert legacy format to new template structure
    content = if legacy_template.system_prompt do
      [
        %{role: "system", content: legacy_template.system_prompt},
        %{role: "user", content: legacy_template.user_template}
      ]
    else
      legacy_template.user_template
    end

    variables = Enum.map(legacy_template.variables, fn var_name ->
      Template.variable(to_string(var_name), :string, description: "Legacy variable")
    end)

    Template.new(%{
      name: legacy_template.name,
      description: "Converted from legacy template",
      content: content,
      variables: variables,
      metadata: legacy_template.metadata
    })
  end

  defp format_as_messages(rendered_content, _system_prompt) when is_list(rendered_content) do
    rendered_content
  end

  defp format_as_messages(rendered_content, system_prompt) when is_binary(rendered_content) do
    messages = if system_prompt do
      [
        %{role: "system", content: system_prompt},
        %{role: "user", content: rendered_content}
      ]
    else
      [%{role: "user", content: rendered_content}]
    end
    messages
  end

  @doc """
  Load templates from a directory.
  """
  @spec load_templates(String.t()) :: {:ok, [template()]} | {:error, String.t()}
  def load_templates(directory) do
    case File.ls(directory) do
      {:ok, files} ->
        templates =
          files
          |> Enum.filter(&String.ends_with?(&1, ".exs"))
          |> Enum.map(&load_template_file(Path.join(directory, &1)))
          |> Enum.filter(&(&1 != nil))

        {:ok, templates}

      {:error, reason} ->
        {:error, "Failed to load templates: #{reason}"}
    end
  end

  @doc """
  Get built-in coding templates.
  """
  @spec builtin_templates() :: [template()]
  def builtin_templates do
    [
      code_explanation_template(),
      code_generation_template(),
      test_generation_template(),
      refactoring_template(),
      documentation_template()
    ]
  end

  # Built-in templates

  defp code_explanation_template do
    new(
      "code_explanation",
      """
      Please explain the following {{language}} code:

      ```{{language}}
      {{code}}
      ```

      {{#context}}
      Additional context: {{context}}
      {{/context}}

      Please provide:
      1. A high-level overview of what the code does
      2. Explanation of key components and logic
      3. Any potential issues or improvements
      """,
      system_prompt:
        "You are an expert software engineer helping to explain code clearly and comprehensively.",
      metadata: %{category: "explanation", difficulty: "beginner"}
    )
  end

  defp code_generation_template do
    new(
      "code_generation",
      """
      Generate {{language}} code for the following requirements:

      {{requirements}}

      {{#specifications}}
      Specifications:
      {{specifications}}
      {{/specifications}}

      {{#constraints}}
      Constraints:
      {{constraints}}
      {{/constraints}}

      Please provide clean, well-documented code that follows best practices.
      """,
      system_prompt:
        "You are an expert {{language}} developer. Write clean, efficient, and well-documented code.",
      metadata: %{category: "generation", difficulty: "intermediate"}
    )
  end

  defp test_generation_template do
    new(
      "test_generation",
      """
      Generate comprehensive tests for the following {{language}} code:

      ```{{language}}
      {{code}}
      ```

      {{#test_framework}}
      Use the {{test_framework}} testing framework.
      {{/test_framework}}

      Please include:
      1. Unit tests for all public functions
      2. Edge case testing
      3. Property-based tests where applicable
      4. Integration tests if relevant
      """,
      system_prompt:
        "You are an expert in test-driven development and {{language}} testing frameworks.",
      metadata: %{category: "testing", difficulty: "intermediate"}
    )
  end

  defp refactoring_template do
    new(
      "refactoring",
      """
      Refactor the following {{language}} code to improve:

      {{#improvements}}
      {{improvements}}
      {{/improvements}}

      Original code:
      ```{{language}}
      {{code}}
      ```

      {{#constraints}}
      Constraints:
      {{constraints}}
      {{/constraints}}

      Please provide the refactored code with explanations of the changes made.
      """,
      system_prompt:
        "You are an expert software engineer specializing in code refactoring and clean code principles.",
      metadata: %{category: "refactoring", difficulty: "advanced"}
    )
  end

  defp documentation_template do
    new(
      "documentation",
      """
      Generate documentation for the following {{language}} code:

      ```{{language}}
      {{code}}
      ```

      {{#doc_type}}
      Documentation type: {{doc_type}}
      {{/doc_type}}

      Please include:
      1. Module/function descriptions
      2. Parameter documentation
      3. Return value documentation
      4. Usage examples
      5. Any relevant notes or warnings
      """,
      system_prompt: "You are a technical writer specializing in {{language}} documentation.",
      metadata: %{category: "documentation", difficulty: "beginner"}
    )
  end

  # Private functions

  defp extract_variables(template) do
    # Extract {{variable}} patterns
    Regex.scan(~r/\{\{([^}]+)\}\}/, template, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1)
    |> Enum.uniq()
  end


  defp load_template_file(file_path) do
    try do
      {template_data, _bindings} = Code.eval_file(file_path)

      case template_data do
        %{name: name, user_template: user_template} = data ->
          new(name, user_template, Map.to_list(Map.drop(data, [:name, :user_template])))

        _ ->
          nil
      end
    rescue
      _ -> nil
    end
  end
end
