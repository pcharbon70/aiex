package events

import (
	"fmt"
	"sync"
	"time"
)

// EventProcessor handles event processing, categorization, and batching
type EventProcessor struct {
	categorizer *EventCategorizer
	batcher     *EventBatcher
	debouncer   *EventDebouncer
	middleware  []EventMiddleware
	metrics     *ProcessorMetrics
	config      ProcessorConfig
	mutex       sync.RWMutex
}

// EventCategorizer categorizes events based on type and content
type EventCategorizer struct {
	rules     []CategorizationRule
	defaults  map[string]EventCategory
	mutex     sync.RWMutex
}

// EventBatcher groups events for batch processing
type EventBatcher struct {
	batches      map[string]*EventBatch
	batchSize    int
	batchTimeout time.Duration
	mutex        sync.RWMutex
}

// EventDebouncer prevents duplicate events within a time window
type EventDebouncer struct {
	window    time.Duration
	entries   map[string]time.Time
	rules     []DebounceRule
	mutex     sync.RWMutex
}

// EventMiddleware defines the interface for event processing middleware
type EventMiddleware interface {
	ProcessEvent(event StreamEvent, next func(StreamEvent) StreamEvent) StreamEvent
}

// CategorizationRule defines how to categorize events
type CategorizationRule struct {
	Name      string                           `json:"name"`
	Priority  int                              `json:"priority"`
	Condition func(StreamEvent) bool           `json:"-"`
	Category  EventCategory                    `json:"category"`
	Tags      []string                         `json:"tags"`
}

// DebounceRule defines debouncing behavior for specific event types
type DebounceRule struct {
	EventType    string        `json:"event_type"`
	Category     EventCategory `json:"category"`
	Window       time.Duration `json:"window"`
	KeyExtractor func(StreamEvent) string `json:"-"`
}

// EventBatch represents a batch of related events
type EventBatch struct {
	ID        string        `json:"id"`
	Events    []StreamEvent `json:"events"`
	Category  EventCategory `json:"category"`
	CreatedAt time.Time     `json:"created_at"`
	UpdatedAt time.Time     `json:"updated_at"`
	Timeout   time.Duration `json:"timeout"`
}

// ProcessorConfig configures the event processor
type ProcessorConfig struct {
	EnableCategorization bool          `json:"enable_categorization"`
	EnableBatching       bool          `json:"enable_batching"`
	EnableDebouncing     bool          `json:"enable_debouncing"`
	BatchSize            int           `json:"batch_size"`
	BatchTimeout         time.Duration `json:"batch_timeout"`
	DebounceWindow       time.Duration `json:"debounce_window"`
	MaxConcurrentBatches int           `json:"max_concurrent_batches"`
}

// ProcessorMetrics tracks processor performance
type ProcessorMetrics struct {
	EventsProcessed    int64         `json:"events_processed"`
	EventsCategorized  int64         `json:"events_categorized"`
	EventsBatched      int64         `json:"events_batched"`
	EventsDebounced    int64         `json:"events_debounced"`
	BatchesCreated     int64         `json:"batches_created"`
	BatchesCompleted   int64         `json:"batches_completed"`
	AverageProcessTime time.Duration `json:"average_process_time"`
	mutex              sync.RWMutex
}

// NewEventProcessor creates a new event processor
func NewEventProcessor() *EventProcessor {
	config := ProcessorConfig{
		EnableCategorization: true,
		EnableBatching:       true,
		EnableDebouncing:     true,
		BatchSize:            10,
		BatchTimeout:         50 * time.Millisecond,
		DebounceWindow:       100 * time.Millisecond,
		MaxConcurrentBatches: 10,
	}
	
	return &EventProcessor{
		categorizer: NewEventCategorizer(),
		batcher:     NewEventBatcher(config.BatchSize, config.BatchTimeout),
		debouncer:   NewEventDebouncer(config.DebounceWindow),
		middleware:  make([]EventMiddleware, 0),
		metrics:     NewProcessorMetrics(),
		config:      config,
	}
}

// ProcessEvent processes a single event through the pipeline
func (ep *EventProcessor) ProcessEvent(event StreamEvent) StreamEvent {
	startTime := time.Now()
	
	ep.mutex.RLock()
	middleware := make([]EventMiddleware, len(ep.middleware))
	copy(middleware, ep.middleware)
	ep.mutex.RUnlock()
	
	// Create middleware chain
	processFunc := func(e StreamEvent) StreamEvent {
		return e
	}
	
	// Apply middleware in reverse order
	for i := len(middleware) - 1; i >= 0; i-- {
		mw := middleware[i]
		nextFunc := processFunc
		processFunc = func(e StreamEvent) StreamEvent {
			return mw.ProcessEvent(e, nextFunc)
		}
	}
	
	// Apply core processing
	coreFunc := processFunc
	processFunc = func(e StreamEvent) StreamEvent {
		return ep.coreProcessing(coreFunc(e))
	}
	
	// Process the event
	processedEvent := processFunc(event)
	
	// Update metrics
	processingTime := time.Since(startTime)
	ep.metrics.updateProcessTime(processingTime)
	ep.metrics.incrementProcessed()
	
	return processedEvent
}

// coreProcessing handles the core event processing logic
func (ep *EventProcessor) coreProcessing(event StreamEvent) StreamEvent {
	// Categorize event
	if ep.config.EnableCategorization {
		event.Category = ep.categorizer.CategorizeEvent(event)
		ep.metrics.incrementCategorized()
	}
	
	// Add processing metadata
	if event.Metadata == nil {
		event.Metadata = make(map[string]interface{})
	}
	event.Metadata["processed_at"] = time.Now()
	event.Metadata["processor_version"] = "1.0"
	
	return event
}

// AddMiddleware adds middleware to the processing pipeline
func (ep *EventProcessor) AddMiddleware(middleware EventMiddleware) {
	ep.mutex.Lock()
	defer ep.mutex.Unlock()
	ep.middleware = append(ep.middleware, middleware)
}

// RemoveMiddleware removes middleware from the processing pipeline
func (ep *EventProcessor) RemoveMiddleware(middleware EventMiddleware) {
	ep.mutex.Lock()
	defer ep.mutex.Unlock()
	
	for i, mw := range ep.middleware {
		if mw == middleware {
			ep.middleware = append(ep.middleware[:i], ep.middleware[i+1:]...)
			break
		}
	}
}

// GetMetrics returns current processor metrics
func (ep *EventProcessor) GetMetrics() ProcessorMetrics {
	ep.metrics.mutex.RLock()
	defer ep.metrics.mutex.RUnlock()
	return *ep.metrics
}

// NewEventCategorizer creates a new event categorizer
func NewEventCategorizer() *EventCategorizer {
	categorizer := &EventCategorizer{
		rules:    make([]CategorizationRule, 0),
		defaults: make(map[string]EventCategory),
	}
	
	// Add default categorization rules
	categorizer.addDefaultRules()
	
	return categorizer
}

// CategorizeEvent categorizes an event based on rules
func (ec *EventCategorizer) CategorizeEvent(event StreamEvent) EventCategory {
	ec.mutex.RLock()
	defer ec.mutex.RUnlock()
	
	// Check rules in priority order
	for _, rule := range ec.rules {
		if rule.Condition(event) {
			return rule.Category
		}
	}
	
	// Check default mappings
	if category, exists := ec.defaults[event.Type]; exists {
		return category
	}
	
	// Default category
	return CategorySystem
}

// AddRule adds a categorization rule
func (ec *EventCategorizer) AddRule(rule CategorizationRule) {
	ec.mutex.Lock()
	defer ec.mutex.Unlock()
	
	// Insert rule in priority order
	inserted := false
	for i, existingRule := range ec.rules {
		if rule.Priority > existingRule.Priority {
			ec.rules = append(ec.rules[:i], append([]CategorizationRule{rule}, ec.rules[i:]...)...)
			inserted = true
			break
		}
	}
	
	if !inserted {
		ec.rules = append(ec.rules, rule)
	}
}

// addDefaultRules adds default categorization rules
func (ec *EventCategorizer) addDefaultRules() {
	// UI update events
	ec.AddRule(CategorizationRule{
		Name:     "UI Updates",
		Priority: 100,
		Condition: func(event StreamEvent) bool {
			return event.Type == "ui_update" || event.Type == "focus_change" || event.Type == "panel_resize"
		},
		Category: CategoryUIUpdate,
	})
	
	// AI response events
	ec.AddRule(CategorizationRule{
		Name:     "AI Responses",
		Priority: 90,
		Condition: func(event StreamEvent) bool {
			return event.Type == "ai_response" || event.Type == "ai_streaming" || event.Type == "ai_suggestion"
		},
		Category: CategoryAIResponse,
	})
	
	// File system events
	ec.AddRule(CategorizationRule{
		Name:     "File System",
		Priority: 80,
		Condition: func(event StreamEvent) bool {
			return event.Type == "file_change" || event.Type == "file_created" || event.Type == "file_deleted"
		},
		Category: CategoryFileSystem,
	})
	
	// Error events
	ec.AddRule(CategorizationRule{
		Name:     "Errors",
		Priority: 95,
		Condition: func(event StreamEvent) bool {
			return event.Type == "error" || event.Type == "warning" || 
				   (event.Metadata != nil && event.Metadata["error"] != nil)
		},
		Category: CategoryError,
	})
	
	// User interaction events
	ec.AddRule(CategorizationRule{
		Name:     "User Interactions",
		Priority: 85,
		Condition: func(event StreamEvent) bool {
			return event.Type == "key_press" || event.Type == "mouse_click" || event.Type == "user_input"
		},
		Category: CategoryUser,
	})
	
	// Network events
	ec.AddRule(CategorizationRule{
		Name:     "Network",
		Priority: 70,
		Condition: func(event StreamEvent) bool {
			return event.Type == "connection_lost" || event.Type == "connection_established" || event.Type == "network_error"
		},
		Category: CategoryNetwork,
	})
}

// NewEventBatcher creates a new event batcher
func NewEventBatcher(batchSize int, batchTimeout time.Duration) *EventBatcher {
	return &EventBatcher{
		batches:      make(map[string]*EventBatch),
		batchSize:    batchSize,
		batchTimeout: batchTimeout,
	}
}

// ShouldBatch determines if an event should be batched
func (eb *EventBatcher) ShouldBatch(event StreamEvent) bool {
	// Batch certain types of events
	batchableTypes := map[string]bool{
		"ui_update":      true,
		"file_change":    true,
		"ai_streaming":   true,
		"state_update":   true,
	}
	
	return batchableTypes[event.Type]
}

// AddToBatch adds an event to a batch, returns completed batch if any
func (eb *EventBatcher) AddToBatch(event StreamEvent) []StreamEvent {
	eb.mutex.Lock()
	defer eb.mutex.Unlock()
	
	batchKey := fmt.Sprintf("%s_%d", event.Type, event.Category)
	
	batch, exists := eb.batches[batchKey]
	if !exists {
		batch = &EventBatch{
			ID:        fmt.Sprintf("batch_%s_%d", batchKey, time.Now().UnixNano()),
			Events:    make([]StreamEvent, 0, eb.batchSize),
			Category:  event.Category,
			CreatedAt: time.Now(),
			Timeout:   eb.batchTimeout,
		}
		eb.batches[batchKey] = batch
		
		// Start timeout timer
		go eb.handleBatchTimeout(batchKey, batch.ID)
	}
	
	batch.Events = append(batch.Events, event)
	batch.UpdatedAt = time.Now()
	
	// Check if batch is complete
	if len(batch.Events) >= eb.batchSize {
		completedBatch := batch.Events
		delete(eb.batches, batchKey)
		return completedBatch
	}
	
	return nil
}

// handleBatchTimeout handles batch timeout
func (eb *EventBatcher) handleBatchTimeout(batchKey, batchID string) {
	time.Sleep(eb.batchTimeout)
	
	eb.mutex.Lock()
	defer eb.mutex.Unlock()
	
	if batch, exists := eb.batches[batchKey]; exists && batch.ID == batchID {
		// Batch still exists and hasn't been completed, flush it
		if len(batch.Events) > 0 {
			// This would normally trigger completion via a callback
			// For now, we just remove it
			delete(eb.batches, batchKey)
		}
	}
}

// UpdateConfig updates the batcher configuration
func (eb *EventBatcher) UpdateConfig(batchSize int, timeout time.Duration) {
	eb.mutex.Lock()
	defer eb.mutex.Unlock()
	
	eb.batchSize = batchSize
	eb.batchTimeout = timeout
}

// NewEventDebouncer creates a new event debouncer
func NewEventDebouncer(window time.Duration) *EventDebouncer {
	debouncer := &EventDebouncer{
		window:  window,
		entries: make(map[string]time.Time),
		rules:   make([]DebounceRule, 0),
	}
	
	// Add default debounce rules
	debouncer.addDefaultRules()
	
	return debouncer
}

// ShouldDebounce determines if an event should be debounced
func (ed *EventDebouncer) ShouldDebounce(event StreamEvent) bool {
	ed.mutex.Lock()
	defer ed.mutex.Unlock()
	
	// Check debounce rules
	for _, rule := range ed.rules {
		if rule.EventType == event.Type || rule.Category == event.Category {
			key := rule.KeyExtractor(event)
			if lastTime, exists := ed.entries[key]; exists {
				if time.Since(lastTime) < rule.Window {
					return true
				}
			}
			ed.entries[key] = time.Now()
			return false
		}
	}
	
	// Default debouncing
	key := fmt.Sprintf("%s_%s", event.Type, event.Source)
	if lastTime, exists := ed.entries[key]; exists {
		if time.Since(lastTime) < ed.window {
			return true
		}
	}
	
	ed.entries[key] = time.Now()
	return false
}

// addDefaultRules adds default debounce rules
func (ed *EventDebouncer) addDefaultRules() {
	// Debounce UI updates
	ed.rules = append(ed.rules, DebounceRule{
		EventType: "ui_update",
		Category:  CategoryUIUpdate,
		Window:    50 * time.Millisecond,
		KeyExtractor: func(event StreamEvent) string {
			return fmt.Sprintf("ui_%s", event.Source)
		},
	})
	
	// Debounce file changes
	ed.rules = append(ed.rules, DebounceRule{
		EventType: "file_change",
		Category:  CategoryFileSystem,
		Window:    200 * time.Millisecond,
		KeyExtractor: func(event StreamEvent) string {
			if path, ok := event.Metadata["path"].(string); ok {
				return fmt.Sprintf("file_%s", path)
			}
			return fmt.Sprintf("file_%s", event.Source)
		},
	})
}

// UpdateWindow updates the debounce window
func (ed *EventDebouncer) UpdateWindow(window time.Duration) {
	ed.mutex.Lock()
	defer ed.mutex.Unlock()
	ed.window = window
}

// CleanupOldEntries removes old debounce entries
func (ed *EventDebouncer) CleanupOldEntries() {
	ed.mutex.Lock()
	defer ed.mutex.Unlock()
	
	cutoff := time.Now().Add(-ed.window * 2)
	for key, timestamp := range ed.entries {
		if timestamp.Before(cutoff) {
			delete(ed.entries, key)
		}
	}
}

// ProcessorMetrics methods
func NewProcessorMetrics() *ProcessorMetrics {
	return &ProcessorMetrics{}
}

func (pm *ProcessorMetrics) incrementProcessed() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	pm.EventsProcessed++
}

func (pm *ProcessorMetrics) incrementCategorized() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	pm.EventsCategorized++
}

func (pm *ProcessorMetrics) incrementBatched() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	pm.EventsBatched++
}

func (pm *ProcessorMetrics) incrementDebounced() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	pm.EventsDebounced++
}

func (pm *ProcessorMetrics) updateProcessTime(duration time.Duration) {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	
	if pm.AverageProcessTime == 0 {
		pm.AverageProcessTime = duration
	} else {
		pm.AverageProcessTime = (pm.AverageProcessTime + duration) / 2
	}
}

// Example middleware implementations
type LoggingMiddleware struct {
	logger func(string)
}

func (lm *LoggingMiddleware) ProcessEvent(event StreamEvent, next func(StreamEvent) StreamEvent) StreamEvent {
	lm.logger(fmt.Sprintf("Processing event: %s (type: %s)", event.ID, event.Type))
	result := next(event)
	lm.logger(fmt.Sprintf("Completed event: %s", event.ID))
	return result
}

type EnrichmentMiddleware struct {
	enrichers map[string]func(StreamEvent) StreamEvent
}

func (em *EnrichmentMiddleware) ProcessEvent(event StreamEvent, next func(StreamEvent) StreamEvent) StreamEvent {
	if enricher, exists := em.enrichers[event.Type]; exists {
		event = enricher(event)
	}
	return next(event)
}

type ValidationMiddleware struct {
	validators map[string]func(StreamEvent) error
}

func (vm *ValidationMiddleware) ProcessEvent(event StreamEvent, next func(StreamEvent) StreamEvent) StreamEvent {
	if validator, exists := vm.validators[event.Type]; exists {
		if err := validator(event); err != nil {
			// Add error to metadata
			if event.Metadata == nil {
				event.Metadata = make(map[string]interface{})
			}
			event.Metadata["validation_error"] = err.Error()
		}
	}
	return next(event)
}