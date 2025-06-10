package ui

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Style definitions
var (
	headerStyle = lipgloss.NewStyle().
			Background(lipgloss.Color("63")).
			Foreground(lipgloss.Color("230")).
			Bold(true).
			Padding(0, 1)

	statusStyle = lipgloss.NewStyle().
			Background(lipgloss.Color("240")).
			Foreground(lipgloss.Color("250")).
			Padding(0, 1)

	dividerStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("241"))

	errorStyle = lipgloss.NewStyle().
			Background(lipgloss.Color("196")).
			Foreground(lipgloss.Color("230")).
			Bold(true).
			Padding(0, 1)

	successStyle = lipgloss.NewStyle().
			Background(lipgloss.Color("34")).
			Foreground(lipgloss.Color("230")).
			Bold(true).
			Padding(0, 1)
)

// renderLoadingScreen renders the initial loading screen
func (m AIAssistantModel) renderLoadingScreen() string {
	content := lipgloss.Place(
		m.width, m.height,
		lipgloss.Center, lipgloss.Center,
		lipgloss.JoinVertical(
			lipgloss.Center,
			"🤖",
			"",
			"Aiex AI Assistant",
			"",
			"Connecting to backend...",
		),
	)
	return content
}

// renderHeader renders the application header
func (m AIAssistantModel) renderHeader() string {
	title := "🤖 Aiex AI Assistant"
	
	connectionStatus := "🔴 Disconnected"
	if m.connected {
		connectionStatus = "🟢 Connected"
	}
	
	leftSide := headerStyle.Render(title)
	rightSide := headerStyle.Render(connectionStatus)
	
	spacer := strings.Repeat(" ", m.width-lipgloss.Width(leftSide)-lipgloss.Width(rightSide))
	
	return leftSide + spacer + rightSide
}

// renderStatusBar renders the bottom status bar
func (m AIAssistantModel) renderStatusBar() string {
	var parts []string
	
	// Panel indicator
	panelName := map[PanelType]string{
		FileTreePanel: "Files",
		EditorPanel:   "Editor",
		ChatPanel:     "Chat",
		ContextPanel:  "Context",
	}[m.activePanel]
	
	parts = append(parts, fmt.Sprintf("Panel: %s", panelName))
	
	// Status message or error
	if m.errorMessage != "" {
		parts = append(parts, errorStyle.Render(m.errorMessage))
	} else if m.statusMessage != "" {
		parts = append(parts, successStyle.Render(m.statusMessage))
	}
	
	// Shortcuts
	shortcuts := "Tab: Switch Panel | F1: Toggle Sidebar | F2: Toggle Context | Ctrl+C: Quit"
	
	// Last update time
	updateTime := ""
	if !m.lastUpdate.IsZero() {
		updateTime = fmt.Sprintf("Updated: %s", m.lastUpdate.Format("15:04:05"))
	}
	
	leftSide := strings.Join(parts, " | ")
	rightSide := updateTime
	
	availableWidth := m.width - lipgloss.Width(leftSide) - lipgloss.Width(rightSide) - 4
	if availableWidth > len(shortcuts) {
		leftSide += " | " + shortcuts
	}
	
	spacer := strings.Repeat(" ", m.width-lipgloss.Width(leftSide)-lipgloss.Width(rightSide))
	
	return statusStyle.Render(leftSide + spacer + rightSide)
}

// renderSidebar renders the file explorer sidebar
func (m AIAssistantModel) renderSidebar(width, height int) string {
	m.fileExplorer.width = width
	m.fileExplorer.height = height
	m.fileExplorer.focused = m.focusManager.IsFocused(FileTreePanel)
	
	return m.fileExplorer.View()
}

// renderEditor renders the code editor panel
func (m AIAssistantModel) renderEditor(width, height int) string {
	m.codeEditor.width = width
	m.codeEditor.height = height
	m.codeEditor.focused = m.focusManager.IsFocused(EditorPanel)
	
	return m.codeEditor.View()
}

// renderChat renders the chat panel
func (m AIAssistantModel) renderChat(width, height int) string {
	m.chatPanel.width = width
	m.chatPanel.height = height
	m.chatPanel.focused = m.focusManager.IsFocused(ChatPanel)
	
	return m.chatPanel.View()
}

// renderVerticalDivider renders a vertical divider
func (m AIAssistantModel) renderVerticalDivider(height int) string {
	return dividerStyle.Render(strings.Repeat("│\n", height-1) + "│")
}

// Helper methods for commands
func (m AIAssistantModel) connectToBackend() tea.Cmd {
	return func() tea.Msg {
		// This would normally connect to the RPC backend
		// For now, simulate connection after delay
		time.Sleep(100 * time.Millisecond)
		return ConnectionEstablishedMsg{}
	}
}

func (m AIAssistantModel) loadInitialState() tea.Cmd {
	return func() tea.Msg {
		// Load initial application state
		return StateLoadedMsg{}
	}
}

func (m AIAssistantModel) initializePanels() tea.Cmd {
	return func() tea.Msg {
		// Initialize all panels
		return PanelsInitializedMsg{}
	}
}

func (m AIAssistantModel) subscribeToEvents() tea.Cmd {
	return func() tea.Msg {
		// Subscribe to real-time events
		return EventSubscriptionMsg{}
	}
}

func (m AIAssistantModel) loadFile(path string) tea.Cmd {
	return func() tea.Msg {
		// Load file content for editing
		return FileLoadedMsg{Path: path, Content: []string{"// File content would be loaded here"}}
	}
}

func (m AIAssistantModel) handleStreamEvent(msg EventStreamMsg) (AIAssistantModel, tea.Cmd) {
	// Process streaming events from backend
	m.lastUpdate = time.Now()
	
	switch msg.Type {
	case "ai_response":
		// Handle AI response
	case "file_change":
		// Handle file system changes
	case "context_update":
		// Handle context updates
	}
	
	return m, nil
}

func (m AIAssistantModel) handleRPCResponse(msg RPCResponseMsg) (AIAssistantModel, tea.Cmd) {
	// Process RPC responses
	m.lastUpdate = time.Now()
	
	if msg.Error != nil {
		m.errorMessage = fmt.Sprintf("RPC Error: %v", msg.Error)
	} else {
		m.errorMessage = ""
		m.statusMessage = fmt.Sprintf("RPC %s completed", msg.Method)
	}
	
	return m, nil
}

// Additional message types
type StateLoadedMsg struct{}
type PanelsInitializedMsg struct{}
type EventSubscriptionMsg struct{}
type FileLoadedMsg struct {
	Path    string
	Content []string
}