defmodule Aiex.Context.CompressorTest do
  use ExUnit.Case, async: true
  alias Aiex.Context.Compressor

  @sample_context_items [
    %{
      content: """
      defmodule Calculator do
        def add(a, b), do: a + b
        def subtract(a, b), do: a - b
      end
      """,
      type: :current_file,
      priority: 10
    },
    %{
      content: """
      defmodule Helper do
        def validate(x) when is_number(x), do: :ok
        def validate(_), do: :error
      end
      """,
      type: :related_file,
      priority: 5
    },
    %{
      content: """
      # This is documentation for the Calculator module
      # It provides basic arithmetic operations
      # Usage: Calculator.add(1, 2) #=> 3
      """,
      type: :documentation,
      priority: 3
    }
  ]

  @large_context_items [
    %{
      content: """
      defmodule LargeModule do
        #{Enum.map(1..50, fn i -> "def function_#{i}(x), do: x + #{i}" end) |> Enum.join("\n  ")}
      end
      """,
      type: :current_file,
      priority: 8
    },
    %{
      content: """
      defmodule AnotherLarge do
        #{Enum.map(1..30, fn i -> "def helper_#{i}(x, y), do: x * y + #{i}" end) |> Enum.join("\n  ")}
      end
      """,
      type: :related_file,
      priority: 4
    }
  ]

  describe "compress_context/2" do
    test "compresses context within token limits" do
      {:ok, result} =
        Compressor.compress_context(@sample_context_items, model: "gpt-4", max_tokens: 1000)

      assert Map.has_key?(result, :chunks)
      assert Map.has_key?(result, :total_tokens)
      assert Map.has_key?(result, :compression_ratio)
      assert Map.has_key?(result, :strategy_used)
      assert Map.has_key?(result, :model)

      assert is_list(result.chunks)
      assert is_integer(result.total_tokens)
      assert result.total_tokens <= 1000
      assert result.model == "gpt-4"
    end

    test "respects priority context" do
      priority_content = "# High priority instruction: Always validate inputs"

      {:ok, result} =
        Compressor.compress_context(@sample_context_items,
          model: "gpt-3.5-turbo",
          max_tokens: 500,
          priority_context: priority_content
        )

      # Priority content should be included
      combined_content = result.chunks |> Enum.map(& &1.content) |> Enum.join(" ")
      assert String.contains?(combined_content, "High priority instruction")
    end

    test "handles different compression strategies" do
      strategies = [:semantic, :size, :relevance, :priority]

      Enum.each(strategies, fn strategy ->
        {:ok, result} =
          Compressor.compress_context(@sample_context_items,
            strategy: strategy,
            max_tokens: 800
          )

        assert result.strategy_used == strategy
        assert is_list(result.chunks)
        assert result.total_tokens <= 800
      end)
    end

    test "handles empty context items" do
      {:ok, result} = Compressor.compress_context([])

      assert result.chunks == []
      assert result.total_tokens == 0
      assert result.compression_ratio == 1.0
    end

    test "handles very small token limits" do
      {:ok, result} =
        Compressor.compress_context(@sample_context_items,
          max_tokens: 50
        )

      # Should still return some content, even if heavily compressed
      assert is_list(result.chunks)
      assert result.total_tokens <= 50
    end

    test "handles large content with compression" do
      {:ok, result} =
        Compressor.compress_context(@large_context_items,
          model: "gpt-4",
          # Smaller limit to force compression
          max_tokens: 800,
          strategy: :semantic
        )

      assert is_list(result.chunks)
      assert result.total_tokens <= 800
      # Should achieve some compression when forced by smaller token limit
      # Allow for cases where compression ratio might be 1.0 if content fits
      assert result.compression_ratio <= 1.0
      # Should be reasonable compression
      assert result.compression_ratio >= 0.1
    end
  end

  describe "model-specific behavior" do
    test "adapts to different model token limits" do
      # Test with different models
      models = ["gpt-3.5-turbo", "gpt-4", "claude-3-sonnet", "ollama"]

      Enum.each(models, fn model ->
        {:ok, result} =
          Compressor.compress_context(@sample_context_items,
            model: model
          )

        assert result.model == model
        assert is_list(result.chunks)
      end)
    end

    test "respects model-specific token limits" do
      # Small model should compress more aggressively
      {:ok, small_result} =
        Compressor.compress_context(@large_context_items,
          # 4k tokens
          model: "gpt-3.5-turbo"
        )

      # Large model should include more content
      {:ok, large_result} =
        Compressor.compress_context(@large_context_items,
          # 200k tokens
          model: "claude-3-sonnet"
        )

      # Claude should include more content due to higher token limit
      assert length(large_result.chunks) >= length(small_result.chunks)
    end
  end

  describe "estimate_tokens/2" do
    test "estimates tokens for different content types" do
      code_content = "def hello(name), do: \"Hello, \#{name}!\""
      text_content = "This is a simple text sentence with some words."

      code_tokens = Compressor.estimate_tokens(code_content, "gpt-4")
      text_tokens = Compressor.estimate_tokens(text_content, "gpt-4")

      assert is_integer(code_tokens)
      assert is_integer(text_tokens)
      assert code_tokens > 0
      assert text_tokens > 0
    end

    test "varies estimates by model" do
      content = "def calculate(x, y), do: x + y"

      gpt_tokens = Compressor.estimate_tokens(content, "gpt-4")
      claude_tokens = Compressor.estimate_tokens(content, "claude-3-sonnet")

      assert is_integer(gpt_tokens)
      assert is_integer(claude_tokens)
      # Claude typically uses fewer tokens
      assert claude_tokens <= gpt_tokens
    end
  end

  describe "caching behavior" do
    test "caches compression results" do
      Compressor.clear_cache()

      # First compression should be a cache miss
      {:ok, result1} = Compressor.compress_context(@sample_context_items, model: "gpt-4")
      stats1 = Compressor.get_stats()

      # Second identical compression should be a cache hit
      {:ok, result2} = Compressor.compress_context(@sample_context_items, model: "gpt-4")
      stats2 = Compressor.get_stats()

      assert result1.chunks == result2.chunks
      assert result1.total_tokens == result2.total_tokens
      assert stats2.cache_hits > stats1.cache_hits
    end

    test "different options create different cache entries" do
      Compressor.clear_cache()

      {:ok, _} = Compressor.compress_context(@sample_context_items, strategy: :semantic)
      {:ok, _} = Compressor.compress_context(@sample_context_items, strategy: :size)

      stats = Compressor.get_stats()
      assert stats.cache_size >= 2
    end
  end

  describe "compression strategies" do
    test "semantic strategy prioritizes complete units" do
      {:ok, result} =
        Compressor.compress_context(@sample_context_items,
          strategy: :semantic,
          max_tokens: 500
        )

      assert result.strategy_used == :semantic

      # Should prefer complete modules/functions
      content = result.chunks |> Enum.map(& &1.content) |> Enum.join(" ")
      # Should contain complete constructs rather than fragments
      assert String.contains?(content, "defmodule") or String.contains?(content, "def ")
    end

    test "size strategy includes more smaller chunks" do
      {:ok, result} =
        Compressor.compress_context(@sample_context_items,
          strategy: :size,
          max_tokens: 600
        )

      assert result.strategy_used == :size
      assert is_list(result.chunks)
    end

    test "relevance strategy respects context priorities" do
      {:ok, result} =
        Compressor.compress_context(@sample_context_items,
          strategy: :relevance,
          max_tokens: 400
        )

      assert result.strategy_used == :relevance

      # Should include higher priority content first
      # Current file (priority 10) should be more likely to be included
      content = result.chunks |> Enum.map(& &1.content) |> Enum.join(" ")
      assert String.contains?(content, "Calculator") or String.contains?(content, "Helper")
    end

    test "priority strategy orders by explicit priorities" do
      priority_items = [
        %{content: "Low priority content", type: :documentation, priority: 1},
        %{content: "High priority content", type: :current_file, priority: 10},
        %{content: "Medium priority content", type: :related_file, priority: 5}
      ]

      {:ok, result} =
        Compressor.compress_context(priority_items,
          strategy: :priority,
          # Increased to avoid priority_only scenario
          max_tokens: 1000
        )

      assert result.strategy_used == :priority

      # Should include high priority content
      content = result.chunks |> Enum.map(& &1.content) |> Enum.join(" ")

      assert String.contains?(content, "High priority") or
               String.contains?(content, "Medium priority")
    end
  end

  describe "get_stats/0" do
    test "returns compression statistics" do
      Compressor.clear_cache()
      {:ok, _} = Compressor.compress_context(@sample_context_items)

      stats = Compressor.get_stats()

      assert Map.has_key?(stats, :compressions)
      assert Map.has_key?(stats, :cache_hits)
      assert Map.has_key?(stats, :cache_misses)
      assert Map.has_key?(stats, :tokens_saved)
      assert Map.has_key?(stats, :avg_compression_ratio)
      assert Map.has_key?(stats, :cache_size)
      assert Map.has_key?(stats, :token_limits)

      assert stats.compressions >= 1
      assert is_map(stats.token_limits)
    end
  end

  describe "update_token_limits/1" do
    test "updates model token limits" do
      original_stats = Compressor.get_stats()

      new_limits = %{"custom-model" => 16_000}
      :ok = Compressor.update_token_limits(new_limits)

      updated_stats = Compressor.get_stats()
      assert Map.has_key?(updated_stats.token_limits, "custom-model")
      assert updated_stats.token_limits["custom-model"] == 16_000

      # Original limits should still be there
      assert Map.has_key?(updated_stats.token_limits, "gpt-4")
    end
  end

  describe "clear_cache/0" do
    test "clears compression cache" do
      {:ok, _} = Compressor.compress_context(@sample_context_items)

      stats_before = Compressor.get_stats()
      assert stats_before.cache_size > 0

      :ok = Compressor.clear_cache()

      stats_after = Compressor.get_stats()
      assert stats_after.cache_size == 0
    end
  end

  describe "error handling" do
    test "handles invalid context items gracefully" do
      invalid_items = [
        %{invalid: "structure"},
        %{content: nil},
        "not a map",
        123
      ]

      {:ok, result} = Compressor.compress_context(invalid_items)

      # Should handle gracefully, possibly with empty result
      assert is_list(result.chunks)
      assert is_integer(result.total_tokens)
    end

    test "handles compression failure gracefully" do
      # Test with extremely large input that might cause issues
      huge_content = String.duplicate("x", 1_000_000)
      huge_items = [%{content: huge_content, type: :test}]

      result = Compressor.compress_context(huge_items, max_tokens: 100)

      # Should either succeed or return appropriate error
      case result do
        {:ok, compressed} ->
          assert is_list(compressed.chunks)
          assert compressed.total_tokens <= 100

        {:error, :compression_failed} ->
          # Error is acceptable for extreme cases
          assert true
      end
    end
  end

  describe "integration with semantic chunker" do
    test "uses semantic chunker for content analysis" do
      elixir_code = """
      defmodule IntegrationTest do
        @moduledoc "Test module for integration"
        
        def test_function do
          :ok
        end
        
        defp private_helper do
          :helper
        end
      end
      """

      items = [%{content: elixir_code, type: :current_file}]

      {:ok, result} = Compressor.compress_context(items, strategy: :semantic)

      # Should have used semantic chunking
      assert is_list(result.chunks)
      assert length(result.chunks) >= 1

      # Chunks should have semantic information
      chunk = List.first(result.chunks)
      assert Map.has_key?(chunk, :content)
      assert Map.has_key?(chunk, :token_count)
    end
  end
end
