package chat

import (
	"encoding/json"
	"fmt"
	"sort"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"aiex-tui/pkg/types"
)

// ConversationManager handles conversation lifecycle and management
type ConversationManager struct {
	// Core components
	chatPanel    *StreamingChatPanel
	persistence  *ConversationPersistence

	// Conversation state
	conversations map[string]*Conversation
	archived     map[string]*Conversation
	tags         map[string][]string // conversation_id -> tags

	// Search and filtering
	searchIndex  *ConversationSearchIndex
	filters      *ConversationFilters

	// Configuration
	config       ConversationConfig

	// Synchronization
	mutex        sync.RWMutex
}

// ConversationConfig configures conversation management
type ConversationConfig struct {
	MaxConversations     int           `json:"max_conversations"`
	AutoArchiveAfter     time.Duration `json:"auto_archive_after"`
	AutoDeleteAfter      time.Duration `json:"auto_delete_after"`
	EnableSearch         bool          `json:"enable_search"`
	EnableTagging        bool          `json:"enable_tagging"`
	EnableAutoTitling    bool          `json:"enable_auto_titling"`
	AutoSaveInterval     time.Duration `json:"auto_save_interval"`
	BackupOnChange       bool          `json:"backup_on_change"`
}

// ConversationSearchIndex provides fast conversation search
type ConversationSearchIndex struct {
	titleIndex   map[string][]string // word -> conversation_ids
	contentIndex map[string][]string // word -> conversation_ids
	tagIndex     map[string][]string // tag -> conversation_ids
	mutex        sync.RWMutex
}

// ConversationFilters manages conversation filtering
type ConversationFilters struct {
	providers    []string
	tags         []string
	dateRange    *DateRange
	messageCount *RangeFilter
	activeOnly   bool
}

// DateRange represents a date range filter
type DateRange struct {
	Start time.Time `json:"start"`
	End   time.Time `json:"end"`
}

// RangeFilter represents a numeric range filter
type RangeFilter struct {
	Min int `json:"min"`
	Max int `json:"max"`
}

// ConversationSummary provides conversation overview
type ConversationSummary struct {
	ID            string            `json:"id"`
	Title         string            `json:"title"`
	Provider      string            `json:"provider"`
	MessageCount  int               `json:"message_count"`
	LastActivity  time.Time         `json:"last_activity"`
	Tags          []string          `json:"tags"`
	Preview       string            `json:"preview"`
	Active        bool              `json:"active"`
}

// NewConversationManager creates a new conversation manager
func NewConversationManager(chatPanel *StreamingChatPanel) *ConversationManager {
	config := ConversationConfig{
		MaxConversations:  100,
		AutoArchiveAfter:  30 * 24 * time.Hour, // 30 days
		AutoDeleteAfter:   90 * 24 * time.Hour, // 90 days
		EnableSearch:      true,
		EnableTagging:     true,
		EnableAutoTitling: true,
		AutoSaveInterval:  30 * time.Second,
		BackupOnChange:    true,
	}

	cm := &ConversationManager{
		chatPanel:     chatPanel,
		persistence:   NewConversationPersistence(),
		conversations: make(map[string]*Conversation),
		archived:      make(map[string]*Conversation),
		tags:          make(map[string][]string),
		searchIndex:   NewConversationSearchIndex(),
		filters:       NewConversationFilters(),
		config:        config,
	}

	// Load existing conversations
	cm.loadConversations()

	return cm
}

// CreateConversation creates a new conversation
func (cm *ConversationManager) CreateConversation(title, provider string) (*Conversation, error) {
	cm.mutex.Lock()
	defer cm.mutex.Unlock()

	// Check conversation limit
	if len(cm.conversations) >= cm.config.MaxConversations {
		return nil, fmt.Errorf("maximum conversations reached (%d)", cm.config.MaxConversations)
	}

	// Create conversation
	conv := &Conversation{
		ID:        generateConversationID(),
		Title:     title,
		Provider:  provider,
		Messages:  make([]types.Message, 0),
		Metadata:  make(map[string]interface{}),
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
		Active:    true,
		Threads:   make(map[string]*MessageThread),
	}

	// Auto-generate title if enabled and title is empty
	if cm.config.EnableAutoTitling && (title == "" || title == "New Conversation") {
		conv.Title = cm.generateConversationTitle(conv)
	}

	cm.conversations[conv.ID] = conv

	// Update search index
	if cm.config.EnableSearch {
		cm.searchIndex.AddConversation(conv)
	}

	// Save if configured
	if cm.config.BackupOnChange {
		cm.persistence.SaveConversation(conv)
	}

	return conv, nil
}

// GetConversation retrieves a conversation by ID
func (cm *ConversationManager) GetConversation(id string) (*Conversation, bool) {
	cm.mutex.RLock()
	defer cm.mutex.RUnlock()

	conv, exists := cm.conversations[id]
	return conv, exists
}

// GetAllConversations returns all active conversations
func (cm *ConversationManager) GetAllConversations() []*Conversation {
	cm.mutex.RLock()
	defer cm.mutex.RUnlock()

	conversations := make([]*Conversation, 0, len(cm.conversations))
	for _, conv := range cm.conversations {
		conversations = append(conversations, conv)
	}

	// Sort by last activity
	sort.Slice(conversations, func(i, j int) bool {
		return conversations[i].UpdatedAt.After(conversations[j].UpdatedAt)
	})

	return conversations
}

// GetConversationSummaries returns conversation summaries
func (cm *ConversationManager) GetConversationSummaries() []ConversationSummary {
	cm.mutex.RLock()
	defer cm.mutex.RUnlock()

	summaries := make([]ConversationSummary, 0, len(cm.conversations))
	for _, conv := range cm.conversations {
		summary := ConversationSummary{
			ID:           conv.ID,
			Title:        conv.Title,
			Provider:     conv.Provider,
			MessageCount: len(conv.Messages),
			LastActivity: conv.UpdatedAt,
			Tags:         cm.tags[conv.ID],
			Preview:      cm.generatePreview(conv),
			Active:       conv.Active,
		}
		summaries = append(summaries, summary)
	}

	// Sort by last activity
	sort.Slice(summaries, func(i, j int) bool {
		return summaries[i].LastActivity.After(summaries[j].LastActivity)
	})

	return summaries
}

// UpdateConversation updates a conversation
func (cm *ConversationManager) UpdateConversation(id string, updates map[string]interface{}) error {
	cm.mutex.Lock()
	defer cm.mutex.Unlock()

	conv, exists := cm.conversations[id]
	if !exists {
		return fmt.Errorf("conversation not found: %s", id)
	}

	// Apply updates
	if title, ok := updates["title"].(string); ok {
		conv.Title = title
	}
	if provider, ok := updates["provider"].(string); ok {
		conv.Provider = provider
	}
	if active, ok := updates["active"].(bool); ok {
		conv.Active = active
	}

	conv.UpdatedAt = time.Now()

	// Update search index
	if cm.config.EnableSearch {
		cm.searchIndex.UpdateConversation(conv)
	}

	// Save if configured
	if cm.config.BackupOnChange {
		cm.persistence.SaveConversation(conv)
	}

	return nil
}

// DeleteConversation deletes a conversation
func (cm *ConversationManager) DeleteConversation(id string) error {
	cm.mutex.Lock()
	defer cm.mutex.Unlock()

	conv, exists := cm.conversations[id]
	if !exists {
		return fmt.Errorf("conversation not found: %s", id)
	}

	// Remove from active conversations
	delete(cm.conversations, id)

	// Remove tags
	delete(cm.tags, id)

	// Remove from search index
	if cm.config.EnableSearch {
		cm.searchIndex.RemoveConversation(id)
	}

	// Delete from persistence
	cm.persistence.DeleteConversation(id)

	return nil
}

// ArchiveConversation moves a conversation to archive
func (cm *ConversationManager) ArchiveConversation(id string) error {
	cm.mutex.Lock()
	defer cm.mutex.Unlock()

	conv, exists := cm.conversations[id]
	if !exists {
		return fmt.Errorf("conversation not found: %s", id)
	}

	// Move to archive
	conv.Active = false
	cm.archived[id] = conv
	delete(cm.conversations, id)

	// Update persistence
	cm.persistence.ArchiveConversation(conv)

	return nil
}

// SearchConversations searches conversations by query
func (cm *ConversationManager) SearchConversations(query string) []*Conversation {
	if !cm.config.EnableSearch {
		return cm.GetAllConversations()
	}

	cm.mutex.RLock()
	defer cm.mutex.RUnlock()

	conversationIDs := cm.searchIndex.Search(query)
	results := make([]*Conversation, 0, len(conversationIDs))

	for _, id := range conversationIDs {
		if conv, exists := cm.conversations[id]; exists {
			results = append(results, conv)
		}
	}

	return results
}

// AddTag adds a tag to a conversation
func (cm *ConversationManager) AddTag(conversationID, tag string) error {
	if !cm.config.EnableTagging {
		return fmt.Errorf("tagging disabled")
	}

	cm.mutex.Lock()
	defer cm.mutex.Unlock()

	// Check if conversation exists
	if _, exists := cm.conversations[conversationID]; !exists {
		return fmt.Errorf("conversation not found: %s", conversationID)
	}

	// Add tag if not already present
	tags := cm.tags[conversationID]
	for _, existingTag := range tags {
		if existingTag == tag {
			return nil // Tag already exists
		}
	}

	cm.tags[conversationID] = append(tags, tag)

	// Update search index
	if cm.config.EnableSearch {
		cm.searchIndex.AddTag(conversationID, tag)
	}

	return nil
}

// RemoveTag removes a tag from a conversation
func (cm *ConversationManager) RemoveTag(conversationID, tag string) error {
	if !cm.config.EnableTagging {
		return fmt.Errorf("tagging disabled")
	}

	cm.mutex.Lock()
	defer cm.mutex.Unlock()

	tags := cm.tags[conversationID]
	for i, existingTag := range tags {
		if existingTag == tag {
			cm.tags[conversationID] = append(tags[:i], tags[i+1:]...)
			break
		}
	}

	// Update search index
	if cm.config.EnableSearch {
		cm.searchIndex.RemoveTag(conversationID, tag)
	}

	return nil
}

// FilterConversations filters conversations by criteria
func (cm *ConversationManager) FilterConversations(filters *ConversationFilters) []*Conversation {
	cm.mutex.RLock()
	defer cm.mutex.RUnlock()

	var results []*Conversation

	for _, conv := range cm.conversations {
		if cm.matchesFilters(conv, filters) {
			results = append(results, conv)
		}
	}

	return results
}

// AddMessage adds a message to a conversation
func (cm *ConversationManager) AddMessage(conversationID string, message types.Message) error {
	cm.mutex.Lock()
	defer cm.mutex.Unlock()

	conv, exists := cm.conversations[conversationID]
	if !exists {
		return fmt.Errorf("conversation not found: %s", conversationID)
	}

	conv.Messages = append(conv.Messages, message)
	conv.UpdatedAt = time.Now()

	// Update search index with message content
	if cm.config.EnableSearch {
		cm.searchIndex.AddMessageContent(conversationID, message.Content)
	}

	// Auto-generate title from first message if needed
	if cm.config.EnableAutoTitling && len(conv.Messages) == 1 && 
	   (conv.Title == "" || conv.Title == "New Conversation") {
		conv.Title = cm.generateTitleFromMessage(message)
	}

	// Save if configured
	if cm.config.BackupOnChange {
		cm.persistence.SaveConversation(conv)
	}

	return nil
}

// Internal helper methods
func (cm *ConversationManager) loadConversations() {
	// Load conversations from persistence
	conversations := cm.persistence.LoadAllConversations()
	for _, conv := range conversations {
		cm.conversations[conv.ID] = conv
		if cm.config.EnableSearch {
			cm.searchIndex.AddConversation(conv)
		}
	}
}

func (cm *ConversationManager) generateConversationTitle(conv *Conversation) string {
	timestamp := conv.CreatedAt.Format("Jan 2 15:04")
	return fmt.Sprintf("Chat %s", timestamp)
}

func (cm *ConversationManager) generateTitleFromMessage(message types.Message) string {
	// Extract first few words from message
	words := strings.Fields(message.Content)
	if len(words) == 0 {
		return "New Conversation"
	}

	maxWords := 5
	if len(words) < maxWords {
		maxWords = len(words)
	}

	title := strings.Join(words[:maxWords], " ")
	if len(words) > maxWords {
		title += "..."
	}

	return title
}

func (cm *ConversationManager) generatePreview(conv *Conversation) string {
	if len(conv.Messages) == 0 {
		return "No messages"
	}

	lastMessage := conv.Messages[len(conv.Messages)-1]
	preview := lastMessage.Content
	if len(preview) > 100 {
		preview = preview[:100] + "..."
	}

	return preview
}

func (cm *ConversationManager) matchesFilters(conv *Conversation, filters *ConversationFilters) bool {
	// Provider filter
	if len(filters.providers) > 0 {
		match := false
		for _, provider := range filters.providers {
			if conv.Provider == provider {
				match = true
				break
			}
		}
		if !match {
			return false
		}
	}

	// Tag filter
	if len(filters.tags) > 0 {
		convTags := cm.tags[conv.ID]
		match := false
		for _, filterTag := range filters.tags {
			for _, convTag := range convTags {
				if convTag == filterTag {
					match = true
					break
				}
			}
			if match {
				break
			}
		}
		if !match {
			return false
		}
	}

	// Date range filter
	if filters.dateRange != nil {
		if conv.UpdatedAt.Before(filters.dateRange.Start) || conv.UpdatedAt.After(filters.dateRange.End) {
			return false
		}
	}

	// Message count filter
	if filters.messageCount != nil {
		count := len(conv.Messages)
		if count < filters.messageCount.Min || count > filters.messageCount.Max {
			return false
		}
	}

	// Active filter
	if filters.activeOnly && !conv.Active {
		return false
	}

	return true
}

// Factory functions
func NewConversationSearchIndex() *ConversationSearchIndex {
	return &ConversationSearchIndex{
		titleIndex:   make(map[string][]string),
		contentIndex: make(map[string][]string),
		tagIndex:     make(map[string][]string),
	}
}

func NewConversationFilters() *ConversationFilters {
	return &ConversationFilters{
		providers:    make([]string, 0),
		tags:         make([]string, 0),
		activeOnly:   false,
	}
}

// ConversationSearchIndex methods
func (csi *ConversationSearchIndex) AddConversation(conv *Conversation) {
	csi.mutex.Lock()
	defer csi.mutex.Unlock()

	// Index title
	titleWords := strings.Fields(strings.ToLower(conv.Title))
	for _, word := range titleWords {
		csi.titleIndex[word] = append(csi.titleIndex[word], conv.ID)
	}

	// Index message content
	for _, message := range conv.Messages {
		csi.addMessageContentToIndex(conv.ID, message.Content)
	}
}

func (csi *ConversationSearchIndex) UpdateConversation(conv *Conversation) {
	// Remove and re-add
	csi.RemoveConversation(conv.ID)
	csi.AddConversation(conv)
}

func (csi *ConversationSearchIndex) RemoveConversation(conversationID string) {
	csi.mutex.Lock()
	defer csi.mutex.Unlock()

	// Remove from all indexes
	for word, ids := range csi.titleIndex {
		csi.titleIndex[word] = removeStringFromSlice(ids, conversationID)
	}
	for word, ids := range csi.contentIndex {
		csi.contentIndex[word] = removeStringFromSlice(ids, conversationID)
	}
	for tag, ids := range csi.tagIndex {
		csi.tagIndex[tag] = removeStringFromSlice(ids, conversationID)
	}
}

func (csi *ConversationSearchIndex) AddMessageContent(conversationID, content string) {
	csi.mutex.Lock()
	defer csi.mutex.Unlock()
	csi.addMessageContentToIndex(conversationID, content)
}

func (csi *ConversationSearchIndex) addMessageContentToIndex(conversationID, content string) {
	words := strings.Fields(strings.ToLower(content))
	for _, word := range words {
		if !contains(csi.contentIndex[word], conversationID) {
			csi.contentIndex[word] = append(csi.contentIndex[word], conversationID)
		}
	}
}

func (csi *ConversationSearchIndex) AddTag(conversationID, tag string) {
	csi.mutex.Lock()
	defer csi.mutex.Unlock()

	if !contains(csi.tagIndex[tag], conversationID) {
		csi.tagIndex[tag] = append(csi.tagIndex[tag], conversationID)
	}
}

func (csi *ConversationSearchIndex) RemoveTag(conversationID, tag string) {
	csi.mutex.Lock()
	defer csi.mutex.Unlock()

	csi.tagIndex[tag] = removeStringFromSlice(csi.tagIndex[tag], conversationID)
}

func (csi *ConversationSearchIndex) Search(query string) []string {
	csi.mutex.RLock()
	defer csi.mutex.RUnlock()

	queryWords := strings.Fields(strings.ToLower(query))
	if len(queryWords) == 0 {
		return []string{}
	}

	resultSets := make([][]string, 0)

	// Search in titles and content
	for _, word := range queryWords {
		var wordResults []string
		
		// Add title matches
		if titleIDs, exists := csi.titleIndex[word]; exists {
			wordResults = append(wordResults, titleIDs...)
		}
		
		// Add content matches
		if contentIDs, exists := csi.contentIndex[word]; exists {
			wordResults = append(wordResults, contentIDs...)
		}
		
		if len(wordResults) > 0 {
			resultSets = append(resultSets, wordResults)
		}
	}

	// Find intersection of all result sets
	if len(resultSets) == 0 {
		return []string{}
	}

	results := resultSets[0]
	for i := 1; i < len(resultSets); i++ {
		results = intersectSlices(results, resultSets[i])
	}

	return results
}

// Utility functions
func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

func removeStringFromSlice(slice []string, item string) []string {
	for i, s := range slice {
		if s == item {
			return append(slice[:i], slice[i+1:]...)
		}
	}
	return slice
}

func intersectSlices(a, b []string) []string {
	var result []string
	for _, item := range a {
		if contains(b, item) {
			result = append(result, item)
		}
	}
	return result
}

// Placeholder implementation for persistence
type ConversationPersistence struct{}

func NewConversationPersistence() *ConversationPersistence {
	return &ConversationPersistence{}
}

func (cp *ConversationPersistence) SaveConversation(conv *Conversation) error {
	// Implementation would save to file/database
	return nil
}

func (cp *ConversationPersistence) LoadAllConversations() []*Conversation {
	// Implementation would load from file/database
	return []*Conversation{}
}

func (cp *ConversationPersistence) DeleteConversation(id string) error {
	// Implementation would delete from file/database
	return nil
}

func (cp *ConversationPersistence) ArchiveConversation(conv *Conversation) error {
	// Implementation would move to archive
	return nil
}
