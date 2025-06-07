defmodule Mix.Tasks.Ai.Gen.ModuleTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  describe "mix ai.gen.module" do
    test "shows help when requested" do
      output = capture_io(fn ->
        Mix.Tasks.Ai.Gen.Module.run(["--help"])
      end)
      
      assert output =~ "Generate an Elixir module using AI-powered assistance"
      assert output =~ "Usage"
      assert output =~ "Examples"
      assert output =~ "Options"
    end
    
    test "shows usage error when no arguments provided" do
      output = capture_io(fn ->
        Mix.Tasks.Ai.Gen.Module.run([])
      end)
      
      assert output =~ "Module name and description required"
      assert output =~ "Usage: mix ai.gen.module ModuleName"
    end
    
    test "shows usage error when only module name provided" do
      output = capture_io(fn ->
        Mix.Tasks.Ai.Gen.Module.run(["TestModule"])
      end)
      
      assert output =~ "Description required"
      assert output =~ "Usage: mix ai.gen.module TestModule"
    end
    
    test "shows usage error when too many arguments provided" do
      output = capture_io(fn ->
        Mix.Tasks.Ai.Gen.Module.run(["TestModule", "description", "extra", "args"])
      end)
      
      assert output =~ "Too many arguments"
    end
    
    @tag :skip  # Skip actual LLM generation in tests
    test "generates module with valid arguments" do
      # This would test actual module generation but requires LLM setup
      # In a real test environment, you'd mock the LLM client
      :ok
    end
  end
end