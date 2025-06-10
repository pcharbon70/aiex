package performance

import (
	"context"
	"encoding/json"
	"fmt"
	"runtime"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// PerformanceMonitor provides comprehensive performance monitoring and profiling
type PerformanceMonitor struct {
	// Core components
	memoryManager   *MemoryManager
	renderPipeline  *RenderPipeline
	virtualScroller *VirtualScroller
	lazyLoader      *LazyLoader

	// Monitoring state
	metrics         *PerformanceMetrics
	profiler        *SystemProfiler
	alerts          *AlertManager

	// Configuration
	config          MonitorConfig

	// Synchronization
	mutex           sync.RWMutex
	running         bool

	// Context
	ctx             context.Context
	cancel          context.CancelFunc
}

// MonitorConfig configures performance monitoring
type MonitorConfig struct {
	SampleInterval     time.Duration `json:"sample_interval"`
	RetentionPeriod    time.Duration `json:"retention_period"`
	AlertThresholds    AlertThresholds `json:"alert_thresholds"`
	EnableProfiling    bool          `json:"enable_profiling"`
	EnableRealtimeView bool          `json:"enable_realtime_view"`
	MaxSamples         int           `json:"max_samples"`
	ReportInterval     time.Duration `json:"report_interval"`
}

// PerformanceMetrics aggregates all performance data
type PerformanceMetrics struct {
	// System metrics
	Memory         MemoryMetrics        `json:"memory"`
	CPU            CPUMetrics           `json:"cpu"`
	Goroutines     GoroutineMetrics     `json:"goroutines"`

	// Component metrics
	Rendering      RenderingMetrics     `json:"rendering"`
	Scrolling      ScrollingMetrics     `json:"scrolling"`
	Loading        LoadingMetrics       `json:"loading"`
	Caching        CachingMetrics       `json:"caching"`

	// Performance metrics
	Framerate      FramerateMetrics     `json:"framerate"`
	Latency        LatencyMetrics       `json:"latency"`
	Throughput     ThroughputMetrics    `json:"throughput"`

	// Historical data
	Samples        []PerformanceSample  `json:"samples"`
	Timestamp      time.Time            `json:"timestamp"`
	mutex          sync.RWMutex
}

// Individual metric types
type MemoryMetrics struct {
	Allocated      uint64        `json:"allocated"`
	Total          uint64        `json:"total"`
	System         uint64        `json:"system"`
	GCPauses       time.Duration `json:"gc_pauses"`
	GCFrequency    float64       `json:"gc_frequency"`
	PressureLevel  int           `json:"pressure_level"`
}

type CPUMetrics struct {
	Usage          float64       `json:"usage"`
	IdleTime       time.Duration `json:"idle_time"`
	SystemTime     time.Duration `json:"system_time"`
	UserTime       time.Duration `json:"user_time"`
}

type GoroutineMetrics struct {
	Active         int     `json:"active"`
	Peak           int     `json:"peak"`
	Average        float64 `json:"average"`
	Blocked        int     `json:"blocked"`
}

type RenderingMetrics struct {
	FPS            float64       `json:"fps"`
	FrameTime      time.Duration `json:"frame_time"`
	SkippedFrames  int           `json:"skipped_frames"`
	CacheHitRate   float64       `json:"cache_hit_rate"`
	DirtyRegions   int           `json:"dirty_regions"`
}

type ScrollingMetrics struct {
	ScrollFPS      float64       `json:"scroll_fps"`
	ScrollLatency  time.Duration `json:"scroll_latency"`
	VisibleItems   int           `json:"visible_items"`
	TotalItems     int           `json:"total_items"`
	CacheEfficiency float64      `json:"cache_efficiency"`
}

type LoadingMetrics struct {
	PendingLoads   int           `json:"pending_loads"`
	ActiveLoads    int           `json:"active_loads"`
	AverageTime    time.Duration `json:"average_time"`
	SuccessRate    float64       `json:"success_rate"`
	Throughput     float64       `json:"throughput"`
}

type CachingMetrics struct {
	HitRate        float64 `json:"hit_rate"`
	MissRate       float64 `json:"miss_rate"`
	EvictionRate   float64 `json:"eviction_rate"`
	MemoryUsage    int64   `json:"memory_usage"`
	ItemCount      int     `json:"item_count"`
}

type FramerateMetrics struct {
	Current        float64 `json:"current"`
	Average        float64 `json:"average"`
	Min            float64 `json:"min"`
	Max            float64 `json:"max"`
	Target         float64 `json:"target"`
}

type LatencyMetrics struct {
	Input          time.Duration `json:"input"`
	Render         time.Duration `json:"render"`
	Network        time.Duration `json:"network"`
	Total          time.Duration `json:"total"`
}

type ThroughputMetrics struct {
	Messages       float64 `json:"messages"`
	Files          float64 `json:"files"`
	Operations     float64 `json:"operations"`
	BytesProcessed int64   `json:"bytes_processed"`
}

// PerformanceSample represents a point-in-time performance sample
type PerformanceSample struct {
	Timestamp      time.Time     `json:"timestamp"`
	MemoryUsage    uint64        `json:"memory_usage"`
	CPUUsage       float64       `json:"cpu_usage"`
	Goroutines     int           `json:"goroutines"`
	FPS            float64       `json:"fps"`
	Latency        time.Duration `json:"latency"`
	CacheHitRate   float64       `json:"cache_hit_rate"`
	ActiveLoads    int           `json:"active_loads"`
}

// SystemProfiler provides detailed system profiling
type SystemProfiler struct {
	profiles       map[string]*Profile
	hotspots       []*Hotspot
	enabled        bool
	sampling       bool
	sampleRate     time.Duration
	mutex          sync.RWMutex
}

// Profile represents a performance profile
type Profile struct {
	Name           string            `json:"name"`
	StartTime      time.Time         `json:"start_time"`
	Duration       time.Duration     `json:"duration"`
	Samples        []ProfileSample   `json:"samples"`
	StackTraces    []StackTrace      `json:"stack_traces"`
	FunctionStats  map[string]*FuncStat `json:"function_stats"`
}

// FuncStat represents function-level statistics
type FuncStat struct {
	Name           string        `json:"name"`
	CallCount      uint64        `json:"call_count"`
	TotalTime      time.Duration `json:"total_time"`
	SelfTime       time.Duration `json:"self_time"`
	AverageTime    time.Duration `json:"average_time"`
	MaxTime        time.Duration `json:"max_time"`
}

// StackTrace represents a stack trace sample
type StackTrace struct {
	Timestamp      time.Time `json:"timestamp"`
	GoroutineID    int       `json:"goroutine_id"`
	Stack          []string  `json:"stack"`
	CPUTime        time.Duration `json:"cpu_time"`
}

// AlertManager handles performance alerts
type AlertManager struct {
	thresholds     AlertThresholds
	active         map[string]*Alert
	callbacks      []AlertCallback
	mutex          sync.RWMutex
}

// AlertThresholds defines performance alert thresholds
type AlertThresholds struct {
	MemoryUsage    uint64        `json:"memory_usage"`
	CPUUsage       float64       `json:"cpu_usage"`
	Framerate      float64       `json:"framerate"`
	Latency        time.Duration `json:"latency"`
	Goroutines     int           `json:"goroutines"`
	CacheHitRate   float64       `json:"cache_hit_rate"`
	LoadTime       time.Duration `json:"load_time"`
}

// Alert represents a performance alert
type Alert struct {
	ID             string                 `json:"id"`
	Type           AlertType              `json:"type"`
	Severity       AlertSeverity          `json:"severity"`
	Message        string                 `json:"message"`
	Metric         string                 `json:"metric"`
	Value          interface{}            `json:"value"`
	Threshold      interface{}            `json:"threshold"`
	Timestamp      time.Time              `json:"timestamp"`
	Acknowledged   bool                   `json:"acknowledged"`
	Metadata       map[string]interface{} `json:"metadata"`
}

// AlertType represents the type of alert
type AlertType int

const (
	AlertTypeMemory AlertType = iota
	AlertTypeCPU
	AlertTypeFramerate
	AlertTypeLatency
	AlertTypeGoroutines
	AlertTypeCache
	AlertTypeLoading
)

// AlertSeverity represents alert severity
type AlertSeverity int

const (
	SeverityInfo AlertSeverity = iota
	SeverityWarning
	SeverityError
	SeverityCritical
)

// AlertCallback is called when alerts are triggered
type AlertCallback func(alert *Alert)

// NewPerformanceMonitor creates a new performance monitor
func NewPerformanceMonitor(memoryManager *MemoryManager, renderPipeline *RenderPipeline, virtualScroller *VirtualScroller, lazyLoader *LazyLoader) *PerformanceMonitor {
	ctx, cancel := context.WithCancel(context.Background())

	config := MonitorConfig{
		SampleInterval:     1 * time.Second,
		RetentionPeriod:    1 * time.Hour,
		EnableProfiling:    true,
		EnableRealtimeView: true,
		MaxSamples:         3600, // 1 hour at 1 second intervals
		ReportInterval:     10 * time.Second,
		AlertThresholds: AlertThresholds{
			MemoryUsage:  256 * 1024 * 1024, // 256MB
			CPUUsage:     80.0,              // 80%
			Framerate:    30.0,              // 30 FPS minimum
			Latency:      100 * time.Millisecond,
			Goroutines:   1000,
			CacheHitRate: 0.8,               // 80% minimum
			LoadTime:     5 * time.Second,
		},
	}

	pm := &PerformanceMonitor{
		memoryManager:   memoryManager,
		renderPipeline:  renderPipeline,
		virtualScroller: virtualScroller,
		lazyLoader:      lazyLoader,
		metrics:         NewPerformanceMetrics(),
		profiler:        NewSystemProfiler(config.EnableProfiling),
		alerts:          NewAlertManager(config.AlertThresholds),
		config:          config,
		ctx:             ctx,
		cancel:          cancel,
	}

	return pm
}

// Start begins performance monitoring
func (pm *PerformanceMonitor) Start() error {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()

	if pm.running {
		return fmt.Errorf("performance monitor already running")
	}

	pm.running = true

	// Start monitoring loops
	go pm.monitoringLoop()
	go pm.alertingLoop()

	if pm.config.EnableProfiling {
		go pm.profilingLoop()
	}

	go pm.reportingLoop()

	return nil
}

// Stop ends performance monitoring
func (pm *PerformanceMonitor) Stop() error {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()

	if !pm.running {
		return fmt.Errorf("performance monitor not running")
	}

	pm.running = false
	pm.cancel()

	return nil
}

// GetMetrics returns current performance metrics
func (pm *PerformanceMonitor) GetMetrics() PerformanceMetrics {
	pm.metrics.mutex.RLock()
	defer pm.metrics.mutex.RUnlock()
	return *pm.metrics
}

// GetRealtimeStats returns real-time performance statistics
func (pm *PerformanceMonitor) GetRealtimeStats() map[string]interface{} {
	metrics := pm.GetMetrics()
	return map[string]interface{}{
		"memory_usage":    metrics.Memory.Allocated,
		"cpu_usage":       metrics.CPU.Usage,
		"goroutines":      metrics.Goroutines.Active,
		"fps":             metrics.Framerate.Current,
		"cache_hit_rate":  metrics.Caching.HitRate,
		"active_loads":    metrics.Loading.ActiveLoads,
		"timestamp":       time.Now(),
	}
}

// StartProfiling begins profiling a specific operation
func (pm *PerformanceMonitor) StartProfiling(name string) {
	pm.profiler.StartProfile(name)
}

// StopProfiling ends profiling and returns results
func (pm *PerformanceMonitor) StopProfiling(name string) *Profile {
	return pm.profiler.StopProfile(name)
}

// RegisterAlertCallback registers an alert callback
func (pm *PerformanceMonitor) RegisterAlertCallback(callback AlertCallback) {
	pm.alerts.RegisterCallback(callback)
}

// GetActiveAlerts returns currently active alerts
func (pm *PerformanceMonitor) GetActiveAlerts() []*Alert {
	return pm.alerts.GetActiveAlerts()
}

// AcknowledgeAlert acknowledges an alert
func (pm *PerformanceMonitor) AcknowledgeAlert(alertID string) {
	pm.alerts.Acknowledge(alertID)
}

// Background monitoring loops
func (pm *PerformanceMonitor) monitoringLoop() {
	ticker := time.NewTicker(pm.config.SampleInterval)
	defer ticker.Stop()

	for {
		select {
		case <-pm.ctx.Done():
			return
		case <-ticker.C:
			pm.collectMetrics()
		}
	}
}

func (pm *PerformanceMonitor) collectMetrics() {
	// Collect system metrics
	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)

	// Collect component metrics
	renderMetrics := pm.renderPipeline.GetMetrics()
	scrollStats := pm.virtualScroller.GetPerformanceStats()
	cacheStats := pm.lazyLoader.GetCacheStats()
	memoryStats := pm.memoryManager.GetStats()

	// Update metrics
	pm.metrics.mutex.Lock()
	pm.metrics.Memory = MemoryMetrics{
		Allocated:     memStats.Alloc,
		Total:         memStats.TotalAlloc,
		System:        memStats.Sys,
		GCPauses:      time.Duration(memStats.PauseTotalNs),
		GCFrequency:   float64(memStats.NumGC),
		PressureLevel: 0, // Would be calculated from memory manager
	}

	pm.metrics.Goroutines = GoroutineMetrics{
		Active:  runtime.NumGoroutine(),
		Peak:    0, // Track peak
		Average: 0, // Calculate average
		Blocked: 0, // Would need runtime introspection
	}

	pm.metrics.Rendering = RenderingMetrics{
		FPS:           60.0, // Calculate from render metrics
		FrameTime:     renderMetrics.AverageFrameTime,
		SkippedFrames: int(renderMetrics.SkippedFrames),
		CacheHitRate:  float64(renderMetrics.CacheHits) / float64(renderMetrics.CacheHits+renderMetrics.CacheMisses),
		DirtyRegions:  0, // Would be tracked by render pipeline
	}

	pm.metrics.Scrolling = ScrollingMetrics{
		ScrollFPS:       60.0, // Calculate from scroll stats
		ScrollLatency:   scrollStats.FrameTime,
		VisibleItems:    scrollStats.VisibleItems,
		TotalItems:      scrollStats.TotalItems,
		CacheEfficiency: scrollStats.CacheHitRate,
	}

	pm.metrics.Caching = CachingMetrics{
		HitRate:      cacheStats.HitRate,
		MissRate:     1.0 - cacheStats.HitRate,
		EvictionRate: 0, // Would be tracked by cache
		MemoryUsage:  cacheStats.MemoryUsage,
		ItemCount:    cacheStats.Items,
	}

	pm.metrics.Timestamp = time.Now()

	// Add sample to history
	sample := PerformanceSample{
		Timestamp:    time.Now(),
		MemoryUsage:  memStats.Alloc,
		CPUUsage:     0, // Would need CPU monitoring
		Goroutines:   runtime.NumGoroutine(),
		FPS:          pm.metrics.Rendering.FPS,
		Latency:      pm.metrics.Rendering.FrameTime,
		CacheHitRate: pm.metrics.Caching.HitRate,
		ActiveLoads:  pm.metrics.Loading.ActiveLoads,
	}

	pm.metrics.Samples = append(pm.metrics.Samples, sample)
	if len(pm.metrics.Samples) > pm.config.MaxSamples {
		pm.metrics.Samples = pm.metrics.Samples[1:]
	}

	pm.metrics.mutex.Unlock()
}

func (pm *PerformanceMonitor) alertingLoop() {
	ticker := time.NewTicker(pm.config.SampleInterval)
	defer ticker.Stop()

	for {
		select {
		case <-pm.ctx.Done():
			return
		case <-ticker.C:
			pm.checkAlerts()
		}
	}
}

func (pm *PerformanceMonitor) checkAlerts() {
	metrics := pm.GetMetrics()

	// Check memory alerts
	if metrics.Memory.Allocated > pm.config.AlertThresholds.MemoryUsage {
		pm.alerts.TriggerAlert(AlertTypeMemory, SeverityWarning, 
			fmt.Sprintf("High memory usage: %d bytes", metrics.Memory.Allocated),
			metrics.Memory.Allocated, pm.config.AlertThresholds.MemoryUsage)
	}

	// Check framerate alerts
	if metrics.Framerate.Current < pm.config.AlertThresholds.Framerate {
		pm.alerts.TriggerAlert(AlertTypeFramerate, SeverityWarning,
			fmt.Sprintf("Low framerate: %.1f FPS", metrics.Framerate.Current),
			metrics.Framerate.Current, pm.config.AlertThresholds.Framerate)
	}

	// Check cache hit rate alerts
	if metrics.Caching.HitRate < pm.config.AlertThresholds.CacheHitRate {
		pm.alerts.TriggerAlert(AlertTypeCache, SeverityWarning,
			fmt.Sprintf("Low cache hit rate: %.2f", metrics.Caching.HitRate),
			metrics.Caching.HitRate, pm.config.AlertThresholds.CacheHitRate)
	}

	// Check goroutine alerts
	if metrics.Goroutines.Active > pm.config.AlertThresholds.Goroutines {
		pm.alerts.TriggerAlert(AlertTypeGoroutines, SeverityError,
			fmt.Sprintf("High goroutine count: %d", metrics.Goroutines.Active),
			metrics.Goroutines.Active, pm.config.AlertThresholds.Goroutines)
	}
}

func (pm *PerformanceMonitor) profilingLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-pm.ctx.Done():
			return
		case <-ticker.C:
			pm.profiler.CollectSample()
		}
	}
}

func (pm *PerformanceMonitor) reportingLoop() {
	ticker := time.NewTicker(pm.config.ReportInterval)
	defer ticker.Stop()

	for {
		select {
		case <-pm.ctx.Done():
			return
		case <-ticker.C:
			pm.generateReport()
		}
	}
}

func (pm *PerformanceMonitor) generateReport() {
	// Generate performance report
	metrics := pm.GetMetrics()
	report := map[string]interface{}{
		"timestamp":      time.Now(),
		"memory_usage":   metrics.Memory.Allocated,
		"goroutines":     metrics.Goroutines.Active,
		"framerate":      metrics.Framerate.Current,
		"cache_hit_rate": metrics.Caching.HitRate,
		"active_alerts":  len(pm.alerts.GetActiveAlerts()),
	}

	// In a real implementation, this would be sent to logging/monitoring systems
	_ = report
}

// Factory functions for components
func NewPerformanceMetrics() *PerformanceMetrics {
	return &PerformanceMetrics{
		Samples:   make([]PerformanceSample, 0),
		Timestamp: time.Now(),
	}
}

func NewSystemProfiler(enabled bool) *SystemProfiler {
	return &SystemProfiler{
		profiles:   make(map[string]*Profile),
		hotspots:   make([]*Hotspot, 0),
		enabled:    enabled,
		sampleRate: 100 * time.Millisecond,
	}
}

func NewAlertManager(thresholds AlertThresholds) *AlertManager {
	return &AlertManager{
		thresholds: thresholds,
		active:     make(map[string]*Alert),
		callbacks:  make([]AlertCallback, 0),
	}
}

// SystemProfiler implementation
func (sp *SystemProfiler) StartProfile(name string) {
	if !sp.enabled {
		return
	}

	sp.mutex.Lock()
	defer sp.mutex.Unlock()

	profile := &Profile{
		Name:          name,
		StartTime:     time.Now(),
		Samples:       make([]ProfileSample, 0),
		StackTraces:   make([]StackTrace, 0),
		FunctionStats: make(map[string]*FuncStat),
	}

	sp.profiles[name] = profile
}

func (sp *SystemProfiler) StopProfile(name string) *Profile {
	if !sp.enabled {
		return nil
	}

	sp.mutex.Lock()
	defer sp.mutex.Unlock()

	profile, exists := sp.profiles[name]
	if !exists {
		return nil
	}

	profile.Duration = time.Since(profile.StartTime)
	delete(sp.profiles, name)

	return profile
}

func (sp *SystemProfiler) CollectSample() {
	if !sp.enabled {
		return
	}

	// Collect stack traces and performance samples
	// In a real implementation, this would use runtime/pprof
}

// AlertManager implementation
func (am *AlertManager) TriggerAlert(alertType AlertType, severity AlertSeverity, message string, value, threshold interface{}) {
	alertID := fmt.Sprintf("%d_%d", alertType, time.Now().UnixNano())

	alert := &Alert{
		ID:        alertID,
		Type:      alertType,
		Severity:  severity,
		Message:   message,
		Value:     value,
		Threshold: threshold,
		Timestamp: time.Now(),
		Metadata:  make(map[string]interface{}),
	}

	am.mutex.Lock()
	am.active[alertID] = alert
	am.mutex.Unlock()

	// Notify callbacks
	am.notifyCallbacks(alert)
}

func (am *AlertManager) RegisterCallback(callback AlertCallback) {
	am.mutex.Lock()
	defer am.mutex.Unlock()
	am.callbacks = append(am.callbacks, callback)
}

func (am *AlertManager) GetActiveAlerts() []*Alert {
	am.mutex.RLock()
	defer am.mutex.RUnlock()

	alerts := make([]*Alert, 0, len(am.active))
	for _, alert := range am.active {
		if !alert.Acknowledged {
			alerts = append(alerts, alert)
		}
	}

	return alerts
}

func (am *AlertManager) Acknowledge(alertID string) {
	am.mutex.Lock()
	defer am.mutex.Unlock()

	if alert, exists := am.active[alertID]; exists {
		alert.Acknowledged = true
	}
}

func (am *AlertManager) notifyCallbacks(alert *Alert) {
	am.mutex.RLock()
	callbacks := make([]AlertCallback, len(am.callbacks))
	copy(callbacks, am.callbacks)
	am.mutex.RUnlock()

	for _, callback := range callbacks {
		go callback(alert)
	}
}

// Message types for Bubble Tea integration
type PerformanceUpdateMsg struct {
	Metrics   PerformanceMetrics
	Timestamp time.Time
}

type PerformanceAlertMsg struct {
	Alert *Alert
}

type PerformanceReportMsg struct {
	Report map[string]interface{}
}

// Command constructors
func (pm *PerformanceMonitor) PerformanceUpdateCmd() tea.Cmd {
	return func() tea.Msg {
		return PerformanceUpdateMsg{
			Metrics:   pm.GetMetrics(),
			Timestamp: time.Now(),
		}
	}
}

// GetPerformanceDashboard returns a formatted dashboard view
func (pm *PerformanceMonitor) GetPerformanceDashboard() string {
	metrics := pm.GetMetrics()
	var dashboard strings.Builder

	dashboard.WriteString("📊 Performance Dashboard\n")
	dashboard.WriteString("═══════════════════════\n")
	dashboard.WriteString(fmt.Sprintf("💾 Memory: %d MB / %d GB\n", 
		metrics.Memory.Allocated/(1024*1024), 
		metrics.Memory.System/(1024*1024*1024)))
	dashboard.WriteString(fmt.Sprintf("🔄 Goroutines: %d\n", metrics.Goroutines.Active))
	dashboard.WriteString(fmt.Sprintf("🎬 FPS: %.1f\n", metrics.Framerate.Current))
	dashboard.WriteString(fmt.Sprintf("⚡ Cache Hit Rate: %.1f%%\n", metrics.Caching.HitRate*100))
	dashboard.WriteString(fmt.Sprintf("📥 Active Loads: %d\n", metrics.Loading.ActiveLoads))

	alerts := pm.GetActiveAlerts()
	if len(alerts) > 0 {
		dashboard.WriteString(fmt.Sprintf("🚨 Active Alerts: %d\n", len(alerts)))
	}

	return dashboard.String()
}

// ExportMetrics exports metrics in JSON format
func (pm *PerformanceMonitor) ExportMetrics() ([]byte, error) {
	metrics := pm.GetMetrics()
	return json.MarshalIndent(metrics, "", "  ")
}

import "strings"