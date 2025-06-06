defmodule AiexTest do
  use ExUnit.Case

  test "application starts successfully" do
    # Test that our application modules are loaded
    assert Code.ensure_loaded?(Aiex.Context.Engine)
    assert Code.ensure_loaded?(Aiex.Sandbox.Config)
    assert Code.ensure_loaded?(Aiex.Sandbox.AuditLogger)
  end

  test "context engine is running" do
    # The context engine should be started by the application
    assert Process.whereis(Aiex.Context.Engine) |> is_pid()
  end

  test "sandbox config is running" do
    # The sandbox config should be started by the application
    assert Process.whereis(Aiex.Sandbox.Config) |> is_pid()
  end
end
