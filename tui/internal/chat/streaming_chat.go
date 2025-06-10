package chat

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"

	"aiex-tui/internal/events"
	"aiex-tui/internal/rpc"
	"aiex-tui/pkg/types"
)

// StreamingChatPanel provides real-time chat interface with AI streaming
type StreamingChatPanel struct {
	// Core components
	width         int
	height        int
	focused       bool

	// Chat components
	messageView   viewport.Model
	inputArea     textarea.Model
	conversationManager *ConversationManager
	streamingEngine     *StreamingEngine

	// State
	conversations    map[string]*Conversation
	activeConversation string
	messages         []types.Message
	currentInput     string

	// AI Integration
	aiProviders      map[string]*AIProvider
	activeProvider   string
	providerSelector *ProviderSelector

	// Real-time features
	typingIndicator  *TypingIndicator
	presenceManager  *PresenceManager
	messageComposer  *MessageComposer

	// Communication
	rpcClient       *rpc.Client
	eventStream     *events.EventStreamManager
	stateManager    *events.DistributedStateManager

	// Configuration
	config          ChatConfig

	// Synchronization
	mutex           sync.RWMutex
}

// ChatConfig configures the chat panel
type ChatConfig struct {
	EnableStreaming          bool          `json:"enable_streaming"`
	EnableTypingIndicators   bool          `json:"enable_typing_indicators"`
	EnableMessageThreading   bool          `json:"enable_message_threading"`
	EnableMultiProvider      bool          `json:"enable_multi_provider"`
	MaxMessageHistory        int           `json:"max_message_history"`
	StreamingTimeout         time.Duration `json:"streaming_timeout"`
	TypingTimeout           time.Duration `json:"typing_timeout"`
	AutoSaveInterval        time.Duration `json:"auto_save_interval"`
	EnableMarkdownRendering  bool          `json:"enable_markdown_rendering"`
	EnableCodeHighlighting   bool          `json:"enable_code_highlighting"`
	EnableMentions          bool          `json:"enable_mentions"`
	EnableEmojis            bool          `json:"enable_emojis"`
}

// Conversation represents a chat conversation
type Conversation struct {
	ID          string            `json:"id"`
	Title       string            `json:"title"`
	Provider    string            `json:"provider"`
	Messages    []types.Message   `json:"messages"`
	Metadata    map[string]interface{} `json:"metadata"`
	CreatedAt   time.Time         `json:"created_at"`
	UpdatedAt   time.Time         `json:"updated_at"`
	Active      bool              `json:"active"`
	Threads     map[string]*MessageThread `json:"threads,omitempty"`
}

// MessageThread represents a threaded conversation
type MessageThread struct {
	ID        string            `json:"id"`
	ParentID  string            `json:"parent_id"`
	Messages  []types.Message   `json:"messages"`
	Active    bool              `json:"active"`
	CreatedAt time.Time         `json:"created_at"`
}

// AIProvider represents an AI service provider
type AIProvider struct {
	ID          string                 `json:"id"`
	Name        string                 `json:"name"`
	Type        string                 `json:"type"` // openai, anthropic, ollama, etc.
	Endpoint    string                 `json:"endpoint"`
	Model       string                 `json:"model"`
	Config      map[string]interface{} `json:"config"`
	Capabilities []string              `json:"capabilities"`
	Status      ProviderStatus         `json:"status"`
	LastUsed    time.Time             `json:"last_used"`
	UsageStats  ProviderStats         `json:"usage_stats"`
}

// ProviderStatus represents provider status
type ProviderStatus int

const (
	ProviderStatusUnknown ProviderStatus = iota
	ProviderStatusActive
	ProviderStatusBusy
	ProviderStatusError
	ProviderStatusOffline
)

// ProviderStats tracks provider usage statistics
type ProviderStats struct {
	MessagesProcessed int           `json:"messages_processed"`
	TokensUsed       int           `json:"tokens_used"`
	AverageLatency   time.Duration `json:"average_latency"`
	ErrorCount       int           `json:"error_count"`
	LastError        string        `json:"last_error,omitempty"`
}

// StreamingMessage represents a message being streamed
type StreamingMessage struct {
	ID          string                 `json:"id"`
	ConversationID string              `json:"conversation_id"`
	Provider    string                 `json:"provider"`
	Content     string                 `json:"content"`
	Delta       string                 `json:"delta"`
	Complete    bool                   `json:"complete"`
	Metadata    map[string]interface{} `json:"metadata"`
	Timestamp   time.Time              `json:"timestamp"`
	Error       string                 `json:"error,omitempty"`
}

// NewStreamingChatPanel creates a new streaming chat panel
func NewStreamingChatPanel(width, height int, rpcClient *rpc.Client, eventStream *events.EventStreamManager, stateManager *events.DistributedStateManager) *StreamingChatPanel {
	config := ChatConfig{
		EnableStreaming:          true,
		EnableTypingIndicators:   true,
		EnableMessageThreading:   true,
		EnableMultiProvider:      true,
		MaxMessageHistory:        1000,
		StreamingTimeout:         30 * time.Second,
		TypingTimeout:           3 * time.Second,
		AutoSaveInterval:        10 * time.Second,
		EnableMarkdownRendering:  true,
		EnableCodeHighlighting:   true,
		EnableMentions:          true,
		EnableEmojis:            true,
	}

	// Initialize viewport for messages
	messageView := viewport.New(width-2, height-6)
	messageView.SetContent("Welcome to AI Chat! Start a conversation...")

	// Initialize textarea for input
	inputArea := textarea.New()
	inputArea.SetWidth(width - 2)
	inputArea.SetHeight(3)
	inputArea.Placeholder = "Type your message..."
	inputArea.Focus()

	scp := &StreamingChatPanel{
		width:               width,
		height:              height,
		focused:             true,
		messageView:         messageView,
		inputArea:           inputArea,
		conversations:       make(map[string]*Conversation),
		messages:            make([]types.Message, 0),
		aiProviders:         make(map[string]*AIProvider),
		rpcClient:           rpcClient,
		eventStream:         eventStream,
		stateManager:        stateManager,
		config:              config,
	}

	// Initialize components
	scp.conversationManager = NewConversationManager(scp)
	scp.streamingEngine = NewStreamingEngine(rpcClient, eventStream)
	scp.typingIndicator = NewTypingIndicator()
	scp.presenceManager = NewPresenceManager()
	scp.messageComposer = NewMessageComposer(config)
	scp.providerSelector = NewProviderSelector()

	// Load default providers
	scp.loadDefaultProviders()

	// Create default conversation
	scp.createDefaultConversation()

	return scp
}

// Update handles chat panel updates
func (scp *StreamingChatPanel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if !scp.focused {
		return scp, nil
	}

	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		cmd := scp.handleKeyPress(msg)
		if cmd != nil {
			cmds = append(cmds, cmd)
		}

	case tea.WindowSizeMsg:
		scp.updateSize(msg.Width, msg.Height)

	case StreamingMessageMsg:
		scp.handleStreamingMessage(msg)
		cmds = append(cmds, scp.updateMessageDisplay())

	case ConversationSwitchedMsg:
		scp.switchConversation(msg.ConversationID)
		cmds = append(cmds, scp.updateMessageDisplay())

	case ProviderChangedMsg:
		scp.switchProvider(msg.ProviderID)

	case TypingIndicatorMsg:
		scp.typingIndicator.Update(msg)
		cmds = append(cmds, scp.updateMessageDisplay())

	case PresenceUpdateMsg:
		scp.presenceManager.Update(msg)
	}

	// Update child components
	var cmd tea.Cmd
	scp.messageView, cmd = scp.messageView.Update(msg)
	if cmd != nil {
		cmds = append(cmds, cmd)
	}

	scp.inputArea, cmd = scp.inputArea.Update(msg)
	if cmd != nil {
		cmds = append(cmds, cmd)
	}

	return scp, tea.Batch(cmds...)
}

// View renders the chat panel
func (scp *StreamingChatPanel) View() string {
	if scp.width == 0 || scp.height == 0 {
		return ""
	}

	scp.mutex.RLock()
	defer scp.mutex.RUnlock()

	// Build the chat interface
	var sections []string

	// Header with provider and conversation info
	header := scp.renderHeader()
	sections = append(sections, header)

	// Message area
	messageArea := scp.renderMessageArea()
	sections = append(sections, messageArea)

	// Typing indicators
	if scp.config.EnableTypingIndicators {
		typingArea := scp.renderTypingIndicators()
		if typingArea != "" {
			sections = append(sections, typingArea)
		}
	}

	// Input area
	inputArea := scp.renderInputArea()
	sections = append(sections, inputArea)

	// Status bar
	statusBar := scp.renderStatusBar()
	sections = append(sections, statusBar)

	content := strings.Join(sections, "\n")

	return scp.applyChatPanelStyle(content)
}

// Message sending and receiving
func (scp *StreamingChatPanel) SendMessage(content string) tea.Cmd {
	return func() tea.Msg {
		scp.mutex.Lock()
		defer scp.mutex.Unlock()

		// Create user message
		userMessage := types.Message{
			ID:             generateMessageID(),
			ConversationID: scp.activeConversation,
			Role:           "user",
			Content:        content,
			Timestamp:      time.Now(),
			Metadata:       make(map[string]interface{}),
		}

		// Add to conversation
		scp.addMessageToConversation(userMessage)

		// Clear input
		scp.currentInput = ""
		scp.inputArea.SetValue("")

		// Send to AI provider
		if scp.config.EnableStreaming {
			return scp.streamingEngine.SendStreamingMessage(userMessage, scp.activeProvider)
		} else {
			return scp.sendRegularMessage(userMessage)
		}
	}
}

// Internal rendering methods
func (scp *StreamingChatPanel) renderHeader() string {
	providerName := "No Provider"
	conversationTitle := "No Conversation"

	if provider, exists := scp.aiProviders[scp.activeProvider]; exists {
		providerName = provider.Name
	}

	if conv, exists := scp.conversations[scp.activeConversation]; exists {
		conversationTitle = conv.Title
	}

	headerText := fmt.Sprintf("🤖 %s | 💬 %s", providerName, conversationTitle)

	// Add status indicators
	statusIndicators := scp.getStatusIndicators()
	if statusIndicators != "" {
		headerText += " | " + statusIndicators
	}

	return lipgloss.NewStyle().
		Foreground(lipgloss.Color("63")).
		Bold(true).
		Padding(0, 1).
		Render(headerText)
}

func (scp *StreamingChatPanel) renderMessageArea() string {
	messageContent := scp.formatMessages()
	scp.messageView.SetContent(messageContent)
	return scp.messageView.View()
}

func (scp *StreamingChatPanel) renderTypingIndicators() string {
	if !scp.typingIndicator.HasActiveIndicators() {
		return ""
	}

	indicators := scp.typingIndicator.Render()
	return lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Italic(true).
		Padding(0, 1).
		Render(indicators)
}

func (scp *StreamingChatPanel) renderInputArea() string {
	// Add input hints
	hints := scp.getInputHints()
	inputWithHints := scp.inputArea.View()

	if hints != "" {
		inputWithHints += "\n" + hints
	}

	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("63")).
		Padding(0, 1).
		Render(inputWithHints)
}

func (scp *StreamingChatPanel) renderStatusBar() string {
	var statusParts []string

	// Message count
	messageCount := len(scp.messages)
	statusparts := append(statusParts, fmt.Sprintf("Messages: %d", messageCount))

	// Active users
	activeUsers := scp.presenceManager.GetActiveUserCount()
	if activeUsers > 1 {
		statusparts = append(statusParts, fmt.Sprintf("Users: %d", activeUsers))
	}

	// Provider status
	if provider, exists := scp.aiProviders[scp.activeProvider]; exists {
		statusText := scp.getProviderStatusText(provider.Status)
		statusparts = append(statusParts, fmt.Sprintf("Provider: %s", statusText))
	}

	statusText := strings.Join(statusParts, " | ")

	return lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Render(statusText)
}

// Helper methods
func (scp *StreamingChatPanel) handleKeyPress(msg tea.KeyMsg) tea.Cmd {
	switch msg.String() {
	case "enter":
		if !msg.Alt {
			// Send message
			content := strings.TrimSpace(scp.inputArea.Value())
			if content != "" {
				return scp.SendMessage(content)
			}
		}
		// Alt+Enter for new line (handled by textarea)

	case "ctrl+n":
		// New conversation
		return scp.createNewConversation()

	case "ctrl+p":
		// Switch provider
		return scp.showProviderSelector()

	case "ctrl+t":
		// Switch conversation
		return scp.showConversationSelector()

	case "ctrl+s":
		// Save conversation
		return scp.saveCurrentConversation()

	case "esc":
		// Clear input or exit
		if scp.inputArea.Value() != "" {
			scp.inputArea.SetValue("")
		} else {
			scp.focused = false
		}
	}

	return nil
}

func (scp *StreamingChatPanel) updateSize(width, height int) {
	scp.width = width
	scp.height = height

	// Update child components
	scp.messageView.Width = width - 2
	scp.messageView.Height = height - 8 // Reserve space for header, input, status

	scp.inputArea.SetWidth(width - 4)
}

func (scp *StreamingChatPanel) handleStreamingMessage(msg StreamingMessageMsg) {
	// Find or create the streaming message
	if msg.Complete {
		// Finalize the message
		finalMessage := types.Message{
			ID:             msg.ID,
			ConversationID: msg.ConversationID,
			Role:           "assistant",
			Content:        msg.Content,
			Timestamp:      msg.Timestamp,
			Metadata:       msg.Metadata,
		}
		scp.addMessageToConversation(finalMessage)
	} else {
		// Update streaming content
		scp.updateStreamingContent(msg.ID, msg.Content)
	}
}

func (scp *StreamingChatPanel) switchConversation(conversationID string) {
	scp.mutex.Lock()
	defer scp.mutex.Unlock()

	if conv, exists := scp.conversations[conversationID]; exists {
		scp.activeConversation = conversationID
		scp.messages = conv.Messages
		conv.UpdatedAt = time.Now()
	}
}

func (scp *StreamingChatPanel) switchProvider(providerID string) {
	scp.mutex.Lock()
	defer scp.mutex.Unlock()

	if _, exists := scp.aiProviders[providerID]; exists {
		scp.activeProvider = providerID
	}
}

// Placeholder implementations
func (scp *StreamingChatPanel) loadDefaultProviders() {
	// Load default AI providers
	defaultProviders := []*AIProvider{
		{
			ID:   "anthropic",
			Name: "Claude (Anthropic)",
			Type: "anthropic",
			Status: ProviderStatusActive,
		},
		{
			ID:   "openai",
			Name: "GPT (OpenAI)",
			Type: "openai",
			Status: ProviderStatusActive,
		},
	}

	for _, provider := range defaultProviders {
		scp.aiProviders[provider.ID] = provider
	}

	if len(defaultProviders) > 0 {
		scp.activeProvider = defaultProviders[0].ID
	}
}

func (scp *StreamingChatPanel) createDefaultConversation() {
	conv := &Conversation{
		ID:       generateConversationID(),
		Title:    "New Conversation",
		Provider: scp.activeProvider,
		Messages: make([]types.Message, 0),
		Metadata: make(map[string]interface{}),
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
		Active:   true,
	}

	scp.conversations[conv.ID] = conv
	scp.activeConversation = conv.ID
}

// Message formatting and display
func (scp *StreamingChatPanel) formatMessages() string {
	var formatted []string

	for _, message := range scp.messages {
		formattedMsg := scp.formatSingleMessage(message)
		formatted = append(formatted, formattedMsg)
	}

	return strings.Join(formatted, "\n\n")
}

func (scp *StreamingChatPanel) formatSingleMessage(message types.Message) string {
	// Format timestamp
	timestamp := message.Timestamp.Format("15:04")

	// Format role
	roleIcon := "👤"
	if message.Role == "assistant" {
		roleIcon = "🤖"
	}

	// Format content with syntax highlighting if enabled
	content := message.Content
	if scp.config.EnableMarkdownRendering {
		content = scp.renderMarkdown(content)
	}

	header := fmt.Sprintf("%s %s [%s]", roleIcon, strings.Title(message.Role), timestamp)

	return fmt.Sprintf("%s\n%s", header, content)
}

func (scp *StreamingChatPanel) renderMarkdown(content string) string {
	// Simple markdown rendering (code blocks, emphasis)
	// In a real implementation, use a proper markdown renderer
	return content
}

// Utility functions
func (scp *StreamingChatPanel) addMessageToConversation(message types.Message) {
	if conv, exists := scp.conversations[scp.activeConversation]; exists {
		conv.Messages = append(conv.Messages, message)
		conv.UpdatedAt = time.Now()
		
		// Update local messages if this is the active conversation
		if scp.activeConversation == conv.ID {
			scp.messages = conv.Messages
		}
		
		// Limit message history
		if len(conv.Messages) > scp.config.MaxMessageHistory {
			conv.Messages = conv.Messages[len(conv.Messages)-scp.config.MaxMessageHistory:]
		}
	}
}

func (scp *StreamingChatPanel) updateStreamingContent(messageID, content string) {
	// Update the streaming message content in the display
	// This is a simplified implementation
}

func (scp *StreamingChatPanel) updateMessageDisplay() tea.Cmd {
	return func() tea.Msg {
		return MessageDisplayUpdateMsg{}
	}
}

func (scp *StreamingChatPanel) getStatusIndicators() string {
	var indicators []string
	
	if scp.streamingEngine != nil && scp.streamingEngine.IsStreaming() {
		indicators = append(indicators, "🔄 Streaming")
	}
	
	if scp.typingIndicator.HasActiveIndicators() {
		indicators = append(indicators, "✍️ Typing")
	}
	
	return strings.Join(indicators, " ")
}

func (scp *StreamingChatPanel) getInputHints() string {
	hints := []string{}
	
	if scp.config.EnableMentions {
		hints = append(hints, "@mention")
	}
	
	if len(hints) > 0 {
		return "💡 " + strings.Join(hints, ", ")
	}
	
	return ""
}

func (scp *StreamingChatPanel) getProviderStatusText(status ProviderStatus) string {
	switch status {
	case ProviderStatusActive:
		return "🟢 Active"
	case ProviderStatusBusy:
		return "🟡 Busy"
	case ProviderStatusError:
		return "🔴 Error"
	case ProviderStatusOffline:
		return "⚫ Offline"
	default:
		return "❔ Unknown"
	}
}

func (scp *StreamingChatPanel) applyChatPanelStyle(content string) string {
	style := lipgloss.NewStyle().
		Width(scp.width).
		Height(scp.height)

	if scp.focused {
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

// Command generators
func (scp *StreamingChatPanel) createNewConversation() tea.Cmd {
	return func() tea.Msg {
		conv := &Conversation{
			ID:       generateConversationID(),
			Title:    "New Conversation",
			Provider: scp.activeProvider,
			Messages: make([]types.Message, 0),
			Metadata: make(map[string]interface{}),
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
			Active:   true,
		}
		
		scp.conversations[conv.ID] = conv
		return ConversationSwitchedMsg{ConversationID: conv.ID}
	}
}

func (scp *StreamingChatPanel) showProviderSelector() tea.Cmd {
	return func() tea.Msg {
		return ShowProviderSelectorMsg{}
	}
}

func (scp *StreamingChatPanel) showConversationSelector() tea.Cmd {
	return func() tea.Msg {
		return ShowConversationSelectorMsg{}
	}
}

func (scp *StreamingChatPanel) saveCurrentConversation() tea.Cmd {
	return func() tea.Msg {
		return ConversationSavedMsg{ConversationID: scp.activeConversation}
	}
}

func (scp *StreamingChatPanel) sendRegularMessage(message types.Message) tea.Msg {
	// Implementation for non-streaming message sending
	return MessageSentMsg{Message: message}
}

// Utility functions
func generateMessageID() string {
	return fmt.Sprintf("msg_%d", time.Now().UnixNano())
}

func generateConversationID() string {
	return fmt.Sprintf("conv_%d", time.Now().UnixNano())
}

// Message types for tea.Cmd
type StreamingMessageMsg struct {
	ID             string
	ConversationID string
	Content        string
	Delta          string
	Complete       bool
	Timestamp      time.Time
	Metadata       map[string]interface{}
}

type ConversationSwitchedMsg struct {
	ConversationID string
}

type ProviderChangedMsg struct {
	ProviderID string
}

type TypingIndicatorMsg struct {
	UserID string
	Active bool
}

type PresenceUpdateMsg struct {
	UserID   string
	Presence string
}

type MessageDisplayUpdateMsg struct{}

type ShowProviderSelectorMsg struct{}

type ShowConversationSelectorMsg struct{}

type ConversationSavedMsg struct {
	ConversationID string
}

type MessageSentMsg struct {
	Message types.Message
}

// Focus management
func (scp *StreamingChatPanel) Focus() {
	scp.focused = true
	scp.inputArea.Focus()
}

func (scp *StreamingChatPanel) Blur() {
	scp.focused = false
	scp.inputArea.Blur()
}

func (scp *StreamingChatPanel) Focused() bool {
	return scp.focused
}

// Resize handling
func (scp *StreamingChatPanel) SetSize(width, height int) {
	scp.updateSize(width, height)
}
