defmodule Mix.Tasks.Ai.ExplainTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  describe "mix ai.explain" do
    test "shows help when requested" do
      output =
        capture_io(fn ->
          Mix.Tasks.Ai.Explain.run(["--help"])
        end)

      assert output =~ "Analyze and explain Elixir code using AI-powered assistance"
      assert output =~ "Usage"
      assert output =~ "Examples"
      assert output =~ "Options"
    end

    test "shows usage error when no arguments provided" do
      output =
        capture_io(fn ->
          Mix.Tasks.Ai.Explain.run([])
        end)

      assert output =~ "File path required"
      assert output =~ "Usage: mix ai.explain file_path"
    end

    test "shows usage error when too many arguments provided" do
      output =
        capture_io(fn ->
          Mix.Tasks.Ai.Explain.run(["file1", "function", "extra", "args"])
        end)

      assert output =~ "Too many arguments"
    end

    test "handles non-existent file gracefully" do
      output =
        capture_io(fn ->
          assert_raise SystemExit, fn ->
            Mix.Tasks.Ai.Explain.run(["non_existent_file.ex"])
          end
        end)

      assert output =~ "Failed to read non_existent_file.ex"
    end

    # Skip actual LLM explanation in tests
    @tag :skip
    test "explains existing file" do
      # This would test actual code explanation but requires LLM setup
      # In a real test environment, you'd mock the LLM client
      :ok
    end
  end

  describe "function extraction" do
    test "extracts specific function from code" do
      code = """
      defmodule TestModule do
        def function_one do
          :one
        end
        
        def function_two do
          :two
        end
        
        defp private_function do
          :private
        end
      end
      """

      # Test function extraction logic
      lines = String.split(code, "\n")
      bounds = Mix.Tasks.Ai.Explain.find_function_bounds(lines, "function_two")

      assert bounds != nil
      {start_line, end_line} = bounds
      extracted_lines = Enum.slice(lines, start_line, end_line - start_line + 1)
      extracted_code = Enum.join(extracted_lines, "\n")

      assert extracted_code =~ "def function_two"
      assert extracted_code =~ ":two"
      refute extracted_code =~ "function_one"
    end

    test "returns nil for non-existent function" do
      code = """
      defmodule TestModule do
        def existing_function do
          :exists
        end
      end
      """

      lines = String.split(code, "\n")
      bounds = Mix.Tasks.Ai.Explain.find_function_bounds(lines, "non_existent_function")

      assert bounds == nil
    end
  end
end
