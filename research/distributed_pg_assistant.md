# OTP-native event-driven architecture patterns for Elixir without Phoenix.PubSub

Building robust event-driven architectures in Elixir using only OTP primitives provides complete control over message distribution, fault tolerance, and performance characteristics. This comprehensive guide explores proven patterns from production systems handling billions of events daily.

## Core OTP pub/sub implementations with GenServer and Registry

The Registry module offers the most scalable foundation for building pub/sub systems in pure OTP. Unlike custom GenServer implementations with ETS, Registry provides built-in process monitoring, automatic cleanup, and efficient concurrent access patterns tested up to 40 cores.

### Registry-based pub/sub pattern

```elixir
defmodule RegistryPubSub do
  def child_spec(_) do
    Registry.child_spec(
      keys: :duplicate,
      name: __MODULE__,
      partitions: System.schedulers_online()
    )
  end

  def subscribe(topic) do
    Registry.register(__MODULE__, topic, [])
  end

  def broadcast(topic, message) do
    Registry.dispatch(__MODULE__, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, topic, message})
    end)
  end
end
```

**Key advantages:** Registry partitions its internal ETS tables across cores, eliminating contention. The `:duplicate` key mode allows multiple processes to subscribe to the same topic. Process monitoring happens automatically - when a subscriber crashes, Registry removes it immediately.

### GenServer-based topic router

For scenarios requiring custom routing logic or message transformation, a GenServer-based approach provides maximum flexibility:

```elixir
defmodule TopicPubSub do
  use GenServer

  def init(_) do
    {:ok, %{}}
  end

  def handle_cast({:subscribe, topic, pid}, state) do
    Process.monitor(pid)
    subscribers = Map.get(state, topic, MapSet.new())
    new_subscribers = MapSet.put(subscribers, pid)
    {:noreply, Map.put(state, topic, new_subscribers)}
  end

  def handle_cast({:publish, topic, message}, state) do
    case Map.get(state, topic) do
      nil -> {:noreply, state}
      subscribers ->
        Enum.each(subscribers, fn pid ->
          send(pid, {:pubsub_message, topic, message})
        end)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    new_state = Enum.reduce(state, %{}, fn {topic, subscribers}, acc ->
      new_subscribers = MapSet.delete(subscribers, pid)
      if MapSet.size(new_subscribers) == 0 do
        acc
      else
        Map.put(acc, topic, new_subscribers)
      end
    end)
    {:noreply, new_state}
  end
end
```

This pattern excels when you need fine-grained control over subscription lifecycles or custom message dispatching logic. Process monitoring ensures dead subscribers are cleaned up automatically.

## Erlang's pg module powers distributed pub/sub

The `pg` module (OTP 23+) provides strongly consistent distributed process groups, replacing the deprecated `pg2` with significant performance improvements. Discord uses similar patterns to handle 26 million WebSocket events per second.

### Basic pg implementation

```elixir
defmodule ProcessGroupPubSub do
  def start_link do
    :pg.start_link()
  end

  def join(group, pid \\ self()) do
    :pg.join(group, pid)
  end

  def broadcast(group, message) do
    :pg.get_members(group)
    |> Enum.each(fn pid ->
      send(pid, {:pg_message, group, message})
    end)
  end
end
```

**Performance characteristics:** pg handles 10,000+ processes per group efficiently using ETS tables for lookups. Its strong eventual consistency model ensures all nodes eventually see the same membership view, even during network partitions.

### Advanced distributed event bus

```elixir
defmodule DistributedEventBus do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [], name: {:global, __MODULE__})
  end

  def publish(topic, event, data) do
    Members = pg:get_members(event_bus_scope, topic),
    Message = {event, topic, event, data, node()},
    
    # Parallel message dispatch
    Task.async_stream(Members, fn pid -> 
      send(pid, Message) 
    end, max_concurrency: System.schedulers_online() * 2)
    |> Stream.run()
  end

  def init([]) do
    pg:start_link(event_bus_scope),
    {:ok, %{}}
  end
end
```

This pattern leverages `Task.async_stream` for concurrent message delivery, preventing slow subscribers from blocking the entire broadcast operation.

## GenStage and Flow enable backpressure-aware streaming

GenStage provides demand-driven event processing with automatic backpressure. Consumers control the flow by requesting specific amounts of data, preventing memory overflow in high-throughput scenarios.

### Producer with adaptive demand

```elixir
defmodule EventProducer do
  use GenStage

  def init(counter) do
    {:producer, counter}
  end

  def handle_demand(demand, counter) when demand > 0 do
    events = Enum.to_list(counter..counter+demand-1)
    {:noreply, events, counter + demand}
  end
end

defmodule EventConsumer do
  use GenStage

  def init(:ok) do
    {:consumer, :ok, subscribe_to: [{EventProducer, max_demand: 1000, min_demand: 500}]}
  end

  def handle_events(events, _from, state) do
    # Process events - backpressure automatically handled
    process_batch(events)
    {:noreply, [], state}
  end
end
```

### Flow for parallel processing

Flow builds on GenStage to provide map-reduce style computations with automatic partitioning:

```elixir
events_stream
|> Flow.from_enumerable()
|> Flow.partition(stages: System.schedulers_online())
|> Flow.flat_map(&parse_event/1)
|> Flow.reduce(fn -> %{} end, fn event, acc ->
  Map.update(acc, event.type, 1, & &1 + 1)
end)
|> Enum.to_list()
```

Flow automatically manages producer-consumer relationships and handles failures gracefully. Use it for CPU-intensive event transformations that benefit from parallelization.

## Building custom event buses with OTP primitives

A production-ready event bus requires subscription management, event persistence, and fault tolerance. Here's a complete implementation:

```elixir
defmodule OTPEventBus do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def subscribe(topic, options \\ []) do
    Registry.register(OTPEventBus.Registry, topic, options)
  end

  def publish(topic, event, metadata \\ %{}) do
    event_with_metadata = %{
      event: event,
      topic: topic,
      timestamp: System.system_time(:microsecond),
      metadata: metadata,
      id: generate_id()
    }
    
    # Store event
    OTPEventBus.EventStore.store(event_with_metadata)
    
    # Dispatch to subscribers
    Registry.dispatch(OTPEventBus.Registry, topic, fn entries ->
      dispatch_to_subscribers(entries, event_with_metadata)
    end)
  end

  defp dispatch_to_subscribers(entries, event) do
    Task.Supervisor.async_stream_nolink(
      OTPEventBus.TaskSupervisor,
      entries,
      fn {pid, options} ->
        safe_dispatch(pid, event, options)
      end,
      max_concurrency: System.schedulers_online() * 2
    )
    |> Stream.run()
  end

  defp safe_dispatch(pid, event, options) do
    try do
      case Keyword.get(options, :handler) do
        {module, function} ->
          apply(module, function, [event])
        _ ->
          send(pid, {:event_bus, event})
      end
    catch
      kind, reason ->
        Logger.error("Failed to dispatch event: #{Exception.format(kind, reason)}")
    end
  end
end
```

This implementation provides error isolation, concurrent dispatch, and flexible subscription options. The use of `Task.Supervisor` ensures failing handlers don't crash the event bus.

## Process registry patterns optimize subscription management

While Registry handles most use cases, specific scenarios benefit from custom patterns:

### Pattern-based subscriptions

```elixir
defmodule PatternEventBus do
  use GenServer

  def subscribe(pattern, pid \\ self()) do
    GenServer.call(__MODULE__, {:subscribe, pattern, pid})
  end

  def publish(event) do
    GenServer.cast(__MODULE__, {:publish, event})
  end

  def handle_cast({:publish, event}, state) do
    matching_subscribers = Enum.filter(state.subscribers, fn {pattern, _pid} ->
      matches_pattern?(event, pattern)
    end)

    Enum.each(matching_subscribers, fn {_pattern, pid} ->
      send(pid, {:pattern_event, event})
    end)
    
    {:noreply, state}
  end

  defp matches_pattern?(event, pattern) when is_map(event) and is_map(pattern) do
    Enum.all?(pattern, fn {key, expected_value} ->
      case Map.get(event, key) do
        ^expected_value -> true
        actual_value when is_function(expected_value) -> expected_value.(actual_value)
        _ -> false
      end
    end)
  end
end
```

This enables subscriptions like `%{type: :order, amount: fn amt -> amt > 1000 end}` for complex event filtering.

## Distributed event broadcasting via global module

Erlang's global module enables cluster-wide coordination, though it's better suited for low-frequency coordination than high-throughput events:

```elixir
defmodule GlobalEventBroadcaster do
  def register_listener(event_type, pid) do
    name = {event_listener, event_type, node(pid)}
    global:register_name(name, pid)
  end

  def broadcast_event(event_type, event_data) do
    all_nodes = [node() | nodes()]
    
    Task.async_stream(all_nodes, fn node ->
      name = {event_listener, event_type, node}
      case global:whereis_name(name) of
        undefined -> :ok
        pid -> send(pid, {:global_event, event_type, event_data, node()})
      end
    end, max_concurrency: length(all_nodes))
    |> Stream.run()
  end
end
```

Global operations are synchronous and can be slow during network partitions. Use sparingly for critical coordination rather than high-frequency events.

## Message passing patterns for multi-node distribution

### Gossip-based propagation

```elixir
defmodule GossipPropagation do
  def gossip_event(event, state) do
    event_id = generate_event_id(event)
    
    # Select random subset of nodes
    nodes_to_gossip = nodes()
    |> Enum.take_random(3)
    
    Enum.each(nodes_to_gossip, fn node ->
      {gossip_handler, node} ! {gossip, event, node()}
    end)
    
    add_known_event(event_id, event, state)
  end

  def handle_gossip({gossip, event, from_node}, state) do
    event_id = generate_event_id(event)
    
    if not seen_event?(event_id, state) do
      process_event(event)
      gossip_event(event, state)  # Continue gossiping
    end
  end
end
```

Gossip protocols provide eventual consistency with high resilience to node failures. They excel in large clusters where strong consistency isn't required.

### Tree-based hierarchical distribution

```elixir
defmodule TreePropagation do
  def propagate_down(event, %{children: children}) do
    Task.async_stream(children, fn child ->
      {tree_propagator, child} ! {tree_event, event, :down}
    end)
    |> Stream.run()
  end

  def handle_tree_event({tree_event, event, :down}, tree_node) do
    process_event(event)
    propagate_down(event, tree_node)
  end
end
```

Tree topologies minimize message duplication and provide predictable propagation delays, ideal for hierarchical systems.

## Using ETS and Mnesia for subscription storage

### High-performance ETS patterns

Discord's FastGlobal pattern eliminates ETS copy overhead for read-heavy workloads:

```elixir
defmodule FastSubscriptionCache do
  def put(key, value) do
    # Store in ETS
    :ets.insert(:subscription_cache, {key, value})
    
    # Also compile into module for zero-copy reads
    module_name = Module.concat(__MODULE__, key)
    Module.create(module_name, quote do
      def get, do: unquote(Macro.escape(value))
    end, Macro.Env.location(__ENV__))
  end

  def get(key) do
    module_name = Module.concat(__MODULE__, key)
    module_name.get()
  rescue
    UndefinedFunctionError ->
      case :ets.lookup(:subscription_cache, key) do
        [{^key, value}] -> value
        [] -> nil
      end
  end
end
```

This achieves 0.33 μs/op compared to 7.64 μs/op for standard ETS lookups.

### Mnesia for persistent subscriptions

```elixir
defmodule PersistentSubscriptions do
  def create_tables do
    :mnesia.create_table(Subscription, [
      attributes: [:id, :topic, :handler, :created_at],
      type: :set,
      disc_copies: [node()]
    ])
  end

  def add_subscription(topic, handler) do
    :mnesia.transaction(fn ->
      :mnesia.write({Subscription, generate_id(), topic, handler, DateTime.utc_now()})
    end)
  end

  def get_subscriptions(topic) do
    :mnesia.transaction(fn ->
      :mnesia.match_object({Subscription, :_, topic, :_, :_})
    end)
  end
end
```

**Important:** Mnesia's consistency requirements make it unsuitable for high-frequency updates. Discord abandoned Mnesia twice due to performance issues under load.

## GenEvent alternatives in modern OTP

Since GenEvent is deprecated, use supervisor-based patterns:

```elixir
defmodule EventManager do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: EventHandlerRegistry},
      {DynamicSupervisor, name: EventHandlerSupervisor, strategy: :one_for_one}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end

  def add_handler(handler_module, args) do
    spec = {EventHandlerWrapper, {handler_module, args}}
    DynamicSupervisor.start_child(EventHandlerSupervisor, spec)
  end

  def notify(event) do
    Registry.dispatch(EventHandlerRegistry, :handlers, fn entries ->
      for {pid, _} <- entries do
        GenServer.cast(pid, {:handle_event, event})
      end
    end)
  end
end
```

This provides similar functionality with better supervision and error isolation.

## Event buffering and persistence strategies

### Ring buffer for bounded memory usage

```elixir
defmodule EventRingBuffer do
  use GenServer

  def init(size) do
    buffer = :queue.new()
    {:ok, %{buffer: buffer, size: size, count: 0}}
  end

  def handle_cast({:add_event, event}, state) do
    new_buffer = :queue.in(event, state.buffer)
    
    {final_buffer, new_count} = 
      if state.count >= state.size do
        {_, trimmed} = :queue.out(new_buffer)
        {trimmed, state.count}
      else
        {new_buffer, state.count + 1}
      end
    
    {:noreply, %{state | buffer: final_buffer, count: new_count}}
  end
end
```

### Persistent event log with crash recovery

```elixir
defmodule EventLog do
  use GenServer

  def init(file_path) do
    case File.open(file_path, [:read, :write, :binary, :raw, :append]) do
      {:ok, file} ->
        {:ok, %{file: file, path: file_path}}
      error ->
        {:stop, error}
    end
  end

  def handle_call({:append, event}, _from, state) do
    binary = :erlang.term_to_binary(event)
    size = byte_size(binary)
    
    # Write size header then event
    case IO.binwrite(state.file, <<size::32>> <> binary) do
      :ok ->
        :file.sync(state.file)  # Ensure durability
        {:reply, :ok, state}
      error ->
        {:reply, error, state}
    end
  end

  def replay_events(file_path) do
    {:ok, file} = File.open(file_path, [:read, :binary])
    replay_loop(file, [])
  end

  defp replay_loop(file, events) do
    case IO.binread(file, 4) do
      <<size::32>> ->
        event_binary = IO.binread(file, size)
        event = :erlang.binary_to_term(event_binary)
        replay_loop(file, [event | events])
      _ ->
        File.close(file)
        Enum.reverse(events)
    end
  end
end
```

## Performance comparison: pg vs pg2 vs syn

Based on production experiences and benchmarks:

| Feature | pg (OTP 23+) | pg2 (deprecated) | syn |
|---------|--------------|------------------|-----|
| Max processes/group | 10,000+ | ~45,000 (4 nodes) | Unlimited |
| Network partition handling | Strong eventual consistency | Uses global:trans (fails) | Eventual consistency |
| Performance | Optimized ETS lookups | Slower with scale | Good |
| Multi-scope support | Yes | No | Yes |
| Recommendation | Use for new systems | Migrate away | Consider for specific needs |

## Event sourcing implementation with pure OTP

```elixir
defmodule EventSourcedAggregate do
  use GenServer

  def init(aggregate_id) do
    events = EventStore.load_events(aggregate_id)
    state = Enum.reduce(events, %{id: aggregate_id}, &apply_event/2)
    {:ok, state}
  end

  def handle_call({:execute_command, command}, _from, state) do
    case validate_command(command, state) do
      {:ok, events} ->
        new_state = Enum.reduce(events, state, &apply_event/2)
        :ok = EventStore.persist_events(state.id, events)
        publish_events(events)
        {:reply, {:ok, new_state}, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp apply_event(%UserCreated{} = event, state) do
    %{state | email: event.email, status: :active}
  end

  defp apply_event(%UserDeactivated{}, state) do
    %{state | status: :inactive}
  end
end
```

### Event replay with snapshots

```elixir
defmodule EventReplay do
  def replay_from_snapshot(aggregate_id) do
    case SnapshotStore.load_latest(aggregate_id) do
      {:ok, %{state: state, version: version}} ->
        events = EventStore.load_events_after(aggregate_id, version)
        Enum.reduce(events, state, &apply_event/2)
      :not_found ->
        replay_all_events(aggregate_id)
    end
  end

  def create_snapshot(aggregate_id, state, version) when rem(version, 100) == 0 do
    SnapshotStore.save(%{
      aggregate_id: aggregate_id,
      state: state,
      version: version,
      timestamp: DateTime.utc_now()
    })
  end
end
```

## Performance considerations for OTP-based systems

### Benchmarking results from production

Discord's production metrics demonstrate OTP's scalability:
- **26 million WebSocket events/second**
- **12+ million concurrent users**
- **500 Elixir machines for chat infrastructure**

Key optimizations:
- FastGlobal for read-heavy subscription data (20x faster than ETS)
- Process dictionaries for hot paths (controversial but effective)
- NIFs in Rust for CPU-intensive operations
- Semaphore pattern for backpressure control

### Memory optimization strategies

```elixir
defmodule MemoryOptimizedBus do
  def broadcast(topic, event) do
    # Use binary references to avoid copying
    event_binary = :erlang.term_to_binary(event)
    
    Registry.dispatch(__MODULE__, topic, fn entries ->
      for {pid, _} <- entries do
        # Send binary reference, not full copy
        send(pid, {:event_ref, topic, event_binary})
      end
    end)
  end

  def handle_info({:event_ref, topic, event_binary}, state) do
    # Deserialize only when needed
    event = :erlang.binary_to_term(event_binary)
    process_event(topic, event)
    {:noreply, state}
  end
end
```

## Multi-node event synchronization

### Vector clock implementation

```elixir
defmodule VectorClock do
  def new(nodes) do
    Enum.into(nodes, %{}, fn node -> {node, 0} end)
  end

  def increment(vector_clock, node) do
    Map.update!(vector_clock, node, & &1 + 1)
  end

  def happens_before?(vc1, vc2) do
    Enum.all?(vc1, fn {node, time1} ->
      time2 = Map.get(vc2, node, 0)
      time1 <= time2
    end) and vc1 != vc2
  end

  def concurrent?(vc1, vc2) do
    not happens_before?(vc1, vc2) and not happens_before?(vc2, vc1)
  end
end
```

### Causal delivery guarantee

```elixir
defmodule CausalDelivery do
  def deliver_if_ready(event, delivered_events) do
    dependencies_met? = Enum.all?(event.dependencies, fn dep_id ->
      Enum.any?(delivered_events, & &1.id == dep_id)
    end)

    if dependencies_met? do
      {:deliver, event}
    else
      {:buffer, event}
    end
  end
end
```

## Topic-based routing with Registry and GenServer

Registry's built-in dispatching provides efficient topic-based routing:

```elixir
defmodule TopicRouter do
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end

  def start_link do
    children = [
      {Registry, keys: :duplicate, name: __MODULE__.Registry, 
       partitions: System.schedulers_online()},
      {__MODULE__.Dispatcher, []}
    ]
    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def subscribe(topic, metadata \\ %{}) do
    Registry.register(__MODULE__.Registry, topic, metadata)
  end

  def publish(topic, event) do
    Registry.dispatch(__MODULE__.Registry, topic, fn entries ->
      # Group by priority if specified in metadata
      grouped = Enum.group_by(entries, fn {_pid, meta} -> 
        Map.get(meta, :priority, :normal) 
      end)
      
      # Deliver to high priority first
      dispatch_priority_group(grouped[:high] || [], event)
      dispatch_priority_group(grouped[:normal] || [], event)
      dispatch_priority_group(grouped[:low] || [], event)
    end)
  end

  defp dispatch_priority_group(entries, event) do
    Task.async_stream(entries, fn {pid, _meta} ->
      send(pid, {:topic_event, event})
    end, max_concurrency: 50, ordered: false)
    |> Stream.run()
  end
end
```

## Event ordering guarantees

### Partition-based ordering

```elixir
defmodule OrderedEventProcessor do
  use GenStage

  def init(partition_id) do
    {:producer_consumer, %{partition: partition_id, sequence: 0}}
  end

  def handle_events(events, _from, state) do
    # Sort by sequence within partition
    sorted_events = Enum.sort_by(events, & &1.sequence)
    
    # Verify no gaps
    {valid_events, new_sequence} = 
      process_sequential_events(sorted_events, state.sequence, [])
    
    {:noreply, valid_events, %{state | sequence: new_sequence}}
  end

  defp process_sequential_events([], sequence, acc), do: {Enum.reverse(acc), sequence}
  
  defp process_sequential_events([event | rest], expected_seq, acc) do
    if event.sequence == expected_seq + 1 do
      process_sequential_events(rest, event.sequence, [event | acc])
    else
      # Gap detected, stop processing
      {Enum.reverse(acc), expected_seq}
    end
  end
end
```

### Total ordering with logical timestamps

```elixir
defmodule LamportClock do
  def send_event(event, clock) do
    new_clock = clock + 1
    timestamped_event = Map.put(event, :lamport_time, new_clock)
    {timestamped_event, new_clock}
  end

  def receive_event(event, local_clock) do
    new_clock = max(event.lamport_time, local_clock) + 1
    {event, new_clock}
  end
end
```

## Integration with Mnesia for persistence

While Mnesia has limitations for high-frequency events, it excels at storing subscription metadata and configuration:

```elixir
defmodule MnesiaSubscriptionStore do
  def init_schema do
    :mnesia.create_schema([node()])
    :mnesia.start()
    
    :mnesia.create_table(Subscription, [
      attributes: [:id, :topic, :filter, :handler, :options],
      disc_copies: [node()],
      type: :set,
      index: [:topic]
    ])
  end

  def save_subscription(subscription) do
    :mnesia.transaction(fn ->
      :mnesia.write(Subscription, subscription, :write)
    end)
  end

  def find_by_topic(topic) do
    :mnesia.transaction(fn ->
      :mnesia.index_read(Subscription, topic, :topic)
    end)
  end

  def restore_subscriptions do
    {:atomic, subscriptions} = :mnesia.transaction(fn ->
      :mnesia.match_object({Subscription, :_, :_, :_, :_, :_})
    end)
    
    Enum.each(subscriptions, fn sub ->
      Registry.register(EventBus.Registry, sub.topic, sub.options)
    end)
  end
end
```

## Production examples from Discord and WhatsApp

### Discord's architecture insights

Discord's event system handles massive scale through careful optimization:

1. **FastGlobal pattern**: Compiles frequently-read data into module attributes, achieving 0.33 μs/op vs 7.64 μs/op for ETS
2. **Manifold library**: Batches messages between nodes to reduce network overhead
3. **Semaphore pattern**: ETS-based counters for distributed rate limiting
4. **Guild process isolation**: Each Discord server runs as an isolated process, preventing cascade failures

### WhatsApp's simplicity

WhatsApp's architecture proves that OTP's primitives scale to billions of messages daily:
- 50 billion messages/day with just 32 engineers
- Built on ejabberd (Erlang XMPP server)
- Hot code loading enables zero-downtime deployments
- FreeBSD + Erlang/OTP provides the entire stack

### Key lessons from production

1. **Start simple**: Basic GenServer + Registry patterns handle most use cases
2. **Monitor everything**: Use `:telemetry` and `:observer` for visibility
3. **Isolate failures**: One slow subscriber shouldn't affect others
4. **Benchmark realistically**: Test with production-like message sizes and rates
5. **Plan for growth**: Design APIs that allow implementation changes

## Distributed event propagation strategies

### Reliable multicast pattern

```elixir
defmodule ReliableMulticast do
  def broadcast(event, nodes \\ Node.list()) do
    ref = make_ref()
    
    # Send to all nodes
    tasks = Enum.map(nodes, fn node ->
      Task.async(fn ->
        try do
          :rpc.call(node, EventHandler, :handle, [event], 5000)
        catch
          :exit, reason -> {:error, node, reason}
        end
      end)
    end)
    
    # Collect results with timeout
    results = Task.yield_many(tasks, 5000)
    
    # Retry failed nodes
    failed_nodes = collect_failed_nodes(results)
    retry_with_backoff(event, failed_nodes)
  end
end
```

## Fault tolerance patterns

### Circuit breaker for event consumers

```elixir
defmodule CircuitBreaker do
  def call(fun, breaker_name) do
    case check_state(breaker_name) do
      :open ->
        {:error, :circuit_open}
      
      :half_open ->
        case safe_call(fun) do
          {:ok, result} ->
            reset(breaker_name)
            {:ok, result}
          error ->
            trip(breaker_name)
            error
        end
      
      :closed ->
        case safe_call(fun) do
          {:ok, result} ->
            {:ok, result}
          error ->
            record_failure(breaker_name)
            error
        end
    end
  end

  defp safe_call(fun) do
    try do
      {:ok, fun.()}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end
end
```

### Supervision tree for event processing

```elixir
defmodule EventSystemSupervisor do
  use Supervisor

  def init(_) do
    children = [
      # Core infrastructure
      {Registry, keys: :duplicate, name: EventBus.Registry},
      
      # Event storage
      {EventStore, []},
      
      # Processing pipeline
      {EventProducerSupervisor, []},
      {ConsumerSupervisor, 
        strategy: :one_for_one,
        max_restarts: 10,
        max_seconds: 60
      },
      
      # Monitoring
      {EventMetricsCollector, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
```

## Subscription management patterns

### Dynamic subscription with lifecycle hooks

```elixir
defmodule SubscriptionManager do
  use GenServer

  def subscribe(subscriber_pid, topic, opts \\ []) do
    GenServer.call(__MODULE__, {:subscribe, subscriber_pid, topic, opts})
  end

  def handle_call({:subscribe, pid, topic, opts}, _from, state) do
    # Monitor subscriber
    ref = Process.monitor(pid)
    
    # Run before_subscribe hooks
    case run_hooks(:before_subscribe, {pid, topic, opts}) do
      :ok ->
        Registry.register(EventBus.Registry, topic, opts)
        subscription = %{
          pid: pid,
          topic: topic,
          ref: ref,
          subscribed_at: DateTime.utc_now(),
          options: opts
        }
        {:reply, {:ok, subscription}, store_subscription(subscription, state)}
      
      {:error, reason} ->
        Process.demonitor(ref)
        {:reply, {:error, reason}, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Find and remove subscription
    case find_subscription_by_ref(ref, state) do
      nil ->
        {:noreply, state}
      
      subscription ->
        run_hooks(:after_unsubscribe, {subscription, reason})
        {:noreply, remove_subscription(subscription, state)}
    end
  end
end
```

## Key takeaways for production systems

Building event-driven architectures with pure OTP provides complete control and proven scalability. The patterns demonstrated here power systems handling billions of events daily at companies like Discord and WhatsApp.

**Essential principles:**
- Start with Registry for pub/sub - it's battle-tested and scales across cores
- Use pg for distributed process groups with strong eventual consistency  
- Implement GenStage when you need backpressure and flow control
- Monitor everything with :telemetry and proper supervision trees
- Design for failure - isolate components and implement circuit breakers

**Performance guidelines:**
- Benchmark with realistic workloads before optimizing
- Consider FastGlobal pattern for read-heavy subscription data
- Use Task.async_stream for concurrent message dispatch
- Implement proper backpressure to prevent memory overflow

**Architecture recommendations:**
- Keep event buses simple - complexity belongs in handlers
- Use supervision trees to isolate failures
- Implement event sourcing for audit trails and replay capability
- Plan for distributed operation from the start

The combination of OTP's robust primitives, Elixir's excellent tooling, and these proven patterns enables building event-driven systems that scale from prototypes to production systems handling millions of concurrent users.
