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
	
	// Chat functionality
	messages []string
	input    string
	
	// Status information
	connected    bool
	provider     string
	messageCount int
	lastActivity string
	
	// RPC client
	client   *rpc.Client
}

// NewApp creates a new application instance
func NewApp(client *rpc.Client) *SimpleApp {
	return &SimpleApp{
		width:   80,
		height:  24,
		messages: []string{
			"🤖 Welcome to Aiex AI Assistant!",
			"",
			"I'm here to help you with coding, explanations, and analysis.",
			"Type your message below and press Enter to chat with me.",
			"",
			"Try asking me about:",
			"• Code explanations and reviews",
			"• Programming concepts and best practices", 
			"• Debugging help and suggestions",
			"• Architecture and design patterns",
		},
		input:        "",
		connected:    true,  // Assume connected initially
		provider:     "Mock AI",
		messageCount: 0,
		lastActivity: "Just started",
		client:       client,
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
			
		case "enter":
			if m.input != "" {
				// Check for special commands
				if strings.HasPrefix(m.input, "/") {
					return m.handleCommand(m.input), nil
				}
				
				// Send message
				m.messages = append(m.messages, "")
				m.messages = append(m.messages, "💬 You: "+m.input)
				
				// Generate AI response
				response := m.generateAIResponse(m.input)
				m.messages = append(m.messages, "🤖 AI: "+response)
				m.messages = append(m.messages, "")
				
				// Update status
				m.messageCount++
				m.lastActivity = "Message sent"
				
				m.input = ""
				return m, nil
			}
			return m, nil
			
		case "backspace":
			if len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
			}
			return m, nil
			
		case "esc":
			// Clear input
			m.input = ""
			m.lastActivity = "Input cleared"
			return m, nil
			
		default:
			// Add character to input
			if len(msg.String()) == 1 {
				m.input += msg.String()
			}
			return m, nil
		}
	}
	return m, nil
}

func (m *SimpleApp) View() string {
	// Calculate dimensions - reserve space for status bars
	chatHeight := m.height - 8 // Top status + bottom status + input + borders
	
	// Define styles
	topStatusStyle := lipgloss.NewStyle().
		Background(lipgloss.Color("62")).
		Foreground(lipgloss.Color("230")).
		Bold(true).
		Width(m.width).
		Padding(0, 1)
	
	bottomStatusStyle := lipgloss.NewStyle().
		Background(lipgloss.Color("240")).
		Foreground(lipgloss.Color("15")).
		Width(m.width).
		Padding(0, 1)
	
	chatStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62")).
		Padding(1)
	
	inputStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("240")).
		Padding(0, 1)
	
	// Build top status bar with multiple sections
	connectionStatus := "🔌 Disconnected"
	connectionColor := "196" // Red
	if m.connected {
		connectionStatus = "🟢 Connected"
		connectionColor = "46" // Green
	}
	
	connectionIndicator := lipgloss.NewStyle().
		Foreground(lipgloss.Color(connectionColor)).
		Render(connectionStatus)
	
	// Create status sections
	leftStatus := lipgloss.NewStyle().
		Width(m.width / 3).
		Align(lipgloss.Left).
		Render("🤖 Aiex AI Assistant")
	
	centerStatus := lipgloss.NewStyle().
		Width(m.width / 3).
		Align(lipgloss.Center).
		Render(connectionIndicator + " • " + m.provider)
	
	rightStatus := lipgloss.NewStyle().
		Width(m.width / 3).
		Align(lipgloss.Right).
		Render("💬 " + fmt.Sprintf("%d messages", m.messageCount))
	
	// Combine top status sections
	topBar := topStatusStyle.Render(
		lipgloss.JoinHorizontal(lipgloss.Top, leftStatus, centerStatus, rightStatus),
	)
	
	// Limit messages to fit in chat area
	displayMessages := m.messages
	if len(displayMessages) > chatHeight-2 {
		displayMessages = displayMessages[len(displayMessages)-(chatHeight-2):]
	}
	
	// Chat content
	chatContent := strings.Join(displayMessages, "\n")
	chatPanel := chatStyle.
		Width(m.width - 2).
		Height(chatHeight).
		Render(chatContent)
	
	// Input area with character count
	charCount := len(m.input)
	inputPrompt := "💬 Type your message"
	if charCount > 0 {
		inputPrompt += fmt.Sprintf(" (%d chars)", charCount)
	}
	inputContent := inputPrompt + ": " + m.input + "█"
	inputPanel := inputStyle.
		Width(m.width - 2).
		Render(inputContent)
	
	// Build bottom status bar
	leftBottom := lipgloss.NewStyle().
		Width(m.width / 3).
		Align(lipgloss.Left).
		Render("📊 " + m.lastActivity)
	
	centerBottom := lipgloss.NewStyle().
		Width(m.width / 3).
		Align(lipgloss.Center).
		Render("Press /help for commands")
	
	rightBottom := lipgloss.NewStyle().
		Width(m.width / 3).
		Align(lipgloss.Right).
		Render("ESC: clear • Ctrl+C: quit")
	
	bottomBar := bottomStatusStyle.Render(
		lipgloss.JoinHorizontal(lipgloss.Top, leftBottom, centerBottom, rightBottom),
	)
	
	// Combine all elements
	return lipgloss.JoinVertical(
		lipgloss.Left,
		topBar,
		chatPanel,
		inputPanel,
		bottomBar,
	)
}

// generateAIResponse creates a simulated AI response
func (m *SimpleApp) generateAIResponse(input string) string {
	// This is a simplified response generator
	// In a real implementation, this would call the RPC client to get AI responses
	
	responses := []string{
		"That's an interesting question! Let me help you with that.",
		"I understand what you're asking. Here's my take on it...",
		"Great question! This is a common topic in software development.",
		"I'd be happy to explain that concept to you.",
		"That's a good observation. Let me break it down for you.",
		"I can definitely help you with that problem.",
		"This is a fascinating area of programming. Here's what I think...",
		"Let me analyze that for you and provide some insights.",
	}
	
	// Simple response selection based on input length
	idx := len(input) % len(responses)
	baseResponse := responses[idx]
	
	// Add some context based on keywords
	lowerInput := strings.ToLower(input)
	if strings.Contains(lowerInput, "code") || strings.Contains(lowerInput, "program") {
		return baseResponse + " When it comes to coding, it's important to write clean, maintainable code that follows best practices."
	} else if strings.Contains(lowerInput, "debug") || strings.Contains(lowerInput, "error") {
		return baseResponse + " Debugging is a crucial skill. I recommend using systematic approaches like logging and step-by-step analysis."
	} else if strings.Contains(lowerInput, "design") || strings.Contains(lowerInput, "architecture") {
		return baseResponse + " Good software design involves considering scalability, maintainability, and separation of concerns."
	} else if strings.Contains(lowerInput, "help") || strings.Contains(lowerInput, "how") {
		return baseResponse + " I'm here to assist you with any programming questions or challenges you might have."
	}
	
	return baseResponse + " Feel free to ask me more specific questions, and I'll do my best to provide helpful guidance!"
}

// handleCommand processes special slash commands
func (m *SimpleApp) handleCommand(cmd string) *SimpleApp {
	m.messages = append(m.messages, "")
	m.messages = append(m.messages, "💬 You: "+cmd)
	
	switch strings.ToLower(strings.TrimSpace(cmd)) {
	case "/status", "/health":
		m.messages = append(m.messages, "🔍 Checking LLM connection status...")
		// In a real implementation, this would call:
		// - Aiex.LLM.ModelCoordinator.get_cluster_status()
		// - Aiex.LLM.ModelCoordinator.force_health_check()
		m.messages = append(m.messages, "✅ Connection Status:")
		m.messages = append(m.messages, "• Backend: Connected to ws://localhost:4000/ws")
		m.messages = append(m.messages, "• LLM Providers: Mock mode (no real LLM configured)")
		m.messages = append(m.messages, "• Health: Simulated responses active")
		m.lastActivity = "Status checked"
		
	case "/providers":
		m.messages = append(m.messages, "📋 Available LLM Providers:")
		m.messages = append(m.messages, "• OpenAI - Not configured")
		m.messages = append(m.messages, "• Anthropic - Not configured")
		m.messages = append(m.messages, "• Ollama - Not configured")
		m.messages = append(m.messages, "• LM Studio - Not configured")
		m.messages = append(m.messages, "ℹ️  Currently using mock responses")
		
	case "/help":
		m.messages = append(m.messages, "📚 Available Commands:")
		m.messages = append(m.messages, "• /status or /health - Check LLM connection status")
		m.messages = append(m.messages, "• /providers - List available LLM providers")
		m.messages = append(m.messages, "• /help - Show this help message")
		m.messages = append(m.messages, "• /clear - Clear chat history")
		
	case "/clear":
		m.messages = []string{
			"🤖 Welcome to Aiex AI Assistant!",
			"",
			"Chat history cleared. How can I help you today?",
		}
		
	default:
		m.messages = append(m.messages, "❓ Unknown command. Type /help for available commands.")
	}
	
	m.messages = append(m.messages, "")
	m.input = ""
	return m
}