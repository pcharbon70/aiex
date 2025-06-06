defmodule Aiex.LLM.Templates.PromptTemplate do
  @moduledoc """
  Prompt templating system for consistent and reusable prompts.

  Supports variable substitution, conditional sections, and template inheritance
  to create maintainable and flexible prompts for different coding tasks.
  """

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
  """
  @spec render(template(), map()) :: {:ok, [Aiex.LLM.Adapter.message()]} | {:error, String.t()}
  def render(template, variables \\ %{}) do
    with :ok <- validate_variables(template, variables),
         {:ok, rendered_user} <- render_template(template.user_template, variables) do
      messages = build_message_list(template.system_prompt, rendered_user, variables)
      {:ok, messages}
    end
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

  defp validate_variables(template, variables) do
    required_vars = template.variables
    provided_vars = Map.keys(variables) |> MapSet.new()
    required_set = MapSet.new(required_vars)

    missing = MapSet.difference(required_set, provided_vars) |> MapSet.to_list()

    if missing == [] do
      :ok
    else
      {:error, "Missing required variables: #{inspect(missing)}"}
    end
  end

  defp render_template(template, variables) do
    try do
      rendered =
        Enum.reduce(variables, template, fn {key, value}, acc ->
          # Handle conditional sections {{#key}}...{{/key}}
          acc = render_conditional_sections(acc, key, value)

          # Handle simple variable substitution {{key}}
          String.replace(acc, "{{#{key}}}", to_string(value))
        end)

      # Remove any unprocessed conditional sections
      cleaned = Regex.replace(~r/\{\{#\w+\}\}.*?\{\{\/\w+\}\}/s, rendered, "")

      {:ok, cleaned}
    rescue
      e -> {:error, "Template rendering failed: #{Exception.message(e)}"}
    end
  end

  defp render_conditional_sections(template, key, value) do
    pattern = ~r/\{\{##{key}\}\}(.*?)\{\{\/#{key}\}\}/s

    if value && value != "" && value != false do
      # Render the section
      Regex.replace(pattern, template, "\\1")
    else
      # Remove the section
      Regex.replace(pattern, template, "")
    end
  end

  defp build_message_list(nil, user_content, _variables) do
    [%{role: :user, content: user_content}]
  end

  defp build_message_list(system_template, user_content, variables) do
    {:ok, system_content} = render_template(system_template, variables)

    [
      %{role: :system, content: system_content},
      %{role: :user, content: user_content}
    ]
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
