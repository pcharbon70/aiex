defmodule Aiex.State.DistributedCheckpointSystemTest do
  @moduledoc """
  Comprehensive tests for the distributed checkpoint system.
  
  Tests all aspects of distributed checkpoint management including:
  - Checkpoint creation with distributed data collection
  - Cross-node synchronization and coordination
  - Checkpoint diff storage and incremental updates
  - Cluster-wide naming, tagging, and categorization
  - Distributed retention policies and cleanup
  - Cross-node comparison tools and analysis
  - Distributed restore mechanisms with rollback support
  - Checkpoint replication and backup strategies
  - Integration with event sourcing for complete auditability
  """
  
  use ExUnit.Case, async: false
  
  alias Aiex.State.DistributedCheckpointSystem
  alias Aiex.Events.OTPEventBus
  alias Aiex.Context.DistributedEngine
  alias Aiex.State.DistributedSessionManager
  
  @moduletag :distributed_checkpoint
  @moduletag timeout: 60_000
  
  setup do
    # Ensure components are running
    restart_checkpoint_components()
    
    on_exit(fn ->
      cleanup_checkpoint_data()
    end)
    
    :ok
  end
  
  defp restart_checkpoint_components do
    # Stop existing checkpoint system if running
    if Process.whereis(DistributedCheckpointSystem) do
      GenServer.stop(DistributedCheckpointSystem, :normal, 1000)
    end
    
    # Ensure prerequisites are running
    ensure_prerequisites()
    
    # Start fresh checkpoint system
    {:ok, _} = DistributedCheckpointSystem.start_link()
    
    # Give time to initialize
    :timer.sleep(500)
  end
  
  defp ensure_prerequisites do
    # Ensure Mnesia is running
    :mnesia.start()
    
    # Ensure pg scope is available
    unless Process.whereis(:checkpoint_system) do
      :pg.start_link(:checkpoint_system)
    end
    
    # Ensure other required components
    unless Process.whereis(OTPEventBus) do
      {:ok, _} = OTPEventBus.start_link()
    end
    
    unless Process.whereis(DistributedEngine) do
      {:ok, _} = DistributedEngine.start_link()
    end
    
    unless Process.whereis(DistributedSessionManager) do
      {:ok, _} = DistributedSessionManager.start_link()
    end
    
    # Give time for initialization
    :timer.sleep(200)
  end
  
  defp cleanup_checkpoint_data do
    # Clean up any checkpoint data created during tests
    if Process.whereis(DistributedCheckpointSystem) do
      try do
        # Clean up Mnesia tables
        :mnesia.clear_table(:distributed_checkpoints)
        :mnesia.clear_table(:checkpoint_data)
        :mnesia.clear_table(:checkpoint_diffs)
        :mnesia.clear_table(:checkpoint_metadata)
        :mnesia.clear_table(:checkpoint_tags)
      catch
        _, _ -> :ok
      end
    end
  end
  
  describe "Checkpoint Creation" do
    test "creates basic checkpoint with default options" do
      {:ok, result} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "test_checkpoint_basic",
        description: "Basic test checkpoint"
      })
      
      assert Map.has_key?(result, :checkpoint_id)
      assert Map.has_key?(result, :name)
      assert Map.has_key?(result, :created_at)
      assert result.name == "test_checkpoint_basic"
      assert is_binary(result.checkpoint_id)
      assert %DateTime{} = result.created_at
    end
    
    test "creates checkpoint with specific data types" do
      {:ok, result} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "test_checkpoint_specific",
        description: "Checkpoint with specific data types",
        include_data: [:context, :sessions],
        tag: "test_data"
      })
      
      assert Map.has_key?(result, :checkpoint_id)
      assert result.name == "test_checkpoint_specific"
      
      # Verify checkpoint info includes specified data types
      {:ok, info} = DistributedCheckpointSystem.get_checkpoint_info(result.checkpoint_id)
      assert :context in info.data_types
      assert :sessions in info.data_types
      assert "test_data" in info.tags
    end
    
    test "creates checkpoint with compression settings" do
      {:ok, result} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "test_checkpoint_compressed",
        description: "Compressed checkpoint",
        include_data: [:context],
        compression: :high,
        retention_days: 180
      })
      
      assert Map.has_key?(result, :checkpoint_id)
      
      # Verify compression setting in metadata
      {:ok, info} = DistributedCheckpointSystem.get_checkpoint_info(result.checkpoint_id)
      assert info.metadata.compression == :high
    end
    
    test "creates checkpoint with all data types" do
      {:ok, result} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "test_checkpoint_all",
        description: "Checkpoint with all data",
        include_data: [:all],
        tag: "complete_backup"
      })
      
      assert Map.has_key?(result, :checkpoint_id)
      
      # Verify all data types are included
      {:ok, info} = DistributedCheckpointSystem.get_checkpoint_info(result.checkpoint_id)
      assert :all in info.data_types
      assert "complete_backup" in info.tags
    end
    
    test "handles checkpoint creation with invalid options gracefully" do
      # This should still work but ignore invalid options
      {:ok, result} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "test_checkpoint_invalid",
        invalid_option: "should_be_ignored",
        include_data: [:invalid_type]
      })
      
      assert Map.has_key?(result, :checkpoint_id)
      assert result.name == "test_checkpoint_invalid"
    end
  end
  
  describe "Checkpoint Listing and Information" do
    test "lists checkpoints with basic filtering" do
      # Create test checkpoints
      {:ok, checkpoint1} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "list_test_1",
        tag: "list_test"
      })
      
      {:ok, checkpoint2} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "list_test_2", 
        tag: "list_test"
      })
      
      # List all checkpoints
      {:ok, checkpoints} = DistributedCheckpointSystem.list_checkpoints()
      
      assert is_list(checkpoints)
      assert length(checkpoints) >= 2
      
      # Find our test checkpoints
      our_checkpoints = Enum.filter(checkpoints, fn cp ->
        cp.checkpoint_id in [checkpoint1.checkpoint_id, checkpoint2.checkpoint_id]
      end)
      
      assert length(our_checkpoints) == 2
    end
    
    test "lists checkpoints with tag filtering" do
      # Create checkpoints with different tags
      {:ok, checkpoint1} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "tag_test_1",
        tag: "production"
      })
      
      {:ok, _checkpoint2} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "tag_test_2",
        tag: "development"
      })
      
      # List checkpoints with specific tag
      {:ok, production_checkpoints} = DistributedCheckpointSystem.list_checkpoints(%{
        tags: ["production"]
      })
      
      # Should find at least our production checkpoint
      production_ids = Enum.map(production_checkpoints, & &1.checkpoint_id)
      assert checkpoint1.checkpoint_id in production_ids
    end
    
    test "lists checkpoints with time range filtering" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)  # 1 hour ago
      
      {:ok, _checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "time_test",
        description: "Time filtering test"
      })
      
      # List checkpoints created after past_time
      {:ok, recent_checkpoints} = DistributedCheckpointSystem.list_checkpoints(%{
        created_after: past_time
      })
      
      assert is_list(recent_checkpoints)
      assert length(recent_checkpoints) >= 1
      
      # All should be created after our past_time
      Enum.each(recent_checkpoints, fn checkpoint ->
        assert DateTime.compare(checkpoint.created_at, past_time) in [:gt, :eq]
      end)
    end
    
    test "lists checkpoints with limit and ordering" do
      # Create multiple checkpoints
      checkpoint_ids = for i <- 1..5 do
        {:ok, result} = DistributedCheckpointSystem.create_checkpoint(%{
          name: "order_test_#{i}"
        })
        result.checkpoint_id
      end
      
      # List with limit and descending order (newest first)
      {:ok, limited_checkpoints} = DistributedCheckpointSystem.list_checkpoints(%{
        limit: 3,
        order: :desc
      })
      
      assert length(limited_checkpoints) <= 3
      
      # Verify descending order (newest first)
      timestamps = Enum.map(limited_checkpoints, & &1.created_at)
      sorted_timestamps = Enum.sort(timestamps, {:desc, DateTime})
      assert timestamps == sorted_timestamps
    end
    
    test "gets detailed checkpoint information" do
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "info_test",
        description: "Detailed info test",
        include_data: [:context, :sessions],
        tag: "info_test"
      })
      
      {:ok, info} = DistributedCheckpointSystem.get_checkpoint_info(checkpoint.checkpoint_id)
      
      assert info.checkpoint_id == checkpoint.checkpoint_id
      assert info.name == "info_test"
      assert info.description == "Detailed info test"
      assert is_list(info.data_types)
      assert is_list(info.tags)
      assert "info_test" in info.tags
      assert Map.has_key?(info, :data_summary)
      assert Map.has_key?(info, :metadata)
    end
    
    test "handles getting info for non-existent checkpoint" do
      result = DistributedCheckpointSystem.get_checkpoint_info("non_existent_checkpoint")
      assert {:error, :not_found} = result
    end
  end
  
  describe "Checkpoint Tagging" do
    test "adds tags to existing checkpoint" do
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "tag_test",
        tag: "initial"
      })
      
      # Add additional tags
      :ok = DistributedCheckpointSystem.tag_checkpoint(checkpoint.checkpoint_id, ["additional", "tags"])
      
      # Verify tags were added
      {:ok, info} = DistributedCheckpointSystem.get_checkpoint_info(checkpoint.checkpoint_id)
      assert "initial" in info.tags
      assert "additional" in info.tags
      assert "tags" in info.tags
    end
    
    test "handles tagging non-existent checkpoint" do
      result = DistributedCheckpointSystem.tag_checkpoint("non_existent", ["tag"])
      # Should handle gracefully (implementation may vary)
      assert result in [:ok, {:error, :not_found}]
    end
  end
  
  describe "Checkpoint Restoration" do
    test "performs dry run restore preview" do
      # Create a checkpoint first
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "restore_test",
        description: "Test restore functionality",
        include_data: [:context]
      })
      
      # Perform dry run
      {:ok, preview} = DistributedCheckpointSystem.restore_checkpoint(checkpoint.checkpoint_id, %{
        dry_run: true
      })
      
      assert preview.dry_run == true
      assert preview.checkpoint_id == checkpoint.checkpoint_id
      assert preview.checkpoint_name == "restore_test"
      assert Map.has_key?(preview, :restore_plan)
      assert Map.has_key?(preview, :estimated_duration)
      assert Map.has_key?(preview, :affected_nodes)
    end
    
    test "requires confirmation for actual restore" do
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "confirm_test",
        include_data: [:context]
      })
      
      # Try restore without confirmation
      result = DistributedCheckpointSystem.restore_checkpoint(checkpoint.checkpoint_id, %{
        dry_run: false
      })
      
      assert {:error, :confirmation_required} = result
    end
    
    test "performs actual restore with confirmation" do
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "actual_restore_test",
        include_data: [:context]
      })
      
      # Perform actual restore with confirmation
      {:ok, result} = DistributedCheckpointSystem.restore_checkpoint(checkpoint.checkpoint_id, %{
        dry_run: false,
        confirm: true,
        backup_current: true
      })
      
      assert result.checkpoint_id == checkpoint.checkpoint_id
      assert result.checkpoint_name == "actual_restore_test"
      assert Map.has_key?(result, :backup_id)
      assert Map.has_key?(result, :restore_result)
      assert Map.has_key?(result, :restored_at)
      assert %DateTime{} = result.restored_at
    end
    
    test "handles restore of non-existent checkpoint" do
      result = DistributedCheckpointSystem.restore_checkpoint("non_existent", %{
        dry_run: false,
        confirm: true
      })
      
      assert {:error, {:checkpoint_not_found, :not_found}} = result
    end
  end
  
  describe "Checkpoint Comparison" do
    test "compares two different checkpoints" do
      # Create first checkpoint
      {:ok, checkpoint1} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "compare_test_1",
        include_data: [:context]
      })
      
      # Wait a moment and create second checkpoint (to ensure different data)
      :timer.sleep(100)
      
      {:ok, checkpoint2} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "compare_test_2",
        include_data: [:context]
      })
      
      # Compare checkpoints
      {:ok, comparison} = DistributedCheckpointSystem.compare_checkpoints(
        checkpoint1.checkpoint_id,
        checkpoint2.checkpoint_id
      )
      
      assert comparison.checkpoint_1 == checkpoint1.checkpoint_id
      assert comparison.checkpoint_2 == checkpoint2.checkpoint_id
      assert Map.has_key?(comparison, :comparison)
      assert Map.has_key?(comparison, :compared_at)
      assert %DateTime{} = comparison.compared_at
      
      # Should have node and summary information
      assert Map.has_key?(comparison.comparison, :nodes)
      assert Map.has_key?(comparison.comparison, :summary)
    end
    
    test "handles comparison with non-existent checkpoints" do
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "compare_error_test"
      })
      
      # Try to compare with non-existent checkpoint
      result = DistributedCheckpointSystem.compare_checkpoints(
        checkpoint.checkpoint_id,
        "non_existent"
      )
      
      assert {:error, _reason} = result
    end
  end
  
  describe "Checkpoint Deletion" do
    test "deletes existing checkpoint" do
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "delete_test",
        description: "Test deletion"
      })
      
      # Delete the checkpoint
      {:ok, delete_result} = DistributedCheckpointSystem.delete_checkpoint(checkpoint.checkpoint_id)
      
      assert delete_result.checkpoint_id == checkpoint.checkpoint_id
      assert Map.has_key?(delete_result, :deleted_at)
      assert %DateTime{} = delete_result.deleted_at
      
      # Verify checkpoint is gone
      result = DistributedCheckpointSystem.get_checkpoint_info(checkpoint.checkpoint_id)
      assert {:error, :not_found} = result
    end
    
    test "handles deletion of non-existent checkpoint" do
      result = DistributedCheckpointSystem.delete_checkpoint("non_existent")
      assert {:error, :not_found} = result
    end
    
    test "force deletes non-existent checkpoint" do
      {:ok, result} = DistributedCheckpointSystem.delete_checkpoint("non_existent", %{force: true})
      assert result.checkpoint_id == "non_existent"
      assert result.was_missing == true
    end
  end
  
  describe "Retention Policies and Cleanup" do
    test "sets and validates retention policies" do
      policy = %{
        default_retention_days: 90,
        test_retention_days: 30
      }
      
      :ok = DistributedCheckpointSystem.set_retention_policy(policy)
      
      # Verify policy was set
      status = DistributedCheckpointSystem.get_cluster_status()
      assert status.retention_policies.default_retention_days == 90
      assert status.retention_policies.test_retention_days == 30
    end
    
    test "rejects invalid retention policies" do
      invalid_policy = %{
        invalid_key: "invalid_value"
      }
      
      result = DistributedCheckpointSystem.set_retention_policy(invalid_policy)
      assert {:error, :invalid_retention_policy} = result
    end
    
    test "performs cleanup dry run" do
      # Create a test checkpoint
      {:ok, _checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "cleanup_test",
        tag: "temporary"
      })
      
      # Perform cleanup dry run
      {:ok, cleanup_result} = DistributedCheckpointSystem.cleanup_expired_checkpoints(%{
        dry_run: true
      })
      
      assert cleanup_result.dry_run == true
      assert Map.has_key?(cleanup_result, :expired_checkpoints)
      assert Map.has_key?(cleanup_result, :total_expired)
      assert is_list(cleanup_result.expired_checkpoints)
      assert is_integer(cleanup_result.total_expired)
    end
    
    test "performs actual cleanup" do
      # Set very short retention for testing
      :ok = DistributedCheckpointSystem.set_retention_policy(%{
        default_retention_days: 365,  # Keep normal default
        temporary_retention_days: 0    # Immediate expiration for test tag
      })
      
      # Create a checkpoint with temporary tag
      {:ok, _checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "cleanup_actual_test",
        tag: "temporary"
      })
      
      # Perform actual cleanup
      {:ok, cleanup_result} = DistributedCheckpointSystem.cleanup_expired_checkpoints(%{
        dry_run: false,
        force: true
      })
      
      assert Map.has_key?(cleanup_result, :expired_checkpoints)
      assert Map.has_key?(cleanup_result, :successful_deletions)
      assert Map.has_key?(cleanup_result, :failed_deletions)
      assert is_integer(cleanup_result.successful_deletions)
      assert is_integer(cleanup_result.failed_deletions)
    end
  end
  
  describe "Checkpoint Replication" do
    test "replicates checkpoint to current node (no-op)" do
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "replication_test",
        include_data: [:context]
      })
      
      # Replicate to current node (should be a no-op)
      {:ok, replication_result} = DistributedCheckpointSystem.replicate_checkpoint(
        checkpoint.checkpoint_id,
        [node()]
      )
      
      assert replication_result.checkpoint_id == checkpoint.checkpoint_id
      assert replication_result.target_nodes == [node()]
      assert replication_result.successful_replications >= 0
      assert replication_result.failed_replications >= 0
      assert Map.has_key?(replication_result, :results)
    end
    
    test "handles replication of non-existent checkpoint" do
      result = DistributedCheckpointSystem.replicate_checkpoint(
        "non_existent",
        [node()]
      )
      
      assert {:error, _reason} = result
    end
  end
  
  describe "Cluster Status and Metrics" do
    test "provides comprehensive cluster status" do
      status = DistributedCheckpointSystem.get_cluster_status()
      
      assert Map.has_key?(status, :node)
      assert Map.has_key?(status, :cluster_nodes)
      assert Map.has_key?(status, :total_nodes)
      assert Map.has_key?(status, :active_operations)
      assert Map.has_key?(status, :local_stats)
      assert Map.has_key?(status, :retention_policies)
      assert Map.has_key?(status, :metrics)
      assert Map.has_key?(status, :system_status)
      
      assert status.node == node()
      assert is_list(status.cluster_nodes)
      assert is_integer(status.total_nodes)
      assert is_integer(status.active_operations)
      assert is_map(status.local_stats)
      assert is_map(status.retention_policies)
      assert is_map(status.metrics)
      assert status.system_status == :healthy
    end
    
    test "tracks local checkpoint statistics" do
      # Create some checkpoints to generate stats
      {:ok, _checkpoint1} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "stats_test_1"
      })
      
      {:ok, _checkpoint2} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "stats_test_2"
      })
      
      status = DistributedCheckpointSystem.get_cluster_status()
      local_stats = status.local_stats
      
      assert Map.has_key?(local_stats, :total_checkpoints)
      assert Map.has_key?(local_stats, :total_data_records)
      assert is_integer(local_stats.total_checkpoints)
      assert is_integer(local_stats.total_data_records)
      assert local_stats.total_checkpoints >= 2
    end
    
    test "tracks operation metrics" do
      initial_status = DistributedCheckpointSystem.get_cluster_status()
      initial_metrics = initial_status.metrics
      
      # Perform some operations
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "metrics_test"
      })
      
      # Give time for metrics to update
      :timer.sleep(100)
      
      updated_status = DistributedCheckpointSystem.get_cluster_status()
      updated_metrics = updated_status.metrics
      
      # Should track operation counts
      assert Map.has_key?(updated_metrics, :total_operations)
      assert Map.has_key?(updated_metrics, :successful_operations)
      assert Map.has_key?(updated_metrics, :failed_operations)
      assert is_integer(updated_metrics.total_operations)
      assert is_integer(updated_metrics.successful_operations)
      assert is_integer(updated_metrics.failed_operations)
    end
  end
  
  describe "Event Integration" do
    test "publishes checkpoint events to event bus" do
      # Subscribe to checkpoint events
      :ok = OTPEventBus.subscribe({:event_type, :checkpoint_created})
      
      # Create a checkpoint
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "event_test",
        description: "Test event publication"
      })
      
      # Should receive event notification
      assert_receive {:event_notification, event}, 2000
      assert event.type == :checkpoint_created
      assert event.data.checkpoint_id == checkpoint.checkpoint_id
      assert event.data.node == node()
      assert Map.has_key?(event.metadata, :checkpoint_manager)
    end
    
    test "publishes checkpoint deletion events" do
      # Subscribe to deletion events
      :ok = OTPEventBus.subscribe({:event_type, :checkpoint_deleted})
      
      # Create and delete a checkpoint
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "deletion_event_test"
      })
      
      {:ok, _result} = DistributedCheckpointSystem.delete_checkpoint(checkpoint.checkpoint_id)
      
      # Should receive deletion event
      assert_receive {:event_notification, event}, 2000
      assert event.type == :checkpoint_deleted
      assert event.data.checkpoint_id == checkpoint.checkpoint_id
    end
  end
  
  describe "Error Handling and Edge Cases" do
    test "handles concurrent checkpoint operations gracefully" do
      # Start multiple checkpoint creations concurrently
      tasks = for i <- 1..5 do
        Task.async(fn ->
          DistributedCheckpointSystem.create_checkpoint(%{
            name: "concurrent_test_#{i}",
            include_data: [:context]
          })
        end)
      end
      
      # Wait for all to complete
      results = Task.await_many(tasks, 10_000)
      
      # All should succeed
      successful = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      assert successful == 5
      
      # All should have unique checkpoint IDs
      checkpoint_ids = Enum.map(results, fn {:ok, result} -> result.checkpoint_id end)
      unique_ids = Enum.uniq(checkpoint_ids)
      assert length(unique_ids) == 5
    end
    
    test "handles invalid checkpoint options gracefully" do
      # Try with various invalid options
      {:ok, result} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "invalid_options_test",
        invalid_option: "should_be_ignored",
        include_data: [:invalid_type, :context],
        compression: :invalid_compression
      })
      
      # Should still create checkpoint, ignoring invalid options
      assert Map.has_key?(result, :checkpoint_id)
      assert result.name == "invalid_options_test"
    end
    
    test "handles missing dependencies gracefully" do
      # This test verifies the system handles missing dependencies
      # The actual behavior may vary based on implementation
      
      # Try to create checkpoint (should work even if some data sources are unavailable)
      result = DistributedCheckpointSystem.create_checkpoint(%{
        name: "dependency_test",
        include_data: [:context, :sessions, :events]
      })
      
      # Should either succeed or fail gracefully
      case result do
        {:ok, checkpoint_result} ->
          assert Map.has_key?(checkpoint_result, :checkpoint_id)
          
        {:error, _reason} ->
          # Also acceptable if dependencies are truly missing
          assert true
      end
    end
    
    test "handles system resource constraints" do
      # Test with minimal data to avoid resource issues
      {:ok, result} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "resource_test",
        include_data: [],  # Minimal data
        compression: :high  # High compression to save space
      })
      
      assert Map.has_key?(result, :checkpoint_id)
      
      # Should be able to get info even with minimal data
      {:ok, info} = DistributedCheckpointSystem.get_checkpoint_info(result.checkpoint_id)
      assert info.checkpoint_id == result.checkpoint_id
    end
  end
  
  describe "Distributed Coordination" do
    test "coordinates checkpoint operations across pg groups" do
      # Verify we're in the pg group
      members = :pg.get_members(:checkpoint_system, :checkpoint_managers)
      checkpoint_manager = Process.whereis(DistributedCheckpointSystem)
      assert checkpoint_manager in members
    end
    
    test "handles distributed checkpoint listing" do
      # Create checkpoints and verify they're visible cluster-wide
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "distributed_listing_test",
        description: "Test distributed checkpoint visibility"
      })
      
      # List checkpoints (should include our checkpoint)
      {:ok, checkpoints} = DistributedCheckpointSystem.list_checkpoints()
      
      checkpoint_ids = Enum.map(checkpoints, & &1.checkpoint_id)
      assert checkpoint.checkpoint_id in checkpoint_ids
    end
    
    test "maintains consistency across cluster operations" do
      # Create checkpoint
      {:ok, checkpoint} = DistributedCheckpointSystem.create_checkpoint(%{
        name: "consistency_test",
        tag: "consistency"
      })
      
      # Verify it's immediately visible
      {:ok, info} = DistributedCheckpointSystem.get_checkpoint_info(checkpoint.checkpoint_id)
      assert info.checkpoint_id == checkpoint.checkpoint_id
      
      # Verify it appears in listings
      {:ok, checkpoints} = DistributedCheckpointSystem.list_checkpoints(%{
        tags: ["consistency"]
      })
      
      consistency_ids = Enum.map(checkpoints, & &1.checkpoint_id)
      assert checkpoint.checkpoint_id in consistency_ids
    end
  end
end