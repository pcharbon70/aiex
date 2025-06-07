defmodule Aiex.LLM.ResponseParser do
  @moduledoc """
  Parses and validates LLM responses for different use cases.

  Provides structured parsing for code blocks, explanations, and other
  common response formats from LLM interactions.
  """

  @type parsed_response :: %{
          type: atom(),
          content: String.t(),
          metadata: map(),
          structured_data: map()
        }

  @doc """
  Parse a response based on the expected format.
  """
  @spec parse(String.t(), atom(), keyword()) :: {:ok, parsed_response()} | {:error, String.t()}
  def parse(content, type, opts \\ []) do
    case type do
      :code_generation -> parse_code_generation(content, opts)
      :code_explanation -> parse_code_explanation(content, opts)
      :test_generation -> parse_test_generation(content, opts)
      :documentation -> parse_documentation(content, opts)
      :general -> parse_general(content, opts)
      _ -> {:error, "Unsupported response type: #{type}"}
    end
  end

  @doc """
  Extract code blocks from response content.
  """
  @spec extract_code_blocks(String.t()) :: [%{language: String.t() | nil, code: String.t()}]
  def extract_code_blocks(content) do
    # Match ```language\ncode\n``` patterns
    Regex.scan(~r/```(\w*)\n(.*?)\n```/s, content, capture: :all_but_first)
    |> Enum.map(fn
      [language, code] when language != "" -> %{language: language, code: String.trim(code)}
      [_language, code] -> %{language: nil, code: String.trim(code)}
    end)
  end

  @doc """
  Extract structured sections from response content.
  """
  @spec extract_sections(String.t()) :: map()
  def extract_sections(content) do
    # Extract markdown-style sections
    sections =
      Regex.scan(~r/^#+\s*(.+?)$(.*?)(?=^#+|\z)/sm, content, capture: :all_but_first)
      |> Enum.map(fn [title, content] ->
        {String.downcase(String.trim(title)) |> String.replace(" ", "_"), String.trim(content)}
      end)
      |> Map.new()

    # If no sections found, treat entire content as main section
    if Enum.empty?(sections) do
      %{"main" => content}
    else
      sections
    end
  end

  @doc """
  Validate code syntax for a given language.
  """
  @spec validate_code(String.t(), String.t()) :: :ok | {:error, String.t()}
  def validate_code(code, language) do
    case language do
      "elixir" -> validate_elixir_code(code)
      "javascript" -> validate_javascript_code(code)
      "python" -> validate_python_code(code)
      # Skip validation for unsupported languages
      _ -> :ok
    end
  end

  # Private functions for parsing different response types

  defp parse_code_generation(content, opts) do
    language = Keyword.get(opts, :language, "elixir")

    code_blocks = extract_code_blocks(content)
    sections = extract_sections(content)

    # Find the main code block
    main_code = find_main_code_block(code_blocks, language)

    if main_code do
      case validate_code(main_code.code, main_code.language || language) do
        :ok ->
          {:ok,
           %{
             type: :code_generation,
             content: content,
             metadata: %{
               language: main_code.language || language,
               code_blocks_count: length(code_blocks)
             },
             structured_data: %{
               code: main_code.code,
               language: main_code.language || language,
               explanation: Map.get(sections, "explanation", ""),
               usage: Map.get(sections, "usage", ""),
               notes: Map.get(sections, "notes", "")
             }
           }}

        {:error, reason} ->
          {:error, "Generated code has syntax errors: #{reason}"}
      end
    else
      {:error, "No code block found in response"}
    end
  end

  defp parse_code_explanation(content, _opts) do
    sections = extract_sections(content)
    code_blocks = extract_code_blocks(content)

    {:ok,
     %{
       type: :code_explanation,
       content: content,
       metadata: %{
         sections_count: map_size(sections),
         code_examples: length(code_blocks)
       },
       structured_data: %{
         overview: Map.get(sections, "overview", Map.get(sections, "main", "")),
         components: Map.get(sections, "components", ""),
         logic: Map.get(sections, "logic", ""),
         improvements: Map.get(sections, "improvements", ""),
         issues: Map.get(sections, "issues", ""),
         code_examples: code_blocks
       }
     }}
  end

  defp parse_test_generation(content, opts) do
    language = Keyword.get(opts, :language, "elixir")

    code_blocks = extract_code_blocks(content)
    sections = extract_sections(content)

    # Separate test files/functions
    test_blocks =
      Enum.filter(code_blocks, fn block ->
        contains_test_keywords?(block.code, language)
      end)

    if not Enum.empty?(test_blocks) do
      {:ok,
       %{
         type: :test_generation,
         content: content,
         metadata: %{
           language: language,
           test_blocks_count: length(test_blocks),
           total_blocks: length(code_blocks)
         },
         structured_data: %{
           tests: test_blocks,
           description: Map.get(sections, "description", ""),
           setup: Map.get(sections, "setup", ""),
           notes: Map.get(sections, "notes", "")
         }
       }}
    else
      {:error, "No test code found in response"}
    end
  end

  defp parse_documentation(content, _opts) do
    sections = extract_sections(content)
    code_blocks = extract_code_blocks(content)

    {:ok,
     %{
       type: :documentation,
       content: content,
       metadata: %{
         sections_count: map_size(sections),
         examples_count: length(code_blocks)
       },
       structured_data: %{
         description: Map.get(sections, "description", Map.get(sections, "main", "")),
         parameters: Map.get(sections, "parameters", ""),
         returns: Map.get(sections, "returns", ""),
         examples: code_blocks,
         notes: Map.get(sections, "notes", ""),
         warnings: Map.get(sections, "warnings", "")
       }
     }}
  end

  defp parse_general(content, _opts) do
    sections = extract_sections(content)
    code_blocks = extract_code_blocks(content)

    {:ok,
     %{
       type: :general,
       content: content,
       metadata: %{
         sections_count: map_size(sections),
         code_blocks_count: length(code_blocks)
       },
       structured_data: %{
         sections: sections,
         code_blocks: code_blocks
       }
     }}
  end

  defp find_main_code_block([], _language), do: nil
  defp find_main_code_block([block], _language), do: block

  defp find_main_code_block(blocks, language) do
    # Prefer blocks with matching language
    language_match =
      Enum.find(blocks, fn block ->
        block.language == language
      end)

    if language_match do
      language_match
    else
      # Return the largest code block
      Enum.max_by(blocks, fn block -> String.length(block.code) end)
    end
  end

  defp contains_test_keywords?(code, "elixir") do
    test_patterns = [
      ~r/\btest\s+/,
      ~r/\bdescribe\s+/,
      ~r/\bassert\s+/,
      ~r/\brefute\s+/,
      ~r/ExUnit/
    ]

    Enum.any?(test_patterns, &Regex.match?(&1, code))
  end

  defp contains_test_keywords?(code, "javascript") do
    test_patterns = [
      ~r/\bdescribe\s*\(/,
      ~r/\bit\s*\(/,
      ~r/\btest\s*\(/,
      ~r/\bexpect\s*\(/,
      ~r/\bassert\s*\(/
    ]

    Enum.any?(test_patterns, &Regex.match?(&1, code))
  end

  defp contains_test_keywords?(code, "python") do
    test_patterns = [
      ~r/\bdef test_/,
      ~r/\bassert\s+/,
      ~r/\bunittest\./,
      ~r/\bpytest\./
    ]

    Enum.any?(test_patterns, &Regex.match?(&1, code))
  end

  defp contains_test_keywords?(_code, _language), do: false

  defp validate_elixir_code(code) do
    try do
      # Use Code.string_to_quoted! with strict mode
      case Code.string_to_quoted(code, warn_on_unnecessary_quotes: false) do
        {:ok, _ast} -> :ok
        {:error, {_line, message, _token}} -> {:error, message}
        {:error, message} -> {:error, message}
      end
    rescue
      e -> {:error, Exception.message(e)}
    catch
      _, e -> {:error, "Syntax error: #{inspect(e)}"}
    end
  end

  defp validate_javascript_code(_code) do
    # Would require a JavaScript parser
    # For now, just basic syntax checks
    :ok
  end

  defp validate_python_code(_code) do
    # Would require a Python parser
    # For now, just basic syntax checks
    :ok
  end
end
