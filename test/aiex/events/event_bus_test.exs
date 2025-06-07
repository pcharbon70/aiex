defmodule Aiex.Events.EventBusTest do
  use ExUnit.Case, async: false
  alias Aiex.Events.EventBus

  setup do
    # EventBus should already be running from the application
    # Just ensure it's available
    case Process.whereis(EventBus) do
      nil -> start_supervised!(EventBus)
      _pid -> :ok
    end
    
    :ok
  end

  describe "subscription and publishing" do
    test "subscribes to topic and receives events" do
      topic = "test_topic_#{:rand.uniform(10000)}"
      
      # Subscribe to topic
      assert :ok = EventBus.subscribe(topic)
      
      # Publish event
      event = %{message: "Hello World", data: [1, 2, 3]}
      assert {:ok, 1} = EventBus.publish(topic, event)
      
      # Should receive the event
      assert_receive {:event_bus, received_event}
      assert received_event.event == event
      assert received_event.topic == topic
      assert received_event.node == node()
      assert is_binary(received_event.id)
    end

    test "multiple subscribers receive the same event" do
      topic = "multi_subscriber_#{:rand.uniform(10000)}"
      test_pid = self()
      
      # Start multiple subscriber processes
      subscribers = for i <- 1..3 do
        spawn(fn ->
          EventBus.subscribe(topic)
          receive do
            {:event_bus, event} -> send(test_pid, {:received, i, event})
          end
        end)
      end
      
      # Give subscribers time to register
      Process.sleep(50)
      
      # Publish event
      event = %{test: "multi_subscriber"}
      assert {:ok, 3} = EventBus.publish(topic, event)
      
      # All subscribers should receive the event
      for i <- 1..3 do
        assert_receive {:received, ^i, received_event}, 1000
        assert received_event.event == event
      end
      
      # Clean up
      Enum.each(subscribers, &Process.exit(&1, :kill))
    end

    test "unsubscribes from topic" do
      topic = "unsubscribe_#{:rand.uniform(10000)}"
      
      # Subscribe and then unsubscribe
      assert :ok = EventBus.subscribe(topic)
      assert :ok = EventBus.unsubscribe(topic)
      
      # Publish event
      event = %{message: "Should not receive"}
      assert {:ok, 0} = EventBus.publish(topic, event)
      
      # Should not receive the event
      refute_receive {:event_bus, _}, 100
    end

    test "handles process termination gracefully" do
      topic = "termination_#{:rand.uniform(10000)}"
      
      # Start subscriber process that will terminate
      subscriber_pid = spawn(fn ->
        EventBus.subscribe(topic)
        receive do
          :terminate -> :ok
        end
      end)
      
      # Give time for subscription
      Process.sleep(50)
      
      # Verify subscriber is registered
      {:ok, subscribers} = EventBus.subscribers(topic)
      assert length(subscribers) == 1
      
      # Terminate subscriber
      Process.exit(subscriber_pid, :kill)
      Process.sleep(50)
      
      # Publish event - should work without errors
      event = %{message: "After termination"}
      assert {:ok, 0} = EventBus.publish(topic, event)
    end
  end

  describe "subscriber management" do
    test "lists subscribers for a topic" do
      topic = "subscribers_#{:rand.uniform(10000)}"
      
      # Subscribe with current process
      assert :ok = EventBus.subscribe(topic)
      
      # Get subscribers
      {:ok, subscribers} = EventBus.subscribers(topic)
      
      assert length(subscribers) == 1
      [subscriber] = subscribers
      assert subscriber.pid == self()
      assert subscriber.node == node()
      assert subscriber.alive == true
    end

    test "returns empty list for topic with no subscribers" do
      topic = "no_subscribers_#{:rand.uniform(10000)}"
      
      {:ok, subscribers} = EventBus.subscribers(topic)
      assert subscribers == []
    end
  end

  describe "statistics" do
    test "provides event bus statistics" do
      topic1 = "stats_topic_1_#{:rand.uniform(10000)}"
      topic2 = "stats_topic_2_#{:rand.uniform(10000)}"
      
      # Subscribe to topics
      EventBus.subscribe(topic1)
      EventBus.subscribe(topic2)
      
      # Publish some events
      EventBus.publish(topic1, %{data: 1})
      EventBus.publish(topic2, %{data: 2})
      
      # Get statistics
      stats = EventBus.stats()
      
      assert is_map(stats)
      assert stats.node == node()
      assert is_integer(stats.total_events_published)
      assert is_integer(stats.total_subscriptions)
      assert is_integer(stats.active_topics)
      assert is_list(stats.topic_details)
      assert is_list(stats.cluster_nodes)
      
      # Should have our topics
      topic_names = Enum.map(stats.topic_details, & &1.topic)
      assert topic1 in topic_names
      assert topic2 in topic_names
    end
  end

  describe "event metadata" do
    test "includes metadata in published events" do
      topic = "metadata_#{:rand.uniform(10000)}"
      
      EventBus.subscribe(topic)
      
      event = %{message: "With metadata"}
      metadata = %{priority: :high, source: "test"}
      
      assert {:ok, 1} = EventBus.publish(topic, event, metadata)
      
      assert_receive {:event_bus, received_event}
      assert received_event.metadata == metadata
      assert received_event.event == event
    end

    test "enriches events with timestamp and ID" do
      topic = "enriched_#{:rand.uniform(10000)}"
      
      EventBus.subscribe(topic)
      
      event = %{simple: "event"}
      
      assert {:ok, 1} = EventBus.publish(topic, event)
      
      assert_receive {:event_bus, received_event}
      assert %DateTime{} = received_event.timestamp
      assert is_binary(received_event.id)
      assert received_event.node == node()
    end
  end
end