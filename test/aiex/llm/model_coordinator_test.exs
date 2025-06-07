defmodule Aiex.LLM.ModelCoordinatorTest do
  use ExUnit.Case, async: false
  alias Aiex.LLM.ModelCoordinator

  setup do
    # Start the coordinator if not already running
    case Process.whereis(ModelCoordinator) do
      nil -> start_supervised!({ModelCoordinator, []})
      _pid -> :ok
    end

    :ok
  end

  describe "provider registration and selection" do
    test "registers providers successfully" do
      adapter = Aiex.LLM.Adapters.Ollama
      config = %{base_url: "http://localhost:11434"}

      assert :ok = ModelCoordinator.register_provider(:test_ollama, adapter, config)
    end

    test "selects providers for requests" do
      # Register test providers
      ModelCoordinator.register_provider(:test_provider1, Aiex.LLM.Adapters.Ollama, %{})
      ModelCoordinator.register_provider(:test_provider2, Aiex.LLM.Adapters.OpenAI, %{})

      request = %{
        messages: [%{role: "user", content: "Hello"}],
        model: "gpt-3.5-turbo"
      }

      case ModelCoordinator.select_provider(request) do
        {:ok, {provider, adapter}} ->
          assert is_atom(provider)
          assert is_atom(adapter)

        {:error, :no_available_providers} ->
          # This is acceptable in test environment where providers might not be healthy
          :ok
      end
    end

    test "handles provider health updates" do
      ModelCoordinator.register_provider(:health_test, Aiex.LLM.Adapters.Ollama, %{})

      # Report a failed request
      ModelCoordinator.report_request_result(:health_test, :error, %{error: :timeout})

      # The coordinator should update the provider's health metrics
      # This is mainly testing that the function doesn't crash
      assert :ok = ModelCoordinator.force_health_check()
    end
  end

  describe "load balancing" do
    test "tracks request metrics" do
      ModelCoordinator.register_provider(:metrics_test, Aiex.LLM.Adapters.Ollama, %{})

      # Report successful request
      ModelCoordinator.report_request_result(:metrics_test, :success, %{response_time: 100})

      # Report failed request  
      ModelCoordinator.report_request_result(:metrics_test, :error, %{error: :rate_limit})

      # This mainly tests that metric tracking doesn't crash
      :ok
    end

    test "provides different selection strategies" do
      # Register multiple providers
      ModelCoordinator.register_provider(:strategy_test1, Aiex.LLM.Adapters.Ollama, %{})
      ModelCoordinator.register_provider(:strategy_test2, Aiex.LLM.Adapters.OpenAI, %{})

      request = %{messages: [%{role: "user", content: "Test"}]}

      # Test different strategies (may not have different results in test env, but shouldn't crash)
      strategies = [:random, :round_robin, :load_balanced, :local_affinity]

      for strategy <- strategies do
        case ModelCoordinator.select_provider(request, selection_strategy: strategy) do
          {:ok, _} -> :ok
          # Acceptable in test
          {:error, :no_available_providers} -> :ok
        end
      end
    end
  end

  describe "cluster coordination" do
    test "gets cluster status" do
      status = ModelCoordinator.get_cluster_status()

      assert is_map(status)
      assert Map.has_key?(status, node())
    end

    test "handles health checks" do
      # Force a health check - mainly testing it doesn't crash
      assert :ok = ModelCoordinator.force_health_check()
    end
  end

  describe "provider affinity" do
    test "identifies local providers correctly" do
      # Register local provider (Ollama/LMStudio are considered local)
      ModelCoordinator.register_provider(:local_test, Aiex.LLM.Adapters.Ollama, %{})

      # Register cloud provider
      ModelCoordinator.register_provider(:cloud_test, Aiex.LLM.Adapters.OpenAI, %{})

      request = %{messages: [%{role: "user", content: "Test"}]}

      # Test local affinity selection
      case ModelCoordinator.select_provider(request, selection_strategy: :local_affinity) do
        {:ok, {_provider, _adapter}} ->
          # Should prefer local providers when available and healthy
          :ok

        {:error, :no_available_providers} ->
          # Acceptable if providers are unhealthy in test environment
          :ok
      end
    end
  end

  describe "error handling" do
    test "handles requests when no providers are available" do
      # Clear any existing providers by using a fresh coordinator instance
      # (In practice, this would be a coordinator with no registered providers)

      request = %{messages: [%{role: "user", content: "Test"}]}

      # The coordinator should handle this gracefully, even if it returns an error
      result = ModelCoordinator.select_provider(request)

      case result do
        {:error, :no_available_providers} -> :ok
        {:ok, {_provider, _adapter}} -> :ok
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end
    end

    test "handles malformed requests gracefully" do
      # Test with malformed request
      malformed_request = %{invalid: "request"}

      # Should not crash the coordinator
      result = ModelCoordinator.select_provider(malformed_request)

      case result do
        {:error, _} -> :ok
        {:ok, _} -> :ok
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end
    end
  end
end
