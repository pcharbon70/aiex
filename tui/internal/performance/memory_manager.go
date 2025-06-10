package performance

import (
	"context"
	"fmt"
	"runtime"
	"runtime/debug"
	"sync"
	"sync/atomic"
	"time"
)

// MemoryManager optimizes memory usage and garbage collection
type MemoryManager struct {
	// Configuration
	config         MemoryConfig

	// Memory pools
	bufferPool     *BufferPool
	stringPool     *StringPool
	objectPool     *ObjectPool

	// GC control
	gcController   *GCController
	memoryMonitor  *MemoryMonitor

	// Pressure management
	pressureLevel  atomic.Int32
	lastGC         time.Time

	// Statistics
	stats          *MemoryStats

	// Synchronization
	mutex          sync.RWMutex
	running        bool

	// Context
	ctx            context.Context
	cancel         context.CancelFunc
}

// MemoryConfig configures memory management
type MemoryConfig struct {
	TargetMemory      uint64        `json:"target_memory"` // Target memory usage in bytes
	MaxMemory         uint64        `json:"max_memory"` // Maximum allowed memory
	GCInterval        time.Duration `json:"gc_interval"`
	GCThreshold       float64       `json:"gc_threshold"` // Memory pressure threshold (0-1)
	EnableAutoGC      bool          `json:"enable_auto_gc"`
	EnableProfiling   bool          `json:"enable_profiling"`
	BufferPoolSize    int           `json:"buffer_pool_size"`
	StringInternSize  int           `json:"string_intern_size"`
	CompactionInterval time.Duration `json:"compaction_interval"`
}

// MemoryStats tracks memory usage statistics
type MemoryStats struct {
	Allocated       uint64 `json:"allocated"`
	Total           uint64 `json:"total"`
	System          uint64 `json:"system"`
	GCRuns          uint32 `json:"gc_runs"`
	LastGC          time.Time `json:"last_gc"`
	PauseTotal      time.Duration `json:"pause_total"`
	PauseLast       time.Duration `json:"pause_last"`
	PoolHits        uint64 `json:"pool_hits"`
	PoolMisses      uint64 `json:"pool_misses"`
	PressureEvents  uint64 `json:"pressure_events"`
}

// BufferPool manages reusable byte buffers
type BufferPool struct {
	pool           *sync.Pool
	sizes          []int
	stats          PoolStats
	mutex          sync.RWMutex
}

// StringPool implements string interning for common strings
type StringPool struct {
	interns        map[string]string
	refCounts      map[string]int
	maxSize        int
	evictionQueue  []string
	mutex          sync.RWMutex
}

// ObjectPool manages reusable objects
type ObjectPool struct {
	pools          map[string]*sync.Pool
	factories      map[string]func() interface{}
	stats          map[string]*PoolStats
	mutex          sync.RWMutex
}

// GCController manages garbage collection behavior
type GCController struct {
	targetPause    time.Duration
	maxPause       time.Duration
	gcPercent      int
	adaptive       bool
	lastTuning     time.Time
	mutex          sync.Mutex
}

// MemoryMonitor tracks memory usage and pressure
type MemoryMonitor struct {
	samples        []MemorySample
	maxSamples     int
	pressureThreshold uint64
	callbacks      []MemoryPressureCallback
	mutex          sync.RWMutex
}

// MemorySample represents a memory usage sample
type MemorySample struct {
	Timestamp      time.Time `json:"timestamp"`
	Allocated      uint64    `json:"allocated"`
	Total          uint64    `json:"total"`
	System         uint64    `json:"system"`
	Goroutines     int       `json:"goroutines"`
	PressureLevel  int       `json:"pressure_level"`
}

// PoolStats tracks pool usage statistics
type PoolStats struct {
	Hits       uint64 `json:"hits"`
	Misses     uint64 `json:"misses"`
	Active     int    `json:"active"`
	Total      int    `json:"total"`
}

// MemoryPressureLevel represents memory pressure levels
type MemoryPressureLevel int

const (
	PressureNormal MemoryPressureLevel = iota
	PressureLow
	PressureMedium
	PressureHigh
	PressureCritical
)

// MemoryPressureCallback is called when memory pressure changes
type MemoryPressureCallback func(level MemoryPressureLevel)

// NewMemoryManager creates a new memory manager
func NewMemoryManager(config MemoryConfig) *MemoryManager {
	ctx, cancel := context.WithCancel(context.Background())

	if config.TargetMemory == 0 {
		config.TargetMemory = 256 * 1024 * 1024 // 256MB default
	}
	if config.MaxMemory == 0 {
		config.MaxMemory = 512 * 1024 * 1024 // 512MB default
	}
	if config.GCInterval == 0 {
		config.GCInterval = 30 * time.Second
	}
	if config.GCThreshold == 0 {
		config.GCThreshold = 0.8 // 80% threshold
	}
	if config.BufferPoolSize == 0 {
		config.BufferPoolSize = 100
	}
	if config.StringInternSize == 0 {
		config.StringInternSize = 10000
	}
	if config.CompactionInterval == 0 {
		config.CompactionInterval = 5 * time.Minute
	}

	mm := &MemoryManager{
		config:        config,
		bufferPool:    NewBufferPool(config.BufferPoolSize),
		stringPool:    NewStringPool(config.StringInternSize),
		objectPool:    NewObjectPool(),
		gcController:  NewGCController(),
		memoryMonitor: NewMemoryMonitor(config.TargetMemory),
		stats:         &MemoryStats{},
		ctx:           ctx,
		cancel:        cancel,
	}

	// Set initial GC percentage based on config
	if config.EnableAutoGC {
		debug.SetGCPercent(50) // More aggressive GC
	}

	return mm
}

// Start begins memory management services
func (mm *MemoryManager) Start() error {
	mm.mutex.Lock()
	defer mm.mutex.Unlock()

	if mm.running {
		return fmt.Errorf("memory manager already running")
	}

	mm.running = true

	// Start monitoring
	go mm.monitorLoop()

	// Start GC control loop
	if mm.config.EnableAutoGC {
		go mm.gcLoop()
	}

	// Start compaction loop
	go mm.compactionLoop()

	return nil
}

// Stop ends memory management services
func (mm *MemoryManager) Stop() error {
	mm.mutex.Lock()
	defer mm.mutex.Unlock()

	if !mm.running {
		return fmt.Errorf("memory manager not running")
	}

	mm.running = false
	mm.cancel()

	return nil
}

// GetBuffer retrieves a buffer from the pool
func (mm *MemoryManager) GetBuffer(size int) []byte {
	return mm.bufferPool.Get(size)
}

// PutBuffer returns a buffer to the pool
func (mm *MemoryManager) PutBuffer(buf []byte) {
	mm.bufferPool.Put(buf)
}

// InternString interns a string for memory efficiency
func (mm *MemoryManager) InternString(s string) string {
	return mm.stringPool.Intern(s)
}

// GetObject retrieves an object from the pool
func (mm *MemoryManager) GetObject(typeName string) interface{} {
	return mm.objectPool.Get(typeName)
}

// PutObject returns an object to the pool
func (mm *MemoryManager) PutObject(typeName string, obj interface{}) {
	mm.objectPool.Put(typeName, obj)
}

// RegisterObjectFactory registers a factory for object pooling
func (mm *MemoryManager) RegisterObjectFactory(typeName string, factory func() interface{}) {
	mm.objectPool.RegisterFactory(typeName, factory)
}

// GetStats returns current memory statistics
func (mm *MemoryManager) GetStats() MemoryStats {
	mm.mutex.RLock()
	defer mm.mutex.RUnlock()

	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	stats := *mm.stats
	stats.Allocated = m.Alloc
	stats.Total = m.TotalAlloc
	stats.System = m.Sys
	stats.GCRuns = m.NumGC
	stats.PauseTotal = time.Duration(m.PauseTotalNs)
	if m.NumGC > 0 {
		stats.PauseLast = time.Duration(m.PauseNs[(m.NumGC+255)%256])
	}

	return stats
}

// ForceGC forces a garbage collection
func (mm *MemoryManager) ForceGC() {
	runtime.GC()
	mm.lastGC = time.Now()
}

// SetMemoryLimit sets a soft memory limit
func (mm *MemoryManager) SetMemoryLimit(limit uint64) {
	mm.mutex.Lock()
	defer mm.mutex.Unlock()
	mm.config.TargetMemory = limit
	mm.memoryMonitor.pressureThreshold = uint64(float64(limit) * mm.config.GCThreshold)
}

// RegisterPressureCallback registers a memory pressure callback
func (mm *MemoryManager) RegisterPressureCallback(callback MemoryPressureCallback) {
	mm.memoryMonitor.RegisterCallback(callback)
}

// Background loops
func (mm *MemoryManager) monitorLoop() {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-mm.ctx.Done():
			return
		case <-ticker.C:
			mm.collectMetrics()
			mm.checkMemoryPressure()
		}
	}
}

func (mm *MemoryManager) gcLoop() {
	ticker := time.NewTicker(mm.config.GCInterval)
	defer ticker.Stop()

	for {
		select {
		case <-mm.ctx.Done():
			return
		case <-ticker.C:
			mm.performAdaptiveGC()
		}
	}
}

func (mm *MemoryManager) compactionLoop() {
	ticker := time.NewTicker(mm.config.CompactionInterval)
	defer ticker.Stop()

	for {
		select {
		case <-mm.ctx.Done():
			return
		case <-ticker.C:
			mm.performCompaction()
		}
	}
}

func (mm *MemoryManager) collectMetrics() {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	sample := MemorySample{
		Timestamp:     time.Now(),
		Allocated:     m.Alloc,
		Total:         m.TotalAlloc,
		System:        m.Sys,
		Goroutines:    runtime.NumGoroutine(),
		PressureLevel: int(mm.pressureLevel.Load()),
	}

	mm.memoryMonitor.AddSample(sample)
}

func (mm *MemoryManager) checkMemoryPressure() {
	stats := mm.GetStats()
	pressure := mm.calculatePressure(stats.Allocated)

	oldLevel := MemoryPressureLevel(mm.pressureLevel.Load())
	newLevel := pressure

	if oldLevel != newLevel {
		mm.pressureLevel.Store(int32(newLevel))
		mm.memoryMonitor.NotifyPressureChange(newLevel)

		// Take action based on pressure level
		switch newLevel {
		case PressureHigh:
			mm.ForceGC()
			mm.stringPool.Evict(0.2) // Evict 20%
		case PressureCritical:
			mm.ForceGC()
			mm.stringPool.Evict(0.5) // Evict 50%
			mm.bufferPool.Clear()
		}
	}
}

func (mm *MemoryManager) calculatePressure(allocated uint64) MemoryPressureLevel {
	ratio := float64(allocated) / float64(mm.config.TargetMemory)

	switch {
	case ratio < 0.5:
		return PressureNormal
	case ratio < 0.7:
		return PressureLow
	case ratio < 0.85:
		return PressureMedium
	case ratio < 0.95:
		return PressureHigh
	default:
		return PressureCritical
	}
}

func (mm *MemoryManager) performAdaptiveGC() {
	stats := mm.GetStats()
	pressure := mm.calculatePressure(stats.Allocated)

	if pressure >= PressureMedium || time.Since(mm.lastGC) > mm.config.GCInterval {
		mm.gcController.AdaptiveGC(stats)
		mm.lastGC = time.Now()
	}
}

func (mm *MemoryManager) performCompaction() {
	// Compact string pool
	mm.stringPool.Compact()

	// Clear unused buffer pool entries
	mm.bufferPool.Compact()

	// Clear unused object pools
	mm.objectPool.Compact()
}

// BufferPool implementation
func NewBufferPool(maxSize int) *BufferPool {
	bp := &BufferPool{
		sizes: []int{64, 256, 1024, 4096, 16384, 65536},
		stats: PoolStats{},
	}

	bp.pool = &sync.Pool{
		New: func() interface{} {
			return make([]byte, 0, 1024)
		},
	}

	return bp
}

func (bp *BufferPool) Get(size int) []byte {
	bp.mutex.Lock()
	defer bp.mutex.Unlock()

	buf := bp.pool.Get().([]byte)
	if cap(buf) < size {
		bp.stats.Misses++
		return make([]byte, size)
	}

	bp.stats.Hits++
	return buf[:size]
}

func (bp *BufferPool) Put(buf []byte) {
	bp.mutex.Lock()
	defer bp.mutex.Unlock()

	if cap(buf) > 65536 {
		return // Don't pool very large buffers
	}

	buf = buf[:0]
	bp.pool.Put(buf)
}

func (bp *BufferPool) Clear() {
	bp.mutex.Lock()
	defer bp.mutex.Unlock()

	// Create new pool to clear all buffers
	bp.pool = &sync.Pool{
		New: func() interface{} {
			return make([]byte, 0, 1024)
		},
	}
}

func (bp *BufferPool) Compact() {
	// sync.Pool handles its own compaction
}

// StringPool implementation
func NewStringPool(maxSize int) *StringPool {
	return &StringPool{
		interns:       make(map[string]string),
		refCounts:     make(map[string]int),
		maxSize:       maxSize,
		evictionQueue: make([]string, 0, maxSize),
	}
}

func (sp *StringPool) Intern(s string) string {
	sp.mutex.Lock()
	defer sp.mutex.Unlock()

	if interned, exists := sp.interns[s]; exists {
		sp.refCounts[s]++
		return interned
	}

	// Check if we need to evict
	if len(sp.interns) >= sp.maxSize {
		sp.evictLRU()
	}

	sp.interns[s] = s
	sp.refCounts[s] = 1
	sp.evictionQueue = append(sp.evictionQueue, s)

	return s
}

func (sp *StringPool) Evict(ratio float64) {
	sp.mutex.Lock()
	defer sp.mutex.Unlock()

	toEvict := int(float64(len(sp.interns)) * ratio)
	for i := 0; i < toEvict && len(sp.evictionQueue) > 0; i++ {
		sp.evictLRU()
	}
}

func (sp *StringPool) evictLRU() {
	if len(sp.evictionQueue) == 0 {
		return
	}

	oldest := sp.evictionQueue[0]
	sp.evictionQueue = sp.evictionQueue[1:]

	delete(sp.interns, oldest)
	delete(sp.refCounts, oldest)
}

func (sp *StringPool) Compact() {
	sp.mutex.Lock()
	defer sp.mutex.Unlock()

	// Remove strings with zero references
	for s, count := range sp.refCounts {
		if count == 0 {
			delete(sp.interns, s)
			delete(sp.refCounts, s)
		}
	}

	// Rebuild eviction queue
	sp.evictionQueue = make([]string, 0, len(sp.interns))
	for s := range sp.interns {
		sp.evictionQueue = append(sp.evictionQueue, s)
	}
}

// ObjectPool implementation
func NewObjectPool() *ObjectPool {
	return &ObjectPool{
		pools:     make(map[string]*sync.Pool),
		factories: make(map[string]func() interface{}),
		stats:     make(map[string]*PoolStats),
	}
}

func (op *ObjectPool) RegisterFactory(typeName string, factory func() interface{}) {
	op.mutex.Lock()
	defer op.mutex.Unlock()

	op.factories[typeName] = factory
	op.pools[typeName] = &sync.Pool{
		New: factory,
	}
	op.stats[typeName] = &PoolStats{}
}

func (op *ObjectPool) Get(typeName string) interface{} {
	op.mutex.RLock()
	pool, exists := op.pools[typeName]
	stats := op.stats[typeName]
	op.mutex.RUnlock()

	if !exists {
		return nil
	}

	obj := pool.Get()
	if obj != nil {
		atomic.AddUint64(&stats.Hits, 1)
	} else {
		atomic.AddUint64(&stats.Misses, 1)
	}

	return obj
}

func (op *ObjectPool) Put(typeName string, obj interface{}) {
	op.mutex.RLock()
	pool, exists := op.pools[typeName]
	op.mutex.RUnlock()

	if exists {
		pool.Put(obj)
	}
}

func (op *ObjectPool) Compact() {
	// sync.Pool handles its own compaction
}

// GCController implementation
func NewGCController() *GCController {
	return &GCController{
		targetPause: 10 * time.Millisecond,
		maxPause:    50 * time.Millisecond,
		gcPercent:   100,
		adaptive:    true,
	}
}

func (gc *GCController) AdaptiveGC(stats MemoryStats) {
	gc.mutex.Lock()
	defer gc.mutex.Unlock()

	if !gc.adaptive || time.Since(gc.lastTuning) < 10*time.Second {
		runtime.GC()
		return
	}

	// Adjust GC percentage based on pause times
	if stats.PauseLast > gc.targetPause {
		// Reduce GC frequency
		gc.gcPercent = min(gc.gcPercent+10, 200)
	} else if stats.PauseLast < gc.targetPause/2 {
		// Increase GC frequency
		gc.gcPercent = max(gc.gcPercent-10, 50)
	}

	debug.SetGCPercent(gc.gcPercent)
	runtime.GC()
	gc.lastTuning = time.Now()
}

// MemoryMonitor implementation
func NewMemoryMonitor(threshold uint64) *MemoryMonitor {
	return &MemoryMonitor{
		samples:           make([]MemorySample, 0, 60),
		maxSamples:        60,
		pressureThreshold: threshold,
		callbacks:         make([]MemoryPressureCallback, 0),
	}
}

func (mm *MemoryMonitor) AddSample(sample MemorySample) {
	mm.mutex.Lock()
	defer mm.mutex.Unlock()

	mm.samples = append(mm.samples, sample)
	if len(mm.samples) > mm.maxSamples {
		mm.samples = mm.samples[1:]
	}
}

func (mm *MemoryMonitor) RegisterCallback(callback MemoryPressureCallback) {
	mm.mutex.Lock()
	defer mm.mutex.Unlock()
	mm.callbacks = append(mm.callbacks, callback)
}

func (mm *MemoryMonitor) NotifyPressureChange(level MemoryPressureLevel) {
	mm.mutex.RLock()
	callbacks := make([]MemoryPressureCallback, len(mm.callbacks))
	copy(callbacks, mm.callbacks)
	mm.mutex.RUnlock()

	for _, callback := range callbacks {
		callback(level)
	}
}

// Utility functions
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}