package events

import (
	"context"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewEventStreamManager(t *testing.T) {
	config := StreamConfig{
		BufferSize:        1000,
		MaxEventAge:       5 * time.Minute,
		FlushInterval:     100 * time.Millisecond,
		EnableCompression: true,
		EnableBatching:    true,
		BatchSize:         10,
		BatchTimeout:      50 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	assert.NotNil(t, manager)
	assert.Equal(t, config.BufferSize, manager.config.BufferSize)
	assert.NotNil(t, manager.buffer)
	assert.NotNil(t, manager.rateLimiter)
	assert.NotNil(t, manager.subscribers)
}

func TestEventStreamManagerStartStop(t *testing.T) {
	config := StreamConfig{
		BufferSize:    100,
		FlushInterval: 10 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)

	// Test start
	err := manager.Start()
	assert.NoError(t, err)
	assert.True(t, manager.IsRunning())

	// Test duplicate start
	err = manager.Start()
	assert.Error(t, err)

	// Test stop
	err = manager.Stop()
	assert.NoError(t, err)
	assert.False(t, manager.IsRunning())

	// Test duplicate stop
	err = manager.Stop()
	assert.Error(t, err)
}

func TestEventProcessing(t *testing.T) {
	config := StreamConfig{
		BufferSize:    100,
		FlushInterval: 10 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Create test event
	event := StreamEvent{
		ID:       "test-1",
		Type:     "test_event",
		Category: CategorySystem,
		Priority: PriorityNormal,
		Payload:  map[string]interface{}{"data": "test"},
		Timestamp: time.Now(),
		Source:   "test",
	}

	// Test event processing
	err := manager.ProcessEvent(event)
	assert.NoError(t, err)

	// Verify event was added to buffer
	time.Sleep(20 * time.Millisecond) // Allow processing
	stats := manager.GetStats()
	assert.Equal(t, uint64(1), stats.EventsProcessed)
}

func TestEventSubscription(t *testing.T) {
	config := StreamConfig{
		BufferSize:    100,
		FlushInterval: 10 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Subscribe to events
	receivedEvents := make(chan StreamEvent, 10)
	callback := func(event StreamEvent) {
		receivedEvents <- event
	}

	subscriptionID := manager.Subscribe(CategorySystem, callback)
	assert.NotEmpty(t, subscriptionID)

	// Send test event
	event := StreamEvent{
		ID:       "test-1",
		Type:     "test_event",
		Category: CategorySystem,
		Priority: PriorityNormal,
		Payload:  map[string]interface{}{"data": "test"},
		Timestamp: time.Now(),
		Source:   "test",
	}

	require.NoError(t, manager.ProcessEvent(event))

	// Verify event was received
	select {
	case receivedEvent := <-receivedEvents:
		assert.Equal(t, event.ID, receivedEvent.ID)
		assert.Equal(t, event.Type, receivedEvent.Type)
	case <-time.After(100 * time.Millisecond):
		t.Fatal("Event not received")
	}

	// Test unsubscribe
	manager.Unsubscribe(subscriptionID)

	// Send another event
	event2 := event
	event2.ID = "test-2"
	require.NoError(t, manager.ProcessEvent(event2))

	// Verify event was not received after unsubscribe
	select {
	case <-receivedEvents:
		t.Fatal("Event received after unsubscribe")
	case <-time.After(50 * time.Millisecond):
		// Expected - no event should be received
	}
}

func TestEventFiltering(t *testing.T) {
	config := StreamConfig{
		BufferSize:    100,
		FlushInterval: 10 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Subscribe to specific category
	receivedEvents := make(chan StreamEvent, 10)
	callback := func(event StreamEvent) {
		receivedEvents <- event
	}

	manager.Subscribe(CategorySystem, callback)

	// Send events of different categories
	systemEvent := StreamEvent{
		ID:       "system-1",
		Type:     "system_event",
		Category: CategorySystem,
		Priority: PriorityNormal,
		Timestamp: time.Now(),
		Source:   "test",
	}

	uiEvent := StreamEvent{
		ID:       "ui-1",
		Type:     "ui_event",
		Category: CategoryUI,
		Priority: PriorityNormal,
		Timestamp: time.Now(),
		Source:   "test",
	}

	require.NoError(t, manager.ProcessEvent(systemEvent))
	require.NoError(t, manager.ProcessEvent(uiEvent))

	// Should only receive system event
	select {
	case receivedEvent := <-receivedEvents:
		assert.Equal(t, "system-1", receivedEvent.ID)
	case <-time.After(100 * time.Millisecond):
		t.Fatal("System event not received")
	}

	// Should not receive UI event
	select {
	case <-receivedEvents:
		t.Fatal("UI event received when only subscribed to system events")
	case <-time.After(50 * time.Millisecond):
		// Expected - UI event should be filtered out
	}
}

func TestRateLimiting(t *testing.T) {
	config := StreamConfig{
		BufferSize:    100,
		FlushInterval: 10 * time.Millisecond,
		RateLimit:     2, // 2 events per interval
		RateInterval:  100 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Send events rapidly
	processedCount := 0
	for i := 0; i < 5; i++ {
		event := StreamEvent{
			ID:       fmt.Sprintf("test-%d", i),
			Type:     "test_event",
			Category: CategorySystem,
			Priority: PriorityNormal,
			Timestamp: time.Now(),
			Source:   "test",
		}

		err := manager.ProcessEvent(event)
		if err == nil {
			processedCount++
		}
	}

	// Should have rate limited some events
	assert.LessOrEqual(t, processedCount, 2, "Rate limiting should have limited events")
}

func TestEventPriority(t *testing.T) {
	config := StreamConfig{
		BufferSize:    100,
		FlushInterval: 10 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Subscribe to events
	receivedEvents := make(chan StreamEvent, 10)
	callback := func(event StreamEvent) {
		receivedEvents <- event
	}

	manager.Subscribe(CategorySystem, callback)

	// Send events with different priorities
	lowEvent := StreamEvent{
		ID:       "low-1",
		Type:     "test_event",
		Category: CategorySystem,
		Priority: PriorityLow,
		Timestamp: time.Now(),
		Source:   "test",
	}

	highEvent := StreamEvent{
		ID:       "high-1",
		Type:     "test_event",
		Category: CategorySystem,
		Priority: PriorityHigh,
		Timestamp: time.Now(),
		Source:   "test",
	}

	// Send low priority first, then high priority
	require.NoError(t, manager.ProcessEvent(lowEvent))
	require.NoError(t, manager.ProcessEvent(highEvent))

	// High priority event should be processed first
	select {
	case receivedEvent := <-receivedEvents:
		assert.Equal(t, "high-1", receivedEvent.ID)
	case <-time.After(100 * time.Millisecond):
		t.Fatal("High priority event not received")
	}
}

func TestEventBatching(t *testing.T) {
	config := StreamConfig{
		BufferSize:     100,
		FlushInterval:  10 * time.Millisecond,
		EnableBatching: true,
		BatchSize:      3,
		BatchTimeout:   50 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Subscribe to events
	batchReceived := make(chan []StreamEvent, 10)
	callback := func(batch []StreamEvent) {
		batchReceived <- batch
	}

	manager.SubscribeBatch(CategorySystem, callback)

	// Send multiple events
	for i := 0; i < 3; i++ {
		event := StreamEvent{
			ID:       fmt.Sprintf("test-%d", i),
			Type:     "test_event",
			Category: CategorySystem,
			Priority: PriorityNormal,
			Timestamp: time.Now(),
			Source:   "test",
		}
		require.NoError(t, manager.ProcessEvent(event))
	}

	// Should receive batch
	select {
	case batch := <-batchReceived:
		assert.Len(t, batch, 3)
		assert.Equal(t, "test-0", batch[0].ID)
		assert.Equal(t, "test-1", batch[1].ID)
		assert.Equal(t, "test-2", batch[2].ID)
	case <-time.After(100 * time.Millisecond):
		t.Fatal("Batch not received")
	}
}

func TestEventCompression(t *testing.T) {
	config := StreamConfig{
		BufferSize:        100,
		FlushInterval:     10 * time.Millisecond,
		EnableCompression: true,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Create large event payload
	largePayload := make(map[string]interface{})
	largePayload["data"] = strings.Repeat("test data ", 1000)

	event := StreamEvent{
		ID:       "large-event",
		Type:     "test_event",
		Category: CategorySystem,
		Priority: PriorityNormal,
		Payload:  largePayload,
		Timestamp: time.Now(),
		Source:   "test",
	}

	// Process large event
	err := manager.ProcessEvent(event)
	assert.NoError(t, err)

	// Verify compression stats
	time.Sleep(20 * time.Millisecond)
	stats := manager.GetStats()
	assert.Greater(t, stats.CompressionRatio, 0.0)
}

func TestEventBuffer(t *testing.T) {
	config := StreamConfig{
		BufferSize:    3, // Small buffer for testing
		FlushInterval: 10 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Fill buffer beyond capacity
	for i := 0; i < 5; i++ {
		event := StreamEvent{
			ID:       fmt.Sprintf("test-%d", i),
			Type:     "test_event",
			Category: CategorySystem,
			Priority: PriorityNormal,
			Timestamp: time.Now(),
			Source:   "test",
		}

		err := manager.ProcessEvent(event)
		if i < 3 {
			assert.NoError(t, err)
		} else {
			// Buffer should be full
			assert.Error(t, err)
		}
	}
}

func TestEventStats(t *testing.T) {
	config := StreamConfig{
		BufferSize:    100,
		FlushInterval: 10 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Initial stats
	stats := manager.GetStats()
	assert.Equal(t, uint64(0), stats.EventsProcessed)
	assert.Equal(t, uint64(0), stats.EventsDropped)

	// Process some events
	for i := 0; i < 3; i++ {
		event := StreamEvent{
			ID:       fmt.Sprintf("test-%d", i),
			Type:     "test_event",
			Category: CategorySystem,
			Priority: PriorityNormal,
			Timestamp: time.Now(),
			Source:   "test",
		}
		require.NoError(t, manager.ProcessEvent(event))
	}

	time.Sleep(20 * time.Millisecond)

	// Check updated stats
	stats = manager.GetStats()
	assert.Equal(t, uint64(3), stats.EventsProcessed)
	assert.Greater(t, stats.TotalEventSize, uint64(0))
	assert.Greater(t, stats.AverageEventSize, uint64(0))
}

func TestConcurrentEventProcessing(t *testing.T) {
	config := StreamConfig{
		BufferSize:    1000,
		FlushInterval: 10 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Process events concurrently
	var wg sync.WaitGroup
	successCount := int64(0)
	errorCount := int64(0)

	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			event := StreamEvent{
				ID:       fmt.Sprintf("concurrent-%d", index),
				Type:     "test_event",
				Category: CategorySystem,
				Priority: PriorityNormal,
				Timestamp: time.Now(),
				Source:   "test",
			}

			err := manager.ProcessEvent(event)
			if err != nil {
				atomic.AddInt64(&errorCount, 1)
			} else {
				atomic.AddInt64(&successCount, 1)
			}
		}(i)
	}

	wg.Wait()

	// Most events should succeed
	assert.Greater(t, atomic.LoadInt64(&successCount), int64(90))
	assert.LessOrEqual(t, atomic.LoadInt64(&errorCount), int64(10))
}

func TestEventCleanup(t *testing.T) {
	config := StreamConfig{
		BufferSize:    100,
		FlushInterval: 10 * time.Millisecond,
		MaxEventAge:   50 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	require.NoError(t, manager.Start())
	defer manager.Stop()

	// Add old event
	oldEvent := StreamEvent{
		ID:       "old-event",
		Type:     "test_event",
		Category: CategorySystem,
		Priority: PriorityNormal,
		Timestamp: time.Now().Add(-100 * time.Millisecond),
		Source:   "test",
	}

	require.NoError(t, manager.ProcessEvent(oldEvent))

	// Wait for cleanup
	time.Sleep(100 * time.Millisecond)

	// Check that old events were cleaned up
	stats := manager.GetStats()
	assert.Greater(t, stats.EventsCleaned, uint64(0))
}

func BenchmarkEventProcessing(b *testing.B) {
	config := StreamConfig{
		BufferSize:    10000,
		FlushInterval: 100 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	manager.Start()
	defer manager.Stop()

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			event := StreamEvent{
				ID:       "benchmark-event",
				Type:     "test_event",
				Category: CategorySystem,
				Priority: PriorityNormal,
				Payload:  map[string]interface{}{"data": "test"},
				Timestamp: time.Now(),
				Source:   "benchmark",
			}

			err := manager.ProcessEvent(event)
			if err != nil {
				b.Error(err)
			}
		}
	})
}

func BenchmarkEventSubscription(b *testing.B) {
	config := StreamConfig{
		BufferSize:    10000,
		FlushInterval: 100 * time.Millisecond,
	}

	manager := NewEventStreamManager(config)
	manager.Start()
	defer manager.Stop()

	// Subscribe to events
	callback := func(event StreamEvent) {
		// Minimal processing
	}

	manager.Subscribe(CategorySystem, callback)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		event := StreamEvent{
			ID:       fmt.Sprintf("bench-%d", i),
			Type:     "test_event",
			Category: CategorySystem,
			Priority: PriorityNormal,
			Timestamp: time.Now(),
			Source:   "benchmark",
		}

		err := manager.ProcessEvent(event)
		if err != nil {
			b.Error(err)
		}
	}
}

import (
	"fmt"
	"strings"
)