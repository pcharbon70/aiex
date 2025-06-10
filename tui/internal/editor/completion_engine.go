package editor

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"aiex-tui/internal/events"
	"aiex-tui/internal/rpc"
)

// CompletionEngine provides intelligent code completion and suggestions
type CompletionEngine struct {
	// Core components
	rpcClient     *rpc.Client
	eventStream   *events.EventStreamManager
	completionCache *CompletionCache

	// Completion state
	currentContext *CompletionContext
	lastTrigger    time.Time
	lastResults    []CompletionItem

	// Intelligence
	contextAnalyzer *ContextAnalyzer
	rankingEngine   *RankingEngine
	filterEngine    *FilterEngine

	// Configuration
	config         CompletionConfig

	// Synchronization
	mutex          sync.RWMutex
	running        bool

	// Context
	ctx            context.Context
	cancel         context.CancelFunc
}

// CompletionConfig configures the completion engine
type CompletionConfig struct {
	EnableIntelligentRanking  bool          `json:"enable_intelligent_ranking"`
	EnableContextualFiltering bool          `json:"enable_contextual_filtering"`
	EnableFuzzyMatching      bool          `json:"enable_fuzzy_matching"`
	MaxCompletionItems       int           `json:"max_completion_items"`
	CompletionTimeout        time.Duration `json:"completion_timeout"`
	MinTriggerLength         int           `json:"min_trigger_length"`
	DebounceDelay           time.Duration `json:"debounce_delay"`
	EnableSnippets          bool          `json:"enable_snippets"`
	EnableImports           bool          `json:"enable_imports"`
	EnableSignatureHelp     bool          `json:"enable_signature_help"`
}

// CompletionContext represents the context for code completion
type CompletionContext struct {
	FilePath       string    `json:"file_path"`
	Language       string    `json:"language"`
	Line           int       `json:"line"`
	Column         int       `json:"column"`
	Prefix         string    `json:"prefix"`
	Suffix         string    `json:"suffix"`
	CurrentWord    string    `json:"current_word"`
	LineContent    string    `json:"line_content"`
	SurroundingLines []string `json:"surrounding_lines"`
	ProjectContext string    `json:"project_context"`
	TriggerKind    TriggerKind `json:"trigger_kind"`
	TriggerChar    string    `json:"trigger_char,omitempty"`
	Timestamp      time.Time `json:"timestamp"`
}

// TriggerKind defines how completion was triggered
type TriggerKind int

const (
	TriggerManual TriggerKind = iota
	TriggerAuto
	TriggerCharacter
	TriggerIncomplete
)

// CompletionRequest represents a request for code completion
type CompletionRequest struct {
	ID        string             `json:"id"`
	Context   CompletionContext  `json:"context"`
	Options   CompletionOptions  `json:"options"`
	Timestamp time.Time          `json:"timestamp"`
}

// CompletionOptions configures the completion request
type CompletionOptions struct {
	IncludeSnippets     bool     `json:"include_snippets"`
	IncludeImports      bool     `json:"include_imports"`
	IncludeSignatures   bool     `json:"include_signatures"`
	FilterByPrefix      bool     `json:"filter_by_prefix"`
	MaxResults          int      `json:"max_results"`
	PreferredKinds      []string `json:"preferred_kinds,omitempty"`
	ExcludedKinds       []string `json:"excluded_kinds,omitempty"`
}

// CompletionResponse represents the response from completion
type CompletionResponse struct {
	ID          string           `json:"id"`
	Success     bool             `json:"success"`
	Items       []CompletionItem `json:"items"`
	Incomplete  bool             `json:"incomplete"`
	Signatures  []SignatureHelp  `json:"signatures,omitempty"`
	Error       string           `json:"error,omitempty"`
	ProcessTime time.Duration    `json:"process_time"`
	Timestamp   time.Time        `json:"timestamp"`
}

// SignatureHelp represents function signature help
type SignatureHelp struct {
	Signatures      []Signature `json:"signatures"`
	ActiveSignature int         `json:"active_signature"`
	ActiveParameter int         `json:"active_parameter"`
}

// Signature represents a function signature
type Signature struct {
	Label         string      `json:"label"`
	Documentation string      `json:"documentation,omitempty"`
	Parameters    []Parameter `json:"parameters"`
}

// CompletionRank represents the ranking score for a completion item
type CompletionRank struct {
	Item         CompletionItem `json:"item"`
	Score        float64        `json:"score"`
	Relevance    float64        `json:"relevance"`
	Frequency    float64        `json:"frequency"`
	Recency      float64        `json:"recency"`
	Similarity   float64        `json:"similarity"`
	ContextScore float64        `json:"context_score"`
}

// NewCompletionEngine creates a new completion engine
func NewCompletionEngine(rpcClient *rpc.Client, eventStream *events.EventStreamManager) *CompletionEngine {
	ctx, cancel := context.WithCancel(context.Background())
	
	config := CompletionConfig{
		EnableIntelligentRanking:  true,
		EnableContextualFiltering: true,
		EnableFuzzyMatching:      true,
		MaxCompletionItems:       50,
		CompletionTimeout:        3 * time.Second,
		MinTriggerLength:         1,
		DebounceDelay:           150 * time.Millisecond,
		EnableSnippets:          true,
		EnableImports:           true,
		EnableSignatureHelp:     true,
	}
	
	ce := &CompletionEngine{
		rpcClient:       rpcClient,
		eventStream:     eventStream,
		completionCache: NewCompletionCache(100),
		contextAnalyzer: NewContextAnalyzer(),
		rankingEngine:   NewRankingEngine(),
		filterEngine:    NewFilterEngine(),
		config:          config,
		lastResults:     make([]CompletionItem, 0),
		ctx:             ctx,
		cancel:          cancel,
	}
	
	return ce
}

// Start begins completion services
func (ce *CompletionEngine) Start() error {
	ce.mutex.Lock()
	defer ce.mutex.Unlock()
	
	if ce.running {
		return fmt.Errorf("completion engine already running")
	}
	
	ce.running = true
	
	// Start background processes
	go ce.cacheMaintenanceLoop()
	
	return nil
}

// Stop ends completion services
func (ce *CompletionEngine) Stop() error {
	ce.mutex.Lock()
	defer ce.mutex.Unlock()
	
	if !ce.running {
		return fmt.Errorf("completion engine not running")
	}
	
	ce.running = false
	ce.cancel()
	
	return nil
}

// GetCompletions retrieves code completions for the given context
func (ce *CompletionEngine) GetCompletions(filePath string, line, column int, content []string) ([]CompletionItem, error) {
	ce.mutex.Lock()
	defer ce.mutex.Unlock()
	
	// Build completion context
	context := ce.buildCompletionContext(filePath, line, column, content)
	
	// Check if we should debounce this request
	if ce.shouldDebounce(context) {
		return ce.lastResults, nil
	}
	
	// Check cache first
	if cached, found := ce.completionCache.Get(context); found {
		return cached, nil
	}
	
	// Build completion request
	request := CompletionRequest{
		ID:        ce.generateCompletionID(),
		Context:   *context,
		Options:   ce.buildCompletionOptions(context),
		Timestamp: time.Now(),
	}
	
	// Perform completion
	response, err := ce.performCompletion(request)
	if err != nil {
		return nil, fmt.Errorf("completion failed: %w", err)
	}
	
	// Process and rank results
	items := ce.processCompletionItems(response.Items, context)
	
	// Cache results
	ce.completionCache.Set(context, items)
	
	// Update state
	ce.currentContext = context
	ce.lastTrigger = time.Now()
	ce.lastResults = items
	
	// Send completion event
	ce.sendCompletionEvent(request, items)
	
	return items, nil
}

// GetSignatureHelp retrieves signature help for the given context
func (ce *CompletionEngine) GetSignatureHelp(filePath string, line, column int, content []string) (*SignatureHelp, error) {
	if !ce.config.EnableSignatureHelp {
		return nil, fmt.Errorf("signature help disabled")
	}
	
	context := ce.buildCompletionContext(filePath, line, column, content)
	
	ctx, cancel := context.WithTimeout(ce.ctx, ce.config.CompletionTimeout)
	defer cancel()
	
	request := map[string]interface{}{
		"context": context,
		"options": map[string]interface{}{
			"include_signatures": true,
		},
	}
	
	response, err := ce.rpcClient.Call(ctx, "completion.get_signature_help", request)
	if err != nil {
		return nil, err
	}
	
	var signatureHelp SignatureHelp
	if err := json.Unmarshal(response, &signatureHelp); err != nil {
		return nil, err
	}
	
	return &signatureHelp, nil
}

// Internal methods
func (ce *CompletionEngine) buildCompletionContext(filePath string, line, column int, content []string) *CompletionContext {
	lineContent := ""
	if line < len(content) {
		lineContent = content[line]
	}
	
	// Extract prefix and suffix
	prefix := ""
	suffix := ""
	if column <= len(lineContent) {
		prefix = lineContent[:column]
		suffix = lineContent[column:]
	}
	
	// Extract current word
	currentWord := ce.extractCurrentWord(lineContent, column)
	
	// Get surrounding lines for context
	surroundingLines := ce.getSurroundingLines(content, line, 5)
	
	// Detect language
	language := ce.detectLanguage(filePath)
	
	// Analyze trigger
	triggerKind, triggerChar := ce.analyzeTrigger(prefix)
	
	return &CompletionContext{
		FilePath:         filePath,
		Language:         language,
		Line:             line,
		Column:           column,
		Prefix:           prefix,
		Suffix:           suffix,
		CurrentWord:      currentWord,
		LineContent:      lineContent,
		SurroundingLines: surroundingLines,
		ProjectContext:   ce.getProjectContext(filePath),
		TriggerKind:      triggerKind,
		TriggerChar:      triggerChar,
		Timestamp:        time.Now(),
	}
}

func (ce *CompletionEngine) buildCompletionOptions(context *CompletionContext) CompletionOptions {
	return CompletionOptions{
		IncludeSnippets:   ce.config.EnableSnippets,
		IncludeImports:    ce.config.EnableImports,
		IncludeSignatures: ce.config.EnableSignatureHelp,
		FilterByPrefix:    ce.config.EnableContextualFiltering,
		MaxResults:        ce.config.MaxCompletionItems,
	}
}

func (ce *CompletionEngine) performCompletion(request CompletionRequest) (*CompletionResponse, error) {
	ctx, cancel := context.WithTimeout(ce.ctx, ce.config.CompletionTimeout)
	defer cancel()
	
	response, err := ce.rpcClient.Call(ctx, "completion.get_completions", request)
	if err != nil {
		return nil, err
	}
	
	var completionResponse CompletionResponse
	if err := json.Unmarshal(response, &completionResponse); err != nil {
		return nil, err
	}
	
	if !completionResponse.Success {
		return nil, fmt.Errorf("completion failed: %s", completionResponse.Error)
	}
	
	return &completionResponse, nil
}

func (ce *CompletionEngine) processCompletionItems(items []CompletionItem, context *CompletionContext) []CompletionItem {
	// Apply filtering
	if ce.config.EnableContextualFiltering {
		items = ce.filterEngine.FilterItems(items, context)
	}
	
	// Apply ranking
	if ce.config.EnableIntelligentRanking {
		ranks := ce.rankingEngine.RankItems(items, context)
		
		// Sort by score
		sort.Slice(ranks, func(i, j int) bool {
			return ranks[i].Score > ranks[j].Score
		})
		
		// Extract items in order
		items = make([]CompletionItem, len(ranks))
		for i, rank := range ranks {
			items[i] = rank.Item
		}
	}
	
	// Limit results
	if len(items) > ce.config.MaxCompletionItems {
		items = items[:ce.config.MaxCompletionItems]
	}
	
	return items
}

func (ce *CompletionEngine) shouldDebounce(context *CompletionContext) bool {
	if time.Since(ce.lastTrigger) < ce.config.DebounceDelay {
		// Check if context is similar enough to use cached results
		if ce.currentContext != nil && ce.isContextSimilar(ce.currentContext, context) {
			return true
		}
	}
	return false
}

func (ce *CompletionEngine) isContextSimilar(old, new *CompletionContext) bool {
	return old.FilePath == new.FilePath &&
		   old.Line == new.Line &&
		   strings.HasPrefix(new.CurrentWord, old.CurrentWord)
}

func (ce *CompletionEngine) extractCurrentWord(line string, column int) string {
	if column > len(line) {
		column = len(line)
	}
	
	// Find word boundaries
	start := column
	for start > 0 && isWordChar(rune(line[start-1])) {
		start--
	}
	
	end := column
	for end < len(line) && isWordChar(rune(line[end])) {
		end++
	}
	
	return line[start:end]
}

func (ce *CompletionEngine) getSurroundingLines(content []string, line, radius int) []string {
	start := max(0, line-radius)
	end := min(len(content), line+radius+1)
	
	result := make([]string, end-start)
	copy(result, content[start:end])
	return result
}

func (ce *CompletionEngine) detectLanguage(filePath string) string {
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
	default:
		return "text"
	}
}

func (ce *CompletionEngine) getProjectContext(filePath string) string {
	// Simplified project context extraction
	return "project"
}

func (ce *CompletionEngine) analyzeTrigger(prefix string) (TriggerKind, string) {
	if len(prefix) == 0 {
		return TriggerManual, ""
	}
	
	lastChar := string(prefix[len(prefix)-1])
	triggerChars := []string{".", "->", "::", "("}
	
	for _, trigger := range triggerChars {
		if strings.HasSuffix(prefix, trigger) {
			return TriggerCharacter, trigger
		}
	}
	
	return TriggerAuto, ""
}

func (ce *CompletionEngine) generateCompletionID() string {
	return fmt.Sprintf("completion_%d", time.Now().UnixNano())
}

func (ce *CompletionEngine) sendCompletionEvent(request CompletionRequest, items []CompletionItem) {
	if ce.eventStream != nil {
		event := events.StreamEvent{
			ID:       fmt.Sprintf("completion_%s", request.ID),
			Type:     "completion_completed",
			Category: events.CategoryAIResponse,
			Priority: events.PriorityNormal,
			Payload: map[string]interface{}{
				"request": request,
				"items":   items,
				"count":   len(items),
			},
			Timestamp: time.Now(),
			Source:    "completion_engine",
		}
		
		ce.eventStream.ProcessEvent(event)
	}
}

func (ce *CompletionEngine) cacheMaintenanceLoop() {
	ticker := time.NewTicker(2 * time.Minute)
	defer ticker.Stop()
	
	for {
		select {
		case <-ce.ctx.Done():
			return
		case <-ticker.C:
			ce.completionCache.Cleanup()
		}
	}
}

// Helper functions
func isWordChar(r rune) bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_'
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

// Placeholder implementations for supporting types
type CompletionCache struct {
	entries map[string][]CompletionItem
	mutex   sync.RWMutex
}

func NewCompletionCache(size int) *CompletionCache {
	return &CompletionCache{
		entries: make(map[string][]CompletionItem),
	}
}

func (cc *CompletionCache) Get(context *CompletionContext) ([]CompletionItem, bool) {
	cc.mutex.RLock()
	defer cc.mutex.RUnlock()
	
	key := fmt.Sprintf("%s:%d:%d:%s", context.FilePath, context.Line, context.Column, context.CurrentWord)
	items, exists := cc.entries[key]
	return items, exists
}

func (cc *CompletionCache) Set(context *CompletionContext, items []CompletionItem) {
	cc.mutex.Lock()
	defer cc.mutex.Unlock()
	
	key := fmt.Sprintf("%s:%d:%d:%s", context.FilePath, context.Line, context.Column, context.CurrentWord)
	cc.entries[key] = items
}

func (cc *CompletionCache) Cleanup() {
	cc.mutex.Lock()
	defer cc.mutex.Unlock()
	
	// Simple cleanup - remove all entries
	cc.entries = make(map[string][]CompletionItem)
}

type ContextAnalyzer struct{}
func NewContextAnalyzer() *ContextAnalyzer { return &ContextAnalyzer{} }

type RankingEngine struct{}
func NewRankingEngine() *RankingEngine { return &RankingEngine{} }

func (re *RankingEngine) RankItems(items []CompletionItem, context *CompletionContext) []CompletionRank {
	ranks := make([]CompletionRank, len(items))
	for i, item := range items {
		ranks[i] = CompletionRank{
			Item:  item,
			Score: float64(item.Priority), // Simple scoring based on priority
		}
	}
	return ranks
}

type FilterEngine struct{}
func NewFilterEngine() *FilterEngine { return &FilterEngine{} }

func (fe *FilterEngine) FilterItems(items []CompletionItem, context *CompletionContext) []CompletionItem {
	// Simple filtering - return all items for now
	return items
}
