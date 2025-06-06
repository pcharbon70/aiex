defmodule Aiex.CLI.Commands.VersionTest do
  use ExUnit.Case, async: true
  
  alias Aiex.CLI.Commands.Version

  describe "execute/1" do
    test "returns version information" do
      input = {[:version], %Optimus.ParseResult{args: %{}, flags: %{}, options: %{}}}
      
      assert {:ok, {:info, "Aiex Version Information", info}} = Version.execute(input)
      
      assert is_map(info)
      assert Map.has_key?(info, "Aiex")
      assert Map.has_key?(info, "Elixir") 
      assert Map.has_key?(info, "OTP")
      assert Map.has_key?(info, "Build")
    end
  end
end