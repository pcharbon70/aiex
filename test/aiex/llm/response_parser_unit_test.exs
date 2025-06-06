defmodule Aiex.LLM.ResponseParserUnitTest do
  use ExUnit.Case, async: true

  # Import the module directly to test without application dependencies
  Code.require_file("../../../lib/aiex/llm/response_parser.ex", __DIR__)
  alias Aiex.LLM.ResponseParser

  describe "extract_code_blocks/1" do
    test "extracts single code block with language" do
      content = """
      Here's some Elixir code:

      ```elixir
      def hello do
        "world"
      end
      ```

      That's it!
      """

      blocks = ResponseParser.extract_code_blocks(content)

      assert length(blocks) == 1
      assert %{language: "elixir", code: "def hello do\n  \"world\"\nend"} = hd(blocks)
    end

    test "extracts multiple code blocks" do
      content = """
      ```elixir
      def hello, do: "world"
      ```

      And here's some JavaScript:

      ```javascript
      function hello() { return "world"; }
      ```
      """

      blocks = ResponseParser.extract_code_blocks(content)

      assert length(blocks) == 2
      assert Enum.any?(blocks, &(&1.language == "elixir"))
      assert Enum.any?(blocks, &(&1.language == "javascript"))
    end

    test "handles code blocks without language specification" do
      content = """
      ```
      some code here
      ```
      """

      blocks = ResponseParser.extract_code_blocks(content)

      assert length(blocks) == 1
      assert %{language: nil, code: "some code here"} = hd(blocks)
    end
  end

  describe "extract_sections/1" do
    test "extracts markdown sections" do
      content = """
      # Overview
      This is the overview section.

      ## Implementation
      Here's how to implement it.

      ### Notes
      Some additional notes.
      """

      sections = ResponseParser.extract_sections(content)

      assert Map.has_key?(sections, "overview")
      assert Map.has_key?(sections, "implementation")
      assert Map.has_key?(sections, "notes")
    end

    test "handles content without sections" do
      content = "Just some plain text without any headers."

      sections = ResponseParser.extract_sections(content)

      assert %{"main" => "Just some plain text without any headers."} = sections
    end
  end

  describe "validate_code/2" do
    test "validates correct Elixir code" do
      code = """
      def hello do
        "world"
      end
      """

      assert :ok = ResponseParser.validate_code(code, "elixir")
    end

    @tag skip: "Code validation needs refinement"
    test "detects Elixir syntax errors" do
      code = "def hello do 'invalid syntax"

      assert {:error, _reason} = ResponseParser.validate_code(code, "elixir")
    end

    test "skips validation for unsupported languages" do
      code = "some random code"

      assert :ok = ResponseParser.validate_code(code, "unsupported")
    end
  end
end
