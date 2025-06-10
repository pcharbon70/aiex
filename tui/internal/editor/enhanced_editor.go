package editor

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/alecthomas/chroma/v2"
	"github.com/alecthomas/chroma/v2/lexers"
	"github.com/alecthomas/chroma/v2/styles"
	"github.com/alecthomas/chroma/v2/formatters"

	"aiex-tui/internal/events"
	"aiex-tui/internal/filesystem"
	"aiex-tui/internal/rpc"
	"aiex-tui/pkg/types"
)

// EnhancedCodeEditor provides advanced code editing capabilities with semantic analysis
type EnhancedCodeEditor struct {
	// Core editor state
	width           int
	height          int
	content         []string
	cursor          CursorPosition
	selection       Selection
	viewport        Viewport
	
	// File and language info
	filePath        string
	language        string
	encoding        string
	lineEndings     string
	
	// Editor features
	lineNumbers     bool
	wordWrap        bool
	autoIndent      bool
	tabSize         int
	insertMode      bool
	showWhitespace  bool
	
	// Syntax highlighting
	syntaxHighlighter *SyntaxHighlighter
	theme           string
	
	// Semantic analysis
	semanticAnalyzer *SemanticAnalyzer
	symbols         []Symbol
	diagnostics     []Diagnostic
	suggestions     []CodeSuggestion
	
	// Collaboration
	collaborationEngine *CollaborationEngine
	collaborators      []Collaborator
	
	// Code completion
	completionEngine *CompletionEngine
	completionActive bool
	completionItems  []CompletionItem
	completionIndex  int
	
	// State tracking
	modified        bool
	lastSaved       time.Time
	undoStack       []EditorState
	redoStack       []EditorState
	maxUndoHistory  int
	
	// Event integration
	eventStream     *events.EventStreamManager
	rpcClient       *rpc.Client
	fsManager       *filesystem.FileSystemManager
	
	// UI state
	focused         bool
	searchMode      bool
	searchQuery     string
	searchResults   []SearchResult
	currentResult   int
	
	// Performance
	renderCache     *RenderCache
	lastRender      time.Time
	
	// Configuration
	config          EditorConfig
	
	// Synchronization
	mutex           sync.RWMutex
}

// CursorPosition represents cursor position in the editor
type CursorPosition struct {
	Line   int `json:"line"`
	Column int `json:"column"`
}

// Selection represents a text selection
type Selection struct {
	Start  CursorPosition `json:"start"`
	End    CursorPosition `json:"end"`
	Active bool          `json:"active"`
}

// Viewport represents the visible area of the editor
type Viewport struct {
	TopLine    int `json:"top_line"`
	LeftColumn int `json:"left_column"`
	Height     int `json:"height"`
	Width      int `json:"width"`
}

// EditorState represents editor state for undo/redo
type EditorState struct {
	Content   []string       `json:"content"`
	Cursor    CursorPosition `json:"cursor"`
	Selection Selection      `json:"selection"`
	Timestamp time.Time      `json:"timestamp"`
}

// Symbol represents a code symbol (function, class, variable, etc.)
type Symbol struct {
	Name        string         `json:"name"`
	Type        string         `json:"type"`
	Line        int            `json:"line"`
	Column      int            `json:"column"`
	EndLine     int            `json:"end_line"`
	EndColumn   int            `json:"end_column"`
	Scope       string         `json:"scope"`
	Visibility  string         `json:"visibility"`
	Parameters  []Parameter    `json:"parameters,omitempty"`
	ReturnType  string         `json:"return_type,omitempty"`
	DocString   string         `json:"doc_string,omitempty"`
	References  []Reference    `json:"references,omitempty"`
}

// Parameter represents a function parameter
type Parameter struct {
	Name     string `json:"name"`
	Type     string `json:"type"`
	Optional bool   `json:"optional"`
	Default  string `json:"default,omitempty"`
}

// Reference represents a symbol reference
type Reference struct {
	Line   int    `json:"line"`
	Column int    `json:"column"`
	Type   string `json:"type"` // definition, usage, modification
}

// Diagnostic represents a code diagnostic (error, warning, info)
type Diagnostic struct {
	Line     int    `json:"line"`
	Column   int    `json:"column"`
	EndLine  int    `json:"end_line"`
	EndColumn int   `json:"end_column"`
	Severity string `json:"severity"` // error, warning, info, hint
	Message  string `json:"message"`
	Code     string `json:"code,omitempty"`
	Source   string `json:"source"`
}

// CodeSuggestion represents an intelligent code suggestion
type CodeSuggestion struct {
	Line        int    `json:"line"`
	Column      int    `json:"column"`
	EndLine     int    `json:"end_line"`
	EndColumn   int    `json:"end_column"`
	Type        string `json:"type"` // refactor, fix, improvement
	Title       string `json:"title"`
	Description string `json:"description"`
	NewText     string `json:"new_text"`
	Priority    int    `json:"priority"`
}

// CompletionItem represents a code completion item
type CompletionItem struct {
	Label         string   `json:"label"`
	Kind          string   `json:"kind"` // function, variable, class, etc.
	Detail        string   `json:"detail"`
	Documentation string   `json:"documentation"`
	InsertText    string   `json:"insert_text"`
	Priority      int      `json:"priority"`
	Triggers      []string `json:"triggers,omitempty"`
}

// Collaborator represents a collaborating user
type Collaborator struct {
	ID     string         `json:"id"`
	Name   string         `json:"name"`
	Color  string         `json:"color"`
	Cursor CursorPosition `json:"cursor"`
	Active bool           `json:"active"`
}

// SearchResult represents a search match
type SearchResult struct {
	Line   int    `json:"line"`
	Column int    `json:"column"`
	Length int    `json:"length"`
	Text   string `json:"text"`
}

// EditorConfig configures the editor
type EditorConfig struct {
	TabSize              int           `json:"tab_size"`
	UseSpaces            bool          `json:"use_spaces"`
	AutoIndent           bool          `json:"auto_indent"`
	AutoComplete         bool          `json:"auto_complete"`
	LineNumbers          bool          `json:"line_numbers"`
	WordWrap             bool          `json:"word_wrap"`
	ShowWhitespace       bool          `json:"show_whitespace"`
	HighlightCurrentLine bool          `json:"highlight_current_line"`
	Theme                string        `json:"theme"`
	Font                 string        `json:"font"`
	FontSize             int           `json:"font_size"`
	SemanticAnalysis     bool          `json:"semantic_analysis"`
	RealTimeCollaboration bool         `json:"real_time_collaboration"`
	AutoSave             bool          `json:"auto_save"`
	AutoSaveInterval     time.Duration `json:"auto_save_interval"`
}

// NewEnhancedCodeEditor creates a new enhanced code editor
func NewEnhancedCodeEditor(config EditorConfig, rpcClient *rpc.Client, eventStream *events.EventStreamManager, fsManager *filesystem.FileSystemManager) *EnhancedCodeEditor {
	// Set defaults
	if config.TabSize == 0 {
		config.TabSize = 4
	}
	if config.Theme == "" {
		config.Theme = "monokai"
	}
	if config.AutoSaveInterval == 0 {
		config.AutoSaveInterval = 30 * time.Second
	}
	
	editor := &EnhancedCodeEditor{
		content:         []string{""},
		cursor:          CursorPosition{Line: 0, Column: 0},
		selection:       Selection{Active: false},
		viewport:        Viewport{TopLine: 0, LeftColumn: 0},
		language:        "",
		encoding:        "utf-8",
		lineEndings:     "\n",
		tabSize:         config.TabSize,
		insertMode:      true,
		lineNumbers:     config.LineNumbers,
		wordWrap:        config.WordWrap,
		autoIndent:      config.AutoIndent,
		showWhitespace:  config.ShowWhitespace,
		theme:           config.Theme,
		maxUndoHistory:  100,
		config:          config,
		rpcClient:       rpcClient,
		eventStream:     eventStream,
		fsManager:       fsManager,
		undoStack:       make([]EditorState, 0, 100),
		redoStack:       make([]EditorState, 0, 100),
		symbols:         make([]Symbol, 0),
		diagnostics:     make([]Diagnostic, 0),
		suggestions:     make([]CodeSuggestion, 0),
		collaborators:   make([]Collaborator, 0),
		searchResults:   make([]SearchResult, 0),
	}
	
	// Initialize components
	editor.syntaxHighlighter = NewSyntaxHighlighter(config.Theme)
	
	if config.SemanticAnalysis {
		editor.semanticAnalyzer = NewSemanticAnalyzer(rpcClient)
	}
	
	if config.RealTimeCollaboration {
		editor.collaborationEngine = NewCollaborationEngine(rpcClient, eventStream)
	}
	
	if config.AutoComplete {
		editor.completionEngine = NewCompletionEngine(rpcClient, eventStream)
	}
	
	editor.renderCache = NewRenderCache()
	
	return editor
}

// Update handles editor updates
func (ece *EnhancedCodeEditor) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if !ece.focused {
		return ece, nil
	}
	
	var cmds []tea.Cmd
	
	switch msg := msg.(type) {
	case tea.KeyMsg:
		cmd := ece.handleKeyPress(msg)
		if cmd != nil {
			cmds = append(cmds, cmd)
		}
		
	case SemanticAnalysisCompleteMsg:
		ece.updateSemanticInfo(msg.Symbols, msg.Diagnostics)
		
	case CodeSuggestionsMsg:
		ece.updateSuggestions(msg.Suggestions)
		
	case CompletionItemsMsg:
		ece.updateCompletionItems(msg.Items)
		
	case CollaboratorUpdateMsg:
		ece.updateCollaborator(msg.Collaborator)
		
	case FileContentChangedMsg:
		if msg.Path == ece.filePath {
			ece.handleExternalChange(msg.Content)
		}
	}
	
	// Trigger semantic analysis if content changed
	if ece.isContentModified() && ece.semanticAnalyzer != nil {
		cmds = append(cmds, ece.requestSemanticAnalysis())
	}
	
	// Trigger auto-completion if needed
	if ece.shouldTriggerCompletion() && ece.completionEngine != nil {
		cmds = append(cmds, ece.requestCompletion())
	}
	
	return ece, tea.Batch(cmds...)
}

// View renders the editor
func (ece *EnhancedCodeEditor) View() string {
	if ece.width == 0 || ece.height == 0 {
		return ""
	}
	
	ece.mutex.RLock()
	defer ece.mutex.RUnlock()
	
	// Check render cache
	cacheKey := ece.getRenderCacheKey()
	if cached, found := ece.renderCache.Get(cacheKey); found {
		return cached
	}
	
	// Build view
	var view strings.Builder
	
	// Header
	header := ece.renderHeader()
	view.WriteString(header)
	view.WriteString("\n")
	
	// Content area
	content := ece.renderContent()
	view.WriteString(content)
	
	// Completion popup
	if ece.completionActive {
		completion := ece.renderCompletion()
		// Overlay completion on content (simplified)
		view.WriteString("\n")
		view.WriteString(completion)
	}
	
	// Status line
	status := ece.renderStatusLine()
	view.WriteString("\n")
	view.WriteString(status)
	
	result := ece.applyEditorStyle(view.String())
	
	// Cache result
	ece.renderCache.Set(cacheKey, result)
	ece.lastRender = time.Now()
	
	return result
}

// File operations
func (ece *EnhancedCodeEditor) LoadFile(path string) tea.Cmd {
	return func() tea.Msg {
		if ece.fsManager != nil {
			openFile, err := ece.fsManager.OpenFile(path)
			if err != nil {
				return FileLoadErrorMsg{Path: path, Error: err}
			}
			
			return FileLoadedMsg{
				Path:     path,
				Content:  openFile.Content,
				Language: openFile.Language,
				Modified: openFile.Modified,
			}
		}
		
		return FileLoadErrorMsg{Path: path, Error: fmt.Errorf("file system manager not available")}
	}
}

func (ece *EnhancedCodeEditor) SaveFile() tea.Cmd {
	if ece.filePath == "" {
		return nil
	}
	
	return func() tea.Msg {
		if ece.fsManager != nil {
			// Update file content in file system manager
			err := ece.fsManager.ModifyFileContent(ece.filePath, ece.content)
			if err != nil {
				return FileSaveErrorMsg{Path: ece.filePath, Error: err}
			}
			
			// Save the file
			err = ece.fsManager.SaveFile(ece.filePath)
			if err != nil {
				return FileSaveErrorMsg{Path: ece.filePath, Error: err}
			}
			
			return FileSavedMsg{Path: ece.filePath}
		}
		
		return FileSaveErrorMsg{Path: ece.filePath, Error: fmt.Errorf("file system manager not available")}
	}
}

// Content manipulation
func (ece *EnhancedCodeEditor) InsertText(text string) {
	ece.mutex.Lock()
	defer ece.mutex.Unlock()
	
	ece.saveStateForUndo()
	
	if ece.selection.Active {
		ece.deleteSelection()
	}
	
	// Insert text at cursor
	line := ece.cursor.Line
	col := ece.cursor.Column
	
	if line >= len(ece.content) {
		// Extend content if necessary
		for len(ece.content) <= line {
			ece.content = append(ece.content, "")
		}
	}
	
	currentLine := ece.content[line]
	
	// Handle multi-line text
	lines := strings.Split(text, "\n")
	if len(lines) == 1 {
		// Single line insertion
		newLine := currentLine[:col] + text + currentLine[col:]
		ece.content[line] = newLine
		ece.cursor.Column = col + len(text)
	} else {
		// Multi-line insertion
		firstLine := currentLine[:col] + lines[0]
		lastLine := lines[len(lines)-1] + currentLine[col:]
		
		ece.content[line] = firstLine
		
		// Insert middle lines
		for i := 1; i < len(lines)-1; i++ {
			ece.content = append(ece.content[:line+i], append([]string{lines[i]}, ece.content[line+i:]...)...)
		}
		
		// Insert last line
		if len(lines) > 1 {
			ece.content = append(ece.content[:line+len(lines)-1], append([]string{lastLine}, ece.content[line+len(lines)-1:]...)...)
			ece.cursor.Line = line + len(lines) - 1
			ece.cursor.Column = len(lines[len(lines)-1])
		}
	}
	
	ece.modified = true
	ece.clearRenderCache()
	ece.sendContentChangeEvent()
}

func (ece *EnhancedCodeEditor) DeleteCharacterBackward() {
	ece.mutex.Lock()
	defer ece.mutex.Unlock()
	
	if ece.cursor.Column == 0 && ece.cursor.Line == 0 {
		return
	}
	
	ece.saveStateForUndo()
	
	if ece.cursor.Column > 0 {
		// Delete character in current line
		line := ece.content[ece.cursor.Line]
		newLine := line[:ece.cursor.Column-1] + line[ece.cursor.Column:]
		ece.content[ece.cursor.Line] = newLine
		ece.cursor.Column--
	} else {
		// Join with previous line
		if ece.cursor.Line > 0 {
			prevLine := ece.content[ece.cursor.Line-1]
			currentLine := ece.content[ece.cursor.Line]
			
			ece.content[ece.cursor.Line-1] = prevLine + currentLine
			ece.content = append(ece.content[:ece.cursor.Line], ece.content[ece.cursor.Line+1:]...)
			
			ece.cursor.Line--
			ece.cursor.Column = len(prevLine)
		}
	}
	
	ece.modified = true
	ece.clearRenderCache()
	ece.sendContentChangeEvent()
}

func (ece *EnhancedCodeEditor) InsertNewline() {
	ece.mutex.Lock()
	defer ece.mutex.Unlock()
	
	ece.saveStateForUndo()
	
	line := ece.cursor.Line
	col := ece.cursor.Column
	
	currentLine := ece.content[line]
	leftPart := currentLine[:col]
	rightPart := currentLine[col:]
	
	// Auto-indent
	var indent string
	if ece.autoIndent {
		indent = ece.calculateIndent(line)
	}
	
	ece.content[line] = leftPart
	newLine := indent + rightPart
	
	// Insert new line
	ece.content = append(ece.content[:line+1], append([]string{newLine}, ece.content[line+1:]...)...)
	
	ece.cursor.Line++
	ece.cursor.Column = len(indent)
	
	ece.modified = true
	ece.clearRenderCache()
	ece.sendContentChangeEvent()
}

// Navigation
func (ece *EnhancedCodeEditor) MoveCursor(deltaLine, deltaColumn int) {
	ece.mutex.Lock()
	defer ece.mutex.Unlock()
	
	newLine := ece.cursor.Line + deltaLine
	newColumn := ece.cursor.Column + deltaColumn
	
	// Clamp to valid range
	if newLine < 0 {
		newLine = 0
	}
	if newLine >= len(ece.content) {
		newLine = len(ece.content) - 1
	}
	
	if newLine >= 0 && newLine < len(ece.content) {
		lineLength := len(ece.content[newLine])
		if newColumn < 0 {
			newColumn = 0
		}
		if newColumn > lineLength {
			newColumn = lineLength
		}
		
		ece.cursor.Line = newLine
		ece.cursor.Column = newColumn
	}
	
	ece.updateViewport()
}

func (ece *EnhancedCodeEditor) JumpToLine(line int) {
	ece.mutex.Lock()
	defer ece.mutex.Unlock()
	
	if line >= 0 && line < len(ece.content) {
		ece.cursor.Line = line
		ece.cursor.Column = 0
		ece.updateViewport()
	}
}

// Semantic analysis integration
func (ece *EnhancedCodeEditor) requestSemanticAnalysis() tea.Cmd {
	if ece.semanticAnalyzer == nil {
		return nil
	}
	
	return func() tea.Msg {
		symbols, diagnostics, err := ece.semanticAnalyzer.Analyze(ece.filePath, ece.content)
		if err != nil {
			return SemanticAnalysisErrorMsg{Error: err}
		}
		
		return SemanticAnalysisCompleteMsg{
			Symbols:     symbols,
			Diagnostics: diagnostics,
		}
	}
}

func (ece *EnhancedCodeEditor) requestCompletion() tea.Cmd {
	if ece.completionEngine == nil {
		return nil
	}
	
	return func() tea.Msg {
		items, err := ece.completionEngine.GetCompletions(ece.filePath, ece.cursor.Line, ece.cursor.Column, ece.content)
		if err != nil {
			return CompletionErrorMsg{Error: err}
		}
		
		return CompletionItemsMsg{Items: items}
	}
}

// Internal helper methods
func (ece *EnhancedCodeEditor) handleKeyPress(msg tea.KeyMsg) tea.Cmd {
	switch msg.String() {
	case "up":
		ece.MoveCursor(-1, 0)
	case "down":
		ece.MoveCursor(1, 0)
	case "left":
		ece.MoveCursor(0, -1)
	case "right":
		ece.MoveCursor(0, 1)
	case "home":
		ece.cursor.Column = 0
	case "end":
		if ece.cursor.Line < len(ece.content) {
			ece.cursor.Column = len(ece.content[ece.cursor.Line])
		}
	case "enter":
		ece.InsertNewline()
	case "backspace":
		ece.DeleteCharacterBackward()
	case "tab":
		ece.InsertText(strings.Repeat(" ", ece.tabSize))
	case "ctrl+s":
		return ece.SaveFile()
	case "ctrl+z":
		ece.Undo()
	case "ctrl+y":
		ece.Redo()
	case "ctrl+f":
		ece.searchMode = true
		ece.searchQuery = ""
	case "ctrl+space":
		if ece.completionEngine != nil {
			ece.completionActive = true
			return ece.requestCompletion()
		}
	case "escape":
		ece.completionActive = false
		ece.searchMode = false
	default:
		if len(msg.Runes) > 0 {
			ece.InsertText(string(msg.Runes))
		}
	}
	
	return nil
}

func (ece *EnhancedCodeEditor) renderHeader() string {
	filename := "Untitled"
	if ece.filePath != "" {
		filename = filepath.Base(ece.filePath)
	}
	
	if ece.modified {
		filename += " •"
	}
	
	icon := ece.getLanguageIcon()
	
	// Add collaboration indicators
	collabIndicator := ""
	if len(ece.collaborators) > 0 {
		activeCount := 0
		for _, collab := range ece.collaborators {
			if collab.Active {
				activeCount++
			}
		}
		if activeCount > 0 {
			collabIndicator = fmt.Sprintf(" 👥%d", activeCount)
		}
	}
	
	return lipgloss.NewStyle().
		Foreground(lipgloss.Color("63")).
		Bold(true).
		Render(fmt.Sprintf("%s %s%s", icon, filename, collabIndicator))
}

func (ece *EnhancedCodeEditor) renderContent() string {
	var lines []string
	
	startLine := ece.viewport.TopLine
	endLine := startLine + ece.viewport.Height
	
	if endLine > len(ece.content) {
		endLine = len(ece.content)
	}
	
	lineNumWidth := 0
	if ece.lineNumbers {
		lineNumWidth = len(fmt.Sprintf("%d", len(ece.content))) + 1
	}
	
	for i := startLine; i < endLine; i++ {
		line := ""
		if i < len(ece.content) {
			line = ece.content[i]
		}
		
		// Apply syntax highlighting
		if ece.syntaxHighlighter != nil {
			line = ece.syntaxHighlighter.Highlight(line, ece.language)
		}
		
		// Add line numbers
		if ece.lineNumbers {
			lineNum := fmt.Sprintf("%*d ", lineNumWidth-1, i+1)
			lineNumStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
			line = lineNumStyle.Render(lineNum) + line
		}
		
		// Highlight current line
		if i == ece.cursor.Line && ece.focused {
			line = lipgloss.NewStyle().
				Background(lipgloss.Color("237")).
				Width(ece.width - 2).
				Render(line)
		}
		
		// Add diagnostics indicators
		line = ece.addDiagnosticIndicators(line, i)
		
		lines = append(lines, line)
	}
	
	return strings.Join(lines, "\n")
}

func (ece *EnhancedCodeEditor) renderCompletion() string {
	if len(ece.completionItems) == 0 {
		return ""
	}
	
	var items []string
	for i, item := range ece.completionItems {
		style := lipgloss.NewStyle().Padding(0, 1)
		if i == ece.completionIndex {
			style = style.Background(lipgloss.Color("63")).Foreground(lipgloss.Color("230"))
		}
		
		line := fmt.Sprintf("%s %s", item.Label, item.Kind)
		items = append(items, style.Render(line))
	}
	
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("63")).
		Render(strings.Join(items, "\n"))
}

func (ece *EnhancedCodeEditor) renderStatusLine() string {
	var parts []string
	
	// Cursor position
	parts = append(parts, fmt.Sprintf("Ln %d, Col %d", ece.cursor.Line+1, ece.cursor.Column+1))
	
	// Language
	if ece.language != "" {
		parts = append(parts, ece.language)
	}
	
	// Insert mode
	mode := "INS"
	if !ece.insertMode {
		mode = "OVR"
	}
	parts = append(parts, mode)
	
	// Diagnostics summary
	if len(ece.diagnostics) > 0 {
		errors := 0
		warnings := 0
		for _, diag := range ece.diagnostics {
			switch diag.Severity {
			case "error":
				errors++
			case "warning":
				warnings++
			}
		}
		if errors > 0 || warnings > 0 {
			parts = append(parts, fmt.Sprintf("E:%d W:%d", errors, warnings))
		}
	}
	
	// Collaborators
	if len(ece.collaborators) > 0 {
		active := 0
		for _, collab := range ece.collaborators {
			if collab.Active {
				active++
			}
		}
		if active > 0 {
			parts = append(parts, fmt.Sprintf("👥 %d", active))
		}
	}
	
	status := strings.Join(parts, " | ")
	return lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Render(status)
}

// Supporting methods (simplified implementations)
func (ece *EnhancedCodeEditor) getLanguageIcon() string {
	switch ece.language {
	case "go":
		return "🐹"
	case "elixir":
		return "💧"
	case "javascript":
		return "📜"
	case "typescript":
		return "📘"
	case "python":
		return "🐍"
	case "rust":
		return "🦀"
	default:
		return "📄"
	}
}

func (ece *EnhancedCodeEditor) applyEditorStyle(content string) string {
	style := lipgloss.NewStyle().
		Width(ece.width).
		Height(ece.height)
	
	if ece.focused {
		style = style.
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("63"))
	} else {
		style = style.
			BorderStyle(lipgloss.NormalBorder()).
			BorderForeground(lipgloss.Color("241"))
	}
	
	return style.Render(content)
}

func (ece *EnhancedCodeEditor) isContentModified() bool {
	return time.Since(ece.lastRender) > 100*time.Millisecond
}

func (ece *EnhancedCodeEditor) shouldTriggerCompletion() bool {
	return ece.config.AutoComplete && !ece.completionActive
}

func (ece *EnhancedCodeEditor) updateSemanticInfo(symbols []Symbol, diagnostics []Diagnostic) {
	ece.mutex.Lock()
	defer ece.mutex.Unlock()
	
	ece.symbols = symbols
	ece.diagnostics = diagnostics
	ece.clearRenderCache()
}

func (ece *EnhancedCodeEditor) updateSuggestions(suggestions []CodeSuggestion) {
	ece.mutex.Lock()
	defer ece.mutex.Unlock()
	
	ece.suggestions = suggestions
}

func (ece *EnhancedCodeEditor) updateCompletionItems(items []CompletionItem) {
	ece.mutex.Lock()
	defer ece.mutex.Unlock()
	
	ece.completionItems = items
	ece.completionIndex = 0
	ece.completionActive = len(items) > 0
}

func (ece *EnhancedCodeEditor) updateCollaborator(collaborator Collaborator) {
	ece.mutex.Lock()
	defer ece.mutex.Unlock()
	
	// Update or add collaborator
	for i, collab := range ece.collaborators {
		if collab.ID == collaborator.ID {
			ece.collaborators[i] = collaborator
			return
		}
	}
	
	ece.collaborators = append(ece.collaborators, collaborator)
}

func (ece *EnhancedCodeEditor) handleExternalChange(content []string) {
	ece.mutex.Lock()
	defer ece.mutex.Unlock()
	
	// Handle external file changes (simplified conflict resolution)
	ece.content = content
	ece.clearRenderCache()
}

func (ece *EnhancedCodeEditor) saveStateForUndo() {
	state := EditorState{
		Content:   make([]string, len(ece.content)),
		Cursor:    ece.cursor,
		Selection: ece.selection,
		Timestamp: time.Now(),
	}
	copy(state.Content, ece.content)
	
	ece.undoStack = append(ece.undoStack, state)
	if len(ece.undoStack) > ece.maxUndoHistory {
		ece.undoStack = ece.undoStack[1:]
	}
	
	// Clear redo stack
	ece.redoStack = ece.redoStack[:0]
}

func (ece *EnhancedCodeEditor) Undo() {
	if len(ece.undoStack) == 0 {
		return
	}
	
	// Save current state to redo stack
	currentState := EditorState{
		Content:   make([]string, len(ece.content)),
		Cursor:    ece.cursor,
		Selection: ece.selection,
		Timestamp: time.Now(),
	}
	copy(currentState.Content, ece.content)
	ece.redoStack = append(ece.redoStack, currentState)
	
	// Restore previous state
	prevState := ece.undoStack[len(ece.undoStack)-1]
	ece.undoStack = ece.undoStack[:len(ece.undoStack)-1]
	
	ece.content = make([]string, len(prevState.Content))
	copy(ece.content, prevState.Content)
	ece.cursor = prevState.Cursor
	ece.selection = prevState.Selection
	
	ece.modified = true
	ece.clearRenderCache()
}

func (ece *EnhancedCodeEditor) Redo() {
	if len(ece.redoStack) == 0 {
		return
	}
	
	// Save current state to undo stack
	ece.saveStateForUndo()
	
	// Restore next state
	nextState := ece.redoStack[len(ece.redoStack)-1]
	ece.redoStack = ece.redoStack[:len(ece.redoStack)-1]
	
	ece.content = make([]string, len(nextState.Content))
	copy(ece.content, nextState.Content)
	ece.cursor = nextState.Cursor
	ece.selection = nextState.Selection
	
	ece.modified = true
	ece.clearRenderCache()
}

func (ece *EnhancedCodeEditor) updateViewport() {
	// Update viewport to keep cursor visible
	if ece.cursor.Line < ece.viewport.TopLine {
		ece.viewport.TopLine = ece.cursor.Line
	} else if ece.cursor.Line >= ece.viewport.TopLine+ece.viewport.Height {
		ece.viewport.TopLine = ece.cursor.Line - ece.viewport.Height + 1
	}
}

func (ece *EnhancedCodeEditor) calculateIndent(line int) string {
	if line <= 0 || line >= len(ece.content) {
		return ""
	}
	
	prevLine := ece.content[line-1]
	indent := ""
	
	// Extract existing indentation
	for _, char := range prevLine {
		if char == ' ' || char == '\t' {
			indent += string(char)
		} else {
			break
		}
	}
	
	// TODO: Add language-specific indentation rules
	
	return indent
}

func (ece *EnhancedCodeEditor) deleteSelection() {
	if !ece.selection.Active {
		return
	}
	
	// TODO: Implement selection deletion
	ece.selection.Active = false
}

func (ece *EnhancedCodeEditor) addDiagnosticIndicators(line string, lineNum int) string {
	// TODO: Add diagnostic indicators to line
	return line
}

func (ece *EnhancedCodeEditor) sendContentChangeEvent() {
	if ece.eventStream != nil {
		event := events.StreamEvent{
			ID:       fmt.Sprintf("editor_change_%d", time.Now().UnixNano()),
			Type:     "editor_content_changed",
			Category: events.CategoryUIUpdate,
			Priority: events.PriorityNormal,
			Payload: map[string]interface{}{
				"file_path": ece.filePath,
				"line":      ece.cursor.Line,
				"column":    ece.cursor.Column,
			},
			Timestamp: time.Now(),
			Source:    "enhanced_editor",
		}
		
		ece.eventStream.ProcessEvent(event)
	}
}

func (ece *EnhancedCodeEditor) clearRenderCache() {
	if ece.renderCache != nil {
		ece.renderCache.Clear()
	}
}

func (ece *EnhancedCodeEditor) getRenderCacheKey() string {
	return fmt.Sprintf("editor_%s_%d_%d_%d", ece.filePath, ece.cursor.Line, ece.cursor.Column, len(ece.content))
}

// Message types
type FileLoadedMsg struct {
	Path     string
	Content  []string
	Language string
	Modified bool
}

type FileLoadErrorMsg struct {
	Path  string
	Error error
}

type FileSavedMsg struct {
	Path string
}

type FileSaveErrorMsg struct {
	Path  string
	Error error
}

type FileContentChangedMsg struct {
	Path    string
	Content []string
}

type SemanticAnalysisCompleteMsg struct {
	Symbols     []Symbol
	Diagnostics []Diagnostic
}

type SemanticAnalysisErrorMsg struct {
	Error error
}

type CodeSuggestionsMsg struct {
	Suggestions []CodeSuggestion
}

type CompletionItemsMsg struct {
	Items []CompletionItem
}

type CompletionErrorMsg struct {
	Error error
}

type CollaboratorUpdateMsg struct {
	Collaborator Collaborator
}

// Placeholder implementations for supporting types
type SyntaxHighlighter struct{}
func NewSyntaxHighlighter(theme string) *SyntaxHighlighter { return &SyntaxHighlighter{} }
func (sh *SyntaxHighlighter) Highlight(text, language string) string { return text }

type SemanticAnalyzer struct{}
func NewSemanticAnalyzer(rpcClient *rpc.Client) *SemanticAnalyzer { return &SemanticAnalyzer{} }
func (sa *SemanticAnalyzer) Analyze(path string, content []string) ([]Symbol, []Diagnostic, error) { 
	return nil, nil, nil 
}

type CollaborationEngine struct{}
func NewCollaborationEngine(rpcClient *rpc.Client, eventStream *events.EventStreamManager) *CollaborationEngine { 
	return &CollaborationEngine{} 
}

type CompletionEngine struct{}
func NewCompletionEngine(rpcClient *rpc.Client, eventStream *events.EventStreamManager) *CompletionEngine { 
	return &CompletionEngine{} 
}
func (ce *CompletionEngine) GetCompletions(path string, line, column int, content []string) ([]CompletionItem, error) { 
	return nil, nil 
}

type RenderCache struct{}
func NewRenderCache() *RenderCache { return &RenderCache{} }
func (rc *RenderCache) Get(key string) (string, bool) { return "", false }
func (rc *RenderCache) Set(key, value string) {}
func (rc *RenderCache) Clear() {}