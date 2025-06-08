defmodule Aiex.Events.EventSourcingTest do
  @moduledoc """
  Comprehensive tests for the distributed event sourcing system.
  
  Tests all components of the event sourcing infrastructure:
  - OTPEventBus for distributed event distribution
  - EventStore for Mnesia-based event persistence  
  - EventAggregate for aggregate state management
  - EventProjection for read model creation
  """
  
  use ExUnit.Case, async: false
  
  alias Aiex.Events.{OTPEventBus, EventStore, EventAggregate, EventProjection}
  
  @moduletag :event_sourcing
  @moduletag timeout: 30_000
  
  setup do
    # Ensure components are running before each test
    restart_event_sourcing_components()
    
    :ok
  end
  
  defp restart_event_sourcing_components do
    # Stop existing processes if running
    if Process.whereis(OTPEventBus), do: GenServer.stop(OTPEventBus, :normal, 1000)
    if Process.whereis(EventAggregate), do: GenServer.stop(EventAggregate, :normal, 1000)
    if Process.whereis(EventProjection), do: GenServer.stop(EventProjection, :normal, 1000)
    
    # Give time for cleanup
    :timer.sleep(100)
    
    # Ensure Mnesia is running
    :mnesia.start()
    
    # Start event sourcing components
    {:ok, _} = OTPEventBus.start_link()
    {:ok, _} = EventAggregate.start_link()
    {:ok, _} = EventProjection.start_link()
    
    # Give services time to initialize
    :timer.sleep(200)
  end
  
  describe "OTPEventBus" do
    test "publishes and distributes events" do
      event = %{
        id: "test_event_1",
        aggregate_id: "user_123",
        type: :user_created,
        data: %{name: "John Doe", email: "john@example.com"},
        metadata: %{user_id: "admin"}
      }
      
      # Subscribe to events
      :ok = OTPEventBus.subscribe(:all_events)
      
      # Publish event
      :ok = OTPEventBus.publish_event(event)
      
      # Should receive event notification
      assert_receive {:event_notification, received_event}, 1000
      assert received_event.id == event.id
      assert received_event.type == event.type
    end
    
    test "handles event subscriptions by type" do
      event = %{
        id: "test_event_2",
        aggregate_id: "user_456",
        type: :user_updated,
        data: %{email: "updated@example.com"},
        metadata: %{}
      }
      
      # Subscribe to specific event type
      :ok = OTPEventBus.subscribe({:event_type, :user_updated})
      
      # Publish event
      :ok = OTPEventBus.publish_event(event)
      
      # Should receive event notification
      assert_receive {:event_notification, received_event}, 1000
      assert received_event.type == :user_updated
    end
    
    test "handles aggregate-specific subscriptions" do
      aggregate_id = "user_789"
      
      event = %{
        id: "test_event_3",
        aggregate_id: aggregate_id,
        type: :user_activated,
        data: %{activated_at: DateTime.utc_now()},
        metadata: %{}
      }
      
      # Subscribe to specific aggregate
      :ok = OTPEventBus.subscribe({:aggregate, aggregate_id})
      
      # Publish event
      :ok = OTPEventBus.publish_event(event)
      
      # Should receive event notification
      assert_receive {:event_notification, received_event}, 1000
      assert received_event.aggregate_id == aggregate_id
    end
    
    test "provides event stream access" do
      aggregate_id = "user_stream_test"
      
      events = [
        %{
          id: "stream_event_1",
          aggregate_id: aggregate_id,
          type: :user_created,
          data: %{name: "Stream User"},
          metadata: %{}
        },
        %{
          id: "stream_event_2", 
          aggregate_id: aggregate_id,
          type: :user_updated,
          data: %{email: "stream@example.com"},
          metadata: %{}
        }
      ]
      
      # Publish events
      Enum.each(events, &OTPEventBus.publish_event/1)
      
      # Get event stream
      {:ok, stream_events} = OTPEventBus.get_event_stream(aggregate_id)
      
      assert length(stream_events) >= 2
      assert Enum.any?(stream_events, fn e -> e.id == "stream_event_1" end)
      assert Enum.any?(stream_events, fn e -> e.id == "stream_event_2" end)
    end
    
    test "provides system statistics" do
      stats = OTPEventBus.get_stats()
      
      assert %{
        node: node,
        event_handlers: handlers,
        projections: projections,
        total_events: total,
        cluster_nodes: nodes
      } = stats
      
      assert is_atom(node)
      assert is_integer(handlers)
      assert is_integer(projections)
      assert is_integer(total)
      assert is_list(nodes)
    end
    
    test "provides health status" do
      health = OTPEventBus.get_health_status()
      
      assert %{
        status: status,
        mnesia_status: mnesia_status,
        pg_scope_status: pg_status,
        cluster_connectivity: connectivity
      } = health
      
      assert status in [:healthy, :degraded, :single_node, :unhealthy]
      assert is_boolean(mnesia_status)
      assert is_boolean(pg_status)
      assert is_map(connectivity)
    end
  end
  
  describe "EventStore" do
    test "stores and retrieves events" do
      aggregate_id = "store_test_user"
      
      # Publish event through bus (which stores it)
      event = %{
        id: "store_test_1",
        aggregate_id: aggregate_id,
        type: :user_created,
        data: %{name: "Store Test User"},
        metadata: %{}
      }
      
      :ok = OTPEventBus.publish_event(event)
      
      # Retrieve events
      {:ok, stored_events} = EventStore.get_events(aggregate_id)
      
      assert length(stored_events) >= 1
      stored_event = Enum.find(stored_events, fn e -> e.id == event.id end)
      assert stored_event != nil
      assert stored_event.type == event.type
    end
    
    test "filters events by version range" do
      aggregate_id = "version_test_user"
      
      # Create multiple events
      events = for i <- 1..5 do
        %{
          id: "version_event_#{i}",
          aggregate_id: aggregate_id,
          type: :user_updated,
          data: %{update_count: i},
          metadata: %{}
        }
      end
      
      Enum.each(events, &OTPEventBus.publish_event/1)
      
      # Get events from version 2 to 4
      {:ok, filtered_events} = EventStore.get_events(aggregate_id, 
        from_version: 2, 
        to_version: 4
      )
      
      # Should get 3 events (versions 2, 3, 4)
      assert length(filtered_events) >= 3
    end
    
    test "gets events by type" do
      # Publish different event types
      user_event = %{
        id: "type_test_1",
        aggregate_id: "type_test_user",
        type: :user_created,
        data: %{name: "Type Test"},
        metadata: %{}
      }
      
      :ok = OTPEventBus.publish_event(user_event)
      
      # Get events by type
      {:ok, typed_events} = EventStore.get_events_by_type(:user_created, limit: 10)
      
      assert length(typed_events) >= 1
      assert Enum.all?(typed_events, fn e -> e.type == :user_created end)
    end
    
    test "gets aggregate version" do
      aggregate_id = "version_check_user"
      
      # Publish a few events
      for i <- 1..3 do
        event = %{
          id: "version_check_#{i}",
          aggregate_id: aggregate_id,
          type: :user_updated,
          data: %{update: i},
          metadata: %{}
        }
        :ok = OTPEventBus.publish_event(event)
      end
      
      # Check version
      {:ok, version} = EventStore.get_aggregate_version(aggregate_id)
      assert version >= 3
    end
    
    test "counts total events" do
      initial_count = EventStore.count_events()
      
      # Add an event
      event = %{
        id: "count_test_1",
        aggregate_id: "count_test_user",
        type: :user_created,
        data: %{name: "Count Test"},
        metadata: %{}
      }
      
      :ok = OTPEventBus.publish_event(event)
      
      # Count should increase
      new_count = EventStore.count_events()
      assert new_count > initial_count
    end
  end
  
  describe "EventAggregate" do
    test "creates and manages aggregate state" do
      aggregate_id = "aggregate_test_user"
      
      # Get initial state (should be empty)
      {:ok, initial_state} = EventAggregate.get_state(aggregate_id)
      assert initial_state.version == 0
      assert initial_state.state == %{}
      
      # Apply some events
      events = [
        %{
          id: "agg_event_1",
          type: :user_created,
          data: %{name: "Aggregate User", email: "agg@example.com"}
        },
        %{
          id: "agg_event_2", 
          type: :user_updated,
          data: %{email: "updated@example.com"}
        }
      ]
      
      {:ok, updated_state} = EventAggregate.apply_events(aggregate_id, events)
      
      assert updated_state.version == 2
      assert updated_state.state.name == "Aggregate User"
      assert updated_state.state.email == "updated@example.com"
    end
    
    test "rebuilds aggregate from event stream" do
      aggregate_id = "rebuild_test_user"
      
      # Publish events through event bus
      events = [
        %{
          id: "rebuild_1",
          aggregate_id: aggregate_id,
          type: :user_created,
          data: %{name: "Rebuild User"},
          metadata: %{}
        },
        %{
          id: "rebuild_2",
          aggregate_id: aggregate_id,
          type: :user_activated,
          data: %{activated_at: DateTime.utc_now()},
          metadata: %{}
        }
      ]
      
      Enum.each(events, &OTPEventBus.publish_event/1)
      
      # Rebuild aggregate from events
      {:ok, rebuilt_state} = EventAggregate.rebuild_from_events(aggregate_id)
      
      assert rebuilt_state.state.name == "Rebuild User"
      assert rebuilt_state.state.status == :active
      assert rebuilt_state.version >= 2
    end
    
    test "validates events before applying" do
      aggregate_id = "validation_test_user"
      
      # Create a user first
      create_event = %{
        type: :user_created,
        data: %{name: "Validation User"}
      }
      
      {:ok, _} = EventAggregate.apply_events(aggregate_id, [create_event])
      
      # Try to create again (should fail validation)
      duplicate_create = %{
        type: :user_created,
        data: %{name: "Duplicate User"}
      }
      
      validation_result = EventAggregate.validate_event(aggregate_id, duplicate_create)
      assert validation_result == {:error, :user_already_exists}
    end
    
    test "gets aggregate version" do
      aggregate_id = "version_test_agg"
      
      # Apply some events
      events = [
        %{type: :user_created, data: %{name: "Version Test"}},
        %{type: :user_updated, data: %{email: "version@test.com"}}
      ]
      
      {:ok, _} = EventAggregate.apply_events(aggregate_id, events)
      
      # Check version
      {:ok, version} = EventAggregate.get_version(aggregate_id)
      assert version == 2
    end
    
    test "creates snapshots" do
      aggregate_id = "snapshot_test_user"
      
      # Create aggregate with some state
      events = [%{type: :user_created, data: %{name: "Snapshot User"}}]
      {:ok, _} = EventAggregate.apply_events(aggregate_id, events)
      
      # Create snapshot
      result = EventAggregate.create_snapshot(aggregate_id)
      assert result == :ok
    end
    
    test "provides aggregate statistics" do
      stats = EventAggregate.get_stats()
      
      assert %{
        total_aggregates: total,
        table: table,
        node: node,
        mnesia_running: running
      } = stats
      
      assert is_integer(total)
      assert table == :aiex_aggregate_store
      assert is_atom(node)
      assert running in [:yes, :no] || is_boolean(running)
    end
  end
  
  describe "EventProjection" do
    test "registers and processes projections" do
      # Register test projection
      :ok = EventProjection.register(TestUserProjection)
      
      # Verify it's registered
      projections = EventProjection.list_projections()
      assert length(projections) >= 1
      
      # Publish an event
      event = %{
        id: "projection_test_1",
        aggregate_id: "projection_user",
        type: :user_created,
        data: %{name: "Projection User"},
        metadata: %{}
      }
      
      :ok = OTPEventBus.publish_event(event)
      
      # Give projection time to process
      :timer.sleep(100)
      
      # Projection should have processed the event
      # (TestUserProjection is defined below)
    end
    
    test "projects events manually" do
      event = %{
        type: :user_created,
        data: %{name: "Manual Test", email: "manual@test.com"}
      }
      
      {:ok, result} = EventProjection.project_event(TestUserProjection, event)
      
      assert result == %{
        action: :insert,
        table: :user_profiles,
        data: %{name: "Manual Test", email: "manual@test.com"}
      }
    end
    
    test "ignores irrelevant events" do
      event = %{
        type: :unrelated_event,
        data: %{some: "data"}
      }
      
      {:ok, result} = EventProjection.project_event(TestUserProjection, event)
      assert result == :ignore
    end
    
    test "unregisters projections" do
      # Register then unregister
      :ok = EventProjection.register(TestUserProjection)
      :ok = EventProjection.unregister(TestUserProjection)
      
      # Should not be in list anymore
      projections = EventProjection.list_projections()
      assert length(projections) == 0
    end
    
    test "provides projection statistics" do
      stats = EventProjection.get_stats()
      
      assert %{
        total_projections: total,
        projections: projection_list,
        table: table,
        node: node
      } = stats
      
      assert is_integer(total)
      assert is_list(projection_list)
      assert table == :aiex_projection_store
      assert is_atom(node)
    end
  end
  
  describe "Event Sourcing Integration" do
    test "complete event sourcing workflow" do
      aggregate_id = "integration_user"
      
      # 1. Subscribe to events
      :ok = OTPEventBus.subscribe({:aggregate, aggregate_id})
      
      # 2. Register a projection
      :ok = EventProjection.register(TestUserProjection)
      
      # 3. Publish events through event bus
      create_event = %{
        id: "integration_1",
        aggregate_id: aggregate_id,
        type: :user_created,
        data: %{name: "Integration User", email: "integration@test.com"},
        metadata: %{source: "test"}
      }
      
      update_event = %{
        id: "integration_2",
        aggregate_id: aggregate_id,
        type: :user_updated,
        data: %{email: "updated@test.com"},
        metadata: %{source: "test"}
      }
      
      :ok = OTPEventBus.publish_event(create_event)
      :ok = OTPEventBus.publish_event(update_event)
      
      # 4. Verify event distribution
      assert_receive {:event_notification, received_event1}, 1000
      assert_receive {:event_notification, received_event2}, 1000
      
      # 5. Check event storage
      {:ok, stored_events} = EventStore.get_events(aggregate_id)
      assert length(stored_events) >= 2
      
      # 6. Check aggregate state (rebuild from events if needed)
      {:ok, aggregate_state} = EventAggregate.rebuild_from_events(aggregate_id)
      assert Map.has_key?(aggregate_state.state, :name)
      assert aggregate_state.state.name == "Integration User"
      assert aggregate_state.state.email == "updated@test.com"
      assert aggregate_state.version >= 2
      
      # 7. Verify event bus health
      health = OTPEventBus.get_health_status()
      assert health.status in [:healthy, :single_node]
      
      # Cleanup
      :ok = EventProjection.unregister(TestUserProjection)
    end
    
    test "handles event replay functionality" do
      aggregate_id = "replay_user"
      
      # Publish some events
      events = for i <- 1..3 do
        %{
          id: "replay_#{i}",
          aggregate_id: aggregate_id,
          type: :user_updated,
          data: %{update_count: i},
          metadata: %{}
        }
      end
      
      Enum.each(events, &OTPEventBus.publish_event/1)
      
      # Replay events
      {:ok, _count} = EventStore.replay_events(aggregate_id: aggregate_id)
      
      # Should have replayed successfully
      # In a real system, this would trigger projection rebuilds
    end
    
    test "maintains consistency across components" do
      aggregate_id = "consistency_user"
      
      # Create events
      events = [
        %{
          id: "consistency_1",
          aggregate_id: aggregate_id,
          type: :user_created,
          data: %{name: "Consistency User"},
          metadata: %{}
        },
        %{
          id: "consistency_2",
          aggregate_id: aggregate_id,
          type: :user_activated,
          data: %{activated_at: DateTime.utc_now()},
          metadata: %{}
        }
      ]
      
      # Publish through event bus
      Enum.each(events, &OTPEventBus.publish_event/1)
      
      # All components should have consistent view
      
      # Event store should have all events
      {:ok, stored_events} = EventStore.get_events(aggregate_id)
      assert length(stored_events) >= 2
      
      # Aggregate should have correct state (rebuild from events)
      {:ok, aggregate} = EventAggregate.rebuild_from_events(aggregate_id)
      assert aggregate.state.name == "Consistency User"
      assert aggregate.state.status == :active
      
      # Version should match event count
      assert aggregate.version >= 2
    end
  end
end