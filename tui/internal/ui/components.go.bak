package ui

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"aiex-tui/pkg/types"
)

// FileExplorerModel represents the file explorer panel
type FileExplorerModel struct {
	width       int
	height      int
	files       []types.FileInfo
	selected    int
	focused     bool
	cursor      int
	viewport    ViewportState
}

// CodeEditorModel represents the code editor panel
type CodeEditorModel struct {
	width       int
	height      int
	content     []string
	cursor      CursorPosition
	selection   Selection
	language    string
	filePath    string
	focused     bool
	viewport    ViewportState
	modified    bool
}

// ChatPanelModel represents the chat interface panel
type ChatPanelModel struct {
	width       int
	height      int
	messages    []types.Message
	input       string
	focused     bool
	viewport    ViewportState
	typing      bool
	streaming   bool
}

// ContextPanelModel represents the context awareness panel
type ContextPanelModel struct {
	width       int
	height      int
	project     types.Project
	openFiles   []string
	quickActions []QuickAction
	focused     bool
}

// Supporting types
type ViewportState struct {
	offset int
	height int
}

type CursorPosition struct {
	line   int
	column int
}

type Selection struct {
	start CursorPosition
	end   CursorPosition
	active bool
}

type QuickAction struct {
	id          string
	label       string
	description string
	shortcut    string
	command     string
}

// EventStreamManager handles event stream processing
type EventStreamManager struct {
	buffer       []types.StateUpdate
	bufferSize   int
	rateLimiter  *RateLimiter
	processing   bool
}

// FocusManager handles panel focus state
type FocusManager struct {
	currentPanel PanelType
	history      []PanelType
}

// RateLimiter implements adaptive rate limiting
type RateLimiter struct {
	maxEvents    int
	window       time.Duration
	events       []time.Time
	adaptive     bool
}

// NewEventStreamManager creates a new event stream manager
func NewEventStreamManager() *EventStreamManager {
	return &EventStreamManager{
		buffer:     make([]types.StateUpdate, 0, 1000),
		bufferSize: 1000,
		rateLimiter: &RateLimiter{
			maxEvents: 100,
			window:    time.Second,
			events:    make([]time.Time, 0),
			adaptive:  true,
		},
	}
}

// NewFocusManager creates a new focus manager
func NewFocusManager() *FocusManager {
	return &FocusManager{
		currentPanel: FileTreePanel,
		history:      make([]PanelType, 0),
	}
}

// SetFocus sets the current focused panel
func (fm *FocusManager) SetFocus(panel PanelType) {
	if fm.currentPanel != panel {
		fm.history = append(fm.history, fm.currentPanel)
		if len(fm.history) > 10 {
			fm.history = fm.history[1:]
		}
	}
	fm.currentPanel = panel
}

// FileExplorerModel methods
func (fem FileExplorerModel) Update(msg tea.Msg) (FileExplorerModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !fem.focused {
			return fem, nil
		}
		
		switch msg.String() {
		case "up", "k":
			if fem.selected > 0 {
				fem.selected--
			}
		case "down", "j":
			if fem.selected < len(fem.files)-1 {
				fem.selected++
			}
		case "enter":
			if fem.selected < len(fem.files) {
				selectedFile := fem.files[fem.selected]
				return fem, func() tea.Msg {
					return FileSelectedMsg{Path: selectedFile.Path}
				}
			}
		}
	}
	return fem, nil
}

func (fem FileExplorerModel) View() string {
	if fem.width == 0 || fem.height == 0 {
		return ""
	}

	var lines []string
	style := lipgloss.NewStyle().Width(fem.width).Height(fem.height)
	
	if fem.focused {
		style = style.BorderStyle(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("63"))
	}

	title := "📁 Files"
	lines = append(lines, title)
	lines = append(lines, strings.Repeat("─", fem.width-2))

	for i, file := range fem.files {
		icon := "📄"
		if file.Type == "directory" {
			icon = "📁"
		}
		
		line := fmt.Sprintf("%s %s", icon, file.Name)
		if i == fem.selected && fem.focused {
			line = lipgloss.NewStyle().Background(lipgloss.Color("63")).Render(line)
		}
		
		lines = append(lines, line)
		if len(lines) >= fem.height-1 {
			break
		}
	}

	content := strings.Join(lines, "\n")
	return style.Render(content)
}

func (fem FileExplorerModel) Resize(width, height int) FileExplorerModel {
	fem.width = width
	fem.height = height
	return fem
}

// CodeEditorModel methods
func (cem CodeEditorModel) Update(msg tea.Msg) (CodeEditorModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !cem.focused {
			return cem, nil
		}
		
		switch msg.String() {
		case "up":
			if cem.cursor.line > 0 {
				cem.cursor.line--
			}
		case "down":
			if cem.cursor.line < len(cem.content)-1 {
				cem.cursor.line++
			}
		case "left":
			if cem.cursor.column > 0 {
				cem.cursor.column--
			}
		case "right":
			if cem.cursor.line < len(cem.content) && cem.cursor.column < len(cem.content[cem.cursor.line]) {
				cem.cursor.column++
			}
		}
	}
	return cem, nil
}

func (cem CodeEditorModel) View() string {
	if cem.width == 0 || cem.height == 0 {
		return ""
	}

	var lines []string
	style := lipgloss.NewStyle().Width(cem.width).Height(cem.height)
	
	if cem.focused {
		style = style.BorderStyle(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("63"))
	}

	title := fmt.Sprintf("📝 %s", cem.filePath)
	if cem.modified {
		title += " •"
	}
	
	lines = append(lines, title)
	lines = append(lines, strings.Repeat("─", cem.width-2))

	startLine := cem.viewport.offset
	endLine := startLine + cem.height - 3
	
	if endLine > len(cem.content) {
		endLine = len(cem.content)
	}

	for i := startLine; i < endLine; i++ {
		line := ""
		if i < len(cem.content) {
			line = cem.content[i]
		}
		
		// Highlight current line
		if i == cem.cursor.line && cem.focused {
			line = lipgloss.NewStyle().Background(lipgloss.Color("235")).Render(line)
		}
		
		lines = append(lines, line)
	}

	content := strings.Join(lines, "\n")
	return style.Render(content)
}

func (cem CodeEditorModel) Resize(width, height int) CodeEditorModel {
	cem.width = width
	cem.height = height
	return cem
}

// ChatPanelModel methods
func (cpm ChatPanelModel) Update(msg tea.Msg) (ChatPanelModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !cpm.focused {
			return cpm, nil
		}
		
		switch msg.String() {
		case "enter":
			if strings.TrimSpace(cpm.input) != "" {
				message := types.Message{
					ID:        fmt.Sprintf("msg_%d", time.Now().UnixNano()),
					Role:      "user",
					Content:   cpm.input,
					Timestamp: time.Now(),
				}
				cpm.messages = append(cpm.messages, message)
				cpm.input = ""
				
				return cpm, func() tea.Msg {
					return SendMessageMsg{Content: message.Content}
				}
			}
		default:
			if len(msg.Runes) > 0 {
				cpm.input += string(msg.Runes)
			}
		}
	}
	return cpm, nil
}

func (cpm ChatPanelModel) View() string {
	if cpm.width == 0 || cpm.height == 0 {
		return ""
	}

	var lines []string
	style := lipgloss.NewStyle().Width(cpm.width).Height(cpm.height)
	
	if cpm.focused {
		style = style.BorderStyle(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("63"))
	}

	title := "💬 Chat"
	lines = append(lines, title)
	lines = append(lines, strings.Repeat("─", cpm.width-2))

	// Render messages
	messageLines := cpm.height - 5 // Reserve space for title, separator, input
	for i := len(cpm.messages) - messageLines; i < len(cpm.messages); i++ {
		if i < 0 {
			continue
		}
		
		msg := cpm.messages[i]
		role := "👤"
		if msg.Role == "assistant" {
			role = "🤖"
		}
		
		line := fmt.Sprintf("%s %s", role, msg.Content)
		if len(line) > cpm.width-2 {
			line = line[:cpm.width-5] + "..."
		}
		
		lines = append(lines, line)
	}

	// Add input area
	lines = append(lines, strings.Repeat("─", cpm.width-2))
	inputLine := fmt.Sprintf("> %s", cpm.input)
	if cpm.focused {
		inputLine += "█"
	}
	lines = append(lines, inputLine)

	content := strings.Join(lines, "\n")
	return style.Render(content)
}

func (cpm ChatPanelModel) Resize(width, height int) ChatPanelModel {
	cpm.width = width
	cpm.height = height
	return cpm
}

func (cpm ChatPanelModel) AddMessage(response types.AIResponse) ChatPanelModel {
	message := types.Message{
		ID:        response.ID,
		Role:      response.Role,
		Content:   response.Content,
		Timestamp: response.Timestamp,
	}
	cpm.messages = append(cpm.messages, message)
	return cpm
}

func (cpm ChatPanelModel) ScrollToBottom() tea.Cmd {
	return func() tea.Msg {
		return ScrollToBottomMsg{}
	}
}

// ContextPanelModel methods
func (cpm ContextPanelModel) Update(msg tea.Msg) (ContextPanelModel, tea.Cmd) {
	return cpm, nil
}

func (cpm ContextPanelModel) View() string {
	if cpm.width == 0 || cpm.height == 0 {
		return ""
	}

	var lines []string
	style := lipgloss.NewStyle().Width(cpm.width).Height(cpm.height)
	
	if cpm.focused {
		style = style.BorderStyle(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("63"))
	}

	title := "🔍 Context"
	lines = append(lines, title)
	lines = append(lines, strings.Repeat("─", cpm.width-2))

	// Project info
	lines = append(lines, fmt.Sprintf("📁 %s", cpm.project.Name))
	lines = append(lines, fmt.Sprintf("🏷️  %s", cpm.project.Language))
	
	// Open files
	if len(cpm.openFiles) > 0 {
		lines = append(lines, "")
		lines = append(lines, "📄 Open Files:")
		for _, file := range cpm.openFiles {
			if len(lines) >= cpm.height-1 {
				break
			}
			lines = append(lines, fmt.Sprintf("  %s", file))
		}
	}

	content := strings.Join(lines, "\n")
	return style.Render(content)
}

func (cpm ContextPanelModel) Resize(width, height int) ContextPanelModel {
	cpm.width = width
	cpm.height = height
	return cpm
}

// Additional message types
type SendMessageMsg struct {
	Content string
}

type ScrollToBottomMsg struct{}