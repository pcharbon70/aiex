package performance

import (
	"context"
	"fmt"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"aiex-tui/internal/rpc"
	"aiex-tui/pkg/types"
)

// LazyLoader provides lazy loading for files and conversation history
type LazyLoader struct {
	// Core components
	rpcClient     *rpc.Client
	memoryManager *MemoryManager

	// Loading state
	pendingLoads  map[string]*LoadRequest
	loadedItems   map[string]*LoadedItem
	loadQueue     *LoadQueue

	// Cache management
	cache         *LazyCache
	prefetcher    *Prefetcher

	// Configuration
	config        LazyLoadConfig

	// Synchronization
	mutex         sync.RWMutex
	running       bool

	// Context
	ctx           context.Context
	cancel        context.CancelFunc
}

// LazyLoadConfig configures lazy loading behavior
type LazyLoadConfig struct {
	MaxConcurrentLoads  int           `json:"max_concurrent_loads"`
	MaxCacheSize        int           `json:"max_cache_size"`
	MaxMemoryUsage      uint64        `json:"max_memory_usage"`
	PrefetchDistance    int           `json:"prefetch_distance"`
	PrefetchDelay       time.Duration `json:"prefetch_delay"`
	CacheEvictionRate   float64       `json:"cache_eviction_rate"`
	EnablePrefetching   bool          `json:"enable_prefetching"`
	EnableCompression   bool          `json:"enable_compression"`
	Timeout             time.Duration `json:"timeout"`
}

// LoadRequest represents a pending load request
type LoadRequest struct {
	ID           string                 `json:"id"`
	Type         LoadType               `json:"type"`
	Path         string                 `json:"path,omitempty"`
	ConversationID string              `json:"conversation_id,omitempty"`
	Range        *LoadRange             `json:"range,omitempty"`
	Priority     LoadPriority           `json:"priority"`
	Callback     LoadCallback           `json:"-"`
	StartTime    time.Time              `json:"start_time"`
	Timeout      time.Duration          `json:"timeout"`
	Metadata     map[string]interface{} `json:"metadata"`
	mutex        sync.RWMutex
}

// LoadedItem represents a loaded item in cache
type LoadedItem struct {
	ID           string                 `json:"id"`
	Type         LoadType               `json:"type"`
	Content      interface{}            `json:"content"`
	Size         int64                  `json:"size"`
	LoadTime     time.Time              `json:"load_time"`
	LastAccess   time.Time              `json:"last_access"`
	AccessCount  int                    `json:"access_count"`
	Compressed   bool                   `json:"compressed"`
	Metadata     map[string]interface{} `json:"metadata"`
	mutex        sync.RWMutex
}

// LoadQueue manages load request prioritization
type LoadQueue struct {
	requests     []*LoadRequest
	processing   map[string]bool
	maxSize      int
	mutex        sync.Mutex
}

// LazyCache provides intelligent caching with eviction
type LazyCache struct {
	items        map[string]*LoadedItem
	lru          *LRUList
	maxSize      int
	maxMemory    uint64
	currentSize  int64
	compressionEnabled bool
	mutex        sync.RWMutex
}

// Prefetcher handles intelligent prefetching
type Prefetcher struct {
	accessPatterns map[string]*AccessPattern
	predictions    map[string][]string
	prefetchQueue  []string
	enabled        bool
	mutex          sync.RWMutex
}

// LoadType represents the type of content being loaded
type LoadType int

const (
	LoadTypeFile LoadType = iota
	LoadTypeConversation
	LoadTypeMessages
	LoadTypeDirectory
	LoadTypeImage
	LoadTypeConfig
)

// LoadPriority represents load request priority
type LoadPriority int

const (
	PriorityLow LoadPriority = iota
	PriorityNormal
	PriorityHigh
	PriorityUrgent
)

// LoadRange represents a range of content to load
type LoadRange struct {
	Start  int64 `json:"start"`
	End    int64 `json:"end"`
	Length int64 `json:"length"`
}

// LoadCallback is called when content is loaded
type LoadCallback func(item *LoadedItem, err error)

// AccessPattern tracks access patterns for prefetching
type AccessPattern struct {
	Sequence      []string  `json:"sequence"`
	Frequency     int       `json:"frequency"`
	LastAccess    time.Time `json:"last_access"`
	Confidence    float64   `json:"confidence"`
}

// LRUList implements least recently used eviction
type LRUList struct {
	head   *LRUNode
	tail   *LRUNode
	nodes  map[string]*LRUNode
	mutex  sync.Mutex
}

// LRUNode represents a node in the LRU list
type LRUNode struct {
	key   string
	prev  *LRUNode
	next  *LRUNode
}

// NewLazyLoader creates a new lazy loader
func NewLazyLoader(rpcClient *rpc.Client, memoryManager *MemoryManager) *LazyLoader {
	ctx, cancel := context.WithCancel(context.Background())

	config := LazyLoadConfig{
		MaxConcurrentLoads: 5,
		MaxCacheSize:       1000,
		MaxMemoryUsage:     100 * 1024 * 1024, // 100MB
		PrefetchDistance:   3,
		PrefetchDelay:      100 * time.Millisecond,
		CacheEvictionRate:  0.2, // Evict 20% when cache is full
		EnablePrefetching:  true,
		EnableCompression:  true,
		Timeout:           30 * time.Second,
	}

	ll := &LazyLoader{
		rpcClient:     rpcClient,
		memoryManager: memoryManager,
		pendingLoads:  make(map[string]*LoadRequest),
		loadedItems:   make(map[string]*LoadedItem),
		loadQueue:     NewLoadQueue(100),
		cache:         NewLazyCache(config),
		prefetcher:    NewPrefetcher(config.EnablePrefetching),
		config:        config,
		ctx:           ctx,
		cancel:        cancel,
	}

	return ll
}

// Start begins lazy loading services
func (ll *LazyLoader) Start() error {
	ll.mutex.Lock()
	defer ll.mutex.Unlock()

	if ll.running {
		return fmt.Errorf("lazy loader already running")
	}

	ll.running = true

	// Start load workers
	for i := 0; i < ll.config.MaxConcurrentLoads; i++ {
		go ll.loadWorker(i)
	}

	// Start prefetcher
	if ll.config.EnablePrefetching {
		go ll.prefetchWorker()
	}

	// Start cache maintenance
	go ll.cacheMaintenanceWorker()

	return nil
}

// Stop ends lazy loading services
func (ll *LazyLoader) Stop() error {
	ll.mutex.Lock()
	defer ll.mutex.Unlock()

	if !ll.running {
		return fmt.Errorf("lazy loader not running")
	}

	ll.running = false
	ll.cancel()

	return nil
}

// LoadFile loads a file lazily
func (ll *LazyLoader) LoadFile(path string, priority LoadPriority, callback LoadCallback) tea.Cmd {
	return func() tea.Msg {
		id := fmt.Sprintf("file_%s", path)
		
		// Check cache first
		if item := ll.cache.Get(id); item != nil {
			if callback != nil {
				callback(item, nil)
			}
			return LazyLoadCompleteMsg{
				ID:   id,
				Type: LoadTypeFile,
				Item: item,
			}
		}

		// Queue for loading
		request := &LoadRequest{
			ID:        id,
			Type:      LoadTypeFile,
			Path:      path,
			Priority:  priority,
			Callback:  callback,
			StartTime: time.Now(),
			Timeout:   ll.config.Timeout,
			Metadata:  make(map[string]interface{}),
		}

		ll.loadQueue.Add(request)
		ll.recordAccess(id)

		return LazyLoadRequestedMsg{
			ID:   id,
			Type: LoadTypeFile,
			Path: path,
		}
	}
}

// LoadConversation loads conversation history lazily
func (ll *LazyLoader) LoadConversation(conversationID string, messageRange *LoadRange, priority LoadPriority, callback LoadCallback) tea.Cmd {
	return func() tea.Msg {
		id := fmt.Sprintf("conv_%s", conversationID)
		if messageRange != nil {
			id = fmt.Sprintf("conv_%s_%d_%d", conversationID, messageRange.Start, messageRange.End)
		}

		// Check cache first
		if item := ll.cache.Get(id); item != nil {
			if callback != nil {
				callback(item, nil)
			}
			return LazyLoadCompleteMsg{
				ID:   id,
				Type: LoadTypeConversation,
				Item: item,
			}
		}

		// Queue for loading
		request := &LoadRequest{
			ID:             id,
			Type:           LoadTypeConversation,
			ConversationID: conversationID,
			Range:          messageRange,
			Priority:       priority,
			Callback:       callback,
			StartTime:      time.Now(),
			Timeout:        ll.config.Timeout,
			Metadata:       make(map[string]interface{}),
		}

		ll.loadQueue.Add(request)
		ll.recordAccess(id)

		return LazyLoadRequestedMsg{
			ID:             id,
			Type:           LoadTypeConversation,
			ConversationID: conversationID,
		}
	}
}

// GetCached retrieves an item from cache
func (ll *LazyLoader) GetCached(id string) *LoadedItem {
	return ll.cache.Get(id)
}

// InvalidateCache invalidates cached items
func (ll *LazyLoader) InvalidateCache(pattern string) {
	ll.cache.Invalidate(pattern)
}

// GetCacheStats returns cache statistics
func (ll *LazyLoader) GetCacheStats() CacheStats {
	return ll.cache.GetStats()
}

// Worker functions
func (ll *LazyLoader) loadWorker(workerID int) {
	for {
		select {
		case <-ll.ctx.Done():
			return
		default:
			request := ll.loadQueue.GetNext()
			if request == nil {
				time.Sleep(10 * time.Millisecond)
				continue
			}

			ll.processLoadRequest(workerID, request)
		}
	}
}

func (ll *LazyLoader) processLoadRequest(workerID int, request *LoadRequest) {
	ctx, cancel := context.WithTimeout(ll.ctx, request.Timeout)
	defer cancel()

	start := time.Now()
	var content interface{}
	var err error

	// Load content based on type
	switch request.Type {
	case LoadTypeFile:
		content, err = ll.loadFile(ctx, request.Path)
	case LoadTypeConversation:
		content, err = ll.loadConversation(ctx, request.ConversationID, request.Range)
	case LoadTypeDirectory:
		content, err = ll.loadDirectory(ctx, request.Path)
	default:
		err = fmt.Errorf("unknown load type: %v", request.Type)
	}

	loadTime := time.Since(start)

	if err != nil {
		// Call error callback
		if request.Callback != nil {
			request.Callback(nil, err)
		}
		return
	}

	// Create loaded item
	item := &LoadedItem{
		ID:          request.ID,
		Type:        request.Type,
		Content:     content,
		Size:        ll.calculateSize(content),
		LoadTime:    loadTime,
		LastAccess:  time.Now(),
		AccessCount: 1,
		Compressed:  false,
		Metadata:    make(map[string]interface{}),
	}

	// Compress if enabled and content is large
	if ll.config.EnableCompression && item.Size > 1024 {
		if compressed, ok := ll.compress(content); ok {
			item.Content = compressed
			item.Compressed = true
		}
	}

	// Add to cache
	ll.cache.Set(request.ID, item)

	// Call success callback
	if request.Callback != nil {
		request.Callback(item, nil)
	}

	// Remove from pending
	ll.mutex.Lock()
	delete(ll.pendingLoads, request.ID)
	ll.mutex.Unlock()
}

func (ll *LazyLoader) loadFile(ctx context.Context, path string) (interface{}, error) {
	// Call RPC to load file content
	request := map[string]interface{}{
		"path": path,
	}

	response, err := ll.rpcClient.Call(ctx, "file.read", request)
	if err != nil {
		return nil, fmt.Errorf("failed to load file %s: %w", path, err)
	}

	return response, nil
}

func (ll *LazyLoader) loadConversation(ctx context.Context, conversationID string, loadRange *LoadRange) (interface{}, error) {
	request := map[string]interface{}{
		"conversation_id": conversationID,
	}

	if loadRange != nil {
		request["range"] = map[string]interface{}{
			"start":  loadRange.Start,
			"end":    loadRange.End,
			"length": loadRange.Length,
		}
	}

	response, err := ll.rpcClient.Call(ctx, "conversation.get_messages", request)
	if err != nil {
		return nil, fmt.Errorf("failed to load conversation %s: %w", conversationID, err)
	}

	return response, nil
}

func (ll *LazyLoader) loadDirectory(ctx context.Context, path string) (interface{}, error) {
	request := map[string]interface{}{
		"path": path,
	}

	response, err := ll.rpcClient.Call(ctx, "file.list_directory", request)
	if err != nil {
		return nil, fmt.Errorf("failed to load directory %s: %w", path, err)
	}

	return response, nil
}

func (ll *LazyLoader) prefetchWorker() {
	ticker := time.NewTicker(ll.config.PrefetchDelay)
	defer ticker.Stop()

	for {
		select {
		case <-ll.ctx.Done():
			return
		case <-ticker.C:
			ll.processPrefetching()
		}
	}
}

func (ll *LazyLoader) processPrefetching() {
	predictions := ll.prefetcher.GetPredictions()
	for _, id := range predictions {
		if ll.cache.Get(id) == nil {
			// Item not in cache, prefetch it
			ll.prefetchItem(id)
		}
	}
}

func (ll *LazyLoader) prefetchItem(id string) {
	// Create low-priority prefetch request
	// Implementation would depend on how to parse ID back to request parameters
}

func (ll *LazyLoader) cacheMaintenanceWorker() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ll.ctx.Done():
			return
		case <-ticker.C:
			ll.cache.Maintain()
		}
	}
}

func (ll *LazyLoader) recordAccess(id string) {
	ll.prefetcher.RecordAccess(id)
}

func (ll *LazyLoader) calculateSize(content interface{}) int64 {
	// Rough size calculation
	switch c := content.(type) {
	case string:
		return int64(len(c))
	case []byte:
		return int64(len(c))
	case []types.Message:
		return int64(len(c) * 500) // Rough estimate
	default:
		return 1024 // Default estimate
	}
}

func (ll *LazyLoader) compress(content interface{}) (interface{}, bool) {
	// Simple compression implementation
	// In a real implementation, use actual compression algorithms
	return content, false
}

// LoadQueue implementation
func NewLoadQueue(maxSize int) *LoadQueue {
	return &LoadQueue{
		requests:   make([]*LoadRequest, 0, maxSize),
		processing: make(map[string]bool),
		maxSize:    maxSize,
	}
}

func (lq *LoadQueue) Add(request *LoadRequest) {
	lq.mutex.Lock()
	defer lq.mutex.Unlock()

	// Check if already processing
	if lq.processing[request.ID] {
		return
	}

	// Add to queue
	lq.requests = append(lq.requests, request)

	// Sort by priority
	lq.sortByPriority()

	// Limit queue size
	if len(lq.requests) > lq.maxSize {
		lq.requests = lq.requests[:lq.maxSize]
	}
}

func (lq *LoadQueue) GetNext() *LoadRequest {
	lq.mutex.Lock()
	defer lq.mutex.Unlock()

	if len(lq.requests) == 0 {
		return nil
	}

	request := lq.requests[0]
	lq.requests = lq.requests[1:]
	lq.processing[request.ID] = true

	return request
}

func (lq *LoadQueue) sortByPriority() {
	// Simple bubble sort for small queues
	for i := 0; i < len(lq.requests)-1; i++ {
		for j := 0; j < len(lq.requests)-i-1; j++ {
			if lq.requests[j].Priority < lq.requests[j+1].Priority {
				lq.requests[j], lq.requests[j+1] = lq.requests[j+1], lq.requests[j]
			}
		}
	}
}

// LazyCache implementation
func NewLazyCache(config LazyLoadConfig) *LazyCache {
	return &LazyCache{
		items:              make(map[string]*LoadedItem),
		lru:                NewLRUList(),
		maxSize:            config.MaxCacheSize,
		maxMemory:          config.MaxMemoryUsage,
		compressionEnabled: config.EnableCompression,
	}
}

func (lc *LazyCache) Get(id string) *LoadedItem {
	lc.mutex.RLock()
	defer lc.mutex.RUnlock()

	item, exists := lc.items[id]
	if !exists {
		return nil
	}

	// Update access time and count
	item.mutex.Lock()
	item.LastAccess = time.Now()
	item.AccessCount++
	item.mutex.Unlock()

	// Update LRU
	lc.lru.Access(id)

	return item
}

func (lc *LazyCache) Set(id string, item *LoadedItem) {
	lc.mutex.Lock()
	defer lc.mutex.Unlock()

	// Check if we need to evict
	if len(lc.items) >= lc.maxSize || lc.currentSize+item.Size > int64(lc.maxMemory) {
		lc.evict()
	}

	lc.items[id] = item
	lc.currentSize += item.Size
	lc.lru.Add(id)
}

func (lc *LazyCache) evict() {
	// Remove least recently used items
	toRemove := int(float64(len(lc.items)) * 0.2) // Remove 20%
	if toRemove == 0 {
		toRemove = 1
	}

	for i := 0; i < toRemove; i++ {
		id := lc.lru.RemoveLRU()
		if id == "" {
			break
		}

		if item, exists := lc.items[id]; exists {
			lc.currentSize -= item.Size
			delete(lc.items, id)
		}
	}
}

func (lc *LazyCache) Invalidate(pattern string) {
	lc.mutex.Lock()
	defer lc.mutex.Unlock()

	// Simple pattern matching (in real implementation, use regex)
	for id, item := range lc.items {
		if id == pattern || (pattern == "*" || id[:len(pattern)] == pattern) {
			lc.currentSize -= item.Size
			delete(lc.items, id)
			lc.lru.Remove(id)
		}
	}
}

func (lc *LazyCache) Maintain() {
	lc.mutex.Lock()
	defer lc.mutex.Unlock()

	// Remove expired items
	now := time.Now()
	for id, item := range lc.items {
		if now.Sub(item.LastAccess) > 30*time.Minute {
			lc.currentSize -= item.Size
			delete(lc.items, id)
			lc.lru.Remove(id)
		}
	}
}

func (lc *LazyCache) GetStats() CacheStats {
	lc.mutex.RLock()
	defer lc.mutex.RUnlock()

	return CacheStats{
		Items:       len(lc.items),
		MaxItems:    lc.maxSize,
		MemoryUsage: lc.currentSize,
		MaxMemory:   int64(lc.maxMemory),
		HitRate:     0, // Calculate from access patterns
	}
}

// Prefetcher implementation
func NewPrefetcher(enabled bool) *Prefetcher {
	return &Prefetcher{
		accessPatterns: make(map[string]*AccessPattern),
		predictions:    make(map[string][]string),
		prefetchQueue:  make([]string, 0),
		enabled:        enabled,
	}
}

func (p *Prefetcher) RecordAccess(id string) {
	if !p.enabled {
		return
	}

	p.mutex.Lock()
	defer p.mutex.Unlock()

	// Update access patterns and generate predictions
	// Simplified implementation
	pattern, exists := p.accessPatterns[id]
	if !exists {
		pattern = &AccessPattern{
			Sequence:   make([]string, 0),
			Frequency:  0,
			Confidence: 0.5,
		}
		p.accessPatterns[id] = pattern
	}

	pattern.Frequency++
	pattern.LastAccess = time.Now()
}

func (p *Prefetcher) GetPredictions() []string {
	if !p.enabled {
		return []string{}
	}

	p.mutex.RLock()
	defer p.mutex.RUnlock()

	// Return predicted items to prefetch
	var predictions []string
	for _, items := range p.predictions {
		predictions = append(predictions, items...)
	}

	return predictions
}

// LRUList implementation
func NewLRUList() *LRUList {
	lru := &LRUList{
		nodes: make(map[string]*LRUNode),
	}
	lru.head = &LRUNode{}
	lru.tail = &LRUNode{}
	lru.head.next = lru.tail
	lru.tail.prev = lru.head
	return lru
}

func (lru *LRUList) Add(key string) {
	lru.mutex.Lock()
	defer lru.mutex.Unlock()

	if node, exists := lru.nodes[key]; exists {
		lru.moveToFront(node)
		return
	}

	node := &LRUNode{key: key}
	lru.nodes[key] = node
	lru.addToFront(node)
}

func (lru *LRUList) Access(key string) {
	lru.mutex.Lock()
	defer lru.mutex.Unlock()

	if node, exists := lru.nodes[key]; exists {
		lru.moveToFront(node)
	}
}

func (lru *LRUList) Remove(key string) {
	lru.mutex.Lock()
	defer lru.mutex.Unlock()

	if node, exists := lru.nodes[key]; exists {
		lru.removeNode(node)
		delete(lru.nodes, key)
	}
}

func (lru *LRUList) RemoveLRU() string {
	lru.mutex.Lock()
	defer lru.mutex.Unlock()

	if lru.tail.prev == lru.head {
		return "" // Empty list
	}

	last := lru.tail.prev
	lru.removeNode(last)
	delete(lru.nodes, last.key)
	return last.key
}

func (lru *LRUList) moveToFront(node *LRUNode) {
	lru.removeNode(node)
	lru.addToFront(node)
}

func (lru *LRUList) addToFront(node *LRUNode) {
	node.next = lru.head.next
	node.prev = lru.head
	lru.head.next.prev = node
	lru.head.next = node
}

func (lru *LRUList) removeNode(node *LRUNode) {
	node.prev.next = node.next
	node.next.prev = node.prev
}

// Message types
type LazyLoadRequestedMsg struct {
	ID             string
	Type           LoadType
	Path           string
	ConversationID string
}

type LazyLoadCompleteMsg struct {
	ID   string
	Type LoadType
	Item *LoadedItem
}

type LazyLoadErrorMsg struct {
	ID    string
	Type  LoadType
	Error error
}

// CacheStats represents cache statistics
type CacheStats struct {
	Items       int     `json:"items"`
	MaxItems    int     `json:"max_items"`
	MemoryUsage int64   `json:"memory_usage"`
	MaxMemory   int64   `json:"max_memory"`
	HitRate     float64 `json:"hit_rate"`
}