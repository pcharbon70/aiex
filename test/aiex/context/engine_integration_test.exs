defmodule Aiex.Context.EngineIntegrationTest do
  use ExUnit.Case, async: true
  
  setup do
    # Start a fresh engine for each test with unique DETS file
    unique_id = System.unique_integer([:positive])
    opts = [
      data_dir: System.tmp_dir!(),
      dets_filename: "test_context_#{unique_id}.dets",
      name: nil  # No name to avoid conflicts
    ]
    
    {:ok, pid} = GenServer.start_link(Aiex.Context.Engine, opts)
    
    on_exit(fn ->
      # Clean up
      if Process.alive?(pid), do: GenServer.stop(pid)
      
      # Clean up DETS file
      dets_path = Path.join(System.tmp_dir!(), "test_context_#{unique_id}.dets")
      File.rm(dets_path)
    end)
    
    {:ok, engine: pid}
  end
  
  describe "basic operations" do
    test "put and get", %{engine: engine} do
      assert :ok = TestEngine.put(engine, "key1", "value1")
      assert {:ok, "value1"} = TestEngine.get(engine, "key1")
    end
    
    test "put with metadata", %{engine: engine} do
      metadata = %{file_path: "/lib/test.ex", language: "elixir"}
      assert :ok = TestEngine.put(engine, "key2", "value2", metadata)
      
      # The metadata should be merged with system metadata
      assert {:ok, "value2"} = TestEngine.get(engine, "key2")
    end
    
    test "get non-existent key", %{engine: engine} do
      assert {:error, :not_found} = TestEngine.get(engine, "non_existent")
    end
    
    test "delete existing key", %{engine: engine} do
      TestEngine.put(engine, "key3", "value3")
      assert :ok = TestEngine.delete(engine, "key3")
      assert {:error, :not_found} = TestEngine.get(engine, "key3")
    end
    
    test "delete non-existent key", %{engine: engine} do
      assert {:error, :not_found} = TestEngine.delete(engine, "non_existent")
    end
    
    test "list keys", %{engine: engine} do
      TestEngine.put(engine, "key1", "value1")
      TestEngine.put(engine, "key2", "value2")
      TestEngine.put(engine, "key3", "value3")
      
      keys = TestEngine.list_keys(engine)
      assert length(keys) == 3
      assert "key1" in keys
      assert "key2" in keys
      assert "key3" in keys
    end
    
    test "clear all entries", %{engine: engine} do
      TestEngine.put(engine, "key1", "value1")
      TestEngine.put(engine, "key2", "value2")
      
      assert :ok = TestEngine.clear(engine)
      assert [] = TestEngine.list_keys(engine)
    end
  end
  
  describe "stats tracking" do
    test "tracks entry counts and sizes", %{engine: engine} do
      TestEngine.put(engine, "key1", "short value")
      TestEngine.put(engine, "key2", String.duplicate("long value", 100))
      
      stats = TestEngine.stats(engine)
      
      assert stats.total_entries == 2
      assert stats.hot_tier.entries == 2
      assert stats.hot_tier.size > 0
      assert stats.warm_tier.entries == 0
      assert stats.cold_tier.entries == 0
    end
    
    test "updates stats on deletion", %{engine: engine} do
      TestEngine.put(engine, "key1", "value1")
      initial_stats = TestEngine.stats(engine)
      
      TestEngine.delete(engine, "key1")
      final_stats = TestEngine.stats(engine)
      
      assert final_stats.total_entries == initial_stats.total_entries - 1
      assert final_stats.hot_tier.entries == initial_stats.hot_tier.entries - 1
    end
  end
  
  describe "memory tier management" do
    test "entries start in hot tier", %{engine: engine} do
      TestEngine.put(engine, "key1", "value1")
      stats = TestEngine.stats(engine)
      
      assert stats.hot_tier.entries == 1
      assert stats.warm_tier.entries == 0
      assert stats.cold_tier.entries == 0
    end
    
    test "tracks access patterns", %{engine: engine} do
      TestEngine.put(engine, "key1", "value1")
      
      # Access the key multiple times
      for _ <- 1..5 do
        TestEngine.get(engine, "key1")
      end
      
      # The entry should still be in hot tier with increased access count
      stats = TestEngine.stats(engine)
      assert stats.hot_tier.entries == 1
    end
  end
  
  describe "edge cases" do
    test "handles large values", %{engine: engine} do
      large_value = String.duplicate("x", 10_000) # 10KB string
      assert :ok = TestEngine.put(engine, "large_key", large_value)
      assert {:ok, ^large_value} = TestEngine.get(engine, "large_key")
    end
    
    test "handles special characters in keys", %{engine: engine} do
      special_keys = [
        "key with spaces",
        "key/with/slashes",
        "key:with:colons",
        "key|with|pipes",
        "unicode_key_🚀"
      ]
      
      for key <- special_keys do
        assert :ok = TestEngine.put(engine, key, "value")
        assert {:ok, "value"} = TestEngine.get(engine, key)
      end
    end
    
    test "handles various value types", %{engine: engine} do
      values = [
        123,
        3.14,
        :atom,
        {:tuple, "value"},
        %{map: "value"},
        ["list", "of", "values"]
      ]
      
      for {value, i} <- Enum.with_index(values) do
        key = "key_#{i}"
        assert :ok = TestEngine.put(engine, key, value)
        assert {:ok, ^value} = TestEngine.get(engine, key)
      end
    end
  end
end