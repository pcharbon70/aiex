package chat

import (
	"fmt"
	"strings"
	"sync"
	"time"
)

// TypingIndicator manages typing indicators for real-time feedback
type TypingIndicator struct {
	// Active typing users
	typingUsers map[string]*TypingState

	// Configuration
	timeout     time.Duration
	maxUsers    int
	animation   *TypingAnimation

	// Synchronization
	mutex       sync.RWMutex
}

// TypingState represents a user's typing state
type TypingState struct {
	UserID      string    `json:"user_id"`
	UserName    string    `json:"user_name"`
	StartTime   time.Time `json:"start_time"`
	LastUpdate  time.Time `json:"last_update"`
	Active      bool      `json:"active"`
}

// TypingAnimation handles typing indicator animation
type TypingAnimation struct {
	frames      []string
	currentFrame int
	lastUpdate   time.Time
	frameDelay   time.Duration
}

// PresenceManager manages user presence and status
type PresenceManager struct {
	// Active users
	activeUsers map[string]*UserPresence

	// Configuration
	heartbeatInterval time.Duration
	offlineTimeout    time.Duration

	// Synchronization
	mutex             sync.RWMutex
}

// UserPresence represents a user's presence status
type UserPresence struct {
	UserID       string          `json:"user_id"`
	UserName     string          `json:"user_name"`
	Status       PresenceStatus  `json:"status"`
	LastSeen     time.Time       `json:"last_seen"`
	CustomStatus string          `json:"custom_status,omitempty"`
	Metadata     map[string]interface{} `json:"metadata,omitempty"`
}

// PresenceStatus represents user presence status
type PresenceStatus int

const (
	PresenceStatusOffline PresenceStatus = iota
	PresenceStatusOnline
	PresenceStatusAway
	PresenceStatusBusy
	PresenceStatusInvisible
)

// MessageComposer handles message composition with advanced features
type MessageComposer struct {
	// Composition state
	currentMessage string
	cursorPosition int
	selectionStart int
	selectionEnd   int

	// Features
	mentions       []Mention
	emojiSuggestions []EmojiSuggestion
	commandSuggestions []CommandSuggestion

	// Configuration
	config         MessageComposerConfig

	// Synchronization
	mutex          sync.RWMutex
}

// MessageComposerConfig configures the message composer
type MessageComposerConfig struct {
	EnableMentions     bool `json:"enable_mentions"`
	EnableEmojis       bool `json:"enable_emojis"`
	EnableCommands     bool `json:"enable_commands"`
	EnableAutoComplete bool `json:"enable_auto_complete"`
	MaxMessageLength   int  `json:"max_message_length"`
}

// Mention represents a user mention in a message
type Mention struct {
	UserID    string `json:"user_id"`
	UserName  string `json:"user_name"`
	StartPos  int    `json:"start_pos"`
	EndPos    int    `json:"end_pos"`
	Text      string `json:"text"`
}

// EmojiSuggestion represents an emoji suggestion
type EmojiSuggestion struct {
	Emoji       string   `json:"emoji"`
	Name        string   `json:"name"`
	Keywords    []string `json:"keywords"`
	Category    string   `json:"category"`
}

// CommandSuggestion represents a command suggestion
type CommandSuggestion struct {
	Command     string `json:"command"`
	Description string `json:"description"`
	Usage       string `json:"usage"`
	Category    string `json:"category"`
}

// ProviderSelector manages AI provider selection
type ProviderSelector struct {
	// Available providers
	providers      []*AIProvider
	selectedIndex  int
	visible        bool

	// Configuration
	config         ProviderSelectorConfig

	// Synchronization
	mutex          sync.RWMutex
}

// ProviderSelectorConfig configures the provider selector
type ProviderSelectorConfig struct {
	MaxVisible        int  `json:"max_visible"`
	ShowCapabilities  bool `json:"show_capabilities"`
	ShowStatus        bool `json:"show_status"`
	ShowStats         bool `json:"show_stats"`
}

// NewTypingIndicator creates a new typing indicator
func NewTypingIndicator() *TypingIndicator {
	return &TypingIndicator{
		typingUsers: make(map[string]*TypingState),
		timeout:     3 * time.Second,
		maxUsers:    3,
		animation:   NewTypingAnimation(),
	}
}

// StartTyping starts typing indicator for a user
func (ti *TypingIndicator) StartTyping(userID, userName string) {
	ti.mutex.Lock()
	defer ti.mutex.Unlock()

	now := time.Now()
	if state, exists := ti.typingUsers[userID]; exists {
		state.LastUpdate = now
		state.Active = true
	} else {
		ti.typingUsers[userID] = &TypingState{
			UserID:     userID,
			UserName:   userName,
			StartTime:  now,
			LastUpdate: now,
			Active:     true,
		}
	}
}

// StopTyping stops typing indicator for a user
func (ti *TypingIndicator) StopTyping(userID string) {
	ti.mutex.Lock()
	defer ti.mutex.Unlock()

	if state, exists := ti.typingUsers[userID]; exists {
		state.Active = false
	}
}

// Update updates typing indicator state
func (ti *TypingIndicator) Update(msg TypingIndicatorMsg) {
	if msg.Active {
		ti.StartTyping(msg.UserID, "User")
	} else {
		ti.StopTyping(msg.UserID)
	}
}

// HasActiveIndicators returns true if there are active typing indicators
func (ti *TypingIndicator) HasActiveIndicators() bool {
	ti.mutex.RLock()
	defer ti.mutex.RUnlock()

	now := time.Now()
	for _, state := range ti.typingUsers {
		if state.Active && now.Sub(state.LastUpdate) < ti.timeout {
			return true
		}
	}
	return false
}

// Render renders the typing indicator
func (ti *TypingIndicator) Render() string {
	ti.mutex.RLock()
	defer ti.mutex.RUnlock()

	now := time.Now()
	activeUsers := make([]string, 0)

	for _, state := range ti.typingUsers {
		if state.Active && now.Sub(state.LastUpdate) < ti.timeout {
			activeUsers = append(activeUsers, state.UserName)
			if len(activeUsers) >= ti.maxUsers {
				break
			}
		}
	}

	if len(activeUsers) == 0 {
		return ""
	}

	animation := ti.animation.GetCurrentFrame()
	var text string

	switch len(activeUsers) {
	case 1:
		text = fmt.Sprintf("%s is typing%s", activeUsers[0], animation)
	case 2:
		text = fmt.Sprintf("%s and %s are typing%s", activeUsers[0], activeUsers[1], animation)
	default:
		text = fmt.Sprintf("%s and %d others are typing%s", activeUsers[0], len(activeUsers)-1, animation)
	}

	return text
}

// Cleanup removes expired typing indicators
func (ti *TypingIndicator) Cleanup() {
	ti.mutex.Lock()
	defer ti.mutex.Unlock()

	now := time.Now()
	for userID, state := range ti.typingUsers {
		if now.Sub(state.LastUpdate) > ti.timeout {
			delete(ti.typingUsers, userID)
		}
	}
}

// NewTypingAnimation creates a new typing animation
func NewTypingAnimation() *TypingAnimation {
	return &TypingAnimation{
		frames:      []string{".", "..", "...", "...."},
		currentFrame: 0,
		lastUpdate:   time.Now(),
		frameDelay:   300 * time.Millisecond,
	}
}

// GetCurrentFrame returns the current animation frame
func (ta *TypingAnimation) GetCurrentFrame() string {
	now := time.Now()
	if now.Sub(ta.lastUpdate) > ta.frameDelay {
		ta.currentFrame = (ta.currentFrame + 1) % len(ta.frames)
		ta.lastUpdate = now
	}
	return ta.frames[ta.currentFrame]
}

// NewPresenceManager creates a new presence manager
func NewPresenceManager() *PresenceManager {
	return &PresenceManager{
		activeUsers:       make(map[string]*UserPresence),
		heartbeatInterval: 30 * time.Second,
		offlineTimeout:    2 * time.Minute,
	}
}

// UpdatePresence updates a user's presence
func (pm *PresenceManager) UpdatePresence(userID, userName string, status PresenceStatus) {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()

	now := time.Now()
	if presence, exists := pm.activeUsers[userID]; exists {
		presence.Status = status
		presence.LastSeen = now
	} else {
		pm.activeUsers[userID] = &UserPresence{
			UserID:   userID,
			UserName: userName,
			Status:   status,
			LastSeen: now,
			Metadata: make(map[string]interface{}),
		}
	}
}

// Update handles presence updates
func (pm *PresenceManager) Update(msg PresenceUpdateMsg) {
	var status PresenceStatus
	switch msg.Presence {
	case "online":
		status = PresenceStatusOnline
	case "away":
		status = PresenceStatusAway
	case "busy":
		status = PresenceStatusBusy
	default:
		status = PresenceStatusOffline
	}

	pm.UpdatePresence(msg.UserID, "User", status)
}

// GetActiveUserCount returns the number of active users
func (pm *PresenceManager) GetActiveUserCount() int {
	pm.mutex.RLock()
	defer pm.mutex.RUnlock()

	now := time.Now()
	count := 0
	for _, presence := range pm.activeUsers {
		if presence.Status != PresenceStatusOffline && now.Sub(presence.LastSeen) < pm.offlineTimeout {
			count++
		}
	}
	return count
}

// GetActiveUsers returns all active users
func (pm *PresenceManager) GetActiveUsers() []*UserPresence {
	pm.mutex.RLock()
	defer pm.mutex.RUnlock()

	now := time.Now()
	var activeUsers []*UserPresence
	for _, presence := range pm.activeUsers {
		if presence.Status != PresenceStatusOffline && now.Sub(presence.LastSeen) < pm.offlineTimeout {
			activeUsers = append(activeUsers, presence)
		}
	}
	return activeUsers
}

// Cleanup removes offline users
func (pm *PresenceManager) Cleanup() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()

	now := time.Now()
	for userID, presence := range pm.activeUsers {
		if now.Sub(presence.LastSeen) > pm.offlineTimeout {
			delete(pm.activeUsers, userID)
		}
	}
}

// NewMessageComposer creates a new message composer
func NewMessageComposer(config ChatConfig) *MessageComposer {
	composerConfig := MessageComposerConfig{
		EnableMentions:     config.EnableMentions,
		EnableEmojis:       config.EnableEmojis,
		EnableCommands:     true,
		EnableAutoComplete: true,
		MaxMessageLength:   4000,
	}

	return &MessageComposer{
		currentMessage:     "",
		cursorPosition:     0,
		mentions:           make([]Mention, 0),
		emojiSuggestions:   make([]EmojiSuggestion, 0),
		commandSuggestions: make([]CommandSuggestion, 0),
		config:            composerConfig,
	}
}

// UpdateMessage updates the current message content
func (mc *MessageComposer) UpdateMessage(content string, cursorPos int) {
	mc.mutex.Lock()
	defer mc.mutex.Unlock()

	mc.currentMessage = content
	mc.cursorPosition = cursorPos

	// Update suggestions based on content
	mc.updateSuggestions()
}

// GetSuggestions returns current suggestions based on message content
func (mc *MessageComposer) GetSuggestions() interface{} {
	mc.mutex.RLock()
	defer mc.mutex.RUnlock()

	// Return the most relevant suggestions
	if len(mc.emojiSuggestions) > 0 {
		return mc.emojiSuggestions
	}
	if len(mc.commandSuggestions) > 0 {
		return mc.commandSuggestions
	}
	return nil
}

// ProcessMentions processes @mentions in the message
func (mc *MessageComposer) ProcessMentions(availableUsers []string) []Mention {
	mc.mutex.Lock()
	defer mc.mutex.Unlock()

	mc.mentions = mc.mentions[:0] // Clear existing mentions

	if !mc.config.EnableMentions {
		return mc.mentions
	}

	// Find @mentions in the message
	words := strings.Fields(mc.currentMessage)
	pos := 0
	for _, word := range words {
		if strings.HasPrefix(word, "@") {
			username := strings.TrimPrefix(word, "@")
			for _, user := range availableUsers {
				if strings.EqualFold(user, username) {
					mention := Mention{
						UserID:   user,
						UserName: user,
						StartPos: pos,
						EndPos:   pos + len(word),
						Text:     word,
					}
					mc.mentions = append(mc.mentions, mention)
					break
				}
			}
		}
		pos += len(word) + 1 // +1 for space
	}

	return mc.mentions
}

// updateSuggestions updates suggestions based on current message content
func (mc *MessageComposer) updateSuggestions() {
	// Check for emoji triggers
	if mc.config.EnableEmojis && strings.Contains(mc.currentMessage, ":") {
		mc.updateEmojiSuggestions()
	}

	// Check for command triggers
	if mc.config.EnableCommands && strings.HasPrefix(mc.currentMessage, "/") {
		mc.updateCommandSuggestions()
	}
}

func (mc *MessageComposer) updateEmojiSuggestions() {
	// Simple emoji suggestions (in a real implementation, use a proper emoji database)
	mc.emojiSuggestions = []EmojiSuggestion{
		{Emoji: "😀", Name: "grinning", Keywords: []string{"happy", "smile"}, Category: "faces"},
		{Emoji: "😂", Name: "joy", Keywords: []string{"laugh", "funny"}, Category: "faces"},
		{Emoji: "❤️", Name: "heart", Keywords: []string{"love", "like"}, Category: "symbols"},
	}
}

func (mc *MessageComposer) updateCommandSuggestions() {
	// Simple command suggestions
	mc.commandSuggestions = []CommandSuggestion{
		{Command: "/help", Description: "Show help information", Usage: "/help [command]", Category: "utility"},
		{Command: "/clear", Description: "Clear conversation", Usage: "/clear", Category: "utility"},
		{Command: "/switch", Description: "Switch AI provider", Usage: "/switch [provider]", Category: "ai"},
	}
}

// NewProviderSelector creates a new provider selector
func NewProviderSelector() *ProviderSelector {
	config := ProviderSelectorConfig{
		MaxVisible:       5,
		ShowCapabilities: true,
		ShowStatus:       true,
		ShowStats:        false,
	}

	return &ProviderSelector{
		providers:     make([]*AIProvider, 0),
		selectedIndex: 0,
		visible:       false,
		config:        config,
	}
}

// SetProviders sets the available providers
func (ps *ProviderSelector) SetProviders(providers []*AIProvider) {
	ps.mutex.Lock()
	defer ps.mutex.Unlock()

	ps.providers = providers
	if ps.selectedIndex >= len(providers) {
		ps.selectedIndex = 0
	}
}

// Show shows the provider selector
func (ps *ProviderSelector) Show() {
	ps.mutex.Lock()
	defer ps.mutex.Unlock()
	ps.visible = true
}

// Hide hides the provider selector
func (ps *ProviderSelector) Hide() {
	ps.mutex.Lock()
	defer ps.mutex.Unlock()
	ps.visible = false
}

// Next selects the next provider
func (ps *ProviderSelector) Next() {
	ps.mutex.Lock()
	defer ps.mutex.Unlock()

	if len(ps.providers) > 0 {
		ps.selectedIndex = (ps.selectedIndex + 1) % len(ps.providers)
	}
}

// Previous selects the previous provider
func (ps *ProviderSelector) Previous() {
	ps.mutex.Lock()
	defer ps.mutex.Unlock()

	if len(ps.providers) > 0 {
		ps.selectedIndex = (ps.selectedIndex - 1 + len(ps.providers)) % len(ps.providers)
	}
}

// GetSelected returns the currently selected provider
func (ps *ProviderSelector) GetSelected() *AIProvider {
	ps.mutex.RLock()
	defer ps.mutex.RUnlock()

	if ps.selectedIndex < len(ps.providers) {
		return ps.providers[ps.selectedIndex]
	}
	return nil
}

// IsVisible returns whether the selector is visible
func (ps *ProviderSelector) IsVisible() bool {
	ps.mutex.RLock()
	defer ps.mutex.RUnlock()
	return ps.visible
}

// Render renders the provider selector
func (ps *ProviderSelector) Render() string {
	ps.mutex.RLock()
	defer ps.mutex.RUnlock()

	if !ps.visible || len(ps.providers) == 0 {
		return ""
	}

	var lines []string
	lines = append(lines, "Select AI Provider:")

	for i, provider := range ps.providers {
		if i >= ps.config.MaxVisible {
			break
		}

		prefix := "  "
		if i == ps.selectedIndex {
			prefix = "▶ "
		}

		line := prefix + provider.Name

		if ps.config.ShowStatus {
			statusText := getProviderStatusText(provider.Status)
			line += " (" + statusText + ")"
		}

		lines = append(lines, line)
	}

	return strings.Join(lines, "\n")
}

// Utility function for provider status text
func getProviderStatusText(status ProviderStatus) string {
	switch status {
	case ProviderStatusActive:
		return "Active"
	case ProviderStatusBusy:
		return "Busy"
	case ProviderStatusError:
		return "Error"
	case ProviderStatusOffline:
		return "Offline"
	default:
		return "Unknown"
	}
}
