defmodule Aiex.CLI.Commands.HelpTest do
  use ExUnit.Case, async: true
  
  alias Aiex.CLI.Commands.Help

  describe "execute/1" do
    test "shows general help for empty args" do
      input = %Optimus.ParseResult{args: %{}, flags: %{}, options: %{}}
      
      assert {:ok, {:info, "Aiex - AI-powered Elixir coding assistant", info}} = Help.execute(input)
      
      assert is_map(info)
      assert Map.has_key?(info, "Usage")
      assert Map.has_key?(info, "Commands")
    end

    test "shows general help for help command without args" do
      input = {[:help], %Optimus.ParseResult{args: %{}, flags: %{}, options: %{}}}
      
      assert {:ok, {:info, "Aiex - AI-powered Elixir coding assistant", _info}} = Help.execute(input)
    end

    test "shows command-specific help for create command" do
      input = {[:help], %Optimus.ParseResult{args: %{command: "create"}, flags: %{}, options: %{}}}
      
      assert {:ok, {:info, "Create Command", info}} = Help.execute(input)
      
      assert is_map(info)
      assert Map.has_key?(info, "Usage")
      assert Map.has_key?(info, "Subcommands")
    end

    test "shows command-specific help for analyze command" do
      input = {[:help], %Optimus.ParseResult{args: %{command: "analyze"}, flags: %{}, options: %{}}}
      
      assert {:ok, {:info, "Analyze Command", info}} = Help.execute(input)
      
      assert is_map(info)
      assert Map.has_key?(info, "Usage")
      assert Map.has_key?(info, "Subcommands")
    end

    test "shows error for unknown command help" do
      input = {[:help], %Optimus.ParseResult{args: %{command: "unknown"}, flags: %{}, options: %{}}}
      
      assert {:error, "Unknown command: unknown. Use 'aiex help' for available commands."} = Help.execute(input)
    end
  end
end