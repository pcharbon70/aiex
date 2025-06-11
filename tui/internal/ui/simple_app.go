package ui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"aiex-tui/internal/rpc"
)

// SimpleApp represents the main TUI application
type SimpleApp struct {
	width    int
	height   int
	focused  string // "files", "editor", "chat"
	
	// Simple chat functionality
	messages []string
	input    string
	
	// Simple file list
	files    []string
	fileIdx  int
	
	// Simple editor content
	content  string
	
	// RPC client
	client   *rpc.Client
}

// NewApp creates a new application instance
func NewApp(client *rpc.Client) *SimpleApp {
	return &SimpleApp{
		width:   80,
		height:  24,
		focused: "chat",
		messages: []string{
			"Welcome to Aiex TUI!",
			"This is a chat interface with the AI assistant.",
			"Type your message and press Enter to send.",
		},
		files: []string{
			"main.go",
			"app.go",
			"types.go",
			"README.md",
		},
		fileIdx: 0,
		content: "// Select a file to view its content\n",
		client:  client,
	}
}

func (m *SimpleApp) Init() tea.Cmd {
	return nil
}

func (m *SimpleApp) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
		
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
			
		case "tab":
			// Switch focus between panels
			switch m.focused {
			case "files":
				m.focused = "editor"
			case "editor":
				m.focused = "chat"
			case "chat":
				m.focused = "files"
			}
			return m, nil
			
		case "enter":
			if m.focused == "chat" && m.input != "" {
				// Send message
				m.messages = append(m.messages, "You: "+m.input)
				response := "AI: I received your message: " + m.input
				m.messages = append(m.messages, response)
				m.input = ""
				return m, nil
			} else if m.focused == "files" {
				// Load file content
				if m.fileIdx < len(m.files) {
					filename := m.files[m.fileIdx]
					m.content = fmt.Sprintf("// Content of %s\n// This would load actual file content\n", filename)
				}
				return m, nil
			}
			
		case "up":
			if m.focused == "files" && m.fileIdx > 0 {
				m.fileIdx--
			}
			return m, nil
			
		case "down":
			if m.focused == "files" && m.fileIdx < len(m.files)-1 {
				m.fileIdx++
			}
			return m, nil
			
		case "backspace":
			if m.focused == "chat" && len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
			}
			return m, nil
			
		default:
			// Add character to input
			if m.focused == "chat" && len(msg.String()) == 1 {
				m.input += msg.String()
			}
			return m, nil
		}
	}
	return m, nil
}

func (m *SimpleApp) View() string {
	// Calculate panel dimensions
	panelWidth := m.width / 3
	panelHeight := m.height - 3 // Reserve space for status bar
	
	// Styles
	focusedStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62"))
	
	unfocusedStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("240"))
	
	titleStyle := lipgloss.NewStyle().
		Background(lipgloss.Color("62")).
		Foreground(lipgloss.Color("230")).
		Padding(0, 1).
		Bold(true)
	
	// File Explorer Panel
	var fileStyle lipgloss.Style
	if m.focused == "files" {
		fileStyle = focusedStyle
	} else {
		fileStyle = unfocusedStyle
	}
	
	fileList := []string{}
	for i, file := range m.files {
		if i == m.fileIdx {
			fileList = append(fileList, "> "+file)
		} else {
			fileList = append(fileList, "  "+file)
		}
	}
	
	fileContent := titleStyle.Render("Files") + "\n\n" + strings.Join(fileList, "\n")
	filePanel := fileStyle.
		Width(panelWidth).
		Height(panelHeight).
		Render(fileContent)
	
	// Code Editor Panel
	var editorStyle lipgloss.Style
	if m.focused == "editor" {
		editorStyle = focusedStyle
	} else {
		editorStyle = unfocusedStyle
	}
	
	editorContent := titleStyle.Render("Editor") + "\n\n" + m.content
	editorPanel := editorStyle.
		Width(panelWidth).
		Height(panelHeight).
		Render(editorContent)
	
	// Chat Panel
	var chatStyle lipgloss.Style
	if m.focused == "chat" {
		chatStyle = focusedStyle
	} else {
		chatStyle = unfocusedStyle
	}
	
	// Limit messages to fit in panel
	displayMessages := m.messages
	if len(displayMessages) > panelHeight-6 {
		displayMessages = displayMessages[len(displayMessages)-(panelHeight-6):]
	}
	
	chatContent := titleStyle.Render("AI Chat") + "\n\n" + 
		strings.Join(displayMessages, "\n") + "\n\n" +
		"Input: " + m.input + "█"
	
	chatPanel := chatStyle.
		Width(panelWidth).
		Height(panelHeight).
		Render(chatContent)
	
	// Combine panels horizontally
	panels := lipgloss.JoinHorizontal(lipgloss.Top, filePanel, editorPanel, chatPanel)
	
	// Status bar
	statusBar := lipgloss.NewStyle().
		Background(lipgloss.Color("62")).
		Foreground(lipgloss.Color("230")).
		Width(m.width).
		Render(fmt.Sprintf(" Focused: %s | Tab: switch panels | Enter: select/send | q: quit ", m.focused))
	
	// Combine everything vertically
	return lipgloss.JoinVertical(lipgloss.Left, panels, statusBar)
}