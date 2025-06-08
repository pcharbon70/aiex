defmodule Aiex.AI.Engines.BasicEngineTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Engines.{RefactoringEngine, TestGenerator}
  
  describe "RefactoringEngine" do
    test "starts successfully" do
      assert {:ok, pid} = RefactoringEngine.start_link(session_id: "test_refactoring")
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
    
    test "implements behavior correctly" do
      assert RefactoringEngine.can_handle?(:extract_function)
      assert RefactoringEngine.can_handle?(:refactoring)
      refute RefactoringEngine.can_handle?(:invalid_type)
      
      metadata = RefactoringEngine.get_metadata()
      assert metadata.name == "Refactoring Engine"
      assert is_list(metadata.supported_types)
    end
  end
  
  describe "TestGenerator" do
    test "starts successfully" do
      assert {:ok, pid} = TestGenerator.start_link(session_id: "test_generator")
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
    
    test "implements behavior correctly" do
      assert TestGenerator.can_handle?(:unit_tests)
      assert TestGenerator.can_handle?(:test_generation)
      refute TestGenerator.can_handle?(:invalid_type)
      
      metadata = TestGenerator.get_metadata()
      assert metadata.name == "Test Generator"
      assert is_list(metadata.supported_types)
    end
  end
end