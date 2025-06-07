defmodule Mix.Tasks.Ai.Gen.Module do
  @shortdoc "Generate an Elixir module with AI assistance"

  @moduledoc """
  Generate an Elixir module using AI-powered assistance.

  This task leverages the Aiex LLM integration to generate well-structured
  Elixir modules based on natural language descriptions.

  ## Usage

      mix ai.gen.module ModuleName "description of functionality"

  ## Examples

      mix ai.gen.module UserAuth "authentication module with login/logout"
      mix ai.gen.module DataProcessor "process CSV files and convert to JSON"

  ## Options

      --adapter     LLM adapter to use (openai, anthropic, ollama, lm_studio)
      --model       Specific model to use
      --output-dir  Directory to place generated file (default: lib/)
      --test        Also generate test file
      --docs        Include comprehensive documentation

  """

  use Mix.Task
  require Logger

  @impl Mix.Task
  def run(args) do
    {opts, args, _invalid} =
      OptionParser.parse(args,
        strict: [
          adapter: :string,
          model: :string,
          output_dir: :string,
          test: :boolean,
          docs: :boolean,
          help: :boolean
        ],
        aliases: [h: :help]
      )

    if opts[:help] do
      Mix.shell().info(@moduledoc)
    else
      case args do
        [module_name, description] ->
          generate_module(module_name, description, opts)

        [module_name] ->
          Mix.shell().info(
            "Description required. Usage: mix ai.gen.module #{module_name} \"description\""
          )

        [] ->
          Mix.shell().info(
            "Module name and description required. Usage: mix ai.gen.module ModuleName \"description\""
          )

        _ ->
          Mix.shell().info(
            "Too many arguments. Usage: mix ai.gen.module ModuleName \"description\""
          )
      end
    end
  end

  defp generate_module(module_name, description, opts) do
    Mix.shell().info("🤖 Generating module #{module_name} with AI assistance...")

    # Start application to ensure LLM services are available
    Mix.Task.run("app.start")

    # Build the generation request
    request = build_generation_request(module_name, description, opts)

    case call_llm(request, opts) do
      {:ok, generated_code} ->
        write_module_file(module_name, generated_code, opts)

        if opts[:test] do
          generate_test_file(module_name, description, opts)
        end

        Mix.shell().info("✅ Successfully generated #{module_name}")

      {:error, reason} ->
        Mix.shell().error("❌ Failed to generate module: #{reason}")
        System.halt(1)
    end
  end

  defp build_generation_request(module_name, description, opts) do
    include_docs = Keyword.get(opts, :docs, false)

    prompt = """
    Generate an Elixir module named `#{module_name}` based on this description:

    #{description}

    Requirements:
    - Follow Elixir conventions and best practices
    - Include proper typespec annotations
    - Use appropriate GenServer pattern if stateful behavior is needed
    - Include module documentation#{if include_docs, do: " with comprehensive @doc annotations", else: ""}
    - Handle errors gracefully with {:ok, result} | {:error, reason} patterns
    - Include basic validation for inputs
    - Follow OTP principles for fault tolerance

    Return only the Elixir code without any explanations or markdown formatting.
    """

    %{
      messages: [
        %{
          role: :system,
          content: "You are an expert Elixir developer. Generate clean, idiomatic Elixir code."
        },
        %{role: :user, content: prompt}
      ],
      model: opts[:model],
      # Lower temperature for more consistent code generation
      temperature: 0.3,
      max_tokens: 2000
    }
  end

  defp call_llm(request, opts) do
    adapter = get_adapter(opts)

    case Aiex.LLM.Client.complete(request, adapter: adapter) do
      {:ok, %{content: content}} ->
        {:ok, clean_generated_code(content)}

      {:error, reason} ->
        {:error, "LLM request failed: #{inspect(reason)}"}

      other ->
        {:error, "Unexpected LLM response: #{inspect(other)}"}
    end
  rescue
    error ->
      {:error, "LLM call error: #{Exception.message(error)}"}
  end

  defp get_adapter(opts) do
    case opts[:adapter] do
      "openai" ->
        :openai

      "anthropic" ->
        :anthropic

      "ollama" ->
        :ollama

      "lm_studio" ->
        :lm_studio

      # Default to local model
      nil ->
        :ollama

      other ->
        Mix.shell().info("Unknown adapter '#{other}', using ollama")
        :ollama
    end
  end

  defp clean_generated_code(content) do
    content
    |> String.replace(~r/```elixir\n?/, "")
    |> String.replace(~r/```\n?/, "")
    |> String.trim()
  end

  defp write_module_file(module_name, code, opts) do
    output_dir = Keyword.get(opts, :output_dir, "lib")
    file_path = Path.join([output_dir, "#{Macro.underscore(module_name)}.ex"])

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(file_path))

    # Write the file
    File.write!(file_path, code)

    # Format the file
    case System.cmd("mix", ["format", file_path], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, _} ->
        Mix.shell().info("⚠️  Format warning: #{output}")
    end

    Mix.shell().info("📁 Created #{file_path}")
  end

  defp generate_test_file(module_name, description, opts) do
    Mix.shell().info("🧪 Generating test file...")

    test_request = build_test_generation_request(module_name, description)

    case call_llm(test_request, opts) do
      {:ok, test_code} ->
        test_dir = "test"
        test_file = Path.join([test_dir, "#{Macro.underscore(module_name)}_test.exs"])

        File.mkdir_p!(Path.dirname(test_file))
        File.write!(test_file, test_code)

        # Format the test file
        System.cmd("mix", ["format", test_file])

        Mix.shell().info("📁 Created #{test_file}")

      {:error, reason} ->
        Mix.shell().error("❌ Failed to generate test: #{reason}")
    end
  end

  defp build_test_generation_request(module_name, description) do
    prompt = """
    Generate comprehensive ExUnit tests for the `#{module_name}` module.

    Module description: #{description}

    Requirements:
    - Use ExUnit.Case
    - Include setup if needed
    - Test both success and error cases
    - Use descriptive test names
    - Include edge cases and boundary conditions
    - Follow ExUnit best practices

    Return only the Elixir test code without explanations.
    """

    %{
      messages: [
        %{role: :system, content: "You are an expert at writing comprehensive Elixir tests."},
        %{role: :user, content: prompt}
      ],
      temperature: 0.2,
      max_tokens: 1500
    }
  end
end
