defmodule Aiex.Context.EngineTest do
  use ExUnit.Case, async: false
  alias Aiex.Context.Engine
  
  setup do
    # Start a fresh engine for each test with unique DETS file
    unique_id = System.unique_integer([:positive])
    opts = [
      data_dir: System.tmp_dir!(),
      dets_filename: "test_context_#{unique_id}.dets",
      name: :"test_engine_#{unique_id}"
    ]
    
    {:ok, pid} = Engine.start_link(opts)
    
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
      assert :ok = GenServer.call(engine, {:put, "key1", "value1", %{}})
      assert {:ok, "value1"} = GenServer.call(engine, {:get, "key1"})
    end
    
    test "put with metadata" do
      metadata = %{file_path: "/lib/test.ex", language: "elixir"}
      assert :ok = Engine.put("key2", "value2", metadata)
      
      # The metadata should be merged with system metadata
      assert {:ok, "value2"} = Engine.get("key2")
    end
    
    test "get non-existent key" do
      assert {:error, :not_found} = Engine.get("non_existent")
    end
    
    test "delete existing key" do
      Engine.put("key3", "value3")
      assert :ok = Engine.delete("key3")
      assert {:error, :not_found} = Engine.get("key3")
    end
    
    test "delete non-existent key" do
      assert {:error, :not_found} = Engine.delete("non_existent")
    end
    
    test "list keys" do
      Engine.put("key1", "value1")
      Engine.put("key2", "value2")
      Engine.put("key3", "value3")
      
      keys = Engine.list_keys()
      assert length(keys) == 3
      assert "key1" in keys
      assert "key2" in keys
      assert "key3" in keys
    end
    
    test "clear all entries" do
      Engine.put("key1", "value1")
      Engine.put("key2", "value2")
      
      assert :ok = Engine.clear()
      assert [] = Engine.list_keys()
    end
  end
  
  describe "stats tracking" do
    test "tracks entry counts and sizes" do
      Engine.put("key1", "short value")
      Engine.put("key2", String.duplicate("long value", 100))
      
      stats = Engine.stats()
      
      assert stats.total_entries == 2
      assert stats.hot_tier.entries == 2
      assert stats.hot_tier.size > 0
      assert stats.warm_tier.entries == 0
      assert stats.cold_tier.entries == 0
    end
    
    test "updates stats on deletion" do
      Engine.put("key1", "value1")
      initial_stats = Engine.stats()
      
      Engine.delete("key1")
      final_stats = Engine.stats()
      
      assert final_stats.total_entries == initial_stats.total_entries - 1
      assert final_stats.hot_tier.entries == initial_stats.hot_tier.entries - 1
    end
  end
  
  describe "concurrent access" do
    test "handles concurrent writes" do
      tasks = for i <- 1..100 do
        Task.async(fn ->
          Engine.put("key#{i}", "value#{i}")
        end)
      end
      
      Enum.each(tasks, &Task.await/1)
      
      # Verify all entries were written
      assert length(Engine.list_keys()) == 100
    end
    
    test "handles concurrent reads and writes" do
      # Pre-populate some data
      for i <- 1..50 do
        Engine.put("existing#{i}", "value#{i}")
      end
      
      # Mix of reads and writes
      tasks = for i <- 1..100 do
        Task.async(fn ->
          if rem(i, 2) == 0 do
            Engine.put("new#{i}", "value#{i}")
          else
            Engine.get("existing#{rem(i, 50) + 1}")
          end
        end)
      end
      
      results = Enum.map(tasks, &Task.await/1)
      
      # Verify no crashes and reasonable results
      assert Enum.all?(results, fn
        :ok -> true
        {:ok, _} -> true
        {:error, :not_found} -> true
        _ -> false
      end)
    end
  end
  
  describe "memory tier management" do
    test "entries start in hot tier" do
      Engine.put("key1", "value1")
      stats = Engine.stats()
      
      assert stats.hot_tier.entries == 1
      assert stats.warm_tier.entries == 0
      assert stats.cold_tier.entries == 0
    end
    
    test "tracks access patterns" do
      Engine.put("key1", "value1")
      
      # Access the key multiple times
      for _ <- 1..5 do
        Engine.get("key1")
      end
      
      # The entry should still be in hot tier with increased access count
      stats = Engine.stats()
      assert stats.hot_tier.entries == 1
    end
  end
  
  describe "persistence" do
    test "persists data across restarts" do
      temp_dir = System.tmp_dir!()
      dets_filename = "persistence_test_#{System.unique_integer([:positive])}.dets"
      
      # Start engine and add data (without name to avoid conflicts)
      {:ok, pid1} = GenServer.start_link(Aiex.Context.Engine, [
        data_dir: temp_dir, 
        dets_filename: dets_filename,
        name: nil
      ])
      GenServer.call(pid1, {:put, "persistent_key", "persistent_value", %{}})
      GenServer.stop(pid1)
      
      # Start new engine with same data directory and filename
      {:ok, pid2} = GenServer.start_link(Aiex.Context.Engine, [
        data_dir: temp_dir, 
        dets_filename: dets_filename,
        name: nil
      ])
      
      # Data should be restored from DETS
      assert {:ok, "persistent_value"} = GenServer.call(pid2, {:get, "persistent_key"})
      
      GenServer.stop(pid2)
      
      # Clean up
      File.rm(Path.join(temp_dir, dets_filename))
    end
  end
  
  describe "edge cases" do
    test "handles large values" do
      large_value = String.duplicate("x", 1_000_000) # 1MB string
      assert :ok = Engine.put("large_key", large_value)
      assert {:ok, ^large_value} = Engine.get("large_key")
    end
    
    test "handles special characters in keys" do
      special_keys = [
        "key with spaces",
        "key/with/slashes",
        "key:with:colons",
        "key|with|pipes",
        "unicode_key_🚀"
      ]
      
      for key <- special_keys do
        assert :ok = Engine.put(key, "value")
        assert {:ok, "value"} = Engine.get(key)
      end
    end
    
    test "handles various value types" do
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
        assert :ok = Engine.put(key, value)
        assert {:ok, ^value} = Engine.get(key)
      end
    end
  end
end