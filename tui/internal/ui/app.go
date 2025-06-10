package ui

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"aiex-tui/internal/rpc"
	"aiex-tui/internal/state"
	"aiex-tui/pkg/types"
)

// PanelType represents different UI panels
type PanelType int

const (
	FileTreePanel PanelType = iota
	EditorPanel
	ChatPanel
	ContextPanel
)

// AIAssistantModel represents the main application model
type AIAssistantModel struct {
	// Layout and UI state
	width       int
	height      int
	activePanel PanelType
	layout      LayoutConfig
	ready       bool
	connected   bool

	// Core panels
	fileExplorer FileExplorerModel
	codeEditor   CodeEditorModel
	chatPanel    ChatPanelModel
	contextPanel ContextPanelModel

	// Communication layer
	rpcClient   *rpc.Client
	eventStream *EventStreamManager

	// State management
	stateManager *state.Manager
	focusManager *FocusManager

	// Status and error handling
	statusMessage string
	errorMessage  string
	lastUpdate    time.Time
}

// LayoutConfig defines the layout configuration
type LayoutConfig struct {
	SidebarWidth int
	EditorRatio  float64
	ChatRatio    float64
	ShowSidebar  bool
	ShowContext  bool
}

// NewApp creates a new application instance
func NewApp(rpcClient *rpc.Client) *AIAssistantModel {
	focusManager := NewFocusManager()
	
	return &AIAssistantModel{
		rpcClient:   rpcClient,
		eventStream: NewEventStreamManager(),
		stateManager: state.NewManager(),
		focusManager: focusManager,
		layout: LayoutConfig{
			SidebarWidth: 30,
			EditorRatio:  0.6,
			ChatRatio:    0.4,
			ShowSidebar:  true,
			ShowContext:  true,
		},
		activePanel:  FileTreePanel,
		ready:        false,
		connected:    false,
		fileExplorer: NewFileExplorerModel("/home/ducky/code/aiex"),
		codeEditor:   NewCodeEditorModel(),
		chatPanel:    NewChatPanelModel(),
		contextPanel: ContextPanelModel{focused: false},
	}
}

// Init initializes the application
func (m AIAssistantModel) Init() tea.Cmd {
	return tea.Batch(
		m.connectToBackend(),
		m.loadInitialState(),
		tea.WindowSize(),
		m.initializePanels(),
	)
}

// Update handles all application updates
func (m AIAssistantModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m = m.resizeAllPanels()
		return m, nil

	case tea.KeyMsg:
		// Handle focus shortcuts first
		if cmd := m.focusManager.HandleFocusShortcut(msg.String()); cmd != nil {
			m.activePanel = m.focusManager.GetCurrentFocus()
			return m, cmd
		}
		
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "f1":
			m.layout.ShowSidebar = !m.layout.ShowSidebar
			return m, nil
		case "f2":
			m.layout.ShowContext = !m.layout.ShowContext
			return m, nil
		}

	case ConnectionEstablishedMsg:
		m.connected = true
		m.statusMessage = "Connected to Elixir backend"
		cmds = append(cmds, m.subscribeToEvents())

	case ConnectionLostMsg:
		m.connected = false
		m.errorMessage = "Connection lost, attempting to reconnect..."

	case AIResponseMsg:
		m.chatPanel = m.chatPanel.AddMessage(msg.Response)
		cmds = append(cmds, m.chatPanel.ScrollToBottom())

	case FileSelectedMsg:
		cmds = append(cmds, m.loadFile(msg.Path))

	case EventStreamMsg:
		return m.handleStreamEvent(msg)

	case RPCResponseMsg:
		return m.handleRPCResponse(msg)
	}

	// Update focused panel
	switch m.activePanel {
	case FileTreePanel:
		m.fileExplorer.focused = true
		newExplorer, cmd := m.fileExplorer.Update(msg)
		m.fileExplorer = newExplorer
		cmds = append(cmds, cmd)
	case EditorPanel:
		m.codeEditor.focused = true
		newEditor, cmd := m.codeEditor.Update(msg)
		m.codeEditor = newEditor
		cmds = append(cmds, cmd)
	case ChatPanel:
		m.chatPanel.focused = true
		newChat, cmd := m.chatPanel.Update(msg)
		m.chatPanel = newChat
		cmds = append(cmds, cmd)
	case ContextPanel:
		m.contextPanel.focused = true
		newContext, cmd := m.contextPanel.Update(msg)
		m.contextPanel = newContext
		cmds = append(cmds, cmd)
	}
	
	// Update focus manager
	focusManager, focusCmd := m.focusManager.Update(msg)
	m.focusManager = focusManager.(*FocusManager)
	cmds = append(cmds, focusCmd)

	m.lastUpdate = time.Now()
	return m, tea.Batch(cmds...)
}

// View renders the application
func (m AIAssistantModel) View() string {
	if !m.ready {
		return m.renderLoadingScreen()
	}

	// Calculate panel dimensions
	sidebarWidth := 0
	if m.layout.ShowSidebar {
		sidebarWidth = m.layout.SidebarWidth
	}

	mainAreaWidth := m.width - sidebarWidth
	editorWidth := int(float64(mainAreaWidth) * m.layout.EditorRatio)
	chatWidth := mainAreaWidth - editorWidth

	// Render panels
	var sidebar string
	if m.layout.ShowSidebar {
		sidebar = m.renderSidebar(sidebarWidth, m.height-2) // -2 for header and status
	}

	editor := m.renderEditor(editorWidth, m.height-2)
	chat := m.renderChat(chatWidth, m.height-2)

	// Compose layout
	mainArea := lipgloss.JoinHorizontal(
		lipgloss.Top,
		editor,
		m.renderVerticalDivider(m.height-2),
		chat,
	)

	var content string
	if m.layout.ShowSidebar {
		content = lipgloss.JoinHorizontal(
			lipgloss.Top,
			sidebar,
			m.renderVerticalDivider(m.height-2),
			mainArea,
		)
	} else {
		content = mainArea
	}

	// Add header and status bar
	return lipgloss.JoinVertical(
		lipgloss.Left,
		m.renderHeader(),
		content,
		m.renderStatusBar(),
	)
}

// Helper methods for panel management

func (m AIAssistantModel) resizeAllPanels() AIAssistantModel {
	// Update all panel sizes based on new dimensions
	m.fileExplorer = m.fileExplorer.Resize(m.layout.SidebarWidth, m.height-2)
	m.codeEditor = m.codeEditor.Resize(int(float64(m.width-m.layout.SidebarWidth)*m.layout.EditorRatio), m.height-2)
	m.chatPanel = m.chatPanel.Resize(int(float64(m.width-m.layout.SidebarWidth)*m.layout.ChatRatio), m.height-2)
	m.contextPanel = m.contextPanel.Resize(m.layout.SidebarWidth, m.height-2)
	return m
}

// Message types for communication
type ConnectionEstablishedMsg struct{}
type ConnectionLostMsg struct{}
type AIResponseMsg struct {
	Response types.AIResponse
}
type FileSelectedMsg struct {
	Path string
}
type EventStreamMsg struct {
	Type      string
	Payload   interface{}
	Timestamp time.Time
}
type RPCResponseMsg struct {
	Method   string
	Response interface{}
	Error    error
}