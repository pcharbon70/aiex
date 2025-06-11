package events

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"aiex-tui/pkg/types"
)

// DistributedStateManager handles state management with event sourcing and optimistic updates
type DistributedStateManager struct {
	// Core state
	localState   *AppState
	remoteState  *RemoteState
	
	// Event sourcing
	eventStore   *EventStore
	eventStream  *EventStreamManager
	
	// Synchronization
	syncManager  *StateSyncManager
	
	// Conflict resolution
	resolver     *ConflictResolver
	
	// Configuration
	config       StateManagerConfig
	
	// Runtime state
	running      bool
	subscribers  map[string]StateSubscriber
	mutex        sync.RWMutex
	
	// Context and cancellation
	ctx          context.Context
	cancel       context.CancelFunc
}

// AppState represents the complete application state
type AppState struct {
	// UI State
	ActivePanel    PanelType             `json:"active_panel"`
	PanelStates    map[PanelType]interface{} `json:"panel_states"`
	LayoutConfig   interface{}           `json:"layout_config"`
	FocusHistory   []PanelType          `json:"focus_history"`
	
	// Content State
	Project        types.Project         `json:"project"`
	OpenFiles      []string             `json:"open_files"`
	ActiveFile     string               `json:"active_file"`
	FileContents   map[string][]string  `json:"file_contents"`
	
	// Communication State
	Messages       []types.Message       `json:"messages"`
	Conversations  map[string][]types.Message `json:"conversations"`
	ActiveConversation string            `json:"active_conversation"`
	
	// AI State
	AIProviders    map[string]interface{} `json:"ai_providers"`
	Suggestions    []types.CodeSuggestion `json:"suggestions"`
	AIMetrics      interface{}           `json:"ai_metrics"`
	
	// System State
	Notifications  []types.Notification  `json:"notifications"`
	Errors         []interface{}         `json:"errors"`
	Performance    interface{}           `json:"performance"`
	
	// Metadata
	Version        int64                 `json:"version"`
	LastModified   time.Time            `json:"last_modified"`
	Checksum       string               `json:"checksum"`
}

// RemoteState represents synchronized remote state
type RemoteState struct {
	Version      int64                 `json:"version"`
	Checksum     string               `json:"checksum"`
	Data         map[string]interface{} `json:"data"`
	LastSync     time.Time            `json:"last_sync"`
	SyncStatus   SyncStatus           `json:"sync_status"`
	ConflictData []StateConflict      `json:"conflict_data,omitempty"`
}

// StateEvent represents a state change event
type StateEvent struct {
	ID           string                 `json:"id"`
	Type         string                 `json:"type"`
	Component    string                 `json:"component"`
	Action       string                 `json:"action"`
	Data         map[string]interface{} `json:"data"`
	PreviousData map[string]interface{} `json:"previous_data,omitempty"`
	Timestamp    time.Time             `json:"timestamp"`
	Version      int64                 `json:"version"`
	Source       string                `json:"source"`
	UserID       string                `json:"user_id,omitempty"`
}

// SyncStatus represents synchronization status
type SyncStatus int

const (
	SyncStatusUnknown SyncStatus = iota
	SyncStatusSynced
	SyncStatusPending
	SyncStatusConflict
	SyncStatusError
)

// StateConflict represents a state synchronization conflict
type StateConflict struct {
	Component    string      `json:"component"`
	LocalValue   interface{} `json:"local_value"`
	RemoteValue  interface{} `json:"remote_value"`
	Resolution   string      `json:"resolution,omitempty"`
	ResolvedAt   time.Time   `json:"resolved_at,omitempty"`
}

// StateSubscriber defines the interface for state change subscribers
type StateSubscriber interface {
	OnStateChange(component string, oldState, newState interface{})
	OnStateConflict(conflict StateConflict)
	OnSyncComplete(success bool, errors []error)
}

// StateManagerConfig configures the state manager
type StateManagerConfig struct {
	EnableEventSourcing    bool          `json:"enable_event_sourcing"`
	EnableOptimisticUpdates bool         `json:"enable_optimistic_updates"`
	EnableConflictResolution bool        `json:"enable_conflict_resolution"`
	SyncInterval           time.Duration `json:"sync_interval"`
	MaxEventHistory        int           `json:"max_event_history"`
	ConflictRetryDelay     time.Duration `json:"conflict_retry_delay"`
	StateBackupInterval    time.Duration `json:"state_backup_interval"`
}

// NewDistributedStateManager creates a new distributed state manager
func NewDistributedStateManager(config StateManagerConfig, eventStream *EventStreamManager) *DistributedStateManager {
	ctx, cancel := context.WithCancel(context.Background())
	
	if config.SyncInterval == 0 {
		config.SyncInterval = 5 * time.Second
	}
	if config.MaxEventHistory == 0 {
		config.MaxEventHistory = 1000
	}
	if config.ConflictRetryDelay == 0 {
		config.ConflictRetryDelay = 1 * time.Second
	}
	if config.StateBackupInterval == 0 {
		config.StateBackupInterval = 30 * time.Second
	}
	
	dsm := &DistributedStateManager{
		localState:  NewAppState(),
		remoteState: NewRemoteState(),
		eventStore:  NewEventStore(config.MaxEventHistory),
		eventStream: eventStream,
		syncManager: NewStateSyncManager(),
		resolver:    NewConflictResolver(),
		config:      config,
		subscribers: make(map[string]StateSubscriber),
		ctx:         ctx,
		cancel:      cancel,
	}
	
	return dsm
}

// Start begins state management operations
func (dsm *DistributedStateManager) Start() error {
	dsm.mutex.Lock()
	defer dsm.mutex.Unlock()
	
	if dsm.running {
		return fmt.Errorf("state manager already running")
	}
	
	dsm.running = true
	
	// Start background processes
	if dsm.config.EnableEventSourcing {
		go dsm.eventSourcingLoop()
	}
	
	go dsm.syncLoop()
	go dsm.backupLoop()
	
	return nil
}

// Stop halts state management operations
func (dsm *DistributedStateManager) Stop() error {
	dsm.mutex.Lock()
	defer dsm.mutex.Unlock()
	
	if !dsm.running {
		return fmt.Errorf("state manager not running")
	}
	
	dsm.running = false
	dsm.cancel()
	
	return nil
}

// ApplyStateChange applies a state change with optimistic updates
func (dsm *DistributedStateManager) ApplyStateChange(component string, action string, data map[string]interface{}) error {
	dsm.mutex.Lock()
	defer dsm.mutex.Unlock()
	
	// Create state event
	event := StateEvent{
		ID:        dsm.generateEventID(),
		Type:      "state_change",
		Component: component,
		Action:    action,
		Data:      data,
		Timestamp: time.Now(),
		Version:   dsm.localState.Version + 1,
		Source:    "local",
	}
	
	// Store previous state for rollback
	previousData := dsm.getComponentState(component)
	if previousData != nil {
		if prevMap, ok := previousData.(map[string]interface{}); ok {
			event.PreviousData = prevMap
		}
	}
	
	// Apply optimistic update
	if dsm.config.EnableOptimisticUpdates {
		oldState := dsm.getComponentState(component)
		newState := dsm.applyStateEvent(event)
		
		// Notify subscribers
		dsm.notifyStateChange(component, oldState, newState)
	}
	
	// Store event
	if dsm.config.EnableEventSourcing {
		dsm.eventStore.AddEvent(event)
	}
	
	// Queue for synchronization
	dsm.syncManager.QueueEvent(event)
	
	// Send to event stream if available
	if dsm.eventStream != nil {
		streamEvent := StreamEvent{
			ID:       event.ID,
			Type:     event.Type,
			Category: CategoryStateChange,
			Priority: PriorityNormal,
			Payload:  event,
			Metadata: map[string]interface{}{
				"component": component,
				"action":    action,
			},
			Timestamp: event.Timestamp,
			Source:    "state_manager",
		}
		
		dsm.eventStream.ProcessEvent(streamEvent)
	}
	
	return nil
}

// GetState returns the current state for a component
func (dsm *DistributedStateManager) GetState(component string) interface{} {
	dsm.mutex.RLock()
	defer dsm.mutex.RUnlock()
	
	return dsm.getComponentState(component)
}

// GetFullState returns a copy of the complete application state
func (dsm *DistributedStateManager) GetFullState() AppState {
	dsm.mutex.RLock()
	defer dsm.mutex.RUnlock()
	
	// Return a deep copy
	stateCopy := *dsm.localState
	return stateCopy
}

// Subscribe adds a state change subscriber
func (dsm *DistributedStateManager) Subscribe(id string, subscriber StateSubscriber) {
	dsm.mutex.Lock()
	defer dsm.mutex.Unlock()
	
	dsm.subscribers[id] = subscriber
}

// Unsubscribe removes a state change subscriber
func (dsm *DistributedStateManager) Unsubscribe(id string) {
	dsm.mutex.Lock()
	defer dsm.mutex.Unlock()
	
	delete(dsm.subscribers, id)
}

// RollbackToVersion rolls back state to a specific version
func (dsm *DistributedStateManager) RollbackToVersion(version int64) error {
	dsm.mutex.Lock()
	defer dsm.mutex.Unlock()
	
	if !dsm.config.EnableEventSourcing {
		return fmt.Errorf("event sourcing not enabled")
	}
	
	// Get events up to the target version
	events := dsm.eventStore.GetEventsToVersion(version)
	
	// Rebuild state from events
	newState := NewAppState()
	for _, event := range events {
		dsm.applyStateEventToState(event, newState)
	}
	
	// Update current state
	oldState := dsm.localState
	dsm.localState = newState
	
	// Notify subscribers of complete state change
	for component := range dsm.localState.PanelStates {
		oldComponentState := dsm.getComponentStateFromState(string(component), oldState)
		newComponentState := dsm.getComponentState(string(component))
		dsm.notifyStateChange(string(component), oldComponentState, newComponentState)
	}
	
	return nil
}

// ForceSync forces synchronization with remote state
func (dsm *DistributedStateManager) ForceSync() error {
	return dsm.syncManager.ForcSync(dsm.localState, dsm.remoteState)
}

// ResolveConflict manually resolves a state conflict
func (dsm *DistributedStateManager) ResolveConflict(component string, resolution string) error {
	dsm.mutex.Lock()
	defer dsm.mutex.Unlock()
	
	conflicts := dsm.remoteState.ConflictData
	for i, conflict := range conflicts {
		if conflict.Component == component {
			resolvedConflict := dsm.resolver.ResolveConflict(conflict, resolution)
			dsm.remoteState.ConflictData[i] = resolvedConflict
			
			// Apply resolution to local state
			dsm.applyConflictResolution(resolvedConflict)
			
			return nil
		}
	}
	
	return fmt.Errorf("conflict not found for component: %s", component)
}

// Internal methods
func (dsm *DistributedStateManager) applyStateEvent(event StateEvent) interface{} {
	return dsm.applyStateEventToState(event, dsm.localState)
}

func (dsm *DistributedStateManager) applyStateEventToState(event StateEvent, state *AppState) interface{} {
	component := event.Component
	action := event.Action
	data := event.Data
	
	switch component {
	case "ui":
		dsm.applyUIStateChange(action, data, state)
	case "files":
		dsm.applyFileStateChange(action, data, state)
	case "chat":
		dsm.applyChatStateChange(action, data, state)
	case "ai":
		dsm.applyAIStateChange(action, data, state)
	case "system":
		dsm.applySystemStateChange(action, data, state)
	}
	
	// Update state metadata
	state.Version = event.Version
	state.LastModified = event.Timestamp
	state.Checksum = dsm.calculateChecksum(state)
	
	return dsm.getComponentStateFromState(component, state)
}

func (dsm *DistributedStateManager) applyUIStateChange(action string, data map[string]interface{}, state *AppState) {
	switch action {
	case "focus_change":
		if panel, ok := data["panel"].(PanelType); ok {
			state.ActivePanel = panel
		}
	case "layout_update":
		state.LayoutConfig = data["config"]
	case "panel_state_update":
		if panel, ok := data["panel"].(PanelType); ok {
			if panelState, ok := data["state"]; ok {
				if state.PanelStates == nil {
					state.PanelStates = make(map[PanelType]interface{})
				}
				state.PanelStates[panel] = panelState
			}
		}
	}
}

func (dsm *DistributedStateManager) applyFileStateChange(action string, data map[string]interface{}, state *AppState) {
	switch action {
	case "file_opened":
		if path, ok := data["path"].(string); ok {
			if !contains(state.OpenFiles, path) {
				state.OpenFiles = append(state.OpenFiles, path)
			}
		}
	case "file_closed":
		if path, ok := data["path"].(string); ok {
			state.OpenFiles = removeString(state.OpenFiles, path)
		}
	case "active_file_changed":
		if path, ok := data["path"].(string); ok {
			state.ActiveFile = path
		}
	case "file_content_updated":
		if path, ok := data["path"].(string); ok {
			if content, ok := data["content"].([]string); ok {
				if state.FileContents == nil {
					state.FileContents = make(map[string][]string)
				}
				state.FileContents[path] = content
			}
		}
	}
}

func (dsm *DistributedStateManager) applyChatStateChange(action string, data map[string]interface{}, state *AppState) {
	switch action {
	case "message_added":
		if messageData, ok := data["message"]; ok {
			if message, ok := messageData.(types.Message); ok {
				state.Messages = append(state.Messages, message)
			}
		}
	case "conversation_started":
		if convID, ok := data["conversation_id"].(string); ok {
			if state.Conversations == nil {
				state.Conversations = make(map[string][]types.Message)
			}
			state.Conversations[convID] = make([]types.Message, 0)
			state.ActiveConversation = convID
		}
	case "conversation_switched":
		if convID, ok := data["conversation_id"].(string); ok {
			state.ActiveConversation = convID
		}
	}
}

func (dsm *DistributedStateManager) applyAIStateChange(action string, data map[string]interface{}, state *AppState) {
	switch action {
	case "suggestion_added":
		if suggestionData, ok := data["suggestion"]; ok {
			if suggestion, ok := suggestionData.(types.CodeSuggestion); ok {
				state.Suggestions = append(state.Suggestions, suggestion)
			}
		}
	case "provider_updated":
		if providerID, ok := data["provider_id"].(string); ok {
			if providerData, ok := data["provider_data"]; ok {
				if state.AIProviders == nil {
					state.AIProviders = make(map[string]interface{})
				}
				state.AIProviders[providerID] = providerData
			}
		}
	}
}

func (dsm *DistributedStateManager) applySystemStateChange(action string, data map[string]interface{}, state *AppState) {
	switch action {
	case "notification_added":
		if notificationData, ok := data["notification"]; ok {
			if notification, ok := notificationData.(types.Notification); ok {
				state.Notifications = append(state.Notifications, notification)
			}
		}
	case "error_added":
		if errorData, ok := data["error"]; ok {
			state.Errors = append(state.Errors, errorData)
		}
	}
}

func (dsm *DistributedStateManager) getComponentState(component string) interface{} {
	return dsm.getComponentStateFromState(component, dsm.localState)
}

func (dsm *DistributedStateManager) getComponentStateFromState(component string, state *AppState) interface{} {
	switch component {
	case "ui":
		return map[string]interface{}{
			"active_panel":   state.ActivePanel,
			"layout_config":  state.LayoutConfig,
			"panel_states":   state.PanelStates,
			"focus_history":  state.FocusHistory,
		}
	case "files":
		return map[string]interface{}{
			"open_files":     state.OpenFiles,
			"active_file":    state.ActiveFile,
			"file_contents":  state.FileContents,
		}
	case "chat":
		return map[string]interface{}{
			"messages":            state.Messages,
			"conversations":       state.Conversations,
			"active_conversation": state.ActiveConversation,
		}
	case "ai":
		return map[string]interface{}{
			"providers":   state.AIProviders,
			"suggestions": state.Suggestions,
			"metrics":     state.AIMetrics,
		}
	case "system":
		return map[string]interface{}{
			"notifications": state.Notifications,
			"errors":        state.Errors,
			"performance":   state.Performance,
		}
	default:
		return nil
	}
}

func (dsm *DistributedStateManager) notifyStateChange(component string, oldState, newState interface{}) {
	for _, subscriber := range dsm.subscribers {
		go subscriber.OnStateChange(component, oldState, newState)
	}
}

func (dsm *DistributedStateManager) calculateChecksum(state *AppState) string {
	data, _ := json.Marshal(state)
	hash := sha256.Sum256(data)
	return fmt.Sprintf("%x", hash)
}

func (dsm *DistributedStateManager) generateEventID() string {
	return fmt.Sprintf("state_evt_%d", time.Now().UnixNano())
}

// Background loops
func (dsm *DistributedStateManager) eventSourcingLoop() {
	// Implementation for event sourcing background processing
}

func (dsm *DistributedStateManager) syncLoop() {
	ticker := time.NewTicker(dsm.config.SyncInterval)
	defer ticker.Stop()
	
	for {
		select {
		case <-dsm.ctx.Done():
			return
		case <-ticker.C:
			dsm.performSync()
		}
	}
}

func (dsm *DistributedStateManager) backupLoop() {
	ticker := time.NewTicker(dsm.config.StateBackupInterval)
	defer ticker.Stop()
	
	for {
		select {
		case <-dsm.ctx.Done():
			return
		case <-ticker.C:
			dsm.performBackup()
		}
	}
}

func (dsm *DistributedStateManager) performSync() {
	// Implementation for periodic state synchronization
}

func (dsm *DistributedStateManager) performBackup() {
	// Implementation for periodic state backup
}

func (dsm *DistributedStateManager) applyConflictResolution(conflict StateConflict) {
	// Implementation for applying conflict resolution
}

// Helper functions
func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

func removeString(slice []string, item string) []string {
	for i, s := range slice {
		if s == item {
			return append(slice[:i], slice[i+1:]...)
		}
	}
	return slice
}

// Factory functions
func NewAppState() *AppState {
	return &AppState{
		PanelStates:   make(map[PanelType]interface{}),
		OpenFiles:     make([]string, 0),
		FileContents:  make(map[string][]string),
		Messages:      make([]types.Message, 0),
		Conversations: make(map[string][]types.Message),
		AIProviders:   make(map[string]interface{}),
		Suggestions:   make([]types.CodeSuggestion, 0),
		Notifications: make([]types.Notification, 0),
		Errors:        make([]interface{}, 0),
		Version:       0,
		LastModified:  time.Now(),
	}
}

func NewRemoteState() *RemoteState {
	return &RemoteState{
		Version:      0,
		Data:         make(map[string]interface{}),
		LastSync:     time.Now(),
		SyncStatus:   SyncStatusUnknown,
		ConflictData: make([]StateConflict, 0),
	}
}

// Placeholder types and structs for compilation
type EventStore struct {
	events     []StateEvent
	maxHistory int
	mutex      sync.RWMutex
}

func NewEventStore(maxHistory int) *EventStore {
	return &EventStore{
		events:     make([]StateEvent, 0),
		maxHistory: maxHistory,
	}
}

func (es *EventStore) AddEvent(event StateEvent) {
	es.mutex.Lock()
	defer es.mutex.Unlock()
	
	es.events = append(es.events, event)
	if len(es.events) > es.maxHistory {
		es.events = es.events[1:]
	}
}

func (es *EventStore) GetEventsToVersion(version int64) []StateEvent {
	es.mutex.RLock()
	defer es.mutex.RUnlock()
	
	var events []StateEvent
	for _, event := range es.events {
		if event.Version <= version {
			events = append(events, event)
		}
	}
	return events
}

type StateSyncManager struct{}
func NewStateSyncManager() *StateSyncManager { return &StateSyncManager{} }
func (ssm *StateSyncManager) QueueEvent(event StateEvent) {}
func (ssm *StateSyncManager) ForcSync(local *AppState, remote *RemoteState) error { return nil }

type ConflictResolver struct{}
func NewConflictResolver() *ConflictResolver { return &ConflictResolver{} }
func (cr *ConflictResolver) ResolveConflict(conflict StateConflict, resolution string) StateConflict {
	conflict.Resolution = resolution
	conflict.ResolvedAt = time.Now()
	return conflict
}

// PanelType enum for consistency
type PanelType int

const (
	FileTreePanel PanelType = iota
	EditorPanel
	ChatPanel
	ContextPanel
)