package state

import (
	"fmt"
	"sync"
	"time"

	"aiex-tui/pkg/types"
)

// Manager handles centralized state management with optimistic updates
type Manager struct {
	localState  AppState
	remoteState RemoteState
	eventStore  *EventStore
	syncManager *SyncManager
	mutex       sync.RWMutex
	version     int64
}

// AppState represents the local application state
type AppState struct {
	Project      types.Project         `json:"project"`
	OpenFiles    []string              `json:"open_files"`
	ActiveFile   string                `json:"active_file"`
	Messages     []types.Message       `json:"messages"`
	FileTree     []types.FileInfo      `json:"file_tree"`
	Suggestions  []types.CodeSuggestion `json:"suggestions"`
	Notifications []types.Notification `json:"notifications"`
	LastUpdate   time.Time             `json:"last_update"`
}

// RemoteState represents the synchronized remote state
type RemoteState struct {
	Version    int64                  `json:"version"`
	Checksum   string                 `json:"checksum"`
	Data       map[string]interface{} `json:"data"`
	LastSync   time.Time              `json:"last_sync"`
}

// StateEvent represents a state change event
type StateEvent struct {
	ID        string                 `json:"id"`
	Type      string                 `json:"type"`
	Component string                 `json:"component"`
	Action    string                 `json:"action"`
	Data      map[string]interface{} `json:"data"`
	Timestamp time.Time              `json:"timestamp"`
	Version   int64                  `json:"version"`
}

// EventStore handles event storage and replay
type EventStore struct {
	events []StateEvent
	mutex  sync.RWMutex
}

// SyncManager handles synchronization with remote state
type SyncManager struct {
	pendingEvents []StateEvent
	retryQueue    []StateEvent
	mutex         sync.RWMutex
}

// NewManager creates a new state manager
func NewManager() *Manager {
	return &Manager{
		localState: AppState{
			OpenFiles:    make([]string, 0),
			Messages:     make([]types.Message, 0),
			FileTree:     make([]types.FileInfo, 0),
			Suggestions:  make([]types.CodeSuggestion, 0),
			Notifications: make([]types.Notification, 0),
			LastUpdate:   time.Now(),
		},
		remoteState: RemoteState{
			Version:  0,
			Data:     make(map[string]interface{}),
			LastSync: time.Now(),
		},
		eventStore:  NewEventStore(),
		syncManager: NewSyncManager(),
		version:     0,
	}
}

// NewEventStore creates a new event store
func NewEventStore() *EventStore {
	return &EventStore{
		events: make([]StateEvent, 0),
	}
}

// NewSyncManager creates a new sync manager
func NewSyncManager() *SyncManager {
	return &SyncManager{
		pendingEvents: make([]StateEvent, 0),
		retryQueue:    make([]StateEvent, 0),
	}
}

// GetState returns a copy of the current local state
func (sm *Manager) GetState() AppState {
	sm.mutex.RLock()
	defer sm.mutex.RUnlock()
	
	// Return a copy to prevent external mutations
	return sm.localState
}

// ApplyEvent applies a state change event optimistically
func (sm *Manager) ApplyEvent(event StateEvent) error {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()
	
	// Generate event ID and version if not provided
	if event.ID == "" {
		event.ID = generateEventID()
	}
	if event.Timestamp.IsZero() {
		event.Timestamp = time.Now()
	}
	
	sm.version++
	event.Version = sm.version
	
	// Apply to local state
	if err := sm.applyEventToLocalState(event); err != nil {
		sm.version-- // Rollback version
		return err
	}
	
	// Store event
	sm.eventStore.AddEvent(event)
	
	// Queue for remote sync
	sm.syncManager.QueueEvent(event)
	
	sm.localState.LastUpdate = time.Now()
	
	return nil
}

// applyEventToLocalState applies an event to the local state
func (sm *Manager) applyEventToLocalState(event StateEvent) error {
	switch event.Type {
	case "file_opened":
		filepath := event.Data["path"].(string)
		if !contains(sm.localState.OpenFiles, filepath) {
			sm.localState.OpenFiles = append(sm.localState.OpenFiles, filepath)
		}
		
	case "file_closed":
		filepath := event.Data["path"].(string)
		sm.localState.OpenFiles = remove(sm.localState.OpenFiles, filepath)
		
	case "active_file_changed":
		sm.localState.ActiveFile = event.Data["path"].(string)
		
	case "message_added":
		if msgData, ok := event.Data["message"].(types.Message); ok {
			sm.localState.Messages = append(sm.localState.Messages, msgData)
		}
		
	case "project_loaded":
		if projData, ok := event.Data["project"].(types.Project); ok {
			sm.localState.Project = projData
		}
		
	case "file_tree_updated":
		if treeData, ok := event.Data["tree"].([]types.FileInfo); ok {
			sm.localState.FileTree = treeData
		}
		
	case "suggestion_added":
		if suggData, ok := event.Data["suggestion"].(types.CodeSuggestion); ok {
			sm.localState.Suggestions = append(sm.localState.Suggestions, suggData)
		}
		
	case "notification_added":
		if notifData, ok := event.Data["notification"].(types.Notification); ok {
			sm.localState.Notifications = append(sm.localState.Notifications, notifData)
		}
	}
	
	return nil
}

// RollbackEvent rolls back a failed event
func (sm *Manager) RollbackEvent(eventID string) error {
	sm.mutex.Lock()
	defer sm.mutex.Unlock()
	
	// Find and remove the event
	if event := sm.eventStore.RemoveEvent(eventID); event != nil {
		// Rebuild state from remaining events
		return sm.rebuildStateFromEvents()
	}
	
	return nil
}

// rebuildStateFromEvents rebuilds the local state from stored events
func (sm *Manager) rebuildStateFromEvents() error {
	// Reset state
	sm.localState = AppState{
		OpenFiles:    make([]string, 0),
		Messages:     make([]types.Message, 0),
		FileTree:     make([]types.FileInfo, 0),
		Suggestions:  make([]types.CodeSuggestion, 0),
		Notifications: make([]types.Notification, 0),
		LastUpdate:   time.Now(),
	}
	
	// Replay all events
	events := sm.eventStore.GetAllEvents()
	for _, event := range events {
		if err := sm.applyEventToLocalState(event); err != nil {
			return err
		}
	}
	
	return nil
}

// EventStore methods
func (es *EventStore) AddEvent(event StateEvent) {
	es.mutex.Lock()
	defer es.mutex.Unlock()
	
	es.events = append(es.events, event)
}

func (es *EventStore) RemoveEvent(eventID string) *StateEvent {
	es.mutex.Lock()
	defer es.mutex.Unlock()
	
	for i, event := range es.events {
		if event.ID == eventID {
			// Remove event
			es.events = append(es.events[:i], es.events[i+1:]...)
			return &event
		}
	}
	
	return nil
}

func (es *EventStore) GetAllEvents() []StateEvent {
	es.mutex.RLock()
	defer es.mutex.RUnlock()
	
	// Return a copy
	events := make([]StateEvent, len(es.events))
	copy(events, es.events)
	return events
}

// SyncManager methods
func (sync *SyncManager) QueueEvent(event StateEvent) {
	sync.mutex.Lock()
	defer sync.mutex.Unlock()
	
	sync.pendingEvents = append(sync.pendingEvents, event)
}

func (sync *SyncManager) GetPendingEvents() []StateEvent {
	sync.mutex.RLock()
	defer sync.mutex.RUnlock()
	
	events := make([]StateEvent, len(sync.pendingEvents))
	copy(events, sync.pendingEvents)
	return events
}

func (sync *SyncManager) MarkEventSynced(eventID string) {
	sync.mutex.Lock()
	defer sync.mutex.Unlock()
	
	for i, event := range sync.pendingEvents {
		if event.ID == eventID {
			sync.pendingEvents = append(sync.pendingEvents[:i], sync.pendingEvents[i+1:]...)
			break
		}
	}
}

func (sync *SyncManager) RetryEvent(event StateEvent) {
	sync.mutex.Lock()
	defer sync.mutex.Unlock()
	
	sync.retryQueue = append(sync.retryQueue, event)
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

func remove(slice []string, item string) []string {
	for i, s := range slice {
		if s == item {
			return append(slice[:i], slice[i+1:]...)
		}
	}
	return slice
}

func generateEventID() string {
	return fmt.Sprintf("evt_%d", time.Now().UnixNano())
}