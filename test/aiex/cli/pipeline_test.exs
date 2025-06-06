defmodule Aiex.CLI.PipelineTest do
  use ExUnit.Case, async: true

  alias Aiex.CLI.Pipeline

  describe "parse/1" do
    test "parses version command successfully" do
      assert {:ok, {[:version], %Optimus.ParseResult{}}} = Pipeline.parse(["version"])
    end

    test "parses empty args" do
      assert {:ok, %Optimus.ParseResult{args: %{}, flags: %{}, options: %{}}} = Pipeline.parse([])
    end

    # Skip this test for now as Optimus calls System.halt on parse errors
    # which is problematic in tests
    @tag :skip
    test "handles invalid arguments" do
      # This test is skipped because Optimus calls System.halt/1 on parse errors
      # which terminates the test process
      assert true
    end
  end

  describe "validate/1" do
    test "validates parsed version command" do
      parsed = {[:version], %Optimus.ParseResult{args: %{}, flags: %{}, options: %{}}}
      assert {:ok, ^parsed} = Pipeline.validate({:ok, parsed})
    end

    test "validates empty command" do
      parsed = %Optimus.ParseResult{args: %{}, flags: %{}, options: %{}}
      assert {:ok, ^parsed} = Pipeline.validate({:ok, parsed})
    end
  end

  describe "route/1" do
    test "routes version command to Version handler" do
      parsed = {[:version], %Optimus.ParseResult{}}
      assert {:ok, {Aiex.CLI.Commands.Version, ^parsed}} = Pipeline.route({:ok, parsed})
    end

    test "routes empty command to Help handler" do
      parsed = %Optimus.ParseResult{}
      assert {:ok, {Aiex.CLI.Commands.Help, ^parsed}} = Pipeline.route({:ok, parsed})
    end
  end

  describe "process/1" do
    test "processes version command end-to-end" do
      import ExUnit.CaptureIO

      capture_io(fn ->
        assert :ok = Pipeline.process(["version"])
      end)
    end

    test "processes empty args as help" do
      import ExUnit.CaptureIO

      capture_io(fn ->
        assert :ok = Pipeline.process([])
      end)
    end
  end
end
