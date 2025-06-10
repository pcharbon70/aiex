package events

import (
	"math"
	"sync"
	"time"
)

// AdaptiveRateController implements sophisticated rate limiting with adaptive behavior
type AdaptiveRateController struct {
	// Configuration
	baseLimit        int           // Base events per second
	maxLimit         int           // Maximum events per second
	minLimit         int           // Minimum events per second
	adaptive         bool          // Whether to use adaptive behavior
	
	// Rate limiting state
	currentLimit     int           // Current effective limit
	tokens          float64       // Current token count
	lastRefill      time.Time     // Last token refill time
	
	// Adaptive behavior
	loadFactor      float64       // Current system load factor (0.0 - 1.0)
	pressureHistory []float64     // History of pressure measurements
	adaptiveWindow  int           // Window size for adaptive calculations
	
	// Performance tracking
	eventHistory    []EventRecord // Recent event processing history
	historyWindow   time.Duration // Time window for history
	avgProcessTime  time.Duration // Average event processing time
	peakProcessTime time.Duration // Peak event processing time
	
	// Burst handling
	burstCapacity   int           // Maximum burst size
	burstTokens     float64       // Current burst tokens
	
	// Priority handling
	priorityWeights map[EventPriority]float64 // Token cost per priority
	
	// Synchronization
	mutex           sync.RWMutex
}

// EventRecord tracks individual event processing metrics
type EventRecord struct {
	Timestamp    time.Time     `json:"timestamp"`
	ProcessTime  time.Duration `json:"process_time"`
	Priority     EventPriority `json:"priority"`
	Category     EventCategory `json:"category"`
	Allowed      bool          `json:"allowed"`
}

// RateControllerConfig configures the rate controller
type RateControllerConfig struct {
	BaseLimit       int                            `json:"base_limit"`
	MaxLimit        int                            `json:"max_limit"`
	MinLimit        int                            `json:"min_limit"`
	Adaptive        bool                           `json:"adaptive"`
	BurstCapacity   int                            `json:"burst_capacity"`
	PriorityWeights map[EventPriority]float64      `json:"priority_weights"`
	HistoryWindow   time.Duration                  `json:"history_window"`
	AdaptiveWindow  int                            `json:"adaptive_window"`
}

// NewAdaptiveRateController creates a new adaptive rate controller
func NewAdaptiveRateController(baseLimit int, adaptive bool) *AdaptiveRateController {
	if baseLimit <= 0 {
		baseLimit = 100
	}
	
	defaultWeights := map[EventPriority]float64{
		PriorityLow:      1.0,
		PriorityNormal:   0.8,
		PriorityHigh:     0.5,
		PriorityCritical: 0.1,
	}
	
	arc := &AdaptiveRateController{
		baseLimit:       baseLimit,
		maxLimit:        baseLimit * 3,
		minLimit:        baseLimit / 4,
		adaptive:        adaptive,
		currentLimit:    baseLimit,
		tokens:          float64(baseLimit),
		lastRefill:      time.Now(),
		loadFactor:      0.0,
		pressureHistory: make([]float64, 0, 60), // 1 minute of history at 1Hz
		adaptiveWindow:  10,
		eventHistory:    make([]EventRecord, 0),
		historyWindow:   10 * time.Second,
		burstCapacity:   baseLimit / 2,
		burstTokens:     float64(baseLimit / 2),
		priorityWeights: defaultWeights,
	}
	
	// Start adaptive monitoring if enabled
	if adaptive {
		go arc.adaptiveMonitoringLoop()
	}
	
	return arc
}

// AllowEvent determines if an event should be allowed based on current rate limiting
func (arc *AdaptiveRateController) AllowEvent(event StreamEvent) bool {
	arc.mutex.Lock()
	defer arc.mutex.Unlock()
	
	// Refill tokens based on time elapsed
	arc.refillTokens()
	
	// Calculate token cost for this event
	tokenCost := arc.calculateTokenCost(event)
	
	// Check if we have enough tokens
	allowed := false
	if arc.tokens >= tokenCost {
		arc.tokens -= tokenCost
		allowed = true
	} else if arc.burstTokens >= tokenCost && event.Priority >= PriorityHigh {
		// Allow high priority events using burst tokens
		arc.burstTokens -= tokenCost
		allowed = true
	}
	
	// Record event processing
	record := EventRecord{
		Timestamp: time.Now(),
		Priority:  event.Priority,
		Category:  event.Category,
		Allowed:   allowed,
	}
	arc.recordEvent(record)
	
	// Update load factor if adaptive
	if arc.adaptive {
		arc.updateLoadFactor()
	}
	
	return allowed
}

// refillTokens adds tokens based on elapsed time
func (arc *AdaptiveRateController) refillTokens() {
	now := time.Now()
	elapsed := now.Sub(arc.lastRefill).Seconds()
	arc.lastRefill = now
	
	// Calculate tokens to add
	tokensToAdd := elapsed * float64(arc.currentLimit)
	arc.tokens = math.Min(arc.tokens+tokensToAdd, float64(arc.currentLimit))
	
	// Refill burst tokens more slowly
	burstRefill := elapsed * float64(arc.burstCapacity) * 0.1 // 10% of burst capacity per second
	arc.burstTokens = math.Min(arc.burstTokens+burstRefill, float64(arc.burstCapacity))
}

// calculateTokenCost determines the token cost for an event
func (arc *AdaptiveRateController) calculateTokenCost(event StreamEvent) float64 {
	baseCost := 1.0
	
	// Apply priority weight
	if weight, exists := arc.priorityWeights[event.Priority]; exists {
		baseCost *= weight
	}
	
	// Apply category-based modifiers
	switch event.Category {
	case CategoryUIUpdate:
		baseCost *= 0.5 // UI updates are cheaper
	case CategoryAIResponse:
		baseCost *= 2.0 // AI responses are more expensive
	case CategoryError:
		baseCost *= 0.3 // Errors should be processed quickly
	case CategorySystem:
		baseCost *= 0.7 // System events have moderate cost
	}
	
	// Apply load-based modifier if adaptive
	if arc.adaptive && arc.loadFactor > 0.7 {
		baseCost *= (1.0 + arc.loadFactor)
	}
	
	return baseCost
}

// recordEvent adds an event record to history
func (arc *AdaptiveRateController) recordEvent(record EventRecord) {
	arc.eventHistory = append(arc.eventHistory, record)
	
	// Clean old history
	cutoff := time.Now().Add(-arc.historyWindow)
	for len(arc.eventHistory) > 0 && arc.eventHistory[0].Timestamp.Before(cutoff) {
		arc.eventHistory = arc.eventHistory[1:]
	}
}

// updateLoadFactor calculates current system load factor
func (arc *AdaptiveRateController) updateLoadFactor() {
	if len(arc.eventHistory) == 0 {
		arc.loadFactor = 0.0
		return
	}
	
	// Calculate metrics from recent history
	recent := time.Now().Add(-5 * time.Second)
	var recentEvents, allowedEvents int
	var totalProcessTime time.Duration
	
	for _, record := range arc.eventHistory {
		if record.Timestamp.After(recent) {
			recentEvents++
			if record.Allowed {
				allowedEvents++
			}
			totalProcessTime += record.ProcessTime
		}
	}
	
	if recentEvents == 0 {
		arc.loadFactor = 0.0
		return
	}
	
	// Calculate load factors
	rejectionRate := float64(recentEvents-allowedEvents) / float64(recentEvents)
	avgProcessTime := totalProcessTime / time.Duration(recentEvents)
	
	// Normalize processing time (assume 1ms is baseline)
	processTimeFactor := float64(avgProcessTime) / float64(time.Millisecond)
	processTimeFactor = math.Min(processTimeFactor/10.0, 1.0) // Cap at 10ms = 1.0
	
	// Calculate utilization
	utilizationFactor := float64(recentEvents) / float64(arc.currentLimit*5) // 5 second window
	utilizationFactor = math.Min(utilizationFactor, 1.0)
	
	// Combine factors
	arc.loadFactor = (rejectionRate*0.4 + processTimeFactor*0.3 + utilizationFactor*0.3)
	arc.loadFactor = math.Min(arc.loadFactor, 1.0)
	
	// Add to pressure history
	arc.pressureHistory = append(arc.pressureHistory, arc.loadFactor)
	if len(arc.pressureHistory) > 60 {
		arc.pressureHistory = arc.pressureHistory[1:]
	}
}

// adaptiveMonitoringLoop continuously adjusts the rate limit based on system pressure
func (arc *AdaptiveRateController) adaptiveMonitoringLoop() {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()
	
	for range ticker.C {
		arc.mutex.Lock()
		arc.adaptRateLimit()
		arc.mutex.Unlock()
	}
}

// adaptRateLimit adjusts the current rate limit based on system conditions
func (arc *AdaptiveRateController) adaptRateLimit() {
	if len(arc.pressureHistory) < arc.adaptiveWindow {
		return
	}
	
	// Calculate average pressure over the window
	var avgPressure float64
	recent := arc.pressureHistory[len(arc.pressureHistory)-arc.adaptiveWindow:]
	for _, pressure := range recent {
		avgPressure += pressure
	}
	avgPressure /= float64(len(recent))
	
	// Calculate trend (are we getting worse or better?)
	var trend float64
	if len(arc.pressureHistory) >= 2 {
		recent := arc.pressureHistory[len(arc.pressureHistory)-2:]
		trend = recent[1] - recent[0]
	}
	
	// Determine adjustment
	var adjustment float64
	
	if avgPressure < 0.3 && trend <= 0 {
		// Low pressure and stable/improving - increase limit
		adjustment = 1.1
	} else if avgPressure < 0.5 && trend <= 0 {
		// Moderate pressure and stable/improving - small increase
		adjustment = 1.05
	} else if avgPressure > 0.8 || trend > 0.2 {
		// High pressure or rapidly increasing - decrease limit
		adjustment = 0.8
	} else if avgPressure > 0.6 || trend > 0.1 {
		// Moderate-high pressure or increasing - small decrease
		adjustment = 0.95
	} else {
		// Stable - no change
		adjustment = 1.0
	}
	
	// Apply adjustment with bounds
	newLimit := float64(arc.currentLimit) * adjustment
	arc.currentLimit = int(math.Max(float64(arc.minLimit), 
		math.Min(newLimit, float64(arc.maxLimit))))
}

// UpdateLimit updates the base rate limit
func (arc *AdaptiveRateController) UpdateLimit(newLimit int) {
	arc.mutex.Lock()
	defer arc.mutex.Unlock()
	
	arc.baseLimit = newLimit
	arc.maxLimit = newLimit * 3
	arc.minLimit = newLimit / 4
	
	if !arc.adaptive {
		arc.currentLimit = newLimit
	}
}

// SetAdaptive enables or disables adaptive behavior
func (arc *AdaptiveRateController) SetAdaptive(adaptive bool) {
	arc.mutex.Lock()
	defer arc.mutex.Unlock()
	
	arc.adaptive = adaptive
	if !adaptive {
		arc.currentLimit = arc.baseLimit
	}
}

// UpdatePriorityWeights updates the priority weights
func (arc *AdaptiveRateController) UpdatePriorityWeights(weights map[EventPriority]float64) {
	arc.mutex.Lock()
	defer arc.mutex.Unlock()
	
	arc.priorityWeights = weights
}

// GetStats returns current rate limiting statistics
func (arc *AdaptiveRateController) GetStats() RateControllerStats {
	arc.mutex.RLock()
	defer arc.mutex.RUnlock()
	
	stats := RateControllerStats{
		BaseLimit:       arc.baseLimit,
		CurrentLimit:    arc.currentLimit,
		MaxLimit:        arc.maxLimit,
		MinLimit:        arc.minLimit,
		Tokens:          arc.tokens,
		BurstTokens:     arc.burstTokens,
		LoadFactor:      arc.loadFactor,
		Adaptive:        arc.adaptive,
		TokenUtilization: 1.0 - (arc.tokens / float64(arc.currentLimit)),
		BurstUtilization: 1.0 - (arc.burstTokens / float64(arc.burstCapacity)),
	}
	
	// Calculate recent performance metrics
	if len(arc.eventHistory) > 0 {
		recent := time.Now().Add(-5 * time.Second)
		var recentEvents, allowedEvents int
		
		for _, record := range arc.eventHistory {
			if record.Timestamp.After(recent) {
				recentEvents++
				if record.Allowed {
					allowedEvents++
				}
			}
		}
		
		if recentEvents > 0 {
			stats.RecentThroughput = float64(allowedEvents) / 5.0 // Events per second
			stats.RecentRejectionRate = float64(recentEvents-allowedEvents) / float64(recentEvents)
		}
	}
	
	// Calculate pressure trend
	if len(arc.pressureHistory) >= 2 {
		recent := arc.pressureHistory[len(arc.pressureHistory)-2:]
		stats.PressureTrend = recent[1] - recent[0]
	}
	
	return stats
}

// RateControllerStats represents rate controller statistics
type RateControllerStats struct {
	BaseLimit          int     `json:"base_limit"`
	CurrentLimit       int     `json:"current_limit"`
	MaxLimit           int     `json:"max_limit"`
	MinLimit           int     `json:"min_limit"`
	Tokens             float64 `json:"tokens"`
	BurstTokens        float64 `json:"burst_tokens"`
	LoadFactor         float64 `json:"load_factor"`
	Adaptive           bool    `json:"adaptive"`
	TokenUtilization   float64 `json:"token_utilization"`
	BurstUtilization   float64 `json:"burst_utilization"`
	RecentThroughput   float64 `json:"recent_throughput"`
	RecentRejectionRate float64 `json:"recent_rejection_rate"`
	PressureTrend      float64 `json:"pressure_trend"`
}

// Reset resets the rate controller state
func (arc *AdaptiveRateController) Reset() {
	arc.mutex.Lock()
	defer arc.mutex.Unlock()
	
	arc.tokens = float64(arc.currentLimit)
	arc.burstTokens = float64(arc.burstCapacity)
	arc.lastRefill = time.Now()
	arc.loadFactor = 0.0
	arc.pressureHistory = arc.pressureHistory[:0]
	arc.eventHistory = arc.eventHistory[:0]
}

// SetBurstCapacity updates the burst capacity
func (arc *AdaptiveRateController) SetBurstCapacity(capacity int) {
	arc.mutex.Lock()
	defer arc.mutex.Unlock()
	
	arc.burstCapacity = capacity
	if arc.burstTokens > float64(capacity) {
		arc.burstTokens = float64(capacity)
	}
}

// GetCurrentLimit returns the current effective rate limit
func (arc *AdaptiveRateController) GetCurrentLimit() int {
	arc.mutex.RLock()
	defer arc.mutex.RUnlock()
	return arc.currentLimit
}

// GetLoadFactor returns the current load factor
func (arc *AdaptiveRateController) GetLoadFactor() float64 {
	arc.mutex.RLock()
	defer arc.mutex.RUnlock()
	return arc.loadFactor
}

// IsAdaptive returns whether adaptive behavior is enabled
func (arc *AdaptiveRateController) IsAdaptive() bool {
	arc.mutex.RLock()
	defer arc.mutex.RUnlock()
	return arc.adaptive
}

// GetPressureHistory returns the recent pressure history
func (arc *AdaptiveRateController) GetPressureHistory() []float64 {
	arc.mutex.RLock()
	defer arc.mutex.RUnlock()
	
	history := make([]float64, len(arc.pressureHistory))
	copy(history, arc.pressureHistory)
	return history
}

// PredictAllowance predicts if an event would be allowed without consuming tokens
func (arc *AdaptiveRateController) PredictAllowance(event StreamEvent) bool {
	arc.mutex.RLock()
	defer arc.mutex.RUnlock()
	
	tokenCost := arc.calculateTokenCost(event)
	return arc.tokens >= tokenCost || (arc.burstTokens >= tokenCost && event.Priority >= PriorityHigh)
}

// ForceAllow allows an event bypassing rate limiting (for critical events)
func (arc *AdaptiveRateController) ForceAllow(event StreamEvent) {
	arc.mutex.Lock()
	defer arc.mutex.Unlock()
	
	record := EventRecord{
		Timestamp: time.Now(),
		Priority:  event.Priority,
		Category:  event.Category,
		Allowed:   true,
	}
	arc.recordEvent(record)
}