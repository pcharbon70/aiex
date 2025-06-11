package ui

import (
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
		input:   "",
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
			
		case "enter":
			if m.input != "" {
				// Send message
				m.messages = append(m.messages, "")
				m.messages = append(m.messages, "💬 You: "+m.input)
				
				// Generate AI response
				response := m.generateAIResponse(m.input)
				m.messages = append(m.messages, "🤖 AI: "+response)
				m.messages = append(m.messages, "")
				
				m.input = ""
				return m, nil
			}
			return m, nil
			
		case "backspace":
			if len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
			}
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
	// Calculate chat dimensions - use full width and height minus space for input and header
	chatHeight := m.height - 6 // Reserve space for header, input area, and borders
	
	// Styles
	chatStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62")).
		Padding(1)
	
	titleStyle := lipgloss.NewStyle().
		Background(lipgloss.Color("62")).
		Foreground(lipgloss.Color("230")).
		Padding(0, 1).
		Bold(true).
		Width(m.width - 4) // Account for border padding
	
	inputStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("240")).
		Padding(0, 1)
	
	// Header
	header := titleStyle.Render("🤖 Aiex AI Assistant - Interactive Chat")
	
	// Limit messages to fit in chat area
	displayMessages := m.messages
	if len(displayMessages) > chatHeight {
		displayMessages = displayMessages[len(displayMessages)-chatHeight:]
	}
	
	// Chat content
	chatContent := strings.Join(displayMessages, "\n")
	
	chatPanel := chatStyle.
		Width(m.width - 2).
		Height(chatHeight).
		Render(chatContent)
	
	// Input area
	inputContent := "💬 Type your message: " + m.input + "█"
	inputPanel := inputStyle.
		Width(m.width - 2).
		Render(inputContent)
	
	// Status/help bar
	statusBar := lipgloss.NewStyle().
		Background(lipgloss.Color("240")).
		Foreground(lipgloss.Color("15")).
		Width(m.width).
		Align(lipgloss.Center).
		Render("Enter: send message | Ctrl+C/q: quit")
	
	// Combine everything vertically
	return lipgloss.JoinVertical(
		lipgloss.Left,
		header,
		"",
		chatPanel,
		"",
		inputPanel,
		statusBar,
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