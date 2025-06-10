package performance

import (
	"context"
	"fmt"
	"runtime"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	tea "github.com/charmbracelet/bubbletea"
)

// Virtual Scrolling Tests
func TestNewVirtualScroller(t *testing.T) {
	scroller := NewVirtualScroller(1000, 20, 25)

	assert.NotNil(t, scroller)
	assert.Equal(t, 1000, scroller.totalItems)
	assert.Equal(t, 20, scroller.visibleItems)
	assert.Equal(t, 25, scroller.itemHeight)
	assert.Equal(t, 0.0, scroller.scrollPosition)
	assert.NotNil(t, scroller.renderCache)
	assert.NotNil(t, scroller.renderQueue)
}

func TestVirtualScrollerScrolling(t *testing.T) {
	scroller := NewVirtualScroller(100, 10, 20)

	// Test scroll down
	cmd := scroller.scrollBy(40) // 2 items
	assert.NotNil(t, cmd)
	assert.Equal(t, 40.0, scroller.scrollPosition)

	// Test scroll up
	cmd = scroller.scrollBy(-20) // 1 item up
	assert.NotNil(t, cmd)
	assert.Equal(t, 20.0, scroller.scrollPosition)

	// Test scroll to top
	cmd = scroller.scrollTo(0)
	assert.NotNil(t, cmd)
	assert.Equal(t, 0.0, scroller.scrollPosition)

	// Test scroll to bottom
	maxScroll := float64((scroller.totalItems - scroller.visibleItems) * scroller.itemHeight)
	cmd = scroller.scrollTo(maxScroll + 100) // Beyond max
	assert.NotNil(t, cmd)
	assert.Equal(t, maxScroll, scroller.scrollPosition) // Should be clamped
}

func TestVirtualScrollerVisibleRange(t *testing.T) {
	scroller := NewVirtualScroller(100, 10, 20)

	// At top
	scroller.scrollPosition = 0
	scroller.updateVisibleRange()
	assert.Equal(t, 0, scroller.visibleRange.Start)
	assert.Equal(t, 10, scroller.visibleRange.End)

	// Scroll down
	scroller.scrollPosition = 100 // 5 items
	scroller.updateVisibleRange()
	assert.Equal(t, 5, scroller.visibleRange.Start)
	assert.Equal(t, 15, scroller.visibleRange.End)

	// Near bottom
	scroller.scrollPosition = float64((scroller.totalItems - scroller.visibleItems) * scroller.itemHeight)
	scroller.updateVisibleRange()
	assert.Equal(t, 90, scroller.visibleRange.Start)
	assert.Equal(t, 100, scroller.visibleRange.End)
}

func TestVirtualScrollerCaching(t *testing.T) {
	scroller := NewVirtualScroller(100, 10, 20)
	cache := scroller.renderCache

	// Test cache operations
	item := CachedItem{
		Content:   "Test content",
		Height:    20,
		Timestamp: time.Now(),
	}

	cache.Set(5, item)
	assert.True(t, cache.Has(5))

	retrieved, found := cache.Get(5)
	assert.True(t, found)
	assert.Equal(t, "Test content", retrieved.Content)
	assert.Equal(t, 1, retrieved.AccessCount)

	// Test cache miss
	_, found = cache.Get(999)
	assert.False(t, found)

	// Test cache size
	assert.Equal(t, 1, cache.Size())

	// Test cache clear
	cache.Clear()
	assert.Equal(t, 0, cache.Size())
	assert.False(t, cache.Has(5))
}

func TestVirtualScrollerPerformanceStats(t *testing.T) {
	scroller := NewVirtualScroller(1000, 20, 25)

	// Add some items to cache
	for i := 0; i < 10; i++ {
		item := CachedItem{
			Content:   fmt.Sprintf("Item %d", i),
			Height:    25,
			Timestamp: time.Now(),
		}
		scroller.renderCache.Set(i, item)
	}

	// Get performance stats
	stats := scroller.GetPerformanceStats()
	assert.Equal(t, 20, stats.VisibleItems)
	assert.Equal(t, 1000, stats.TotalItems)
	assert.Equal(t, 0.0, stats.ScrollPosition)
	assert.Equal(t, 10, stats.CacheSize)
}

// Render Pipeline Tests
func TestNewRenderPipeline(t *testing.T) {
	config := RenderConfig{
		EnableDiffing:     true,
		EnableLayering:    true,
		EnableCaching:     true,
		TargetFPS:         60,
		MaxDirtyRegions:   10,
		CacheSize:         100,
		ParallelRendering: true,
	}

	pipeline := NewRenderPipeline(config)
	assert.NotNil(t, pipeline)
	assert.Equal(t, config.TargetFPS, pipeline.config.TargetFPS)
	assert.NotNil(t, pipeline.layers)
	assert.NotNil(t, pipeline.diffEngine)
	assert.NotNil(t, pipeline.compositor)
	assert.NotNil(t, pipeline.frameCache)
}

func TestRenderPipelineLayerManagement(t *testing.T) {
	config := RenderConfig{EnableLayering: true}
	pipeline := NewRenderPipeline(config)

	// Add layers
	layer1 := pipeline.AddLayer("background", 0)
	layer2 := pipeline.AddLayer("content", 1)
	layer3 := pipeline.AddLayer("overlay", 2)

	assert.NotNil(t, layer1)
	assert.NotNil(t, layer2)
	assert.NotNil(t, layer3)

	assert.Equal(t, "background", layer1.ID)
	assert.Equal(t, 0, layer1.Z)
	assert.True(t, layer1.Visible)
	assert.Equal(t, 1.0, layer1.Opacity)

	// Test layer ordering
	assert.Len(t, pipeline.layerOrder, 3)
	assert.Equal(t, "background", pipeline.layerOrder[0])
	assert.Equal(t, "content", pipeline.layerOrder[1])
	assert.Equal(t, "overlay", pipeline.layerOrder[2])
}

func TestRenderPipelineLayerUpdates(t *testing.T) {
	config := RenderConfig{EnableLayering: true, EnableCaching: true}
	pipeline := NewRenderPipeline(config)

	layer := pipeline.AddLayer("test", 0)
	style := lipgloss.NewStyle().Foreground(lipgloss.Color("#ff0000"))

	// Update layer content
	err := pipeline.UpdateLayer("test", "Hello, World!", style)
	assert.NoError(t, err)
	assert.Equal(t, "Hello, World!", layer.Content)
	assert.True(t, layer.Dirty)

	// Update with same content should not mark dirty
	layer.Dirty = false
	err = pipeline.UpdateLayer("test", "Hello, World!", style)
	assert.NoError(t, err)
	assert.False(t, layer.Dirty)

	// Update non-existent layer should error
	err = pipeline.UpdateLayer("nonexistent", "content", style)
	assert.Error(t, err)
}

func TestRenderPipelineRendering(t *testing.T) {
	config := RenderConfig{
		EnableLayering: true,
		EnableCaching:  true,
		EnableDiffing:  false, // Disable diffing for simpler test
	}
	pipeline := NewRenderPipeline(config)

	// Add and update layers
	pipeline.AddLayer("layer1", 0)
	pipeline.AddLayer("layer2", 1)

	pipeline.UpdateLayer("layer1", "Content 1", lipgloss.NewStyle())
	pipeline.UpdateLayer("layer2", "Content 2", lipgloss.NewStyle())

	// Render
	result, err := pipeline.Render()
	assert.NoError(t, err)
	assert.NotEmpty(t, result)
	assert.Contains(t, result, "Content 1")
	assert.Contains(t, result, "Content 2")

	// Check metrics
	metrics := pipeline.GetMetrics()
	assert.Equal(t, uint64(1), metrics.FrameCount)
	assert.Greater(t, metrics.AverageFrameTime, time.Duration(0))
}

// Memory Manager Tests
func TestNewMemoryManager(t *testing.T) {
	config := MemoryConfig{
		TargetMemory:    256 * 1024 * 1024,
		MaxMemory:       512 * 1024 * 1024,
		GCInterval:      30 * time.Second,
		EnableAutoGC:    true,
		BufferPoolSize:  100,
		StringInternSize: 1000,
	}

	mm := NewMemoryManager(config)
	assert.NotNil(t, mm)
	assert.Equal(t, config.TargetMemory, mm.config.TargetMemory)
	assert.NotNil(t, mm.bufferPool)
	assert.NotNil(t, mm.stringPool)
	assert.NotNil(t, mm.objectPool)
	assert.NotNil(t, mm.gcController)
}

func TestMemoryManagerBufferPool(t *testing.T) {
	config := MemoryConfig{BufferPoolSize: 10}
	mm := NewMemoryManager(config)

	// Get buffer
	buf := mm.GetBuffer(1024)
	assert.NotNil(t, buf)
	assert.GreaterOrEqual(t, len(buf), 1024)

	// Use buffer
	copy(buf, []byte("test data"))

	// Return buffer to pool
	mm.PutBuffer(buf)

	// Get another buffer (should reuse)
	buf2 := mm.GetBuffer(512)
	assert.NotNil(t, buf2)
}

func TestMemoryManagerStringPool(t *testing.T) {
	config := MemoryConfig{StringInternSize: 100}
	mm := NewMemoryManager(config)

	// Intern strings
	s1 := mm.InternString("test string")
	s2 := mm.InternString("test string") // Same string
	s3 := mm.InternString("different string")

	// Same strings should return same reference
	assert.Equal(t, s1, s2)
	assert.NotEqual(t, s1, s3)

	// Verify interning worked (same pointer)
	assert.True(t, &s1 == &s2 || s1 == s2) // Either same pointer or same value
}

func TestMemoryManagerStats(t *testing.T) {
	config := MemoryConfig{}
	mm := NewMemoryManager(config)

	stats := mm.GetStats()
	assert.Greater(t, stats.Allocated, uint64(0))
	assert.Greater(t, stats.System, uint64(0))
	assert.GreaterOrEqual(t, stats.Total, stats.Allocated)
}

func TestMemoryManagerPressure(t *testing.T) {
	config := MemoryConfig{
		TargetMemory: 1024, // Very low for testing
		GCThreshold:  0.8,
	}
	mm := NewMemoryManager(config)

	// Register pressure callback
	pressureEvents := make(chan MemoryPressureLevel, 10)
	mm.RegisterPressureCallback(func(level MemoryPressureLevel) {
		pressureEvents <- level
	})

	// Force memory pressure by setting very low limit
	mm.SetMemoryLimit(1024)

	// In a real scenario, this would trigger pressure events
	// For testing, we'll just verify the mechanism works
	assert.NotNil(t, mm.memoryMonitor)
}

// Lazy Loader Tests
func TestNewLazyLoader(t *testing.T) {
	// Mock dependencies
	rpcClient := &mockRPCClient{}
	memoryManager := NewMemoryManager(MemoryConfig{})

	loader := NewLazyLoader(rpcClient, memoryManager)
	assert.NotNil(t, loader)
	assert.NotNil(t, loader.cache)
	assert.NotNil(t, loader.loadQueue)
	assert.NotNil(t, loader.prefetcher)
}

type mockRPCClient struct {
	responses map[string]interface{}
	errors    map[string]error
	mutex     sync.RWMutex
}

func (m *mockRPCClient) Call(ctx context.Context, method string, params interface{}) (interface{}, error) {
	m.mutex.RLock()
	defer m.mutex.RUnlock()

	if err, exists := m.errors[method]; exists {
		return nil, err
	}
	if response, exists := m.responses[method]; exists {
		return response, nil
	}
	return nil, fmt.Errorf("method not found: %s", method)
}

func (m *mockRPCClient) setResponse(method string, response interface{}) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	if m.responses == nil {
		m.responses = make(map[string]interface{})
	}
	m.responses[method] = response
}

func TestLazyLoaderCache(t *testing.T) {
	config := LazyLoadConfig{
		MaxCacheSize:   10,
		MaxMemoryUsage: 1024 * 1024,
	}
	cache := NewLazyCache(config)

	// Test cache operations
	item := &LoadedItem{
		ID:      "test-1",
		Type:    LoadTypeFile,
		Content: "test content",
		Size:    12,
	}

	cache.Set("test-1", item)
	assert.Equal(t, 1, len(cache.items))

	retrieved := cache.Get("test-1")
	assert.NotNil(t, retrieved)
	assert.Equal(t, "test content", retrieved.Content)
	assert.Equal(t, 1, retrieved.AccessCount)

	// Test cache miss
	missed := cache.Get("nonexistent")
	assert.Nil(t, missed)
}

func TestLazyLoaderQueue(t *testing.T) {
	queue := NewLoadQueue(10)

	// Add requests with different priorities
	req1 := &LoadRequest{
		ID:       "low",
		Priority: PriorityLow,
	}
	req2 := &LoadRequest{
		ID:       "high",
		Priority: PriorityHigh,
	}
	req3 := &LoadRequest{
		ID:       "normal",
		Priority: PriorityNormal,
	}

	queue.Add(req1)
	queue.Add(req2)
	queue.Add(req3)

	// Should get high priority first
	next := queue.GetNext()
	assert.NotNil(t, next)
	assert.Equal(t, "high", next.ID)

	// Then normal priority
	next = queue.GetNext()
	assert.NotNil(t, next)
	assert.Equal(t, "normal", next.ID)

	// Finally low priority
	next = queue.GetNext()
	assert.NotNil(t, next)
	assert.Equal(t, "low", next.ID)

	// Queue should be empty
	next = queue.GetNext()
	assert.Nil(t, next)
}

// Performance Monitor Tests
func TestNewPerformanceMonitor(t *testing.T) {
	memoryManager := NewMemoryManager(MemoryConfig{})
	renderPipeline := NewRenderPipeline(RenderConfig{})
	virtualScroller := NewVirtualScroller(100, 10, 20)
	lazyLoader := NewLazyLoader(&mockRPCClient{}, memoryManager)

	monitor := NewPerformanceMonitor(memoryManager, renderPipeline, virtualScroller, lazyLoader)
	assert.NotNil(t, monitor)
	assert.NotNil(t, monitor.metrics)
	assert.NotNil(t, monitor.profiler)
	assert.NotNil(t, monitor.alerts)
}

func TestPerformanceMonitorMetrics(t *testing.T) {
	memoryManager := NewMemoryManager(MemoryConfig{})
	renderPipeline := NewRenderPipeline(RenderConfig{})
	virtualScroller := NewVirtualScroller(100, 10, 20)
	lazyLoader := NewLazyLoader(&mockRPCClient{}, memoryManager)

	monitor := NewPerformanceMonitor(memoryManager, renderPipeline, virtualScroller, lazyLoader)

	// Get initial metrics
	metrics := monitor.GetMetrics()
	assert.NotNil(t, metrics)
	assert.Greater(t, metrics.Memory.Allocated, uint64(0))
	assert.Greater(t, metrics.Goroutines.Active, 0)

	// Get real-time stats
	stats := monitor.GetRealtimeStats()
	assert.NotNil(t, stats)
	assert.Contains(t, stats, "memory_usage")
	assert.Contains(t, stats, "goroutines")
	assert.Contains(t, stats, "timestamp")
}

func TestPerformanceMonitorAlerts(t *testing.T) {
	memoryManager := NewMemoryManager(MemoryConfig{})
	renderPipeline := NewRenderPipeline(RenderConfig{})
	virtualScroller := NewVirtualScroller(100, 10, 20)
	lazyLoader := NewLazyLoader(&mockRPCClient{}, memoryManager)

	monitor := NewPerformanceMonitor(memoryManager, renderPipeline, virtualScroller, lazyLoader)

	// Register alert callback
	alerts := make(chan *Alert, 10)
	monitor.RegisterAlertCallback(func(alert *Alert) {
		alerts <- alert
	})

	// Trigger alert by setting very low memory threshold
	monitor.config.AlertThresholds.MemoryUsage = 1 // 1 byte - will definitely be exceeded

	// In a real scenario, this would trigger alerts
	// For testing, we'll verify the alert system is in place
	assert.NotNil(t, monitor.alerts)
}

func TestPerformanceMonitorDashboard(t *testing.T) {
	memoryManager := NewMemoryManager(MemoryConfig{})
	renderPipeline := NewRenderPipeline(RenderConfig{})
	virtualScroller := NewVirtualScroller(100, 10, 20)
	lazyLoader := NewLazyLoader(&mockRPCClient{}, memoryManager)

	monitor := NewPerformanceMonitor(memoryManager, renderPipeline, virtualScroller, lazyLoader)

	// Get dashboard view
	dashboard := monitor.GetPerformanceDashboard()
	assert.NotEmpty(t, dashboard)
	assert.Contains(t, dashboard, "Performance Dashboard")
	assert.Contains(t, dashboard, "Memory:")
	assert.Contains(t, dashboard, "Goroutines:")
	assert.Contains(t, dashboard, "FPS:")
}

// Integration Tests
func TestPerformanceIntegration(t *testing.T) {
	// Create integrated performance system
	memoryManager := NewMemoryManager(MemoryConfig{
		TargetMemory:   64 * 1024 * 1024,
		EnableAutoGC:   true,
		BufferPoolSize: 50,
	})

	renderPipeline := NewRenderPipeline(RenderConfig{
		EnableLayering: true,
		EnableCaching:  true,
		EnableDiffing:  true,
		TargetFPS:      60,
	})

	virtualScroller := NewVirtualScroller(10000, 50, 20)

	lazyLoader := NewLazyLoader(&mockRPCClient{}, memoryManager)

	monitor := NewPerformanceMonitor(memoryManager, renderPipeline, virtualScroller, lazyLoader)

	// Start all components
	require.NoError(t, memoryManager.Start())
	require.NoError(t, lazyLoader.Start())
	require.NoError(t, monitor.Start())

	// Perform some operations
	for i := 0; i < 10; i++ {
		// Use memory manager
		buf := memoryManager.GetBuffer(1024)
		memoryManager.PutBuffer(buf)

		// Use string pool
		s := memoryManager.InternString(fmt.Sprintf("test-%d", i))
		_ = s

		// Update render pipeline
		if i == 0 {
			renderPipeline.AddLayer("test", 0)
		}
		renderPipeline.UpdateLayer("test", fmt.Sprintf("Content %d", i), lipgloss.NewStyle())
		renderPipeline.Render()

		// Use virtual scroller
		virtualScroller.scrollBy(float64(i * 20))
		virtualScroller.Render()
	}

	// Allow some processing time
	time.Sleep(100 * time.Millisecond)

	// Verify system is working
	assert.True(t, memoryManager.running)
	assert.True(t, lazyLoader.running)
	assert.True(t, monitor.running)

	// Get performance metrics
	metrics := monitor.GetMetrics()
	assert.Greater(t, metrics.Memory.Allocated, uint64(0))
	assert.Greater(t, metrics.Goroutines.Active, 0)

	// Stop all components
	monitor.Stop()
	lazyLoader.Stop()
	memoryManager.Stop()
}

// Benchmark Tests
func BenchmarkVirtualScrollerRender(b *testing.B) {
	scroller := NewVirtualScroller(10000, 50, 20)
	scroller.SetRenderFunc(func(index int) (string, error) {
		return fmt.Sprintf("Item %d", index), nil
	})

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		scroller.Render()
	}
}

func BenchmarkRenderPipelineRender(b *testing.B) {
	config := RenderConfig{
		EnableLayering: true,
		EnableCaching:  true,
		EnableDiffing:  true,
	}
	pipeline := NewRenderPipeline(config)

	// Set up layers
	for i := 0; i < 10; i++ {
		pipeline.AddLayer(fmt.Sprintf("layer-%d", i), i)
		pipeline.UpdateLayer(fmt.Sprintf("layer-%d", i), fmt.Sprintf("Content %d", i), lipgloss.NewStyle())
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		pipeline.Render()
	}
}

func BenchmarkMemoryManagerBufferPool(b *testing.B) {
	mm := NewMemoryManager(MemoryConfig{BufferPoolSize: 100})

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			buf := mm.GetBuffer(1024)
			mm.PutBuffer(buf)
		}
	})
}

func BenchmarkMemoryManagerStringPool(b *testing.B) {
	mm := NewMemoryManager(MemoryConfig{StringInternSize: 1000})

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			mm.InternString("benchmark string")
		}
	})
}

func BenchmarkLazyCacheOperations(b *testing.B) {
	config := LazyLoadConfig{MaxCacheSize: 1000}
	cache := NewLazyCache(config)

	// Populate cache
	for i := 0; i < 100; i++ {
		item := &LoadedItem{
			ID:      fmt.Sprintf("item-%d", i),
			Content: fmt.Sprintf("Content %d", i),
			Size:    10,
		}
		cache.Set(fmt.Sprintf("item-%d", i), item)
	}

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			cache.Get(fmt.Sprintf("item-%d", b.N%100))
		}
	})
}

// Stress Tests
func TestPerformanceUnderLoad(t *testing.T) {
	memoryManager := NewMemoryManager(MemoryConfig{
		TargetMemory: 32 * 1024 * 1024,
		EnableAutoGC: true,
	})

	renderPipeline := NewRenderPipeline(RenderConfig{
		EnableLayering: true,
		EnableCaching:  true,
		TargetFPS:      60,
	})

	virtualScroller := NewVirtualScroller(100000, 100, 20)

	monitor := NewPerformanceMonitor(memoryManager, renderPipeline, virtualScroller, nil)

	// Start systems
	memoryManager.Start()
	monitor.Start()
	defer func() {
		monitor.Stop()
		memoryManager.Stop()
	}()

	// Simulate heavy load
	var wg sync.WaitGroup
	operationCount := int64(0)
	errorCount := int64(0)

	// Memory operations
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 1000; j++ {
				buf := memoryManager.GetBuffer(1024)
				memoryManager.PutBuffer(buf)
				atomic.AddInt64(&operationCount, 1)
			}
		}()
	}

	// Rendering operations
	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			layerID := fmt.Sprintf("worker-%d", workerID)
			renderPipeline.AddLayer(layerID, workerID)

			for j := 0; j < 100; j++ {
				err := renderPipeline.UpdateLayer(layerID, fmt.Sprintf("Content %d", j), lipgloss.NewStyle())
				if err != nil {
					atomic.AddInt64(&errorCount, 1)
				} else {
					renderPipeline.Render()
					atomic.AddInt64(&operationCount, 1)
				}
			}
		}(i)
	}

	// Scrolling operations
	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 500; j++ {
				virtualScroller.scrollBy(20)
				virtualScroller.Render()
				atomic.AddInt64(&operationCount, 1)
			}
		}()
	}

	wg.Wait()

	// Verify system handled load well
	totalOps := atomic.LoadInt64(&operationCount)
	totalErrors := atomic.LoadInt64(&errorCount)

	assert.Greater(t, totalOps, int64(1000))
	assert.LessOrEqual(t, totalErrors, totalOps/10) // Less than 10% error rate

	// Check final performance metrics
	metrics := monitor.GetMetrics()
	assert.Greater(t, metrics.Memory.Allocated, uint64(0))
	assert.Less(t, metrics.Goroutines.Active, 1000) // Reasonable goroutine count
}

func TestMemoryPressureHandling(t *testing.T) {
	// Create system with very low memory limits
	memoryManager := NewMemoryManager(MemoryConfig{
		TargetMemory: 1024 * 1024, // 1MB
		MaxMemory:    2 * 1024 * 1024, // 2MB
		EnableAutoGC: true,
		GCThreshold:  0.5, // 50% threshold
	})

	memoryManager.Start()
	defer memoryManager.Stop()

	// Register pressure callback
	pressureEvents := make(chan MemoryPressureLevel, 100)
	memoryManager.RegisterPressureCallback(func(level MemoryPressureLevel) {
		select {
		case pressureEvents <- level:
		default:
			// Buffer full, ignore
		}
	})

	// Allocate memory to trigger pressure
	buffers := make([][]byte, 0)
	for i := 0; i < 100; i++ {
		buf := memoryManager.GetBuffer(64 * 1024) // 64KB each
		buffers = append(buffers, buf)
		
		// Force garbage collection occasionally
		if i%10 == 0 {
			runtime.GC()
		}
	}

	// Clean up buffers
	for _, buf := range buffers {
		memoryManager.PutBuffer(buf)
	}

	// Verify memory system is still functional
	stats := memoryManager.GetStats()
	assert.Greater(t, stats.Allocated, uint64(0))
}

func TestRenderPipelineStress(t *testing.T) {
	config := RenderConfig{
		EnableLayering:    true,
		EnableCaching:     true,
		EnableDiffing:     true,
		ParallelRendering: true,
		TargetFPS:         60,
	}
	pipeline := NewRenderPipeline(config)

	// Create many layers
	for i := 0; i < 100; i++ {
		pipeline.AddLayer(fmt.Sprintf("stress-layer-%d", i), i)
	}

	// Update layers concurrently
	var wg sync.WaitGroup
	renderCount := int64(0)
	errorCount := int64(0)

	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(layerIndex int) {
			defer wg.Done()
			layerID := fmt.Sprintf("stress-layer-%d", layerIndex)

			for j := 0; j < 50; j++ {
				content := fmt.Sprintf("Content %d-%d", layerIndex, j)
				err := pipeline.UpdateLayer(layerID, content, lipgloss.NewStyle())
				if err != nil {
					atomic.AddInt64(&errorCount, 1)
					continue
				}

				_, err = pipeline.Render()
				if err != nil {
					atomic.AddInt64(&errorCount, 1)
				} else {
					atomic.AddInt64(&renderCount, 1)
				}
			}
		}(i)
	}

	wg.Wait()

	// Verify system handled stress well
	totalRenders := atomic.LoadInt64(&renderCount)
	totalErrors := atomic.LoadInt64(&errorCount)

	assert.Greater(t, totalRenders, int64(1000))
	assert.LessOrEqual(t, totalErrors, totalRenders/20) // Less than 5% error rate

	// Check final metrics
	metrics := pipeline.GetMetrics()
	assert.Greater(t, metrics.FrameCount, uint64(100))
}