package performance

import (
	"fmt"
	"math"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// VirtualScroller provides efficient scrolling for large datasets
type VirtualScroller struct {
	// Core state
	totalItems      int
	visibleItems    int
	itemHeight      int
	viewportHeight  int
	scrollPosition  float64
	scrollVelocity  float64

	// Rendering
	renderCache     *RenderCache
	visibleRange    VisibleRange
	prefetchRange   PrefetchRange
	renderQueue     *RenderQueue

	// Performance
	lastRenderTime  time.Time
	frameTime       time.Duration
	skippedFrames   int

	// Configuration
	config          VirtualScrollConfig

	// Callbacks
	renderItem      RenderItemFunc
	fetchItems      FetchItemsFunc

	// Synchronization
	mutex           sync.RWMutex
}

// VirtualScrollConfig configures virtual scrolling behavior
type VirtualScrollConfig struct {
	BufferSize         int           `json:"buffer_size"`
	PrefetchDistance   int           `json:"prefetch_distance"`
	ScrollSensitivity  float64       `json:"scroll_sensitivity"`
	SmoothScrolling    bool          `json:"smooth_scrolling"`
	MomentumScrolling  bool          `json:"momentum_scrolling"`
	Friction          float64       `json:"friction"`
	MaxVelocity       float64       `json:"max_velocity"`
	TargetFrameTime   time.Duration `json:"target_frame_time"`
	EnableCache       bool          `json:"enable_cache"`
	CacheSize         int           `json:"cache_size"`
}

// VisibleRange represents the currently visible item range
type VisibleRange struct {
	Start int `json:"start"`
	End   int `json:"end"`
}

// PrefetchRange represents the range to prefetch for smooth scrolling
type PrefetchRange struct {
	Start int `json:"start"`
	End   int `json:"end"`
}

// RenderItemFunc renders a single item
type RenderItemFunc func(index int) (string, error)

// FetchItemsFunc fetches items for a given range
type FetchItemsFunc func(start, end int) error

// ScrollEvent represents a scroll event
type ScrollEvent struct {
	Delta     float64   `json:"delta"`
	Timestamp time.Time `json:"timestamp"`
	Source    string    `json:"source"` // wheel, keyboard, programmatic
}

// RenderCache caches rendered items for performance
type RenderCache struct {
	cache      map[int]CachedItem
	maxSize    int
	lru        *LRUTracker
	mutex      sync.RWMutex
	hits       int64
	misses     int64
}

// CachedItem represents a cached rendered item
type CachedItem struct {
	Content    string    `json:"content"`
	Height     int       `json:"height"`
	Timestamp  time.Time `json:"timestamp"`
	AccessCount int      `json:"access_count"`
}

// RenderQueue manages rendering priority
type RenderQueue struct {
	queue      []RenderRequest
	processing map[int]bool
	maxSize    int
	mutex      sync.Mutex
}

// RenderRequest represents a render request
type RenderRequest struct {
	Index     int       `json:"index"`
	Priority  int       `json:"priority"`
	Timestamp time.Time `json:"timestamp"`
}

// NewVirtualScroller creates a new virtual scroller
func NewVirtualScroller(totalItems, visibleItems, itemHeight int) *VirtualScroller {
	config := VirtualScrollConfig{
		BufferSize:        visibleItems * 2,
		PrefetchDistance:  visibleItems,
		ScrollSensitivity: 1.0,
		SmoothScrolling:   true,
		MomentumScrolling: true,
		Friction:         0.95,
		MaxVelocity:      50.0,
		TargetFrameTime:  16 * time.Millisecond, // 60 FPS
		EnableCache:      true,
		CacheSize:        1000,
	}

	vs := &VirtualScroller{
		totalItems:     totalItems,
		visibleItems:   visibleItems,
		itemHeight:     itemHeight,
		viewportHeight: visibleItems * itemHeight,
		scrollPosition: 0,
		scrollVelocity: 0,
		renderCache:    NewRenderCache(config.CacheSize),
		renderQueue:    NewRenderQueue(config.BufferSize),
		config:         config,
		lastRenderTime: time.Now(),
	}

	vs.updateVisibleRange()
	vs.updatePrefetchRange()

	return vs
}

// Update handles virtual scroller updates
func (vs *VirtualScroller) Update(msg tea.Msg) tea.Cmd {
	switch msg := msg.(type) {
	case tea.MouseMsg:
		if msg.Type == tea.MouseWheelUp || msg.Type == tea.MouseWheelDown {
			delta := float64(vs.itemHeight)
			if msg.Type == tea.MouseWheelUp {
				delta = -delta
			}
			return vs.handleScroll(ScrollEvent{
				Delta:     delta * vs.config.ScrollSensitivity,
				Timestamp: time.Now(),
				Source:    "wheel",
			})
		}

	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			return vs.scrollBy(-vs.itemHeight)
		case "down", "j":
			return vs.scrollBy(vs.itemHeight)
		case "pgup":
			return vs.scrollBy(-vs.viewportHeight)
		case "pgdown":
			return vs.scrollBy(vs.viewportHeight)
		case "home":
			return vs.scrollTo(0)
		case "end":
			return vs.scrollTo(float64((vs.totalItems - vs.visibleItems) * vs.itemHeight))
		}

	case ScrollUpdateMsg:
		return vs.updateScroll(msg.Position)
	}

	// Update momentum scrolling
	if vs.config.MomentumScrolling && math.Abs(vs.scrollVelocity) > 0.1 {
		return vs.updateMomentum()
	}

	return nil
}

// Render renders the visible items
func (vs *VirtualScroller) Render() (string, error) {
	vs.mutex.RLock()
	defer vs.mutex.RUnlock()

	// Track frame timing
	now := time.Now()
	frameTime := now.Sub(vs.lastRenderTime)
	vs.lastRenderTime = now

	// Skip frame if running behind
	if frameTime > vs.config.TargetFrameTime*2 {
		vs.skippedFrames++
		if vs.skippedFrames > 3 {
			// Force render after too many skipped frames
			vs.skippedFrames = 0
		} else {
			return "", nil // Skip this frame
		}
	}
	vs.frameTime = frameTime

	// Ensure visible range is up to date
	vs.updateVisibleRange()

	// Prefetch items if needed
	if vs.fetchItems != nil {
		go vs.prefetchItems()
	}

	// Render visible items
	var rendered []string
	for i := vs.visibleRange.Start; i <= vs.visibleRange.End && i < vs.totalItems; i++ {
		// Check cache first
		if vs.config.EnableCache {
			if cached, found := vs.renderCache.Get(i); found {
				rendered = append(rendered, cached.Content)
				continue
			}
		}

		// Render item
		if vs.renderItem != nil {
			content, err := vs.renderItem(i)
			if err != nil {
				content = fmt.Sprintf("Error rendering item %d: %v", i, err)
			}

			// Cache rendered content
			if vs.config.EnableCache {
				vs.renderCache.Set(i, CachedItem{
					Content:   content,
					Height:    vs.itemHeight,
					Timestamp: now,
				})
			}

			rendered = append(rendered, content)
		} else {
			rendered = append(rendered, fmt.Sprintf("Item %d", i))
		}
	}

	// Add scroll indicators
	scrollInfo := vs.getScrollInfo()
	if scrollInfo != "" {
		rendered = append(rendered, scrollInfo)
	}

	return combineRendered(rendered), nil
}

// Scrolling methods
func (vs *VirtualScroller) handleScroll(event ScrollEvent) tea.Cmd {
	vs.mutex.Lock()
	defer vs.mutex.Unlock()

	oldPosition := vs.scrollPosition
	newPosition := vs.scrollPosition + event.Delta

	// Apply bounds
	maxScroll := float64((vs.totalItems - vs.visibleItems) * vs.itemHeight)
	newPosition = math.Max(0, math.Min(newPosition, maxScroll))

	vs.scrollPosition = newPosition

	// Update velocity for momentum scrolling
	if vs.config.MomentumScrolling {
		vs.scrollVelocity = newPosition - oldPosition
		// Clamp velocity
		vs.scrollVelocity = math.Max(-vs.config.MaxVelocity, 
			math.Min(vs.scrollVelocity, vs.config.MaxVelocity))
	}

	// Update ranges
	vs.updateVisibleRange()
	vs.updatePrefetchRange()

	return ScrollUpdateCmd(newPosition)
}

func (vs *VirtualScroller) scrollBy(delta float64) tea.Cmd {
	return vs.handleScroll(ScrollEvent{
		Delta:     delta,
		Timestamp: time.Now(),
		Source:    "keyboard",
	})
}

func (vs *VirtualScroller) scrollTo(position float64) tea.Cmd {
	vs.mutex.Lock()
	defer vs.mutex.Unlock()

	// Apply bounds
	maxScroll := float64((vs.totalItems - vs.visibleItems) * vs.itemHeight)
	position = math.Max(0, math.Min(position, maxScroll))

	vs.scrollPosition = position
	vs.scrollVelocity = 0 // Stop momentum

	// Update ranges
	vs.updateVisibleRange()
	vs.updatePrefetchRange()

	return ScrollUpdateCmd(position)
}

func (vs *VirtualScroller) updateScroll(position float64) tea.Cmd {
	vs.mutex.Lock()
	defer vs.mutex.Unlock()

	vs.scrollPosition = position
	vs.updateVisibleRange()
	vs.updatePrefetchRange()

	return nil
}

func (vs *VirtualScroller) updateMomentum() tea.Cmd {
	vs.mutex.Lock()
	defer vs.mutex.Unlock()

	// Apply friction
	vs.scrollVelocity *= vs.config.Friction

	// Stop if velocity is too small
	if math.Abs(vs.scrollVelocity) < 0.1 {
		vs.scrollVelocity = 0
		return nil
	}

	// Update position
	newPosition := vs.scrollPosition + vs.scrollVelocity
	maxScroll := float64((vs.totalItems - vs.visibleItems) * vs.itemHeight)
	newPosition = math.Max(0, math.Min(newPosition, maxScroll))

	// Bounce effect at boundaries
	if newPosition == 0 || newPosition == maxScroll {
		vs.scrollVelocity = -vs.scrollVelocity * 0.3 // Damped bounce
	}

	vs.scrollPosition = newPosition
	vs.updateVisibleRange()
	vs.updatePrefetchRange()

	// Continue momentum animation
	return tea.Tick(time.Duration(16)*time.Millisecond, func(time.Time) tea.Msg {
		return ScrollUpdateMsg{Position: vs.scrollPosition}
	})
}

// Range management
func (vs *VirtualScroller) updateVisibleRange() {
	startItem := int(vs.scrollPosition) / vs.itemHeight
	endItem := startItem + vs.visibleItems

	vs.visibleRange = VisibleRange{
		Start: startItem,
		End:   endItem,
	}
}

func (vs *VirtualScroller) updatePrefetchRange() {
	prefetchStart := vs.visibleRange.Start - vs.config.PrefetchDistance
	prefetchEnd := vs.visibleRange.End + vs.config.PrefetchDistance

	vs.prefetchRange = PrefetchRange{
		Start: max(0, prefetchStart),
		End:   min(vs.totalItems-1, prefetchEnd),
	}
}

func (vs *VirtualScroller) prefetchItems() {
	if vs.fetchItems == nil {
		return
	}

	// Add prefetch requests to queue
	for i := vs.prefetchRange.Start; i <= vs.prefetchRange.End; i++ {
		if !vs.renderCache.Has(i) {
			vs.renderQueue.Add(RenderRequest{
				Index:     i,
				Priority:  vs.calculatePriority(i),
				Timestamp: time.Now(),
			})
		}
	}

	// Process queue
	vs.renderQueue.Process(func(req RenderRequest) {
		vs.fetchItems(req.Index, req.Index+1)
	})
}

func (vs *VirtualScroller) calculatePriority(index int) int {
	// Higher priority for items closer to visible range
	if index >= vs.visibleRange.Start && index <= vs.visibleRange.End {
		return 10 // Highest priority for visible items
	}

	distance := 0
	if index < vs.visibleRange.Start {
		distance = vs.visibleRange.Start - index
	} else {
		distance = index - vs.visibleRange.End
	}

	return max(1, 10-distance)
}

// Performance methods
func (vs *VirtualScroller) GetPerformanceStats() VirtualScrollStats {
	vs.mutex.RLock()
	defer vs.mutex.RUnlock()

	return VirtualScrollStats{
		VisibleItems:   vs.visibleItems,
		TotalItems:     vs.totalItems,
		ScrollPosition: vs.scrollPosition,
		Velocity:       vs.scrollVelocity,
		FrameTime:      vs.frameTime,
		SkippedFrames:  vs.skippedFrames,
		CacheHitRate:   vs.renderCache.GetHitRate(),
		CacheSize:      vs.renderCache.Size(),
		QueueSize:      vs.renderQueue.Size(),
	}
}

func (vs *VirtualScroller) getScrollInfo() string {
	scrollPercent := (vs.scrollPosition / float64((vs.totalItems-vs.visibleItems)*vs.itemHeight)) * 100
	return fmt.Sprintf("[%d-%d of %d] %.0f%%", 
		vs.visibleRange.Start+1, 
		min(vs.visibleRange.End+1, vs.totalItems), 
		vs.totalItems, 
		scrollPercent)
}

// Configuration methods
func (vs *VirtualScroller) SetRenderFunc(fn RenderItemFunc) {
	vs.renderItem = fn
}

func (vs *VirtualScroller) SetFetchFunc(fn FetchItemsFunc) {
	vs.fetchItems = fn
}

func (vs *VirtualScroller) UpdateTotalItems(total int) {
	vs.mutex.Lock()
	defer vs.mutex.Unlock()

	vs.totalItems = total
	vs.updateVisibleRange()
	vs.updatePrefetchRange()
}

func (vs *VirtualScroller) UpdateViewport(visibleItems, itemHeight int) {
	vs.mutex.Lock()
	defer vs.mutex.Unlock()

	vs.visibleItems = visibleItems
	vs.itemHeight = itemHeight
	vs.viewportHeight = visibleItems * itemHeight
	vs.updateVisibleRange()
	vs.updatePrefetchRange()
}

// RenderCache implementation
func NewRenderCache(maxSize int) *RenderCache {
	return &RenderCache{
		cache:   make(map[int]CachedItem),
		maxSize: maxSize,
		lru:     NewLRUTracker(maxSize),
	}
}

func (rc *RenderCache) Get(index int) (CachedItem, bool) {
	rc.mutex.RLock()
	defer rc.mutex.RUnlock()

	if item, exists := rc.cache[index]; exists {
		rc.hits++
		item.AccessCount++
		rc.lru.Access(index)
		return item, true
	}

	rc.misses++
	return CachedItem{}, false
}

func (rc *RenderCache) Set(index int, item CachedItem) {
	rc.mutex.Lock()
	defer rc.mutex.Unlock()

	// Evict if needed
	if len(rc.cache) >= rc.maxSize {
		if evicted := rc.lru.Evict(); evicted != -1 {
			delete(rc.cache, evicted)
		}
	}

	rc.cache[index] = item
	rc.lru.Access(index)
}

func (rc *RenderCache) Has(index int) bool {
	rc.mutex.RLock()
	defer rc.mutex.RUnlock()
	_, exists := rc.cache[index]
	return exists
}

func (rc *RenderCache) Size() int {
	rc.mutex.RLock()
	defer rc.mutex.RUnlock()
	return len(rc.cache)
}

func (rc *RenderCache) GetHitRate() float64 {
	rc.mutex.RLock()
	defer rc.mutex.RUnlock()

	total := rc.hits + rc.misses
	if total == 0 {
		return 0
	}
	return float64(rc.hits) / float64(total)
}

func (rc *RenderCache) Clear() {
	rc.mutex.Lock()
	defer rc.mutex.Unlock()

	rc.cache = make(map[int]CachedItem)
	rc.lru = NewLRUTracker(rc.maxSize)
	rc.hits = 0
	rc.misses = 0
}

// RenderQueue implementation
func NewRenderQueue(maxSize int) *RenderQueue {
	return &RenderQueue{
		queue:      make([]RenderRequest, 0, maxSize),
		processing: make(map[int]bool),
		maxSize:    maxSize,
	}
}

func (rq *RenderQueue) Add(request RenderRequest) {
	rq.mutex.Lock()
	defer rq.mutex.Unlock()

	// Skip if already processing or in queue
	if rq.processing[request.Index] {
		return
	}

	for _, req := range rq.queue {
		if req.Index == request.Index {
			return
		}
	}

	// Add to queue
	rq.queue = append(rq.queue, request)

	// Sort by priority (higher priority first)
	sortByPriority(rq.queue)

	// Limit queue size
	if len(rq.queue) > rq.maxSize {
		rq.queue = rq.queue[:rq.maxSize]
	}
}

func (rq *RenderQueue) Process(handler func(RenderRequest)) {
	rq.mutex.Lock()
	if len(rq.queue) == 0 {
		rq.mutex.Unlock()
		return
	}

	// Get next request
	request := rq.queue[0]
	rq.queue = rq.queue[1:]
	rq.processing[request.Index] = true
	rq.mutex.Unlock()

	// Process request
	handler(request)

	// Mark as complete
	rq.mutex.Lock()
	delete(rq.processing, request.Index)
	rq.mutex.Unlock()
}

func (rq *RenderQueue) Size() int {
	rq.mutex.Lock()
	defer rq.mutex.Unlock()
	return len(rq.queue)
}

// LRUTracker for cache eviction
type LRUTracker struct {
	accesses map[int]time.Time
	maxSize  int
	mutex    sync.Mutex
}

func NewLRUTracker(maxSize int) *LRUTracker {
	return &LRUTracker{
		accesses: make(map[int]time.Time),
		maxSize:  maxSize,
	}
}

func (lru *LRUTracker) Access(index int) {
	lru.mutex.Lock()
	defer lru.mutex.Unlock()
	lru.accesses[index] = time.Now()
}

func (lru *LRUTracker) Evict() int {
	lru.mutex.Lock()
	defer lru.mutex.Unlock()

	if len(lru.accesses) == 0 {
		return -1
	}

	oldestIndex := -1
	var oldestTime time.Time

	for index, accessTime := range lru.accesses {
		if oldestIndex == -1 || accessTime.Before(oldestTime) {
			oldestIndex = index
			oldestTime = accessTime
		}
	}

	if oldestIndex != -1 {
		delete(lru.accesses, oldestIndex)
	}

	return oldestIndex
}

// Stats and monitoring
type VirtualScrollStats struct {
	VisibleItems   int           `json:"visible_items"`
	TotalItems     int           `json:"total_items"`
	ScrollPosition float64       `json:"scroll_position"`
	Velocity       float64       `json:"velocity"`
	FrameTime      time.Duration `json:"frame_time"`
	SkippedFrames  int           `json:"skipped_frames"`
	CacheHitRate   float64       `json:"cache_hit_rate"`
	CacheSize      int           `json:"cache_size"`
	QueueSize      int           `json:"queue_size"`
}

// Message types
type ScrollUpdateMsg struct {
	Position float64
}

// Command constructors
func ScrollUpdateCmd(position float64) tea.Cmd {
	return func() tea.Msg {
		return ScrollUpdateMsg{Position: position}
	}
}

// Utility functions
func combineRendered(items []string) string {
	result := ""
	for _, item := range items {
		result += item + "\n"
	}
	return result
}

func sortByPriority(queue []RenderRequest) {
	// Simple bubble sort for small queues
	for i := 0; i < len(queue)-1; i++ {
		for j := 0; j < len(queue)-i-1; j++ {
			if queue[j].Priority < queue[j+1].Priority {
				queue[j], queue[j+1] = queue[j+1], queue[j]
			}
		}
	}
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
