defmodule Aiex.LLM.Adapters.AnthropicTest do
  use ExUnit.Case, async: true

  alias Aiex.LLM.Adapters.Anthropic

  describe "validate_config/1" do
    test "validates correct Anthropic API key" do
      opts = [api_key: "sk-ant-api03-valid-key-example"]
      assert :ok = Anthropic.validate_config(opts)
    end

    test "rejects missing API key" do
      opts = []
      assert {:error, "Anthropic API key is required"} = Anthropic.validate_config(opts)
    end

    test "rejects invalid API key format" do
      opts = [api_key: "invalid-key"]
      assert {:error, "Invalid Anthropic API key format"} = Anthropic.validate_config(opts)
    end
  end

  describe "supported_models/0" do
    test "returns list of supported Claude models" do
      models = Anthropic.supported_models()

      assert is_list(models)
      assert "claude-3-opus-20240229" in models
      assert "claude-3-sonnet-20240229" in models
      assert "claude-3-haiku-20240307" in models
    end
  end

  describe "rate_limits/0" do
    test "returns Anthropic rate limits" do
      limits = Anthropic.rate_limits()

      assert %{requests_per_minute: 50, tokens_per_minute: 100_000} = limits
    end
  end

  describe "estimate_cost/1" do
    test "estimates cost for Claude Haiku" do
      request = %{
        model: "claude-3-haiku-20240307",
        messages: [%{role: :user, content: "Hello world"}],
        max_tokens: 1000
      }

      cost = Anthropic.estimate_cost(request)

      assert %{
               input_cost: input_cost,
               estimated_output_cost: output_cost,
               currency: "USD"
             } = cost

      assert is_float(input_cost)
      assert is_float(output_cost)
      assert input_cost >= 0
      assert output_cost >= 0
    end

    test "uses default model when none specified" do
      request = %{
        messages: [%{role: :user, content: "Hello"}],
        max_tokens: 100
      }

      cost = Anthropic.estimate_cost(request)

      assert is_map(cost)
      assert cost.currency == "USD"
    end
  end

  describe "complete/2" do
    @tag skip: "Requires mock HTTP client for testing"
    test "builds correct payload for Anthropic API" do
      # This would require mocking the HTTP client
      # Implementation would test the actual API call formatting
    end

    @tag skip: "Requires mock HTTP client for testing"
    test "handles system messages correctly" do
      # Test that system messages are extracted and placed in separate field
    end

    @tag skip: "Requires mock HTTP client for testing"
    test "parses Anthropic response format" do
      # Test parsing of Anthropic's response format
    end
  end
end
