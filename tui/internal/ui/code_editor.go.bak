package ui

import (
	"fmt"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/alecthomas/chroma/v2"
	"github.com/alecthomas/chroma/v2/lexers"
	"github.com/alecthomas/chroma/v2/styles"
	"github.com/alecthomas/chroma/v2/formatters"
)

// CodeEditorModel represents an enhanced code editor with syntax highlighting
type CodeEditorModel struct {
	width        int
	height       int
	content      []string
	cursor       CursorPosition
	selection    Selection
	language     string
	filePath     string
	focused      bool
	viewport     ViewportState
	modified     bool
	lastSaved    time.Time
	undoStack    []EditorState
	redoStack    []EditorState
	searchQuery  string
	searchMode   bool
	replaceMode  bool
	highlighter  *SyntaxHighlighter
	lineNumbers  bool
	wordWrap     bool
	tabSize      int
	insertMode   bool
}

// EditorState represents a state for undo/redo functionality
type EditorState struct {
	content   []string
	cursor    CursorPosition
	selection Selection
	timestamp time.Time
}

// SyntaxHighlighter handles syntax highlighting using Chroma
type SyntaxHighlighter struct {
	lexer     chroma.Lexer
	style     *chroma.Style
	formatter chroma.Formatter
	theme     string
}

// NewCodeEditorModel creates a new code editor
func NewCodeEditorModel() CodeEditorModel {
	highlighter := NewSyntaxHighlighter("monokai")
	
	return CodeEditorModel{
		content:     []string{""},
		cursor:      CursorPosition{line: 0, column: 0},
		selection:   Selection{active: false},
		viewport:    ViewportState{offset: 0, height: 0},
		undoStack:   make([]EditorState, 0, 100),
		redoStack:   make([]EditorState, 0, 100),
		highlighter: highlighter,
		lineNumbers: true,
		wordWrap:    false,
		tabSize:     4,
		insertMode:  true,
		lastSaved:   time.Now(),
	}
}

// NewSyntaxHighlighter creates a new syntax highlighter
func NewSyntaxHighlighter(theme string) *SyntaxHighlighter {
	style := styles.Get(theme)
	if style == nil {
		style = styles.Fallback
	}
	
	formatter := formatters.Get("terminal16m")
	if formatter == nil {
		formatter = formatters.Fallback
	}
	
	return &SyntaxHighlighter{
		style:     style,
		formatter: formatter,
		theme:     theme,
	}
}

// Update handles code editor updates
func (cem CodeEditorModel) Update(msg tea.Msg) (CodeEditorModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !cem.focused {
			return cem, nil
		}
		
		// Handle search mode
		if cem.searchMode {
			return cem.handleSearchInput(msg)
		}
		
		// Handle replace mode
		if cem.replaceMode {
			return cem.handleReplaceInput(msg)
		}
		
		// Handle normal editing
		return cem.handleEditingInput(msg)
		
	case FileContentLoadedMsg:
		cem.content = msg.Content
		cem.filePath = msg.Path
		cem.language = cem.detectLanguage(msg.Path)
		cem.highlighter.SetLanguage(cem.language)
		cem.cursor = CursorPosition{line: 0, column: 0}
		cem.viewport.offset = 0
		cem.modified = false
		cem.lastSaved = time.Now()
		cem.saveState()
		return cem, nil
		
	case FileSavedMsg:
		cem.modified = false
		cem.lastSaved = time.Now()
		return cem, nil
	}
	
	return cem, nil
}

// handleEditingInput handles normal editing key inputs
func (cem CodeEditorModel) handleEditingInput(msg tea.KeyMsg) (CodeEditorModel, tea.Cmd) {
	var cmd tea.Cmd
	
	switch msg.String() {
	// Navigation
	case "up":
		cem = cem.moveCursorUp()
	case "down":
		cem = cem.moveCursorDown()
	case "left":
		cem = cem.moveCursorLeft()
	case "right":
		cem = cem.moveCursorRight()
	case "home":
		cem = cem.moveCursorToLineStart()
	case "end":
		cem = cem.moveCursorToLineEnd()
	case "ctrl+home":
		cem = cem.moveCursorToStart()
	case "ctrl+end":
		cem = cem.moveCursorToEnd()
	case "pgup":
		cem = cem.moveCursorPageUp()
	case "pgdown":
		cem = cem.moveCursorPageDown()
	case "ctrl+left":
		cem = cem.moveCursorWordLeft()
	case "ctrl+right":
		cem = cem.moveCursorWordRight()
	
	// Selection
	case "shift+up":
		cem = cem.selectUp()
	case "shift+down":
		cem = cem.selectDown()
	case "shift+left":
		cem = cem.selectLeft()
	case "shift+right":
		cem = cem.selectRight()
	case "ctrl+a":
		cem = cem.selectAll()
	case "ctrl+shift+left":
		cem = cem.selectWordLeft()
	case "ctrl+shift+right":
		cem = cem.selectWordRight()
	
	// Editing
	case "enter":
		cem = cem.insertNewline()
	case "backspace":
		cem = cem.deleteBackward()
	case "delete":
		cem = cem.deleteForward()
	case "tab":
		cem = cem.insertTab()
	case "shift+tab":
		cem = cem.unindent()
	
	// File operations
	case "ctrl+s":
		cmd = cem.saveFile()
	case "ctrl+o":
		cmd = cem.openFile()
	case "ctrl+n":
		cem = cem.newFile()
	
	// Edit operations
	case "ctrl+z":
		cem = cem.undo()
	case "ctrl+y", "ctrl+shift+z":
		cem = cem.redo()
	case "ctrl+c":
		cmd = cem.copySelection()
	case "ctrl+x":
		cem, cmd = cem.cutSelection()
	case "ctrl+v":
		cem, cmd = cem.paste()
	case "ctrl+d":
		cem = cem.duplicateLine()
	case "ctrl+l":
		cem = cem.deleteLine()
	
	// Search and replace
	case "ctrl+f":
		cem.searchMode = true
		cem.searchQuery = ""
	case "ctrl+h":
		cem.replaceMode = true
		cem.searchQuery = ""
	case "f3":
		cem = cem.findNext()
	case "shift+f3":
		cem = cem.findPrevious()
	
	// View options
	case "ctrl+g":
		cmd = cem.goToLine()
	case "ctrl+plus", "ctrl+=":
		// Zoom in (could adjust font size if supported)
	case "ctrl+minus", "ctrl+-":
		// Zoom out
	case "ctrl+0":
		// Reset zoom
	
	// Insert mode toggle
	case "insert":
		cem.insertMode = !cem.insertMode
	
	// Regular character input
	default:
		if len(msg.Runes) == 1 {
			cem = cem.insertRune(msg.Runes[0])
		}
	}
	
	cem.adjustViewport()
	return cem, cmd
}

// handleSearchInput handles search mode input
func (cem CodeEditorModel) handleSearchInput(msg tea.KeyMsg) (CodeEditorModel, tea.Cmd) {
	switch msg.String() {
	case "esc":
		cem.searchMode = false
		cem.searchQuery = ""
	case "enter":
		cem.searchMode = false
		cem = cem.findNext()
	case "backspace":
		if len(cem.searchQuery) > 0 {
			cem.searchQuery = cem.searchQuery[:len(cem.searchQuery)-1]
		}
	default:
		if len(msg.Runes) > 0 {
			cem.searchQuery += string(msg.Runes)
		}
	}
	return cem, nil
}

// handleReplaceInput handles replace mode input
func (cem CodeEditorModel) handleReplaceInput(msg tea.KeyMsg) (CodeEditorModel, tea.Cmd) {
	switch msg.String() {
	case "esc":
		cem.replaceMode = false
		cem.searchQuery = ""
	case "enter":
		cem.replaceMode = false
		// Implement replace functionality
	default:
		// Handle replace input
	}
	return cem, nil
}

// View renders the code editor
func (cem CodeEditorModel) View() string {
	if cem.width == 0 || cem.height == 0 {
		return ""
	}
	
	style := lipgloss.NewStyle().
		Width(cem.width).
		Height(cem.height).
		Background(lipgloss.Color("235")).
		Foreground(lipgloss.Color("255"))
	
	if cem.focused {
		style = style.
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("63"))
	} else {
		style = style.
			BorderStyle(lipgloss.NormalBorder()).
			BorderForeground(lipgloss.Color("241"))
	}
	
	var content strings.Builder
	
	// Header with filename and status
	header := cem.renderHeader()
	content.WriteString(header)
	content.WriteString("\n")
	content.WriteString(strings.Repeat("─", cem.width-2))
	content.WriteString("\n")
	
	// Code content with syntax highlighting
	codeLines := cem.renderCodeLines()
	for i, line := range codeLines {
		if i+2 >= cem.height-2 { // Account for header, separator, and status
			break
		}
		content.WriteString(line)
		if i < len(codeLines)-1 {
			content.WriteString("\n")
		}
	}
	
	// Status line
	if cem.height > 3 {
		content.WriteString("\n")
		content.WriteString(cem.renderStatusLine())
	}
	
	return style.Render(content.String())
}

// renderHeader renders the editor header
func (cem CodeEditorModel) renderHeader() string {
	filename := "Untitled"
	if cem.filePath != "" {
		filename = filepath.Base(cem.filePath)
	}
	
	if cem.modified {
		filename += " •"
	}
	
	icon := "📝"
	if cem.language != "" {
		icon = cem.getLanguageIcon(cem.language)
	}
	
	return lipgloss.NewStyle().
		Foreground(lipgloss.Color("63")).
		Bold(true).
		Render(fmt.Sprintf("%s %s", icon, filename))
}

// renderCodeLines renders the code content with syntax highlighting
func (cem CodeEditorModel) renderCodeLines() []string {
	var lines []string
	
	maxVisible := cem.height - 4 // Account for header, separator, and status
	if maxVisible <= 0 {
		return lines
	}
	
	startLine := cem.viewport.offset
	endLine := startLine + maxVisible
	
	if endLine > len(cem.content) {
		endLine = len(cem.content)
	}
	
	// Calculate line number width
	lineNumWidth := 0
	if cem.lineNumbers {
		lineNumWidth = len(fmt.Sprintf("%d", len(cem.content))) + 1
	}
	
	for i := startLine; i < endLine; i++ {
		line := ""
		if i < len(cem.content) {
			line = cem.content[i]
		}
		
		// Apply syntax highlighting
		if cem.highlighter != nil && cem.language != "" {
			highlighted := cem.highlighter.Highlight(line)
			line = highlighted
		}
		
		// Add line numbers
		if cem.lineNumbers {
			lineNum := fmt.Sprintf("%*d ", lineNumWidth-1, i+1)
			lineNumStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
			line = lineNumStyle.Render(lineNum) + line
		}
		
		// Highlight current line
		if i == cem.cursor.line && cem.focused {
			line = lipgloss.NewStyle().
				Background(lipgloss.Color("237")).
				Width(cem.width - 2).
				Render(line)
		}
		
		// Add cursor if on current line
		if i == cem.cursor.line && cem.focused {
			// Insert cursor character at cursor position
			cursorPos := cem.cursor.column
			if cem.lineNumbers {
				cursorPos += lineNumWidth
			}
			
			if cursorPos <= len(line) {
				cursor := "█"
				if !cem.insertMode {
					cursor = "▄"
				}
				
				if cursorPos == len(line) {
					line += cursor
				} else {
					line = line[:cursorPos] + cursor + line[cursorPos+1:]
				}
			}
		}
		
		lines = append(lines, line)
	}
	
	return lines
}

// renderStatusLine renders the editor status line
func (cem CodeEditorModel) renderStatusLine() string {
	var parts []string
	
	// Cursor position
	parts = append(parts, fmt.Sprintf("Ln %d, Col %d", cem.cursor.line+1, cem.cursor.column+1))
	
	// Language
	if cem.language != "" {
		parts = append(parts, cem.language)
	}
	
	// Insert/Replace mode
	mode := "INS"
	if !cem.insertMode {
		mode = "OVR"
	}
	parts = append(parts, mode)
	
	// Search mode
	if cem.searchMode {
		parts = append(parts, fmt.Sprintf("Search: %s", cem.searchQuery))
	}
	
	// Selection info
	if cem.selection.active {
		lines := cem.getSelectionLines()
		parts = append(parts, fmt.Sprintf("Sel: %d lines", lines))
	}
	
	// Modified indicator
	if cem.modified {
		parts = append(parts, "Modified")
	}
	
	status := strings.Join(parts, " | ")
	return lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Render(status)
}

// Syntax highlighting methods
func (sh *SyntaxHighlighter) SetLanguage(language string) {
	sh.lexer = lexers.Get(language)
	if sh.lexer == nil {
		sh.lexer = lexers.Fallback
	}
}

func (sh *SyntaxHighlighter) Highlight(code string) string {
	if sh.lexer == nil {
		return code
	}
	
	iterator, err := sh.lexer.Tokenise(nil, code)
	if err != nil {
		return code
	}
	
	var buf strings.Builder
	err = sh.formatter.Format(&buf, sh.style, iterator)
	if err != nil {
		return code
	}
	
	return buf.String()
}

// Language detection and icons
func (cem CodeEditorModel) detectLanguage(filePath string) string {
	if filePath == "" {
		return ""
	}
	
	ext := strings.ToLower(filepath.Ext(filePath))
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
	case ".md":
		return "markdown"
	case ".json":
		return "json"
	case ".yml", ".yaml":
		return "yaml"
	case ".toml":
		return "toml"
	case ".html":
		return "html"
	case ".css":
		return "css"
	case ".sql":
		return "sql"
	case ".sh":
		return "bash"
	case ".c":
		return "c"
	case ".cpp", ".cc":
		return "cpp"
	case ".java":
		return "java"
	default:
		return "text"
	}
}

func (cem CodeEditorModel) getLanguageIcon(language string) string {
	switch language {
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
	case "markdown":
		return "📝"
	case "json":
		return "📋"
	case "yaml", "toml":
		return "⚙️"
	case "html":
		return "🌐"
	case "css":
		return "🎨"
	case "sql":
		return "🗃️"
	case "bash":
		return "🖥️"
	default:
		return "📄"
	}
}

// Editor operation methods (simplified implementations)
func (cem CodeEditorModel) moveCursorUp() CodeEditorModel {
	if cem.cursor.line > 0 {
		cem.cursor.line--
		cem.ensureCursorInBounds()
	}
	return cem
}

func (cem CodeEditorModel) moveCursorDown() CodeEditorModel {
	if cem.cursor.line < len(cem.content)-1 {
		cem.cursor.line++
		cem.ensureCursorInBounds()
	}
	return cem
}

func (cem CodeEditorModel) moveCursorLeft() CodeEditorModel {
	if cem.cursor.column > 0 {
		cem.cursor.column--
	} else if cem.cursor.line > 0 {
		cem.cursor.line--
		if cem.cursor.line < len(cem.content) {
			cem.cursor.column = len(cem.content[cem.cursor.line])
		}
	}
	return cem
}

func (cem CodeEditorModel) moveCursorRight() CodeEditorModel {
	if cem.cursor.line < len(cem.content) {
		lineLength := len(cem.content[cem.cursor.line])
		if cem.cursor.column < lineLength {
			cem.cursor.column++
		} else if cem.cursor.line < len(cem.content)-1 {
			cem.cursor.line++
			cem.cursor.column = 0
		}
	}
	return cem
}

func (cem CodeEditorModel) insertRune(r rune) CodeEditorModel {
	cem.saveState()
	
	if cem.cursor.line >= len(cem.content) {
		cem.content = append(cem.content, "")
	}
	
	line := cem.content[cem.cursor.line]
	if cem.cursor.column > len(line) {
		cem.cursor.column = len(line)
	}
	
	newLine := line[:cem.cursor.column] + string(r) + line[cem.cursor.column:]
	cem.content[cem.cursor.line] = newLine
	cem.cursor.column++
	cem.modified = true
	
	return cem
}

func (cem CodeEditorModel) insertNewline() CodeEditorModel {
	cem.saveState()
	
	if cem.cursor.line >= len(cem.content) {
		cem.content = append(cem.content, "")
		cem.cursor.line = len(cem.content) - 1
		cem.cursor.column = 0
		return cem
	}
	
	line := cem.content[cem.cursor.line]
	leftPart := line[:cem.cursor.column]
	rightPart := line[cem.cursor.column:]
	
	cem.content[cem.cursor.line] = leftPart
	cem.content = append(cem.content[:cem.cursor.line+1], 
		append([]string{rightPart}, cem.content[cem.cursor.line+1:]...)...)
	
	cem.cursor.line++
	cem.cursor.column = 0
	cem.modified = true
	
	return cem
}

func (cem CodeEditorModel) deleteBackward() CodeEditorModel {
	if cem.cursor.column == 0 && cem.cursor.line == 0 {
		return cem
	}
	
	cem.saveState()
	
	if cem.cursor.column > 0 {
		line := cem.content[cem.cursor.line]
		newLine := line[:cem.cursor.column-1] + line[cem.cursor.column:]
		cem.content[cem.cursor.line] = newLine
		cem.cursor.column--
	} else {
		// Join with previous line
		if cem.cursor.line > 0 {
			prevLine := cem.content[cem.cursor.line-1]
			currentLine := cem.content[cem.cursor.line]
			cem.content[cem.cursor.line-1] = prevLine + currentLine
			cem.content = append(cem.content[:cem.cursor.line], cem.content[cem.cursor.line+1:]...)
			cem.cursor.line--
			cem.cursor.column = len(prevLine)
		}
	}
	
	cem.modified = true
	return cem
}

func (cem CodeEditorModel) ensureCursorInBounds() {
	if cem.cursor.line >= len(cem.content) {
		cem.cursor.line = len(cem.content) - 1
	}
	if cem.cursor.line < 0 {
		cem.cursor.line = 0
	}
	
	if cem.cursor.line < len(cem.content) {
		lineLength := len(cem.content[cem.cursor.line])
		if cem.cursor.column > lineLength {
			cem.cursor.column = lineLength
		}
	}
	
	if cem.cursor.column < 0 {
		cem.cursor.column = 0
	}
}

func (cem CodeEditorModel) adjustViewport() {
	maxVisible := cem.height - 4
	if maxVisible <= 0 {
		return
	}
	
	// Ensure cursor line is visible
	if cem.cursor.line < cem.viewport.offset {
		cem.viewport.offset = cem.cursor.line
	} else if cem.cursor.line >= cem.viewport.offset+maxVisible {
		cem.viewport.offset = cem.cursor.line - maxVisible + 1
	}
	
	if cem.viewport.offset < 0 {
		cem.viewport.offset = 0
	}
}

// State management
func (cem CodeEditorModel) saveState() {
	state := EditorState{
		content:   make([]string, len(cem.content)),
		cursor:    cem.cursor,
		selection: cem.selection,
		timestamp: time.Now(),
	}
	copy(state.content, cem.content)
	
	cem.undoStack = append(cem.undoStack, state)
	if len(cem.undoStack) > 100 {
		cem.undoStack = cem.undoStack[1:]
	}
	
	// Clear redo stack
	cem.redoStack = cem.redoStack[:0]
}

func (cem CodeEditorModel) undo() CodeEditorModel {
	if len(cem.undoStack) == 0 {
		return cem
	}
	
	// Save current state to redo stack
	currentState := EditorState{
		content:   make([]string, len(cem.content)),
		cursor:    cem.cursor,
		selection: cem.selection,
		timestamp: time.Now(),
	}
	copy(currentState.content, cem.content)
	cem.redoStack = append(cem.redoStack, currentState)
	
	// Restore previous state
	prevState := cem.undoStack[len(cem.undoStack)-1]
	cem.undoStack = cem.undoStack[:len(cem.undoStack)-1]
	
	cem.content = make([]string, len(prevState.content))
	copy(cem.content, prevState.content)
	cem.cursor = prevState.cursor
	cem.selection = prevState.selection
	cem.modified = true
	
	return cem
}

func (cem CodeEditorModel) redo() CodeEditorModel {
	if len(cem.redoStack) == 0 {
		return cem
	}
	
	// Save current state to undo stack
	cem.saveState()
	
	// Restore next state
	nextState := cem.redoStack[len(cem.redoStack)-1]
	cem.redoStack = cem.redoStack[:len(cem.redoStack)-1]
	
	cem.content = make([]string, len(nextState.content))
	copy(cem.content, nextState.content)
	cem.cursor = nextState.cursor
	cem.selection = nextState.selection
	cem.modified = true
	
	return cem
}

// Placeholder implementations for remaining methods
func (cem CodeEditorModel) moveCursorToLineStart() CodeEditorModel {
	cem.cursor.column = 0
	return cem
}

func (cem CodeEditorModel) moveCursorToLineEnd() CodeEditorModel {
	if cem.cursor.line < len(cem.content) {
		cem.cursor.column = len(cem.content[cem.cursor.line])
	}
	return cem
}

func (cem CodeEditorModel) moveCursorToStart() CodeEditorModel {
	cem.cursor = CursorPosition{line: 0, column: 0}
	return cem
}

func (cem CodeEditorModel) moveCursorToEnd() CodeEditorModel {
	if len(cem.content) > 0 {
		cem.cursor.line = len(cem.content) - 1
		cem.cursor.column = len(cem.content[cem.cursor.line])
	}
	return cem
}

func (cem CodeEditorModel) moveCursorPageUp() CodeEditorModel {
	pageSize := cem.height - 4
	cem.cursor.line -= pageSize
	if cem.cursor.line < 0 {
		cem.cursor.line = 0
	}
	cem.ensureCursorInBounds()
	return cem
}

func (cem CodeEditorModel) moveCursorPageDown() CodeEditorModel {
	pageSize := cem.height - 4
	cem.cursor.line += pageSize
	if cem.cursor.line >= len(cem.content) {
		cem.cursor.line = len(cem.content) - 1
	}
	cem.ensureCursorInBounds()
	return cem
}

func (cem CodeEditorModel) moveCursorWordLeft() CodeEditorModel {
	// Simplified word movement
	for cem.cursor.column > 0 {
		cem.cursor.column--
		if cem.cursor.line < len(cem.content) {
			char := cem.content[cem.cursor.line][cem.cursor.column]
			if char == ' ' || char == '\t' {
				break
			}
		}
	}
	return cem
}

func (cem CodeEditorModel) moveCursorWordRight() CodeEditorModel {
	// Simplified word movement
	if cem.cursor.line < len(cem.content) {
		for cem.cursor.column < len(cem.content[cem.cursor.line]) {
			char := cem.content[cem.cursor.line][cem.cursor.column]
			cem.cursor.column++
			if char == ' ' || char == '\t' {
				break
			}
		}
	}
	return cem
}

// Placeholder methods for remaining functionality
func (cem CodeEditorModel) selectUp() CodeEditorModel { return cem }
func (cem CodeEditorModel) selectDown() CodeEditorModel { return cem }
func (cem CodeEditorModel) selectLeft() CodeEditorModel { return cem }
func (cem CodeEditorModel) selectRight() CodeEditorModel { return cem }
func (cem CodeEditorModel) selectAll() CodeEditorModel { return cem }
func (cem CodeEditorModel) selectWordLeft() CodeEditorModel { return cem }
func (cem CodeEditorModel) selectWordRight() CodeEditorModel { return cem }
func (cem CodeEditorModel) deleteForward() CodeEditorModel { return cem }
func (cem CodeEditorModel) insertTab() CodeEditorModel { return cem.insertRune('\t') }
func (cem CodeEditorModel) unindent() CodeEditorModel { return cem }
func (cem CodeEditorModel) duplicateLine() CodeEditorModel { return cem }
func (cem CodeEditorModel) deleteLine() CodeEditorModel { return cem }
func (cem CodeEditorModel) findNext() CodeEditorModel { return cem }
func (cem CodeEditorModel) findPrevious() CodeEditorModel { return cem }
func (cem CodeEditorModel) newFile() CodeEditorModel { return cem }
func (cem CodeEditorModel) getSelectionLines() int { return 0 }

// Command methods
func (cem CodeEditorModel) saveFile() tea.Cmd {
	if cem.filePath == "" {
		return nil
	}
	return func() tea.Msg {
		return SaveFileMsg{Path: cem.filePath, Content: cem.content}
	}
}

func (cem CodeEditorModel) openFile() tea.Cmd {
	return func() tea.Msg {
		return OpenFileDialogMsg{}
	}
}

func (cem CodeEditorModel) copySelection() tea.Cmd {
	return func() tea.Msg {
		return CopySelectionMsg{}
	}
}

func (cem CodeEditorModel) cutSelection() (CodeEditorModel, tea.Cmd) {
	return cem, func() tea.Msg {
		return CutSelectionMsg{}
	}
}

func (cem CodeEditorModel) paste() (CodeEditorModel, tea.Cmd) {
	return cem, func() tea.Msg {
		return PasteMsg{}
	}
}

func (cem CodeEditorModel) goToLine() tea.Cmd {
	return func() tea.Msg {
		return GoToLineMsg{}
	}
}

// Additional message types
type FileContentLoadedMsg struct {
	Path    string
	Content []string
}

type FileSavedMsg struct {
	Path string
}

type SaveFileMsg struct {
	Path    string
	Content []string
}

type OpenFileDialogMsg struct{}
type CopySelectionMsg struct{}
type CutSelectionMsg struct{}
type PasteMsg struct{}
type GoToLineMsg struct{}