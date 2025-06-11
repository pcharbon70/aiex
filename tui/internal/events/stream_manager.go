package events

import (
	"context"
	"fmt"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// EventStreamManager handles sophisticated event stream processing with buffering and rate limiting
type EventStreamManager struct {
	// Core components
	buffer       *CircularEventBuffer
	rateLimiter  *AdaptiveRateController
	processor    *EventProcessor
	categorizer  *EventCategorizer
	batcher      *EventBatcher
	debouncer    *EventDebouncer
	
	// State management
	running      bool
	paused       bool
	metrics      *StreamMetrics
	config       StreamConfig
	
	// Synchronization
	mutex        sync.RWMutex
	ctx          context.Context
	cancel       context.CancelFunc
	
	// Communication
	inputChan    chan StreamEvent
	outputChan   chan tea.Cmd
	program      *tea.Program
}

// StreamEvent represents an event in the stream with metadata
type StreamEvent struct {
	ID          string                 `json:"id"`
	Type        string                 `json:"type"`
	Category    EventCategory          `json:"category"`
	Priority    EventPriority          `json:"priority"`
	Payload     interface{}            `json:"payload"`
	Metadata    map[string]interface{} `json:"metadata"`
	Timestamp   time.Time              `json:"timestamp"`
	Source      string                 `json:"source"`
	ProcessedAt time.Time              `json:"processed_at,omitempty"`
	Latency     time.Duration          `json:"latency,omitempty"`
}

// EventCategory categorizes events for processing
type EventCategory int

const (
	CategoryUIUpdate EventCategory = iota
	CategoryAIResponse
	CategoryFileSystem
	CategoryStateChange
	CategoryError
	CategorySystem
	CategoryNetwork
	CategoryUser
)

// EventPriority defines event processing priority
type EventPriority int

const (
	PriorityLow EventPriority = iota
	PriorityNormal
	PriorityHigh
	PriorityCritical
)

// StreamConfig configures the event stream manager
type StreamConfig struct {
	BufferSize           int           `json:"buffer_size"`
	MaxEventsPerSecond   int           `json:"max_events_per_second"`
	DebounceWindow       time.Duration `json:"debounce_window"`
	BatchSize            int           `json:"batch_size"`
	BatchTimeout         time.Duration `json:"batch_timeout"`
	AdaptiveRateLimit    bool          `json:"adaptive_rate_limit"`
	BackpressureEnabled  bool          `json:"backpressure_enabled"`
	MetricsEnabled       bool          `json:"metrics_enabled"`
	ProcessingTimeout    time.Duration `json:"processing_timeout"`
}

// StreamMetrics tracks performance and health metrics
type StreamMetrics struct {
	EventsReceived       int64         `json:"events_received"`
	EventsProcessed      int64         `json:"events_processed"`
	EventsDropped        int64         `json:"events_dropped"`
	EventsBatched        int64         `json:"events_batched"`
	EventsDebounced      int64         `json:"events_debounced"`
	AverageLatency       time.Duration `json:"average_latency"`
	PeakLatency          time.Duration `json:"peak_latency"`
	BufferUtilization    float64       `json:"buffer_utilization"`
	ProcessingRate       float64       `json:"processing_rate"`
	LastProcessedAt      time.Time     `json:"last_processed_at"`
	ErrorCount           int64         `json:"error_count"`
	BackpressureActive   bool          `json:"backpressure_active"`
	mutex                sync.RWMutex
}

// NewEventStreamManager creates a new event stream manager
func NewEventStreamManager(config StreamConfig) *EventStreamManager {
	ctx, cancel := context.WithCancel(context.Background())
	
	if config.BufferSize == 0 {
		config.BufferSize = 1000
	}
	if config.MaxEventsPerSecond == 0 {
		config.MaxEventsPerSecond = 100
	}
	if config.DebounceWindow == 0 {
		config.DebounceWindow = 100 * time.Millisecond
	}
	if config.BatchSize == 0 {
		config.BatchSize = 10
	}
	if config.BatchTimeout == 0 {
		config.BatchTimeout = 50 * time.Millisecond
	}
	if config.ProcessingTimeout == 0 {
		config.ProcessingTimeout = 5 * time.Second
	}
	
	esm := &EventStreamManager{
		buffer:      NewCircularEventBuffer(config.BufferSize),
		rateLimiter: NewAdaptiveRateController(config.MaxEventsPerSecond, config.AdaptiveRateLimit),
		processor:   NewEventProcessor(),
		categorizer: NewEventCategorizer(),
		batcher:     NewEventBatcher(config.BatchSize, config.BatchTimeout),
		debouncer:   NewEventDebouncer(config.DebounceWindow),
		running:     false,
		paused:      false,
		metrics:     NewStreamMetrics(),
		config:      config,
		ctx:         ctx,
		cancel:      cancel,
		inputChan:   make(chan StreamEvent, config.BufferSize),
		outputChan:  make(chan tea.Cmd, config.BufferSize),
	}
	
	return esm
}

// Start begins event stream processing
func (esm *EventStreamManager) Start(program *tea.Program) error {
	esm.mutex.Lock()
	defer esm.mutex.Unlock()
	
	if esm.running {
		return fmt.Errorf("event stream manager already running")
	}
	
	esm.program = program
	esm.running = true
	
	// Start processing goroutines
	go esm.eventProcessingLoop()
	go esm.outputProcessingLoop()
	go esm.metricsUpdateLoop()
	
	return nil
}

// Stop halts event stream processing
func (esm *EventStreamManager) Stop() error {
	esm.mutex.Lock()
	defer esm.mutex.Unlock()
	
	if !esm.running {
		return fmt.Errorf("event stream manager not running")
	}
	
	esm.running = false
	esm.cancel()
	
	// Close channels
	close(esm.inputChan)
	close(esm.outputChan)
	
	return nil
}

// ProcessEvent adds an event to the processing stream
func (esm *EventStreamManager) ProcessEvent(event StreamEvent) error {
	esm.mutex.RLock()
	defer esm.mutex.RUnlock()
	
	if !esm.running {
		return fmt.Errorf("event stream manager not running")
	}
	
	if esm.paused {
		esm.metrics.incrementDropped()
		return fmt.Errorf("event stream manager paused")
	}
	
	// Check rate limiting
	if !esm.rateLimiter.AllowEvent(event) {
		esm.metrics.incrementDropped()
		return fmt.Errorf("event rate limited")
	}
	
	// Add timestamp if not present
	if event.Timestamp.IsZero() {
		event.Timestamp = time.Now()
	}
	
	// Generate ID if not present
	if event.ID == "" {
		event.ID = esm.generateEventID()
	}
	
	// Categorize event
	event.Category = esm.categorizer.CategorizeEvent(event)
	
	// Add to metrics
	esm.metrics.incrementReceived()
	
	// Send to processing channel
	select {
	case esm.inputChan <- event:
		return nil
	default:
		// Channel full, apply backpressure
		if esm.config.BackpressureEnabled {
			esm.metrics.setBackpressureActive(true)
			return esm.handleBackpressure(event)
		}
		esm.metrics.incrementDropped()
		return fmt.Errorf("event buffer full")
	}
}

// eventProcessingLoop is the main event processing loop
func (esm *EventStreamManager) eventProcessingLoop() {
	defer func() {
		if r := recover(); r != nil {
			esm.metrics.incrementErrors()
		}
	}()
	
	for {
		select {
		case <-esm.ctx.Done():
			return
			
		case event, ok := <-esm.inputChan:
			if !ok {
				return
			}
			
			esm.processEventInternal(event)
		}
	}
}

// processEventInternal handles individual event processing
func (esm *EventStreamManager) processEventInternal(event StreamEvent) {
	startTime := time.Now()
	
	// Add to buffer for replay/debugging
	esm.buffer.Add(event)
	
	// Check if event should be debounced
	if esm.debouncer.ShouldDebounce(event) {
		esm.metrics.incrementDebounced()
		return
	}
	
	// Process through categorization
	processedEvent := esm.processor.ProcessEvent(event)
	processedEvent.ProcessedAt = time.Now()
	processedEvent.Latency = time.Since(startTime)
	
	// Update metrics
	esm.metrics.updateLatency(processedEvent.Latency)
	esm.metrics.incrementProcessed()
	
	// Check if event should be batched
	if esm.batcher.ShouldBatch(processedEvent) {
		batch := esm.batcher.AddToBatch(processedEvent)
		if batch != nil {
			esm.sendBatchToUI(batch)
		}
	} else {
		esm.sendEventToUI(processedEvent)
	}
}

// sendEventToUI sends a single event to the UI
func (esm *EventStreamManager) sendEventToUI(event StreamEvent) {
	cmd := esm.createUICommand(event)
	
	select {
	case esm.outputChan <- cmd:
		// Event sent successfully
	default:
		// Output channel full, drop event
		esm.metrics.incrementDropped()
	}
}

// sendBatchToUI sends a batch of events to the UI
func (esm *EventStreamManager) sendBatchToUI(batch []StreamEvent) {
	esm.metrics.addBatched(int64(len(batch)))
	
	cmd := esm.createBatchUICommand(batch)
	
	select {
	case esm.outputChan <- cmd:
		// Batch sent successfully
	default:
		// Output channel full, drop batch
		esm.metrics.incrementDropped()
	}
}

// outputProcessingLoop sends processed events to the UI
func (esm *EventStreamManager) outputProcessingLoop() {
	for {
		select {
		case <-esm.ctx.Done():
			return
			
		case cmd, ok := <-esm.outputChan:
			if !ok {
				return
			}
			
			if esm.program != nil {
				esm.program.Send(cmd)
			}
		}
	}
}

// metricsUpdateLoop periodically updates metrics
func (esm *EventStreamManager) metricsUpdateLoop() {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()
	
	for {
		select {
		case <-esm.ctx.Done():
			return
			
		case <-ticker.C:
			esm.updateMetrics()
		}
	}
}

// updateMetrics calculates and updates performance metrics
func (esm *EventStreamManager) updateMetrics() {
	esm.metrics.mutex.Lock()
	defer esm.metrics.mutex.Unlock()
	
	// Update buffer utilization
	utilization := float64(esm.buffer.Size()) / float64(esm.buffer.Capacity())
	esm.metrics.BufferUtilization = utilization
	
	// Update processing rate
	if esm.metrics.LastProcessedAt.IsZero() {
		esm.metrics.ProcessingRate = 0
	} else {
		duration := time.Since(esm.metrics.LastProcessedAt)
		if duration > 0 {
			esm.metrics.ProcessingRate = float64(esm.metrics.EventsProcessed) / duration.Seconds()
		}
	}
	
	// Check if backpressure should be released
	if esm.metrics.BackpressureActive && utilization < 0.7 {
		esm.metrics.setBackpressureActive(false)
	}
}

// handleBackpressure implements backpressure handling strategies
func (esm *EventStreamManager) handleBackpressure(event StreamEvent) error {
	// Strategy 1: Drop low priority events
	if event.Priority == PriorityLow {
		esm.metrics.incrementDropped()
		return fmt.Errorf("low priority event dropped due to backpressure")
	}
	
	// Strategy 2: Buffer high priority events briefly
	if event.Priority >= PriorityHigh {
		// Try to make space by processing one event immediately
		select {
		case oldEvent := <-esm.inputChan:
			esm.processEventInternal(oldEvent)
			esm.inputChan <- event
			return nil
		default:
			// No space available
		}
	}
	
	esm.metrics.incrementDropped()
	return fmt.Errorf("event dropped due to backpressure")
}

// createUICommand creates a Bubble Tea command from an event
func (esm *EventStreamManager) createUICommand(event StreamEvent) tea.Cmd {
	return func() tea.Msg {
		return UIEventMsg{
			Event:     event,
			Timestamp: time.Now(),
		}
	}
}

// createBatchUICommand creates a Bubble Tea command from a batch of events
func (esm *EventStreamManager) createBatchUICommand(batch []StreamEvent) tea.Cmd {
	return func() tea.Msg {
		return UIBatchEventMsg{
			Events:    batch,
			Timestamp: time.Now(),
		}
	}
}

// generateEventID generates a unique event ID
func (esm *EventStreamManager) generateEventID() string {
	return fmt.Sprintf("evt_%d_%d", time.Now().UnixNano(), esm.metrics.EventsReceived)
}

// Public API methods
func (esm *EventStreamManager) Pause() {
	esm.mutex.Lock()
	defer esm.mutex.Unlock()
	esm.paused = true
}

func (esm *EventStreamManager) Resume() {
	esm.mutex.Lock()
	defer esm.mutex.Unlock()
	esm.paused = false
}

func (esm *EventStreamManager) IsPaused() bool {
	esm.mutex.RLock()
	defer esm.mutex.RUnlock()
	return esm.paused
}

func (esm *EventStreamManager) IsRunning() bool {
	esm.mutex.RLock()
	defer esm.mutex.RUnlock()
	return esm.running
}

func (esm *EventStreamManager) GetMetrics() StreamMetrics {
	esm.metrics.mutex.RLock()
	defer esm.metrics.mutex.RUnlock()
	return *esm.metrics
}

func (esm *EventStreamManager) GetConfig() StreamConfig {
	esm.mutex.RLock()
	defer esm.mutex.RUnlock()
	return esm.config
}

func (esm *EventStreamManager) UpdateConfig(config StreamConfig) {
	esm.mutex.Lock()
	defer esm.mutex.Unlock()
	
	esm.config = config
	esm.rateLimiter.UpdateLimit(config.MaxEventsPerSecond)
	esm.batcher.UpdateConfig(config.BatchSize, config.BatchTimeout)
	esm.debouncer.UpdateWindow(config.DebounceWindow)
}

// StreamMetrics methods
func NewStreamMetrics() *StreamMetrics {
	return &StreamMetrics{
		LastProcessedAt: time.Now(),
	}
}

func (sm *StreamMetrics) incrementReceived() {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()
	sm.EventsReceived++
}

func (sm *StreamMetrics) incrementProcessed() {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()
	sm.EventsProcessed++
	sm.LastProcessedAt = time.Now()
}

func (sm *StreamMetrics) incrementDropped() {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()
	sm.EventsDropped++
}

func (sm *StreamMetrics) incrementDebounced() {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()
	sm.EventsDebounced++
}

func (sm *StreamMetrics) addBatched(count int64) {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()
	sm.EventsBatched += count
}

func (sm *StreamMetrics) incrementErrors() {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()
	sm.ErrorCount++
}

func (sm *StreamMetrics) updateLatency(latency time.Duration) {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()
	
	if latency > sm.PeakLatency {
		sm.PeakLatency = latency
	}
	
	// Simple moving average (could be improved with more sophisticated algorithm)
	if sm.AverageLatency == 0 {
		sm.AverageLatency = latency
	} else {
		sm.AverageLatency = (sm.AverageLatency + latency) / 2
	}
}

func (sm *StreamMetrics) setBackpressureActive(active bool) {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()
	sm.BackpressureActive = active
}

// Message types for UI integration
type UIEventMsg struct {
	Event     StreamEvent
	Timestamp time.Time
}

type UIBatchEventMsg struct {
	Events    []StreamEvent
	Timestamp time.Time
}

type StreamMetricsMsg struct {
	Metrics StreamMetrics
}