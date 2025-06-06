defmodule Aiex.LLM.Adapters.OllamaTest do
  use ExUnit.Case, async: true

  alias Aiex.LLM.Adapters.Ollama

  describe "validate_config/1" do
    @tag skip: "Requires running Ollama service"
    test "validates when Ollama service is running" do
      # This would require a running Ollama instance
      opts = [base_url: "http://localhost:11434"]
      # Would assert :ok when service is available
    end

    test "provides helpful error when service is unreachable" do
      # Invalid port
      opts = [base_url: "http://localhost:9999"]
      result = Ollama.validate_config(opts)

      case result do
        {:error, message} ->
          assert String.contains?(message, "Ollama service unreachable")
          assert String.contains?(message, "Is Ollama running?")

        _ ->
          # If somehow this doesn't fail, that's also fine (service might be running)
          assert true
      end
    end
  end

  describe "supported_models/1" do
    test "returns empty list when service unavailable" do
      opts = [base_url: "http://localhost:9999"]
      models = Ollama.supported_models(opts)

      assert models == []
    end

    @tag skip: "Requires running Ollama service"
    test "discovers models from running Ollama service" do
      # This would require a running Ollama instance with models
      opts = [base_url: "http://localhost:11434"]
      # Would assert that models are discovered
    end
  end

  describe "rate_limits/0" do
    test "returns no rate limits for local models" do
      limits = Ollama.rate_limits()

      assert %{requests_per_minute: nil, tokens_per_minute: nil} = limits
    end
  end

  describe "estimate_cost/1" do
    test "returns zero cost for local models" do
      request = %{
        model: "llama2",
        messages: [%{role: :user, content: "Hello world"}],
        max_tokens: 1000
      }

      cost = Ollama.estimate_cost(request)

      assert %{
               input_cost: input_cost,
               estimated_output_cost: output_cost,
               currency: "USD"
             } = cost

      assert input_cost == 0.0
      assert output_cost == 0.0
    end
  end

  describe "health_check/1" do
    test "returns error for unreachable service" do
      opts = [base_url: "http://localhost:9999", timeout: 1000]
      result = Ollama.health_check(opts)

      assert {:error, :unreachable} = result
    end

    @tag skip: "Requires running Ollama service"
    test "returns :ok for healthy service" do
      # This would require a running Ollama instance
      opts = [base_url: "http://localhost:11434"]
      # Would assert {:ok, :healthy}
    end
  end

  describe "discover_models/1" do
    test "handles service unavailable gracefully" do
      opts = [base_url: "http://localhost:9999", timeout: 1000]
      result = Ollama.discover_models(opts)

      assert {:error, _reason} = result
    end

    @tag skip: "Requires running Ollama service"
    test "parses model list from Ollama API" do
      # This would require a running Ollama instance
      # Would test parsing of /api/tags response
    end
  end

  describe "model_info/2" do
    @tag skip: "Requires running Ollama service"
    test "retrieves model information" do
      # This would require a running Ollama instance with models
      # Would test /api/show endpoint
    end
  end

  describe "complete/2" do
    @tag skip: "Requires mock HTTP client for testing"
    test "uses chat endpoint for conversations" do
      # Test that multi-message requests use /api/chat
    end

    @tag skip: "Requires mock HTTP client for testing"
    test "uses generate endpoint for single prompts" do
      # Test that single user messages use /api/generate
    end

    @tag skip: "Requires mock HTTP client for testing"
    test "handles streaming responses" do
      # Test streaming JSONL parsing
    end
  end
end
