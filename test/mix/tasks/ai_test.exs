defmodule Mix.Tasks.AiTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  describe "mix ai" do
    test "shows overview when run without arguments" do
      output = capture_io(fn ->
        Mix.Tasks.Ai.run([])
      end)
      
      assert output =~ "🤖 Aiex AI-Powered Development Tools"
      assert output =~ "mix ai.gen.module"
      assert output =~ "mix ai.explain"
    end
    
    test "shows detailed help with --help flag" do
      output = capture_io(fn ->
        Mix.Tasks.Ai.run(["--help"])
      end)
      
      assert output =~ "AI-powered development tools for Elixir"
      assert output =~ "Getting Started"
      assert output =~ "Configuration"
    end
    
    test "shows error for unknown task" do
      output = capture_io(fn ->
        assert_raise SystemExit, fn ->
          Mix.Tasks.Ai.run(["unknown.task"])
        end
      end)
      
      assert output =~ "Unknown AI task: unknown.task"
    end
  end
end