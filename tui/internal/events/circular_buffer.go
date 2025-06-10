package events

import (
	"sync"
	"time"
)

// CircularEventBuffer implements a thread-safe circular buffer for events
type CircularEventBuffer struct {
	buffer   []StreamEvent
	head     int
	tail     int
	size     int
	capacity int
	mutex    sync.RWMutex
	full     bool
}

// NewCircularEventBuffer creates a new circular event buffer
func NewCircularEventBuffer(capacity int) *CircularEventBuffer {
	return &CircularEventBuffer{
		buffer:   make([]StreamEvent, capacity),
		capacity: capacity,
		head:     0,
		tail:     0,
		size:     0,
		full:     false,
	}
}

// Add adds an event to the buffer (overwrites oldest if full)
func (ceb *CircularEventBuffer) Add(event StreamEvent) {
	ceb.mutex.Lock()
	defer ceb.mutex.Unlock()
	
	ceb.buffer[ceb.head] = event
	
	if ceb.full {
		// Buffer is full, move tail to maintain circular nature
		ceb.tail = (ceb.tail + 1) % ceb.capacity
	}
	
	ceb.head = (ceb.head + 1) % ceb.capacity
	
	if ceb.head == ceb.tail {
		ceb.full = true
	}
	
	if !ceb.full {
		ceb.size++
	}
}

// Get retrieves the most recent n events
func (ceb *CircularEventBuffer) Get(n int) []StreamEvent {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	
	if n <= 0 || ceb.size == 0 {
		return []StreamEvent{}
	}
	
	if n > ceb.size {
		n = ceb.size
	}
	
	events := make([]StreamEvent, n)
	start := ceb.head - n
	if start < 0 {
		start += ceb.capacity
	}
	
	for i := 0; i < n; i++ {
		index := (start + i) % ceb.capacity
		events[i] = ceb.buffer[index]
	}
	
	return events
}

// GetAll retrieves all events in chronological order
func (ceb *CircularEventBuffer) GetAll() []StreamEvent {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	
	if ceb.size == 0 {
		return []StreamEvent{}
	}
	
	events := make([]StreamEvent, ceb.size)
	
	if ceb.full {
		// Copy from tail to end, then from start to head
		for i := 0; i < ceb.capacity-ceb.tail; i++ {
			events[i] = ceb.buffer[ceb.tail+i]
		}
		for i := 0; i < ceb.head; i++ {
			events[ceb.capacity-ceb.tail+i] = ceb.buffer[i]
		}
	} else {
		// Copy from tail to head
		for i := 0; i < ceb.size; i++ {
			events[i] = ceb.buffer[(ceb.tail+i)%ceb.capacity]
		}
	}
	
	return events
}

// GetByTimeRange retrieves events within a time range
func (ceb *CircularEventBuffer) GetByTimeRange(start, end time.Time) []StreamEvent {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	
	var events []StreamEvent
	allEvents := ceb.getAllUnsafe()
	
	for _, event := range allEvents {
		if (event.Timestamp.After(start) || event.Timestamp.Equal(start)) &&
			(event.Timestamp.Before(end) || event.Timestamp.Equal(end)) {
			events = append(events, event)
		}
	}
	
	return events
}

// GetByCategory retrieves events of a specific category
func (ceb *CircularEventBuffer) GetByCategory(category EventCategory) []StreamEvent {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	
	var events []StreamEvent
	allEvents := ceb.getAllUnsafe()
	
	for _, event := range allEvents {
		if event.Category == category {
			events = append(events, event)
		}
	}
	
	return events
}

// GetByType retrieves events of a specific type
func (ceb *CircularEventBuffer) GetByType(eventType string) []StreamEvent {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	
	var events []StreamEvent
	allEvents := ceb.getAllUnsafe()
	
	for _, event := range allEvents {
		if event.Type == eventType {
			events = append(events, event)
		}
	}
	
	return events
}

// GetByPriority retrieves events of a specific priority or higher
func (ceb *CircularEventBuffer) GetByPriority(minPriority EventPriority) []StreamEvent {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	
	var events []StreamEvent
	allEvents := ceb.getAllUnsafe()
	
	for _, event := range allEvents {
		if event.Priority >= minPriority {
			events = append(events, event)
		}
	}
	
	return events
}

// Search searches for events matching a predicate function
func (ceb *CircularEventBuffer) Search(predicate func(StreamEvent) bool) []StreamEvent {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	
	var events []StreamEvent
	allEvents := ceb.getAllUnsafe()
	
	for _, event := range allEvents {
		if predicate(event) {
			events = append(events, event)
		}
	}
	
	return events
}

// Size returns the current number of events in the buffer
func (ceb *CircularEventBuffer) Size() int {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	return ceb.size
}

// Capacity returns the maximum capacity of the buffer
func (ceb *CircularEventBuffer) Capacity() int {
	return ceb.capacity
}

// IsFull returns true if the buffer is at capacity
func (ceb *CircularEventBuffer) IsFull() bool {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	return ceb.full
}

// IsEmpty returns true if the buffer is empty
func (ceb *CircularEventBuffer) IsEmpty() bool {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	return ceb.size == 0
}

// Utilization returns the buffer utilization as a percentage
func (ceb *CircularEventBuffer) Utilization() float64 {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	return float64(ceb.size) / float64(ceb.capacity)
}

// Clear removes all events from the buffer
func (ceb *CircularEventBuffer) Clear() {
	ceb.mutex.Lock()
	defer ceb.mutex.Unlock()
	
	ceb.head = 0
	ceb.tail = 0
	ceb.size = 0
	ceb.full = false
}

// Resize changes the buffer capacity (preserves most recent events)
func (ceb *CircularEventBuffer) Resize(newCapacity int) {
	ceb.mutex.Lock()
	defer ceb.mutex.Unlock()
	
	if newCapacity <= 0 {
		return
	}
	
	if newCapacity == ceb.capacity {
		return
	}
	
	// Get current events
	currentEvents := ceb.getAllUnsafe()
	
	// Create new buffer
	ceb.buffer = make([]StreamEvent, newCapacity)
	ceb.capacity = newCapacity
	ceb.head = 0
	ceb.tail = 0
	ceb.size = 0
	ceb.full = false
	
	// Add back events (most recent first if necessary)
	if len(currentEvents) > newCapacity {
		// Keep only the most recent events
		start := len(currentEvents) - newCapacity
		currentEvents = currentEvents[start:]
	}
	
	for _, event := range currentEvents {
		ceb.addUnsafe(event)
	}
}

// GetOldest returns the oldest event in the buffer
func (ceb *CircularEventBuffer) GetOldest() (StreamEvent, bool) {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	
	if ceb.size == 0 {
		return StreamEvent{}, false
	}
	
	return ceb.buffer[ceb.tail], true
}

// GetNewest returns the newest event in the buffer
func (ceb *CircularEventBuffer) GetNewest() (StreamEvent, bool) {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	
	if ceb.size == 0 {
		return StreamEvent{}, false
	}
	
	index := ceb.head - 1
	if index < 0 {
		index = ceb.capacity - 1
	}
	
	return ceb.buffer[index], true
}

// GetStats returns buffer statistics
func (ceb *CircularEventBuffer) GetStats() BufferStats {
	ceb.mutex.RLock()
	defer ceb.mutex.RUnlock()
	
	stats := BufferStats{
		Size:        ceb.size,
		Capacity:    ceb.capacity,
		Utilization: float64(ceb.size) / float64(ceb.capacity),
		IsFull:      ceb.full,
		IsEmpty:     ceb.size == 0,
	}
	
	if ceb.size > 0 {
		allEvents := ceb.getAllUnsafe()
		
		// Calculate time span
		oldest := allEvents[0].Timestamp
		newest := allEvents[len(allEvents)-1].Timestamp
		stats.TimeSpan = newest.Sub(oldest)
		
		// Count by category
		stats.CategoryCounts = make(map[EventCategory]int)
		for _, event := range allEvents {
			stats.CategoryCounts[event.Category]++
		}
		
		// Count by priority
		stats.PriorityCounts = make(map[EventPriority]int)
		for _, event := range allEvents {
			stats.PriorityCounts[event.Priority]++
		}
	}
	
	return stats
}

// BufferStats represents buffer statistics
type BufferStats struct {
	Size            int                         `json:"size"`
	Capacity        int                         `json:"capacity"`
	Utilization     float64                     `json:"utilization"`
	IsFull          bool                        `json:"is_full"`
	IsEmpty         bool                        `json:"is_empty"`
	TimeSpan        time.Duration               `json:"time_span"`
	CategoryCounts  map[EventCategory]int       `json:"category_counts"`
	PriorityCounts  map[EventPriority]int       `json:"priority_counts"`
}

// Internal helper methods
func (ceb *CircularEventBuffer) getAllUnsafe() []StreamEvent {
	if ceb.size == 0 {
		return []StreamEvent{}
	}
	
	events := make([]StreamEvent, ceb.size)
	
	if ceb.full {
		// Copy from tail to end, then from start to head
		for i := 0; i < ceb.capacity-ceb.tail; i++ {
			events[i] = ceb.buffer[ceb.tail+i]
		}
		for i := 0; i < ceb.head; i++ {
			events[ceb.capacity-ceb.tail+i] = ceb.buffer[i]
		}
	} else {
		// Copy from tail to head
		for i := 0; i < ceb.size; i++ {
			events[i] = ceb.buffer[(ceb.tail+i)%ceb.capacity]
		}
	}
	
	return events
}

func (ceb *CircularEventBuffer) addUnsafe(event StreamEvent) {
	ceb.buffer[ceb.head] = event
	
	if ceb.full {
		ceb.tail = (ceb.tail + 1) % ceb.capacity
	}
	
	ceb.head = (ceb.head + 1) % ceb.capacity
	
	if ceb.head == ceb.tail {
		ceb.full = true
	}
	
	if !ceb.full {
		ceb.size++
	}
}

// Iterator provides a way to iterate over events
type BufferIterator struct {
	buffer   *CircularEventBuffer
	current  int
	total    int
	events   []StreamEvent
}

// NewIterator creates a new iterator for the buffer
func (ceb *CircularEventBuffer) NewIterator() *BufferIterator {
	ceb.mutex.RLock()
	events := ceb.getAllUnsafe()
	ceb.mutex.RUnlock()
	
	return &BufferIterator{
		buffer:  ceb,
		current: 0,
		total:   len(events),
		events:  events,
	}
}

// HasNext returns true if there are more events to iterate
func (bi *BufferIterator) HasNext() bool {
	return bi.current < bi.total
}

// Next returns the next event
func (bi *BufferIterator) Next() (StreamEvent, bool) {
	if !bi.HasNext() {
		return StreamEvent{}, false
	}
	
	event := bi.events[bi.current]
	bi.current++
	return event, true
}

// Reset resets the iterator to the beginning
func (bi *BufferIterator) Reset() {
	bi.current = 0
}