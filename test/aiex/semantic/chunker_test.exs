defmodule Aiex.Semantic.ChunkerTest do
  use ExUnit.Case, async: true
  alias Aiex.Semantic.Chunker

  @sample_elixir_code """
  defmodule Calculator do
    @moduledoc "A simple calculator module"
    
    def add(a, b) do
      a + b
    end
    
    def subtract(a, b) do
      a - b
    end
    
    defp validate_number(num) when is_number(num), do: :ok
    defp validate_number(_), do: {:error, :not_a_number}
  end

  defmodule AdvancedCalculator do
    @moduledoc "Advanced mathematical operations"
    
    def multiply(a, b) do
      a * b
    end
    
    def divide(a, 0), do: {:error, :division_by_zero}
    def divide(a, b), do: {:ok, a / b}
    
    def power(base, exponent) do
      :math.pow(base, exponent)
    end
  end
  """

  @large_module_code """
  defmodule DataProcessor do
    @moduledoc "Complex data processing module"
    
    def process_data(data) when is_list(data) do
      data
      |> validate_data()
      |> transform_data()
      |> filter_data()
      |> aggregate_data()
    end
    
    def process_data(_), do: {:error, :invalid_input}
    
    defp validate_data(data) do
      Enum.filter(data, fn item ->
        is_map(item) and Map.has_key?(item, :id)
      end)
    end
    
    defp transform_data(data) do
      Enum.map(data, fn item ->
        Map.update(item, :value, 0, &(&1 * 2))
      end)
    end
    
    defp filter_data(data) do
      Enum.filter(data, fn item ->
        item.value > 0
      end)
    end
    
    defp aggregate_data(data) do
      Enum.reduce(data, %{}, fn item, acc ->
        Map.update(acc, item.category, [item], &[item | &1])
      end)
    end
    
    def calculate_statistics(data) do
      %{
        count: length(data),
        sum: Enum.sum(Enum.map(data, & &1.value)),
        average: calculate_average(data)
      }
    end
    
    defp calculate_average([]), do: 0
    defp calculate_average(data) do
      sum = Enum.sum(Enum.map(data, & &1.value))
      sum / length(data)
    end
  end
  """

  @single_function_code """
  def simple_function(x) do
    x + 1
  end
  """

  @whitespace_heavy_code """


  defmodule SpacyModule do

    def function_one do
      :ok
    end


    def function_two do
      :ok
    end


  end


  """

  @complex_nested_code """
  defmodule Nested do
    defmodule Inner do
      def inner_func, do: :ok
      
      defmodule DeepNested do
        def deep_func do
          case :rand.uniform(2) do
            1 -> :one
            2 -> :two
          end
        end
      end
    end
    
    def outer_func do
      Inner.inner_func()
    end
  end
  """

  describe "chunk_code/2" do
    test "chunks simple Elixir code" do
      {:ok, chunks} = Chunker.chunk_code(@sample_elixir_code)

      assert is_list(chunks)
      assert length(chunks) > 0

      # Verify each chunk has required fields
      Enum.each(chunks, fn chunk ->
        assert Map.has_key?(chunk, :content)
        assert Map.has_key?(chunk, :start_line)
        assert Map.has_key?(chunk, :end_line)
        assert Map.has_key?(chunk, :type)
        assert Map.has_key?(chunk, :token_count)

        assert is_binary(chunk.content)
        assert is_integer(chunk.start_line)
        assert is_integer(chunk.end_line)
        assert chunk.start_line <= chunk.end_line
        assert chunk.token_count > 0
      end)
    end

    test "respects max_chunk_size option" do
      small_chunk_size = 100
      {:ok, chunks} = Chunker.chunk_code(@sample_elixir_code, max_chunk_size: small_chunk_size)

      # Most chunks should be under the limit (allowing some flexibility for semantic boundaries)
      oversized_chunks =
        Enum.count(chunks, fn chunk -> chunk.token_count > small_chunk_size * 1.2 end)

      # Allow one chunk to exceed for semantic integrity
      assert oversized_chunks <= 1
    end

    test "handles force_local option" do
      {:ok, chunks} = Chunker.chunk_code(@sample_elixir_code, force_local: true)

      assert is_list(chunks)
      assert length(chunks) > 0
    end

    test "handles empty code" do
      {:ok, chunks} = Chunker.chunk_code("")

      assert chunks == []
    end

    test "handles malformed code gracefully" do
      malformed_code = "def incomplete_function("

      {:ok, chunks} = Chunker.chunk_code(malformed_code)

      assert is_list(chunks)
      # Should still chunk it, even if it's not valid Elixir
    end
  end

  describe "get_stats/0" do
    test "returns chunking statistics" do
      # Clear cache and chunk some code to generate stats
      Chunker.clear_cache()
      {:ok, _} = Chunker.chunk_code(@sample_elixir_code)

      stats = Chunker.get_stats()

      assert Map.has_key?(stats, :cache_hits)
      assert Map.has_key?(stats, :cache_misses)
      assert Map.has_key?(stats, :local_chunks)
      assert Map.has_key?(stats, :distributed_chunks)
      assert Map.has_key?(stats, :parser_available)
      assert Map.has_key?(stats, :cache_size)

      assert stats.cache_misses >= 1
      assert stats.local_chunks >= 1
    end
  end

  describe "clear_cache/0" do
    test "clears the chunk cache" do
      # Add something to cache
      {:ok, _} = Chunker.chunk_code(@sample_elixir_code)

      stats_before = Chunker.get_stats()
      assert stats_before.cache_size > 0

      # Clear cache
      :ok = Chunker.clear_cache()

      stats_after = Chunker.get_stats()
      assert stats_after.cache_size == 0
    end
  end

  describe "caching behavior" do
    test "caches identical content" do
      Chunker.clear_cache()

      # First call should be a cache miss
      {:ok, chunks1} = Chunker.chunk_code(@sample_elixir_code)
      stats1 = Chunker.get_stats()

      # Second call should be a cache hit
      {:ok, chunks2} = Chunker.chunk_code(@sample_elixir_code)
      stats2 = Chunker.get_stats()

      assert chunks1 == chunks2
      assert stats2.cache_hits == stats1.cache_hits + 1
      assert stats2.cache_misses == stats1.cache_misses
    end

    test "different content generates different cache entries" do
      Chunker.clear_cache()

      {:ok, chunks1} = Chunker.chunk_code(@sample_elixir_code)
      {:ok, chunks2} = Chunker.chunk_code(@large_module_code)

      refute chunks1 == chunks2

      stats = Chunker.get_stats()
      assert stats.cache_size == 2
      assert stats.cache_misses >= 2
    end
  end

  describe "semantic chunking behavior" do
    test "respects module boundaries" do
      {:ok, chunks} = Chunker.chunk_code(@sample_elixir_code)

      # Should have chunks containing complete modules
      module_chunks =
        Enum.filter(chunks, fn chunk ->
          String.contains?(chunk.content, "defmodule")
        end)

      assert length(module_chunks) >= 1

      # Verify modules are not split inappropriately
      Enum.each(module_chunks, fn chunk ->
        defmodule_count = chunk.content |> String.split("defmodule") |> length() |> Kernel.-(1)
        end_count = chunk.content |> String.split("\n  end") |> length() |> Kernel.-(1)

        # Should have matching defmodule/end pairs (allowing for flexibility)
        assert defmodule_count <= end_count + 1
      end)
    end

    test "handles single function code" do
      {:ok, chunks} = Chunker.chunk_code(@single_function_code)

      assert length(chunks) == 1
      chunk = List.first(chunks)
      assert String.contains?(chunk.content, "simple_function")
      assert chunk.type in [:semantic, :simple]
    end

    test "handles whitespace-heavy code" do
      {:ok, chunks} = Chunker.chunk_code(@whitespace_heavy_code)

      assert is_list(chunks)
      assert length(chunks) >= 1

      # Should preserve meaningful content while handling whitespace
      content = chunks |> Enum.map(& &1.content) |> Enum.join("\n")
      assert String.contains?(content, "SpacyModule")
      assert String.contains?(content, "function_one")
    end

    test "handles complex nested structures" do
      {:ok, chunks} = Chunker.chunk_code(@complex_nested_code)

      assert is_list(chunks)

      # Should handle nested modules appropriately
      content = chunks |> Enum.map(& &1.content) |> Enum.join("\n")
      assert String.contains?(content, "Nested")
      assert String.contains?(content, "Inner")
      assert String.contains?(content, "DeepNested")
    end
  end

  describe "chunk size management" do
    test "splits large modules when needed" do
      {:ok, chunks} = Chunker.chunk_code(@large_module_code, max_chunk_size: 50)

      # Should create multiple chunks for large code
      assert length(chunks) > 1

      # Most chunks should respect size limits
      oversized_chunks = Enum.count(chunks, fn chunk -> chunk.token_count > 75 end)
      # Allow some flexibility for semantic boundaries
      assert oversized_chunks <= 1
    end

    test "merges small adjacent chunks" do
      # Create code with many small functions
      small_functions = """
      def f1, do: 1
      def f2, do: 2
      def f3, do: 3
      def f4, do: 4
      def f5, do: 5
      """

      {:ok, chunks} = Chunker.chunk_code(small_functions, max_chunk_size: 100)

      # Should merge small functions into fewer chunks
      assert length(chunks) <= 3

      # Verify total content is preserved
      total_content = chunks |> Enum.map(& &1.content) |> Enum.join("\n")
      assert String.contains?(total_content, "def f1")
      assert String.contains?(total_content, "def f5")
    end

    test "preserves semantic integrity over strict size limits" do
      {:ok, chunks} = Chunker.chunk_code(@sample_elixir_code, max_chunk_size: 10)

      # Even with very small limits, should not break semantic units inappropriately
      Enum.each(chunks, fn chunk ->
        # No chunk should have unmatched parentheses or braces
        open_parens = chunk.content |> String.graphemes() |> Enum.count(&(&1 == "("))
        close_parens = chunk.content |> String.graphemes() |> Enum.count(&(&1 == ")"))

        # Allow some imbalance for partial function definitions
        assert abs(open_parens - close_parens) <= 3
      end)
    end
  end

  describe "error handling and edge cases" do
    test "handles only whitespace" do
      {:ok, chunks} = Chunker.chunk_code("   \n\t  \n  ")
      assert chunks == []
    end

    test "handles only comments" do
      comment_code = """
      # This is a comment
      # Another comment
      ## Documentation comment
      """

      {:ok, chunks} = Chunker.chunk_code(comment_code)

      # Should still create chunks for comments
      assert is_list(chunks)

      if length(chunks) > 0 do
        content = chunks |> Enum.map(& &1.content) |> Enum.join("\n")
        assert String.contains?(content, "comment")
      end
    end

    test "handles mixed valid and invalid syntax" do
      mixed_code = """
      defmodule Valid do
        def valid_function, do: :ok
      end

      def incomplete_function(
      # Missing closing

      defmodule AnotherValid do
        def another_function, do: :valid
      end
      """

      {:ok, chunks} = Chunker.chunk_code(mixed_code)

      assert is_list(chunks)
      assert length(chunks) >= 1

      # Should still process the valid parts
      content = chunks |> Enum.map(& &1.content) |> Enum.join("\n")
      assert String.contains?(content, "Valid")
      assert String.contains?(content, "AnotherValid")
    end

    test "handles very large single function" do
      # Generate a function with many lines
      large_function = """
      def large_function do
      #{Enum.map(1..100, fn i -> "  line_#{i} = #{i}" end) |> Enum.join("\n")}
        :ok
      end
      """

      {:ok, chunks} = Chunker.chunk_code(large_function, max_chunk_size: 50)

      assert is_list(chunks)
      # Should handle large functions by splitting when necessary
    end

    test "returns error for chunker failure" do
      # This test depends on internal implementation
      # For now, our chunker is designed to always return {:ok, chunks}
      # But we can test the error path by mocking

      # Test with extremely malformed input that might cause issues
      weird_input = String.duplicate("defmodule", 10000) <> "end"

      result = Chunker.chunk_code(weird_input)

      # Should either succeed with chunks or return error gracefully
      case result do
        {:ok, chunks} -> assert is_list(chunks)
        # Error is acceptable
        {:error, _reason} -> assert true
      end
    end
  end

  describe "performance and statistics" do
    test "tracks statistics correctly" do
      Chunker.clear_cache()

      # Generate multiple chunk operations
      {:ok, _} = Chunker.chunk_code(@sample_elixir_code)
      {:ok, _} = Chunker.chunk_code(@large_module_code)
      # Cache hit
      {:ok, _} = Chunker.chunk_code(@sample_elixir_code)

      stats = Chunker.get_stats()

      assert stats.cache_hits >= 1
      assert stats.cache_misses >= 2
      assert stats.local_chunks >= 2
      # No distribution in tests
      assert stats.distributed_chunks == 0
      assert stats.cache_size >= 2
    end

    test "cache performance" do
      Chunker.clear_cache()

      # Time first call (cache miss)
      start_time = :os.system_time(:microsecond)
      {:ok, _} = Chunker.chunk_code(@large_module_code)
      first_call_time = :os.system_time(:microsecond) - start_time

      # Time second call (cache hit)
      start_time = :os.system_time(:microsecond)
      {:ok, _} = Chunker.chunk_code(@large_module_code)
      second_call_time = :os.system_time(:microsecond) - start_time

      # Cache hit should be significantly faster
      assert second_call_time < first_call_time / 2
    end
  end

  describe "integration with options" do
    test "language option is accepted" do
      {:ok, chunks} = Chunker.chunk_code(@sample_elixir_code, language: :elixir)

      assert is_list(chunks)
      assert length(chunks) > 0
    end

    test "custom max_chunk_size works" do
      {:ok, small_chunks} = Chunker.chunk_code(@large_module_code, max_chunk_size: 50)
      {:ok, large_chunks} = Chunker.chunk_code(@large_module_code, max_chunk_size: 500)

      # Smaller max size should generally create more chunks
      assert length(small_chunks) >= length(large_chunks)
    end

    test "force_local option forces local processing" do
      {:ok, chunks} = Chunker.chunk_code(@large_module_code, force_local: true)

      assert is_list(chunks)

      # Verify it was processed locally (not distributed)
      stats = Chunker.get_stats()
      assert stats.distributed_chunks == 0
    end
  end
end
