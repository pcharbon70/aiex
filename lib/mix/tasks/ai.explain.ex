defmodule Mix.Tasks.Ai.Explain do
  @shortdoc "Explain Elixir code using AI assistance"
  
  @moduledoc """
  Analyze and explain Elixir code using AI-powered assistance.

  This task leverages the Aiex LLM integration to provide detailed explanations
  of Elixir code, including patterns, architecture, and best practices.

  ## Usage

      mix ai.explain [file_path]
      mix ai.explain [file_path] [function_name]

  ## Examples

      mix ai.explain lib/user.ex
      mix ai.explain lib/user.ex create_user
      mix ai.explain --stdin < some_code.ex

  ## Options

      --adapter     LLM adapter to use (openai, anthropic, ollama, lm_studio)
      --model       Specific model to use
      --detail      Detail level: basic, intermediate, advanced (default: intermediate)
      --format      Output format: text, markdown (default: text)
      --stdin       Read code from standard input
      --focus       Focus area: architecture, patterns, performance, security

  """

  use Mix.Task
  require Logger

  @impl Mix.Task
  def run(args) do
    {opts, args, _invalid} = OptionParser.parse(args,
      strict: [
        adapter: :string,
        model: :string,
        detail: :string,
        format: :string,
        stdin: :boolean,
        focus: :string,
        help: :boolean
      ],
      aliases: [h: :help]
    )

    if opts[:help] do
      Mix.shell().info(@moduledoc)
    else

      # Start application to ensure LLM services are available
      Mix.Task.run("app.start")

      cond do
        opts[:stdin] ->
          explain_stdin(opts)
          
        length(args) == 1 ->
          [file_path] = args
          explain_file(file_path, nil, opts)
          
        length(args) == 2 ->
          [file_path, function_name] = args
          explain_file(file_path, function_name, opts)
          
        length(args) == 0 ->
          Mix.shell().info("File path required. Usage: mix ai.explain file_path")
          
        true ->
          Mix.shell().info("Too many arguments. Usage: mix ai.explain file_path [function_name]")
      end
    end
  end

  defp explain_stdin(opts) do
    Mix.shell().info("🤖 Reading code from stdin...")
    
    code = IO.stream(:stdio, :line) |> Enum.join()
    
    if String.trim(code) == "" do
      Mix.shell().error("❌ No code provided via stdin")
      System.halt(1)
    end
    
    analyze_code(code, "stdin", nil, opts)
  end

  defp explain_file(file_path, function_name, opts) do
    Mix.shell().info("🤖 Analyzing #{file_path}#{if function_name, do: " (function: #{function_name})", else: ""}...")
    
    case File.read(file_path) do
      {:ok, code} ->
        filtered_code = if function_name do
          extract_function(code, function_name)
        else
          code
        end
        
        case filtered_code do
          {:ok, function_code} ->
            analyze_code(function_code, file_path, function_name, opts)
            
          {:error, reason} ->
            Mix.shell().error("❌ #{reason}")
            System.halt(1)
            
          code when is_binary(code) ->
            analyze_code(code, file_path, function_name, opts)
        end
        
      {:error, reason} ->
        Mix.shell().error("❌ Failed to read #{file_path}: #{reason}")
        System.halt(1)
    end
  end

  defp extract_function(code, function_name) do
    # Simple function extraction - look for def function_name
    lines = String.split(code, "\n")
    
    case find_function_bounds(lines, function_name) do
      {start_line, end_line} ->
        function_lines = Enum.slice(lines, start_line, end_line - start_line + 1)
        {:ok, Enum.join(function_lines, "\n")}
        
      nil ->
        {:error, "Function '#{function_name}' not found in file"}
    end
  end

  @doc false
  def find_function_bounds(lines, function_name) do
    # Find the start of the function
    start_index = Enum.find_index(lines, fn line ->
      String.match?(line, ~r/^\s*def\s+#{Regex.escape(function_name)}\b/)
    end)
    
    if start_index do
      # Find the end of the function (next def/defp or end of file)
      remaining_lines = Enum.drop(lines, start_index + 1)
      end_offset = Enum.find_index(remaining_lines, fn line ->
        String.match?(line, ~r/^\s*def[p]?\s+\w+/) or String.match?(line, ~r/^\s*end\s*$/)
      end)
      
      end_index = if end_offset do
        start_index + 1 + end_offset
      else
        length(lines) - 1
      end
      
      {start_index, end_index}
    else
      nil
    end
  end

  defp analyze_code(code, source, function_name, opts) do
    request = build_explanation_request(code, source, function_name, opts)
    
    case call_llm(request, opts) do
      {:ok, explanation} ->
        output_explanation(explanation, opts)
        
      {:error, reason} ->
        Mix.shell().error("❌ Failed to explain code: #{reason}")
        System.halt(1)
    end
  end

  defp build_explanation_request(code, source, function_name, opts) do
    detail_level = Keyword.get(opts, :detail, "intermediate")
    focus_area = opts[:focus]
    
    context = if function_name do
      "function `#{function_name}` from #{source}"
    else
      "code from #{source}"
    end
    
    focus_instruction = case focus_area do
      "architecture" -> "Focus on architectural patterns, design decisions, and module organization."
      "patterns" -> "Focus on Elixir patterns, idioms, and functional programming concepts used."
      "performance" -> "Focus on performance characteristics, potential bottlenecks, and optimizations."
      "security" -> "Focus on security considerations, input validation, and potential vulnerabilities."
      _ -> "Provide a comprehensive explanation covering all relevant aspects."
    end
    
    detail_instruction = case detail_level do
      "basic" -> "Provide a high-level explanation suitable for beginners."
      "advanced" -> "Provide detailed technical analysis with deep insights."
      _ -> "Provide a balanced explanation with moderate technical detail."
    end
    
    prompt = """
    Please analyze and explain this Elixir #{context}:

    ```elixir
    #{code}
    ```

    #{focus_instruction}
    #{detail_instruction}

    Include:
    - Purpose and functionality
    - Key Elixir concepts and patterns used
    - Code structure and organization
    - Notable design decisions
    - Potential improvements or concerns
    - How it fits into typical Elixir/OTP applications

    Provide a clear, well-structured explanation.
    """

    %{
      messages: [
        %{role: :system, content: "You are an expert Elixir developer and teacher. Provide clear, accurate explanations of Elixir code."},
        %{role: :user, content: prompt}
      ],
      model: opts[:model],
      temperature: 0.3,
      max_tokens: 2500
    }
  end

  defp call_llm(request, opts) do
    adapter = get_adapter(opts)
    
    case Aiex.LLM.Client.complete(request, adapter: adapter) do
      {:ok, %{content: content}} ->
        {:ok, content}
        
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
      "openai" -> :openai
      "anthropic" -> :anthropic  
      "ollama" -> :ollama
      "lm_studio" -> :lm_studio
      nil -> :ollama  # Default to local model
      other -> 
        Mix.shell().info("Unknown adapter '#{other}', using ollama")
        :ollama
    end
  end

  defp output_explanation(explanation, opts) do
    format = Keyword.get(opts, :format, "text")
    
    case format do
      "markdown" ->
        Mix.shell().info("\n## Code Explanation\n")
        Mix.shell().info(explanation)
        
      _ ->
        Mix.shell().info("\n" <> explanation)
    end
  end
end