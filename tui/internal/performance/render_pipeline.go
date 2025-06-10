package performance

import (
	"bytes"
	"crypto/md5"
	"fmt"
	"runtime"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// RenderPipeline provides efficient rendering with diff-based updates
type RenderPipeline struct {
	// Core components
	layers        map[string]*RenderLayer
	layerOrder    []string
	diffEngine    *DiffEngine
	compositor    *Compositor

	// Caching
	frameCache    *FrameCache
	styleCache    *StyleCache

	// Performance tracking
	metrics       *RenderMetrics
	profiler      *RenderProfiler

	// Configuration
	config        RenderConfig

	// State
	lastFrame     *Frame
	frameCount    uint64
	dirtyRegions  []Region

	// Synchronization
	mutex         sync.RWMutex
}

// RenderConfig configures the render pipeline
type RenderConfig struct {
	EnableDiffing      bool          `json:"enable_diffing"`
	EnableLayering     bool          `json:"enable_layering"`
	EnableCaching      bool          `json:"enable_caching"`
	EnableProfiling    bool          `json:"enable_profiling"`
	TargetFPS          int           `json:"target_fps"`
	MaxDirtyRegions    int           `json:"max_dirty_regions"`
	CacheSize          int           `json:"cache_size"`
	BatchUpdates       bool          `json:"batch_updates"`
	BatchTimeout       time.Duration `json:"batch_timeout"`
	ParallelRendering  bool          `json:"parallel_rendering"`
}

// RenderLayer represents a rendering layer
type RenderLayer struct {
	ID            string
	Z             int // Z-order
	Visible       bool
	Opacity       float64
	Content       string
	Style         lipgloss.Style
	Dirty         bool
	Cacheable     bool
	lastHash      string
	mutex         sync.RWMutex
}

// Frame represents a rendered frame
type Frame struct {
	ID            uint64
	Content       string
	Timestamp     time.Time
	RenderTime    time.Duration
	LayerHashes   map[string]string
	Regions       []Region
}

// Region represents a rectangular area
type Region struct {
	X, Y          int
	Width, Height int
	Dirty         bool
}

// DiffEngine calculates differences between frames
type DiffEngine struct {
	algorithm     DiffAlgorithm
	optimizations DiffOptimizations
	cache         *DiffCache
	mutex         sync.RWMutex
}

// DiffAlgorithm defines the diffing algorithm
type DiffAlgorithm int

const (
	DiffAlgorithmSimple DiffAlgorithm = iota
	DiffAlgorithmMyers
	DiffAlgorithmPatience
)

// DiffOptimizations controls diff optimizations
type DiffOptimizations struct {
	MinRegionSize     int  `json:"min_region_size"`
	MergeAdjacent     bool `json:"merge_adjacent"`
	SkipUnchanged     bool `json:"skip_unchanged"`
	UseHashing        bool `json:"use_hashing"`
}

// DiffResult represents the result of a diff operation
type DiffResult struct {
	ChangedRegions []Region
	Operations     []DiffOperation
	Similarity     float64
}

// DiffOperation represents a diff operation
type DiffOperation struct {
	Type      string // "insert", "delete", "replace"
	Region    Region
	OldContent string
	NewContent string
}

// Compositor combines layers into final output
type Compositor struct {
	blendModes    map[string]BlendMode
	workerPool    *WorkerPool
	buffer        *bytes.Buffer
	mutex         sync.Mutex
}

// BlendMode defines how layers are combined
type BlendMode int

const (
	BlendModeNormal BlendMode = iota
	BlendModeOverlay
	BlendModeMultiply
)

// RenderMetrics tracks rendering performance
type RenderMetrics struct {
	FrameCount       uint64
	TotalRenderTime  time.Duration
	AverageFrameTime time.Duration
	MinFrameTime     time.Duration
	MaxFrameTime     time.Duration
	CacheHits        uint64
	CacheMisses      uint64
	DiffOperations   uint64
	SkippedFrames    uint64
	GCPauses         uint64
	mutex            sync.RWMutex
}

// RenderProfiler provides detailed performance profiling
type RenderProfiler struct {
	samples       []ProfileSample
	maxSamples    int
	hotspots      map[string]*Hotspot
	enabled       bool
	mutex         sync.RWMutex
}

// ProfileSample represents a profiling sample
type ProfileSample struct {
	Timestamp     time.Time
	Phase         string
	Duration      time.Duration
	MemoryUsed    uint64
	Goroutines    int
	Metadata      map[string]interface{}
}

// Hotspot represents a performance hotspot
type Hotspot struct {
	Name          string
	CallCount     uint64
	TotalTime     time.Duration
	AverageTime   time.Duration
	MaxTime       time.Duration
}

// NewRenderPipeline creates a new render pipeline
func NewRenderPipeline(config RenderConfig) *RenderPipeline {
	if config.TargetFPS == 0 {
		config.TargetFPS = 60
	}
	if config.MaxDirtyRegions == 0 {
		config.MaxDirtyRegions = 10
	}
	if config.CacheSize == 0 {
		config.CacheSize = 100
	}
	if config.BatchTimeout == 0 {
		config.BatchTimeout = 16 * time.Millisecond
	}

	rp := &RenderPipeline{
		layers:       make(map[string]*RenderLayer),
		layerOrder:   make([]string, 0),
		diffEngine:   NewDiffEngine(),
		compositor:   NewCompositor(),
		frameCache:   NewFrameCache(config.CacheSize),
		styleCache:   NewStyleCache(config.CacheSize),
		metrics:      NewRenderMetrics(),
		profiler:     NewRenderProfiler(config.EnableProfiling),
		config:       config,
		dirtyRegions: make([]Region, 0, config.MaxDirtyRegions),
	}

	return rp
}

// AddLayer adds a rendering layer
func (rp *RenderPipeline) AddLayer(id string, z int) *RenderLayer {
	rp.mutex.Lock()
	defer rp.mutex.Unlock()

	layer := &RenderLayer{
		ID:        id,
		Z:         z,
		Visible:   true,
		Opacity:   1.0,
		Cacheable: true,
		Dirty:     true,
	}

	rp.layers[id] = layer
	rp.updateLayerOrder()

	return layer
}

// UpdateLayer updates a layer's content
func (rp *RenderPipeline) UpdateLayer(id string, content string, style lipgloss.Style) error {
	rp.mutex.RLock()
	layer, exists := rp.layers[id]
	rp.mutex.RUnlock()

	if !exists {
		return fmt.Errorf("layer not found: %s", id)
	}

	layer.mutex.Lock()
	defer layer.mutex.Unlock()

	// Calculate content hash
	newHash := rp.calculateHash(content)
	if layer.lastHash == newHash && !layer.Dirty {
		return nil // No change
	}

	layer.Content = content
	layer.Style = style
	layer.lastHash = newHash
	layer.Dirty = true

	// Mark regions as dirty
	rp.markDirtyRegions(layer)

	return nil
}

// Render performs the rendering pipeline
func (rp *RenderPipeline) Render() (string, error) {
	startTime := time.Now()

	// Start profiling
	if rp.config.EnableProfiling {
		rp.profiler.StartSample("render_frame")
	}

	// Check if we need to render
	if !rp.hasChanges() && rp.config.EnableDiffing {
		rp.metrics.recordSkippedFrame()
		return rp.getCachedFrame(), nil
	}

	// Create new frame
	frame := &Frame{
		ID:          rp.frameCount + 1,
		Timestamp:   time.Now(),
		LayerHashes: make(map[string]string),
	}

	// Render layers
	var rendered string
	if rp.config.EnableLayering {
		rendered = rp.renderLayers(frame)
	} else {
		rendered = rp.renderSimple()
	}

	// Apply diffing if enabled
	if rp.config.EnableDiffing && rp.lastFrame != nil {
		diffResult := rp.diffEngine.Diff(rp.lastFrame.Content, rendered)
		rp.applyDiff(diffResult)
	}

	// Update frame
	frame.Content = rendered
	frame.RenderTime = time.Since(startTime)

	// Cache frame
	if rp.config.EnableCaching {
		rp.frameCache.Set(frame)
	}

	// Update metrics
	rp.metrics.recordFrame(frame)
	rp.frameCount++
	rp.lastFrame = frame

	// Clear dirty flags
	rp.clearDirtyFlags()

	// End profiling
	if rp.config.EnableProfiling {
		rp.profiler.EndSample("render_frame", map[string]interface{}{
			"frame_id":    frame.ID,
			"render_time": frame.RenderTime,
		})
	}

	return rendered, nil
}

// renderLayers renders all layers in order
func (rp *RenderPipeline) renderLayers(frame *Frame) string {
	rp.mutex.RLock()
	orderCopy := make([]string, len(rp.layerOrder))
	copy(orderCopy, rp.layerOrder)
	rp.mutex.RUnlock()

	if rp.config.ParallelRendering {
		return rp.renderLayersParallel(orderCopy, frame)
	}

	return rp.renderLayersSequential(orderCopy, frame)
}

func (rp *RenderPipeline) renderLayersSequential(order []string, frame *Frame) string {
	results := make([]string, 0, len(order))

	for _, layerID := range order {
		layer := rp.layers[layerID]
		if !layer.Visible {
			continue
		}

		layer.mutex.RLock()
		content := layer.Content
		style := layer.Style
		hash := layer.lastHash
		layer.mutex.RUnlock()

		// Apply style if needed
		if style != (lipgloss.Style{}) {
			content = style.Render(content)
		}

		results = append(results, content)
		frame.LayerHashes[layerID] = hash
	}

	return rp.compositor.Compose(results)
}

func (rp *RenderPipeline) renderLayersParallel(order []string, frame *Frame) string {
	var wg sync.WaitGroup
	results := make([]string, len(order))
	resultMutex := sync.Mutex{}

	for i, layerID := range order {
		wg.Add(1)
		go func(index int, id string) {
			defer wg.Done()

			layer := rp.layers[id]
			if !layer.Visible {
				return
			}

			layer.mutex.RLock()
			content := layer.Content
			style := layer.Style
			hash := layer.lastHash
			layer.mutex.RUnlock()

			// Apply style if needed
			if style != (lipgloss.Style{}) {
				content = style.Render(content)
			}

			resultMutex.Lock()
			results[index] = content
			frame.LayerHashes[id] = hash
			resultMutex.Unlock()
		}(i, layerID)
	}

	wg.Wait()
	return rp.compositor.Compose(results)
}

func (rp *RenderPipeline) renderSimple() string {
	// Simple rendering without layers
	var result strings.Builder
	for _, layerID := range rp.layerOrder {
		layer := rp.layers[layerID]
		if layer.Visible {
			result.WriteString(layer.Content)
			result.WriteString("\n")
		}
	}
	return result.String()
}

// Utility methods
func (rp *RenderPipeline) updateLayerOrder() {
	// Sort layers by Z-order
	rp.layerOrder = make([]string, 0, len(rp.layers))
	for id := range rp.layers {
		rp.layerOrder = append(rp.layerOrder, id)
	}

	// Simple bubble sort for small number of layers
	for i := 0; i < len(rp.layerOrder)-1; i++ {
		for j := 0; j < len(rp.layerOrder)-i-1; j++ {
			if rp.layers[rp.layerOrder[j]].Z > rp.layers[rp.layerOrder[j+1]].Z {
				rp.layerOrder[j], rp.layerOrder[j+1] = rp.layerOrder[j+1], rp.layerOrder[j]
			}
		}
	}
}

func (rp *RenderPipeline) hasChanges() bool {
	for _, layer := range rp.layers {
		if layer.Dirty {
			return true
		}
	}
	return false
}

func (rp *RenderPipeline) clearDirtyFlags() {
	for _, layer := range rp.layers {
		layer.mutex.Lock()
		layer.Dirty = false
		layer.mutex.Unlock()
	}
	rp.dirtyRegions = rp.dirtyRegions[:0]
}

func (rp *RenderPipeline) markDirtyRegions(layer *RenderLayer) {
	// Simplified: mark entire layer as dirty
	// In a real implementation, calculate actual changed regions
	region := Region{
		X:      0,
		Y:      0,
		Width:  -1, // Full width
		Height: -1, // Full height
		Dirty:  true,
	}

	rp.mutex.Lock()
	defer rp.mutex.Unlock()

	rp.dirtyRegions = append(rp.dirtyRegions, region)
	if len(rp.dirtyRegions) > rp.config.MaxDirtyRegions {
		// Merge regions if too many
		rp.mergeDirtyRegions()
	}
}

func (rp *RenderPipeline) mergeDirtyRegions() {
	// Simple merge: combine all into one large region
	// In a real implementation, use spatial algorithms
	if len(rp.dirtyRegions) > 0 {
		rp.dirtyRegions = []Region{{
			X:      0,
			Y:      0,
			Width:  -1,
			Height: -1,
			Dirty:  true,
		}}
	}
}

func (rp *RenderPipeline) calculateHash(content string) string {
	hash := md5.Sum([]byte(content))
	return fmt.Sprintf("%x", hash)
}

func (rp *RenderPipeline) getCachedFrame() string {
	if rp.lastFrame != nil {
		return rp.lastFrame.Content
	}
	return ""
}

func (rp *RenderPipeline) applyDiff(diff *DiffResult) {
	// Apply diff operations
	// In a real implementation, this would update only changed regions
}

// GetMetrics returns current rendering metrics
func (rp *RenderPipeline) GetMetrics() RenderMetrics {
	return rp.metrics.GetSnapshot()
}

// GetProfile returns profiling data
func (rp *RenderPipeline) GetProfile() []ProfileSample {
	return rp.profiler.GetSamples()
}

// DiffEngine implementation
func NewDiffEngine() *DiffEngine {
	return &DiffEngine{
		algorithm: DiffAlgorithmSimple,
		optimizations: DiffOptimizations{
			MinRegionSize: 10,
			MergeAdjacent: true,
			SkipUnchanged: true,
			UseHashing:    true,
		},
		cache: NewDiffCache(100),
	}
}

func (de *DiffEngine) Diff(old, new string) *DiffResult {
	// Simple line-based diff
	oldLines := strings.Split(old, "\n")
	newLines := strings.Split(new, "\n")

	result := &DiffResult{
		ChangedRegions: make([]Region, 0),
		Operations:     make([]DiffOperation, 0),
	}

	// Calculate similarity
	commonLines := 0
	maxLines := max(len(oldLines), len(newLines))
	minLines := min(len(oldLines), len(newLines))

	for i := 0; i < minLines; i++ {
		if oldLines[i] == newLines[i] {
			commonLines++
		}
	}

	if maxLines > 0 {
		result.Similarity = float64(commonLines) / float64(maxLines)
	}

	return result
}

// Compositor implementation
func NewCompositor() *Compositor {
	return &Compositor{
		blendModes: make(map[string]BlendMode),
		workerPool: NewWorkerPool(runtime.NumCPU()),
		buffer:     &bytes.Buffer{},
	}
}

func (c *Compositor) Compose(layers []string) string {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	c.buffer.Reset()
	for _, layer := range layers {
		if layer != "" {
			c.buffer.WriteString(layer)
			c.buffer.WriteString("\n")
		}
	}

	return c.buffer.String()
}

// RenderMetrics implementation
func NewRenderMetrics() *RenderMetrics {
	return &RenderMetrics{}
}

func (rm *RenderMetrics) recordFrame(frame *Frame) {
	rm.mutex.Lock()
	defer rm.mutex.Unlock()

	rm.FrameCount++
	rm.TotalRenderTime += frame.RenderTime

	if rm.FrameCount == 1 {
		rm.MinFrameTime = frame.RenderTime
		rm.MaxFrameTime = frame.RenderTime
	} else {
		if frame.RenderTime < rm.MinFrameTime {
			rm.MinFrameTime = frame.RenderTime
		}
		if frame.RenderTime > rm.MaxFrameTime {
			rm.MaxFrameTime = frame.RenderTime
		}
	}

	rm.AverageFrameTime = rm.TotalRenderTime / time.Duration(rm.FrameCount)
}

func (rm *RenderMetrics) recordSkippedFrame() {
	rm.mutex.Lock()
	defer rm.mutex.Unlock()
	rm.SkippedFrames++
}

func (rm *RenderMetrics) GetSnapshot() RenderMetrics {
	rm.mutex.RLock()
	defer rm.mutex.RUnlock()
	return *rm
}

// RenderProfiler implementation
func NewRenderProfiler(enabled bool) *RenderProfiler {
	return &RenderProfiler{
		samples:    make([]ProfileSample, 0, 1000),
		maxSamples: 1000,
		hotspots:   make(map[string]*Hotspot),
		enabled:    enabled,
	}
}

func (rp *RenderProfiler) StartSample(phase string) {
	if !rp.enabled {
		return
	}

	sample := ProfileSample{
		Timestamp:  time.Now(),
		Phase:      phase,
		Goroutines: runtime.NumGoroutine(),
	}

	// Get memory stats
	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)
	sample.MemoryUsed = memStats.Alloc

	rp.mutex.Lock()
	defer rp.mutex.Unlock()

	if len(rp.samples) >= rp.maxSamples {
		// Remove oldest samples
		rp.samples = rp.samples[100:]
	}
	rp.samples = append(rp.samples, sample)
}

func (rp *RenderProfiler) EndSample(phase string, metadata map[string]interface{}) {
	if !rp.enabled {
		return
	}

	rp.mutex.Lock()
	defer rp.mutex.Unlock()

	// Find matching start sample
	for i := len(rp.samples) - 1; i >= 0; i-- {
		if rp.samples[i].Phase == phase && rp.samples[i].Duration == 0 {
			rp.samples[i].Duration = time.Since(rp.samples[i].Timestamp)
			rp.samples[i].Metadata = metadata

			// Update hotspot
			if hotspot, exists := rp.hotspots[phase]; exists {
				hotspot.CallCount++
				hotspot.TotalTime += rp.samples[i].Duration
				hotspot.AverageTime = hotspot.TotalTime / time.Duration(hotspot.CallCount)
				if rp.samples[i].Duration > hotspot.MaxTime {
					hotspot.MaxTime = rp.samples[i].Duration
				}
			} else {
				rp.hotspots[phase] = &Hotspot{
					Name:        phase,
					CallCount:   1,
					TotalTime:   rp.samples[i].Duration,
					AverageTime: rp.samples[i].Duration,
					MaxTime:     rp.samples[i].Duration,
				}
			}
			break
		}
	}
}

func (rp *RenderProfiler) GetSamples() []ProfileSample {
	rp.mutex.RLock()
	defer rp.mutex.RUnlock()

	result := make([]ProfileSample, len(rp.samples))
	copy(result, rp.samples)
	return result
}

func (rp *RenderProfiler) GetHotspots() map[string]*Hotspot {
	rp.mutex.RLock()
	defer rp.mutex.RUnlock()

	result := make(map[string]*Hotspot)
	for k, v := range rp.hotspots {
		result[k] = v
	}
	return result
}

// Placeholder implementations
type FrameCache struct {
	frames map[uint64]*Frame
	size   int
}

func NewFrameCache(size int) *FrameCache {
	return &FrameCache{
		frames: make(map[uint64]*Frame),
		size:   size,
	}
}

func (fc *FrameCache) Set(frame *Frame) {
	fc.frames[frame.ID] = frame
}

type StyleCache struct {
	styles map[string]lipgloss.Style
	size   int
}

func NewStyleCache(size int) *StyleCache {
	return &StyleCache{
		styles: make(map[string]lipgloss.Style),
		size:   size,
	}
}

type DiffCache struct {
	results map[string]*DiffResult
	size    int
}

func NewDiffCache(size int) *DiffCache {
	return &DiffCache{
		results: make(map[string]*DiffResult),
		size:    size,
	}
}

type WorkerPool struct {
	workers int
}

func NewWorkerPool(workers int) *WorkerPool {
	return &WorkerPool{workers: workers}
}
