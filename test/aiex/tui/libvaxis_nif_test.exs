defmodule Aiex.Tui.LibvaxisNifTest do
  use ExUnit.Case, async: false
  
  alias Aiex.Tui.LibvaxisNif
  
  @moduletag :tui
  @moduletag :integration
  
  describe "init/0" do
    @tag :skip
    test "initializes Vaxis successfully" do
      # This test requires actual terminal environment
      # Skip in CI/automated testing
      assert {:ok, resource} = LibvaxisNif.init()
      assert is_reference(resource)
    end
  end
  
  describe "terminal_size/1" do
    @tag :skip
    test "returns terminal dimensions" do
      # This test requires actual terminal environment
      {:ok, resource} = LibvaxisNif.init()
      assert {:ok, {width, height}} = LibvaxisNif.terminal_size(resource)
      assert is_integer(width) and width > 0
      assert is_integer(height) and height > 0
    end
  end
  
  describe "NIF loading" do
    test "NIF functions are defined" do
      # Verify that NIF functions exist
      assert function_exported?(LibvaxisNif, :init, 0)
      assert function_exported?(LibvaxisNif, :start_event_loop, 1)
      assert function_exported?(LibvaxisNif, :render, 4)
      assert function_exported?(LibvaxisNif, :terminal_size, 1)
    end
  end
end