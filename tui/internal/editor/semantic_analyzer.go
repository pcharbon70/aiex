package editor

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"aiex-tui/internal/rpc"
)

// SemanticAnalyzer provides intelligent code analysis and understanding
type SemanticAnalyzer struct {
	// Core components
	rpcClient     *rpc.Client
	analysisCache *AnalysisCache

	// Analysis state
	currentFile   string
	currentLang   string
	lastAnalysis  time.Time
	analysisID    string

	// Symbol tracking
	symbols       map[string][]Symbol
	references    map[string][]Reference
	diagnostics   map[string][]Diagnostic
	suggestions   map[string][]CodeSuggestion

	// Configuration
	config        SemanticConfig

	// Synchronization
	mutex         sync.RWMutex
	running       bool

	// Context
	ctx           context.Context
	cancel        context.CancelFunc
}

// SemanticConfig configures the semantic analyzer
type SemanticConfig struct {
	EnableRealTimeAnalysis    bool          `json:"enable_real_time_analysis"`
	EnableIncrementalAnalysis bool          `json:"enable_incremental_analysis"`
	AnalysisDebounceDelay     time.Duration `json:"analysis_debounce_delay"`
	MaxCacheSize              int           `json:"max_cache_size"`
	AnalysisTimeout           time.Duration `json:"analysis_timeout"`
	EnableSemanticHighlight   bool          `json:"enable_semantic_highlight"`
	EnableCodeLens           bool          `json:"enable_code_lens"`
	EnableHover              bool          `json:"enable_hover"`
	EnableDefinitionLinks    bool          `json:"enable_definition_links"`
}

// AnalysisRequest represents a request for semantic analysis
type AnalysisRequest struct {
	ID          string                 `json:"id"`
	FilePath    string                 `json:"file_path"`
	Content     []string               `json:"content"`
	Language    string                 `json:"language"`
	ProjectPath string                 `json:"project_path"`
	Incremental bool                   `json:"incremental"`
	Changes     []ContentChange        `json:"changes,omitempty"`
	Options     map[string]interface{} `json:"options,omitempty"`
	Timestamp   time.Time              `json:"timestamp"`
}

// AnalysisResponse represents the response from semantic analysis
type AnalysisResponse struct {
	ID          string            `json:"id"`
	Success     bool              `json:"success"`
	Symbols     []Symbol          `json:"symbols"`
	Diagnostics []Diagnostic      `json:"diagnostics"`
	Suggestions []CodeSuggestion  `json:"suggestions"`
	References  []Reference       `json:"references"`
	Hover       []HoverInfo       `json:"hover,omitempty"`
	CodeLens    []CodeLens        `json:"code_lens,omitempty"`
	SemanticTokens []SemanticToken `json:"semantic_tokens,omitempty"`
	Error       string            `json:"error,omitempty"`
	ProcessTime time.Duration     `json:"process_time"`
	Timestamp   time.Time         `json:"timestamp"`
}

// ContentChange represents an incremental change to file content
type ContentChange struct {
	StartLine   int    `json:"start_line"`
	StartColumn int    `json:"start_column"`
	EndLine     int    `json:"end_line"`
	EndColumn   int    `json:"end_column"`
	NewText     string `json:"new_text"`
	ChangeType  string `json:"change_type"` // insert, delete, replace
}

// HoverInfo represents hover information for a symbol
type HoverInfo struct {
	Line        int    `json:"line"`
	Column      int    `json:"column"`
	Content     string `json:"content"`
	ContentType string `json:"content_type"` // markdown, plaintext
	Language    string `json:"language,omitempty"`
}

// CodeLens represents a code lens annotation
type CodeLens struct {
	Line    int    `json:"line"`
	Column  int    `json:"column"`
	Title   string `json:"title"`
	Command string `json:"command"`
	Args    []interface{} `json:"args,omitempty"`
}

// SemanticToken represents a semantically highlighted token
type SemanticToken struct {
	Line        int    `json:"line"`
	StartColumn int    `json:"start_column"`
	EndColumn   int    `json:"end_column"`
	TokenType   string `json:"token_type"`
	Modifiers   []string `json:"modifiers,omitempty"`
}

// AnalysisCache caches analysis results
type AnalysisCache struct {
	entries   map[string]*CacheEntry
	maxSize   int
	mutex     sync.RWMutex
}

// CacheEntry represents a cached analysis result
type CacheEntry struct {
	Response    AnalysisResponse `json:"response"`
	ContentHash string          `json:"content_hash"`
	Timestamp   time.Time       `json:"timestamp"`
	AccessCount int             `json:"access_count"`
	LastAccess  time.Time       `json:"last_access"`
}

// NewSemanticAnalyzer creates a new semantic analyzer
func NewSemanticAnalyzer(rpcClient *rpc.Client) *SemanticAnalyzer {
	ctx, cancel := context.WithCancel(context.Background())
	
	config := SemanticConfig{
		EnableRealTimeAnalysis:    true,
		EnableIncrementalAnalysis: true,
		AnalysisDebounceDelay:     300 * time.Millisecond,
		MaxCacheSize:              100,
		AnalysisTimeout:           10 * time.Second,
		EnableSemanticHighlight:   true,
		EnableCodeLens:           true,
		EnableHover:              true,
		EnableDefinitionLinks:    true,
	}
	
	sa := &SemanticAnalyzer{
		rpcClient:     rpcClient,
		analysisCache: NewAnalysisCache(config.MaxCacheSize),
		symbols:       make(map[string][]Symbol),
		references:    make(map[string][]Reference),
		diagnostics:   make(map[string][]Diagnostic),
		suggestions:   make(map[string][]CodeSuggestion),
		config:        config,
		ctx:           ctx,
		cancel:        cancel,
	}
	
	return sa
}

// Start begins semantic analysis services
func (sa *SemanticAnalyzer) Start() error {
	sa.mutex.Lock()
	defer sa.mutex.Unlock()
	
	if sa.running {
		return fmt.Errorf("semantic analyzer already running")
	}
	
	sa.running = true
	
	// Start background cache cleanup
	go sa.cacheMaintenanceLoop()
	
	return nil
}

// Stop ends semantic analysis services
func (sa *SemanticAnalyzer) Stop() error {
	sa.mutex.Lock()
	defer sa.mutex.Unlock()
	
	if !sa.running {
		return fmt.Errorf("semantic analyzer not running")
	}
	
	sa.running = false
	sa.cancel()
	
	return nil
}

// Analyze performs semantic analysis on the given file content
func (sa *SemanticAnalyzer) Analyze(filePath string, content []string) ([]Symbol, []Diagnostic, error) {
	sa.mutex.Lock()
	defer sa.mutex.Unlock()
	
	// Check cache first
	contentHash := sa.calculateContentHash(content)
	if cached, found := sa.analysisCache.Get(filePath, contentHash); found {
		// Update local state from cache
		sa.updateFromCachedResponse(filePath, cached.Response)
		return cached.Response.Symbols, cached.Response.Diagnostics, nil
	}
	
	// Detect language
	language := sa.detectLanguage(filePath)
	
	// Create analysis request
	request := AnalysisRequest{
		ID:          sa.generateAnalysisID(),
		FilePath:    filePath,
		Content:     content,
		Language:    language,
		ProjectPath: sa.getProjectPath(filePath),
		Incremental: sa.config.EnableIncrementalAnalysis && sa.currentFile == filePath,
		Options:     sa.buildAnalysisOptions(),
		Timestamp:   time.Now(),
	}
	
	// Add incremental changes if applicable
	if request.Incremental {
		request.Changes = sa.calculateIncrementalChanges(filePath, content)
	}
	
	// Perform analysis
	response, err := sa.performAnalysis(request)
	if err != nil {
		return nil, nil, fmt.Errorf("analysis failed: %w", err)
	}
	
	// Cache result
	sa.analysisCache.Set(filePath, contentHash, *response)
	
	// Update local state
	sa.updateFromResponse(filePath, *response)
	
	// Update tracking
	sa.currentFile = filePath
	sa.currentLang = language
	sa.lastAnalysis = time.Now()
	sa.analysisID = request.ID
	
	return response.Symbols, response.Diagnostics, nil
}

// GetSymbolAtPosition returns the symbol at the given position
func (sa *SemanticAnalyzer) GetSymbolAtPosition(filePath string, line, column int) (*Symbol, error) {
	sa.mutex.RLock()
	defer sa.mutex.RUnlock()
	
	symbols, exists := sa.symbols[filePath]
	if !exists {
		return nil, fmt.Errorf("no symbols found for file: %s", filePath)
	}
	
	for _, symbol := range symbols {
		if sa.positionInRange(line, column, symbol.Line, symbol.Column, symbol.EndLine, symbol.EndColumn) {
			return &symbol, nil
		}
	}
	
	return nil, fmt.Errorf("no symbol found at position %d:%d", line, column)
}

// GetHoverInfo returns hover information for the given position
func (sa *SemanticAnalyzer) GetHoverInfo(filePath string, line, column int) (*HoverInfo, error) {
	if !sa.config.EnableHover {
		return nil, fmt.Errorf("hover information disabled")
	}
	
	ctx, cancel := context.WithTimeout(sa.ctx, 3*time.Second)
	defer cancel()
	
	request := map[string]interface{}{
		"file_path": filePath,
		"line":      line,
		"column":    column,
		"language":  sa.currentLang,
	}
	
	response, err := sa.rpcClient.Call(ctx, "semantic_analysis.get_hover", request)
	if err != nil {
		return nil, err
	}
	
	var hoverInfo HoverInfo
	if err := json.Unmarshal(response, &hoverInfo); err != nil {
		return nil, err
	}
	
	return &hoverInfo, nil
}

// GetDefinition returns the definition location for the symbol at the given position
func (sa *SemanticAnalyzer) GetDefinition(filePath string, line, column int) (*Reference, error) {
	if !sa.config.EnableDefinitionLinks {
		return nil, fmt.Errorf("definition links disabled")
	}
	
	ctx, cancel := context.WithTimeout(sa.ctx, 5*time.Second)
	defer cancel()
	
	request := map[string]interface{}{
		"file_path": filePath,
		"line":      line,
		"column":    column,
		"language":  sa.currentLang,
	}
	
	response, err := sa.rpcClient.Call(ctx, "semantic_analysis.get_definition", request)
	if err != nil {
		return nil, err
	}
	
	var definition Reference
	if err := json.Unmarshal(response, &definition); err != nil {
		return nil, err
	}
	
	return &definition, nil
}

// GetCodeLens returns code lens information for the given file
func (sa *SemanticAnalyzer) GetCodeLens(filePath string) ([]CodeLens, error) {
	if !sa.config.EnableCodeLens {
		return nil, fmt.Errorf("code lens disabled")
	}
	
	ctx, cancel := context.WithTimeout(sa.ctx, 5*time.Second)
	defer cancel()
	
	request := map[string]interface{}{
		"file_path": filePath,
		"language":  sa.currentLang,
	}
	
	response, err := sa.rpcClient.Call(ctx, "semantic_analysis.get_code_lens", request)
	if err != nil {
		return nil, err
	}
	
	var codeLens []CodeLens
	if err := json.Unmarshal(response, &codeLens); err != nil {
		return nil, err
	}
	
	return codeLens, nil
}

// GetDiagnostics returns current diagnostics for the given file
func (sa *SemanticAnalyzer) GetDiagnostics(filePath string) []Diagnostic {
	sa.mutex.RLock()
	defer sa.mutex.RUnlock()
	
	if diagnostics, exists := sa.diagnostics[filePath]; exists {
		return diagnostics
	}
	return []Diagnostic{}
}

// GetSuggestions returns current code suggestions for the given file
func (sa *SemanticAnalyzer) GetSuggestions(filePath string) []CodeSuggestion {
	sa.mutex.RLock()
	defer sa.mutex.RUnlock()
	
	if suggestions, exists := sa.suggestions[filePath]; exists {
		return suggestions
	}
	return []CodeSuggestion{}
}

// Internal methods
func (sa *SemanticAnalyzer) performAnalysis(request AnalysisRequest) (*AnalysisResponse, error) {
	ctx, cancel := context.WithTimeout(sa.ctx, sa.config.AnalysisTimeout)
	defer cancel()
	
	response, err := sa.rpcClient.Call(ctx, "semantic_analysis.analyze", request)
	if err != nil {
		return nil, err
	}
	
	var analysisResponse AnalysisResponse
	if err := json.Unmarshal(response, &analysisResponse); err != nil {
		return nil, err
	}
	
	if !analysisResponse.Success {
		return nil, fmt.Errorf("analysis failed: %s", analysisResponse.Error)
	}
	
	return &analysisResponse, nil
}

func (sa *SemanticAnalyzer) updateFromResponse(filePath string, response AnalysisResponse) {
	sa.symbols[filePath] = response.Symbols
	sa.diagnostics[filePath] = response.Diagnostics
	sa.suggestions[filePath] = response.Suggestions
	sa.references[filePath] = response.References
}

func (sa *SemanticAnalyzer) updateFromCachedResponse(filePath string, response AnalysisResponse) {
	sa.updateFromResponse(filePath, response)
}

func (sa *SemanticAnalyzer) detectLanguage(filePath string) string {
	ext := strings.ToLower(filePath[strings.LastIndex(filePath, "."):])
	switch ext {
	case ".go":
		return "go"
	case ".ex", ".exs":
		return "elixir"
	case ".js":
		return "javascript"
	case ".ts":
		return "typescript"
	case ".py":
		return "python"
	case ".rs":
		return "rust"
	case ".c", ".h":
		return "c"
	case ".cpp", ".hpp", ".cc":
		return "cpp"
	default:
		return "text"
	}
}

func (sa *SemanticAnalyzer) getProjectPath(filePath string) string {
	// Simple heuristic to find project root
	parts := strings.Split(filePath, "/")
	for i := len(parts) - 1; i >= 0; i-- {
		potentialPath := strings.Join(parts[:i+1], "/")
		// Look for common project markers
		if strings.Contains(potentialPath, "go.mod") || 
		   strings.Contains(potentialPath, "mix.exs") ||
		   strings.Contains(potentialPath, "package.json") {
			return potentialPath
		}
	}
	return "/"
}

func (sa *SemanticAnalyzer) buildAnalysisOptions() map[string]interface{} {
	options := map[string]interface{}{
		"enable_semantic_highlight": sa.config.EnableSemanticHighlight,
		"enable_code_lens":          sa.config.EnableCodeLens,
		"enable_hover":              sa.config.EnableHover,
		"enable_definition_links":   sa.config.EnableDefinitionLinks,
	}
	return options
}

func (sa *SemanticAnalyzer) calculateIncrementalChanges(filePath string, content []string) []ContentChange {
	// Simplified incremental change calculation
	// In a real implementation, this would use a diff algorithm
	return []ContentChange{}
}

func (sa *SemanticAnalyzer) calculateContentHash(content []string) string {
	// Simple hash calculation
	hash := 0
	for _, line := range content {
		for _, char := range line {
			hash += int(char)
		}
	}
	return fmt.Sprintf("%x", hash)
}

func (sa *SemanticAnalyzer) generateAnalysisID() string {
	return fmt.Sprintf("analysis_%d", time.Now().UnixNano())
}

func (sa *SemanticAnalyzer) positionInRange(line, column, startLine, startColumn, endLine, endColumn int) bool {
	if line < startLine || line > endLine {
		return false
	}
	if line == startLine && column < startColumn {
		return false
	}
	if line == endLine && column > endColumn {
		return false
	}
	return true
}

func (sa *SemanticAnalyzer) cacheMaintenanceLoop() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	
	for {
		select {
		case <-sa.ctx.Done():
			return
		case <-ticker.C:
			sa.analysisCache.Cleanup()
		}
	}
}

// AnalysisCache implementation
func NewAnalysisCache(maxSize int) *AnalysisCache {
	return &AnalysisCache{
		entries: make(map[string]*CacheEntry),
		maxSize: maxSize,
	}
}

func (ac *AnalysisCache) Get(filePath, contentHash string) (*CacheEntry, bool) {
	ac.mutex.RLock()
	defer ac.mutex.RUnlock()
	
	key := fmt.Sprintf("%s:%s", filePath, contentHash)
	entry, exists := ac.entries[key]
	if exists {
		entry.AccessCount++
		entry.LastAccess = time.Now()
	}
	return entry, exists
}

func (ac *AnalysisCache) Set(filePath, contentHash string, response AnalysisResponse) {
	ac.mutex.Lock()
	defer ac.mutex.Unlock()
	
	// Check if we need to evict entries
	if len(ac.entries) >= ac.maxSize {
		ac.evictOldest()
	}
	
	key := fmt.Sprintf("%s:%s", filePath, contentHash)
	ac.entries[key] = &CacheEntry{
		Response:    response,
		ContentHash: contentHash,
		Timestamp:   time.Now(),
		AccessCount: 1,
		LastAccess:  time.Now(),
	}
}

func (ac *AnalysisCache) Cleanup() {
	ac.mutex.Lock()
	defer ac.mutex.Unlock()
	
	// Remove entries older than 1 hour
	cutoff := time.Now().Add(-time.Hour)
	for key, entry := range ac.entries {
		if entry.LastAccess.Before(cutoff) {
			delete(ac.entries, key)
		}
	}
}

func (ac *AnalysisCache) evictOldest() {
	var oldestKey string
	var oldestTime time.Time
	
	for key, entry := range ac.entries {
		if oldestKey == "" || entry.LastAccess.Before(oldestTime) {
			oldestKey = key
			oldestTime = entry.LastAccess
		}
	}
	
	if oldestKey != "" {
		delete(ac.entries, oldestKey)
	}
}
