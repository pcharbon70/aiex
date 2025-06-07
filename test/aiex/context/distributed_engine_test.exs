defmodule Aiex.Context.DistributedEngineTest do
  use ExUnit.Case, async: false
  alias Aiex.Context.DistributedEngine

  setup do
    # For tests, just use the existing running engine
    # Don't restart Mnesia as it affects other tests
    :ok
  end

  describe "distributed context management" do
    test "stores and retrieves AI context" do
      session_id = "test_session_#{:rand.uniform(10000)}"

      context = %{
        user_id: "user123",
        conversation_history: [
          %{role: "user", content: "Hello"},
          %{role: "assistant", content: "Hi there!"}
        ],
        active_model: "gpt-4"
      }

      # Store context
      assert {:atomic, :ok} = DistributedEngine.put_context(session_id, context)

      # Retrieve context
      assert {:ok, retrieved_context} = DistributedEngine.get_context(session_id)
      assert retrieved_context.user_id == "user123"
      assert retrieved_context.active_model == "gpt-4"
      assert length(retrieved_context.conversation_history) == 2
    end

    test "stores and retrieves code analysis cache" do
      file_path = "/path/to/test.ex"

      analysis = %{
        ast: {:defmodule, [], []},
        symbols: ["Test", "function1"],
        dependencies: ["Logger", "GenServer"]
      }

      # Store analysis
      assert {:atomic, :ok} = DistributedEngine.put_analysis(file_path, analysis)

      # Retrieve analysis
      assert {:ok, retrieved_analysis} = DistributedEngine.get_analysis(file_path)
      assert retrieved_analysis.symbols == ["Test", "function1"]
      assert retrieved_analysis.dependencies == ["Logger", "GenServer"]
      assert retrieved_analysis.file_path == file_path
    end

    test "records and retrieves LLM interactions" do
      session_id = "test_session_#{:rand.uniform(10000)}"

      interaction = %{
        session_id: session_id,
        prompt: "What is Elixir?",
        response: "Elixir is a functional programming language...",
        model_used: "gpt-4",
        tokens_used: 150,
        latency_ms: 1200
      }

      # Record interaction
      assert {:atomic, :ok} = DistributedEngine.record_interaction(interaction)

      # Retrieve interactions for session
      assert {:ok, interactions} = DistributedEngine.get_interactions(session_id)
      assert length(interactions) == 1

      [recorded] = interactions
      assert recorded.session_id == session_id
      assert recorded.prompt == "What is Elixir?"
      assert recorded.model_used == "gpt-4"
      assert recorded.tokens_used == 150
    end

    test "handles non-existent context gracefully" do
      non_existent_session = "non_existent_#{:rand.uniform(10000)}"

      assert {:error, :not_found} = DistributedEngine.get_context(non_existent_session)
    end

    test "provides statistics" do
      stats = DistributedEngine.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :node)
      assert Map.has_key?(stats, :ai_contexts)
      assert Map.has_key?(stats, :code_analyses)
      assert Map.has_key?(stats, :llm_interactions)
      assert Map.has_key?(stats, :cluster_nodes)
      assert stats.node == node()
    end
  end

  describe "context updates" do
    test "updates existing context" do
      session_id = "update_test_#{:rand.uniform(10000)}"

      # Create initial context
      initial_context = %{
        user_id: "user123",
        conversation_history: [],
        active_model: "gpt-3.5"
      }

      assert {:atomic, :ok} = DistributedEngine.put_context(session_id, initial_context)

      # Update context
      updated_context = %{
        user_id: "user123",
        conversation_history: [%{role: "user", content: "Hello"}],
        active_model: "gpt-4"
      }

      assert {:atomic, :ok} = DistributedEngine.put_context(session_id, updated_context)

      # Verify update
      assert {:ok, retrieved} = DistributedEngine.get_context(session_id)
      assert retrieved.active_model == "gpt-4"
      assert length(retrieved.conversation_history) == 1
    end
  end
end
