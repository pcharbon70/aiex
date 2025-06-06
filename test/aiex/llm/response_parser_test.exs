defmodule Aiex.LLM.ResponseParserTest do
  use ExUnit.Case, async: true
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
  
  describe "parse/3 with code_generation type" do
    test "successfully parses code generation response" do
      content = """
      Here's the Elixir function you requested:
      
      ```elixir
      def calculate_sum(a, b) do
        a + b
      end
      ```
      
      # Usage
      You can call it like this: `calculate_sum(1, 2)`
      """
      
      assert {:ok, parsed} = ResponseParser.parse(content, :code_generation, language: "elixir")
      
      assert parsed.type == :code_generation
      assert parsed.structured_data.language == "elixir"
      assert String.contains?(parsed.structured_data.code, "calculate_sum")
      assert String.contains?(parsed.structured_data.usage, "calculate_sum(1, 2)")
    end
    
    test "returns error when no code block found" do
      content = "This is just text without any code blocks."
      
      assert {:error, "No code block found in response"} = 
        ResponseParser.parse(content, :code_generation)
    end
  end
  
  describe "parse/3 with code_explanation type" do
    test "successfully parses code explanation response" do
      content = """
      # Overview
      This function calculates the sum of two numbers.
      
      # Components
      It takes two parameters and returns their sum.
      
      # Improvements
      Could add type validation.
      """
      
      assert {:ok, parsed} = ResponseParser.parse(content, :code_explanation)
      
      assert parsed.type == :code_explanation
      assert String.contains?(parsed.structured_data.overview, "calculates the sum")
      assert String.contains?(parsed.structured_data.components, "two parameters")
      assert String.contains?(parsed.structured_data.improvements, "type validation")
    end
  end
  
  describe "parse/3 with test_generation type" do
    test "successfully parses test generation response" do
      content = """
      Here are the tests for your function:
      
      ```elixir
      defmodule CalculatorTest do
        use ExUnit.Case
        
        test "calculates sum correctly" do
          assert Calculator.calculate_sum(1, 2) == 3
        end
        
        test "handles negative numbers" do
          assert Calculator.calculate_sum(-1, 1) == 0
        end
      end
      ```
      """
      
      assert {:ok, parsed} = ResponseParser.parse(content, :test_generation, language: "elixir")
      
      assert parsed.type == :test_generation
      assert parsed.metadata.test_blocks_count == 1
      assert length(parsed.structured_data.tests) == 1
    end
    
    test "returns error when no test code found" do
      content = """
      ```elixir
      def regular_function do
        "not a test"
      end
      ```
      """
      
      assert {:error, "No test code found in response"} = 
        ResponseParser.parse(content, :test_generation, language: "elixir")
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
    
    test "detects Elixir syntax errors" do
      code = """
      def hello do
        "world"
      # missing end
      """
      
      assert {:error, _reason} = ResponseParser.validate_code(code, "elixir")
    end
    
    test "skips validation for unsupported languages" do
      code = "some random code"
      
      assert :ok = ResponseParser.validate_code(code, "unsupported")
    end
  end
end