package editor

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"aiex-tui/internal/events"
	"aiex-tui/internal/rpc"
)

// CollaborationEngine handles real-time collaborative editing with operational transforms
type CollaborationEngine struct {
	// Core components
	rpcClient    *rpc.Client
	eventStream  *events.EventStreamManager
	stateManager *events.DistributedStateManager

	// Operational Transform state
	documentID   string
	localVector  OperationVector
	remoteVector OperationVector
	pendingOps   []Operation
	ackedOps     []Operation

	// Collaboration state
	collaborators map[string]*Collaborator
	localUserID   string
	localCursor   CursorPosition

	// Conflict resolution
	conflictResolver *ConflictResolver
	transformEngine  *TransformEngine

	// Configuration
	config       CollaborationConfig

	// Synchronization
	mutex        sync.RWMutex
	running      bool

	// Context
	ctx          context.Context
	cancel       context.CancelFunc
}

// Operation represents a document operation for operational transforms
type Operation struct {
	ID        string          `json:"id"`
	Type      OperationType   `json:"type"`
	Position  int             `json:"position"`
	Content   string          `json:"content,omitempty"`
	Length    int             `json:"length,omitempty"`
	Author    string          `json:"author"`
	Timestamp time.Time       `json:"timestamp"`
	Vector    OperationVector `json:"vector"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

// OperationType defines the type of operation
type OperationType int

const (
	OpInsert OperationType = iota
	OpDelete
	OpRetain
	OpCursorMove
	OpSelection
)

// OperationVector represents a vector clock for operations
type OperationVector map[string]int64

// CollaborationConfig configures the collaboration engine
type CollaborationConfig struct {
	EnableRealTimeSync     bool          `json:"enable_real_time_sync"`
	EnableConflictDetection bool         `json:"enable_conflict_detection"`
	SyncInterval           time.Duration `json:"sync_interval"`
	OperationBufferSize    int           `json:"operation_buffer_size"`
	MaxPendingOperations   int           `json:"max_pending_operations"`
	ConflictRetryDelay     time.Duration `json:"conflict_retry_delay"`
	HeartbeatInterval      time.Duration `json:"heartbeat_interval"`
}

// ConflictResolution represents a resolved conflict
type ConflictResolution struct {
	ConflictID   string      `json:"conflict_id"`
	LocalOp      Operation   `json:"local_op"`
	RemoteOp     Operation   `json:"remote_op"`
	Resolution   Operation   `json:"resolution"`
	Strategy     string      `json:"strategy"`
	ResolvedAt   time.Time   `json:"resolved_at"`
}

// NewCollaborationEngine creates a new collaboration engine
func NewCollaborationEngine(rpcClient *rpc.Client, eventStream *events.EventStreamManager) *CollaborationEngine {
	ctx, cancel := context.WithCancel(context.Background())
	
	config := CollaborationConfig{
		EnableRealTimeSync:      true,
		EnableConflictDetection: true,
		SyncInterval:           100 * time.Millisecond,
		OperationBufferSize:    1000,
		MaxPendingOperations:   50,
		ConflictRetryDelay:     500 * time.Millisecond,
		HeartbeatInterval:      5 * time.Second,
	}
	
	ce := &CollaborationEngine{
		rpcClient:        rpcClient,
		eventStream:      eventStream,
		localVector:      make(OperationVector),
		remoteVector:     make(OperationVector),
		pendingOps:       make([]Operation, 0),
		ackedOps:         make([]Operation, 0),
		collaborators:    make(map[string]*Collaborator),
		localUserID:      generateUserID(),
		conflictResolver: NewConflictResolver(),
		transformEngine:  NewTransformEngine(),
		config:          config,
		ctx:             ctx,
		cancel:          cancel,
	}
	
	return ce
}

// Start begins collaborative editing session
func (ce *CollaborationEngine) Start(documentID string) error {
	ce.mutex.Lock()
	defer ce.mutex.Unlock()
	
	if ce.running {
		return fmt.Errorf("collaboration engine already running")
	}
	
	ce.documentID = documentID
	ce.running = true
	
	// Join collaboration session
	if err := ce.joinSession(); err != nil {
		return fmt.Errorf("failed to join session: %w", err)
	}
	
	// Start background processes
	go ce.syncLoop()
	go ce.heartbeatLoop()
	go ce.conflictResolutionLoop()
	
	return nil
}

// Stop ends collaborative editing session
func (ce *CollaborationEngine) Stop() error {
	ce.mutex.Lock()
	defer ce.mutex.Unlock()
	
	if !ce.running {
		return fmt.Errorf("collaboration engine not running")
	}
	
	ce.running = false
	ce.cancel()
	
	// Leave collaboration session
	ce.leaveSession()
	
	return nil
}

// ApplyLocalOperation applies a local operation and prepares for synchronization
func (ce *CollaborationEngine) ApplyLocalOperation(op Operation) error {
	ce.mutex.Lock()
	defer ce.mutex.Unlock()
	
	// Set operation metadata
	op.ID = generateOperationID()
	op.Author = ce.localUserID
	op.Timestamp = time.Now()
	op.Vector = ce.incrementVector(ce.localVector, ce.localUserID)
	
	// Add to pending operations
	ce.pendingOps = append(ce.pendingOps, op)
	
	// Limit pending operations
	if len(ce.pendingOps) > ce.config.MaxPendingOperations {
		ce.pendingOps = ce.pendingOps[1:]
	}
	
	// Send operation to other collaborators
	if ce.config.EnableRealTimeSync {
		go ce.sendOperation(op)
	}
	
	// Send to event stream
	if ce.eventStream != nil {
		ce.sendOperationEvent(op)
	}
	
	return nil
}

// ApplyRemoteOperation applies an operation received from another collaborator
func (ce *CollaborationEngine) ApplyRemoteOperation(op Operation) error {
	ce.mutex.Lock()
	defer ce.mutex.Unlock()
	
	// Check if we've already seen this operation
	if ce.hasSeenOperation(op) {
		return nil
	}
	
	// Transform operation against pending local operations
	transformedOp, err := ce.transformEngine.TransformOperation(op, ce.pendingOps)
	if err != nil {
		return fmt.Errorf("failed to transform operation: %w", err)
	}
	
	// Apply transformation
	ce.applyTransformedOperation(transformedOp)
	
	// Update remote vector
	ce.remoteVector = ce.mergeVectors(ce.remoteVector, op.Vector)
	
	// Update collaborator state
	ce.updateCollaboratorFromOperation(op)
	
	// Send to event stream
	if ce.eventStream != nil {
		ce.sendOperationEvent(transformedOp)
	}
	
	return nil
}

// UpdateCursor updates the local cursor position and broadcasts to collaborators
func (ce *CollaborationEngine) UpdateCursor(position CursorPosition) error {
	ce.mutex.Lock()
	defer ce.mutex.Unlock()
	
	ce.localCursor = position
	
	// Create cursor operation
	op := Operation{
		ID:        generateOperationID(),
		Type:      OpCursorMove,
		Position:  position.Line*1000 + position.Column, // Simple position encoding
		Author:    ce.localUserID,
		Timestamp: time.Now(),
		Vector:    ce.localVector,
		Metadata: map[string]interface{}{
			"cursor_line":   position.Line,
			"cursor_column": position.Column,
		},
	}
	
	// Send cursor update
	go ce.sendOperation(op)
	
	return nil
}

// GetCollaborators returns current collaborators
func (ce *CollaborationEngine) GetCollaborators() map[string]*Collaborator {
	ce.mutex.RLock()
	defer ce.mutex.RUnlock()
	
	result := make(map[string]*Collaborator)
	for id, collaborator := range ce.collaborators {
		result[id] = collaborator
	}
	return result
}

// Internal methods
func (ce *CollaborationEngine) joinSession() error {
	ctx, cancel := context.WithTimeout(ce.ctx, 10*time.Second)
	defer cancel()
	
	request := map[string]interface{}{
		"document_id": ce.documentID,
		"user_id":     ce.localUserID,
		"vector":      ce.localVector,
	}
	
	response, err := ce.rpcClient.Call(ctx, "collaboration.join_session", request)
	if err != nil {
		return err
	}
	
	// Process join response
	var joinData map[string]interface{}
	if err := json.Unmarshal(response, &joinData); err != nil {
		return err
	}
	
	// Update state from server
	ce.processJoinResponse(joinData)
	
	return nil
}

func (ce *CollaborationEngine) leaveSession() {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	
	request := map[string]interface{}{
		"document_id": ce.documentID,
		"user_id":     ce.localUserID,
	}
	
	ce.rpcClient.Call(ctx, "collaboration.leave_session", request)
}

func (ce *CollaborationEngine) sendOperation(op Operation) {
	ctx, cancel := context.WithTimeout(ce.ctx, 5*time.Second)
	defer cancel()
	
	request := map[string]interface{}{
		"document_id": ce.documentID,
		"operation":   op,
	}
	
	response, err := ce.rpcClient.Call(ctx, "collaboration.send_operation", request)
	if err != nil {
		// Handle send failure
		ce.handleSendFailure(op, err)
		return
	}
	
	// Process acknowledgment
	var ackData map[string]interface{}
	if err := json.Unmarshal(response, &ackData); err == nil {
		ce.processOperationAck(op, ackData)
	}
}

func (ce *CollaborationEngine) syncLoop() {
	ticker := time.NewTicker(ce.config.SyncInterval)
	defer ticker.Stop()
	
	for {
		select {
		case <-ce.ctx.Done():
			return
		case <-ticker.C:
			ce.performSync()
		}
	}
}

func (ce *CollaborationEngine) heartbeatLoop() {
	ticker := time.NewTicker(ce.config.HeartbeatInterval)
	defer ticker.Stop()
	
	for {
		select {
		case <-ce.ctx.Done():
			return
		case <-ticker.C:
			ce.sendHeartbeat()
		}
	}
}

func (ce *CollaborationEngine) conflictResolutionLoop() {
	ticker := time.NewTicker(ce.config.ConflictRetryDelay)
	defer ticker.Stop()
	
	for {
		select {
		case <-ce.ctx.Done():
			return
		case <-ticker.C:
			ce.resolveConflicts()
		}
	}
}

func (ce *CollaborationEngine) performSync() {
	// Implementation for periodic synchronization
}

func (ce *CollaborationEngine) sendHeartbeat() {
	ctx, cancel := context.WithTimeout(ce.ctx, 3*time.Second)
	defer cancel()
	
	request := map[string]interface{}{
		"document_id": ce.documentID,
		"user_id":     ce.localUserID,
		"cursor":      ce.localCursor,
		"active":      true,
	}
	
	ce.rpcClient.Call(ctx, "collaboration.heartbeat", request)
}

func (ce *CollaborationEngine) resolveConflicts() {
	// Implementation for conflict resolution
}

// Helper functions
func (ce *CollaborationEngine) incrementVector(vector OperationVector, userID string) OperationVector {
	newVector := make(OperationVector)
	for k, v := range vector {
		newVector[k] = v
	}
	newVector[userID]++
	return newVector
}

func (ce *CollaborationEngine) mergeVectors(local, remote OperationVector) OperationVector {
	merged := make(OperationVector)
	
	// Copy local vector
	for k, v := range local {
		merged[k] = v
	}
	
	// Merge remote vector (take max)
	for k, v := range remote {
		if existing, exists := merged[k]; !exists || v > existing {
			merged[k] = v
		}
	}
	
	return merged
}

func (ce *CollaborationEngine) hasSeenOperation(op Operation) bool {
	if localTime, exists := ce.remoteVector[op.Author]; exists {
		if opTime, exists := op.Vector[op.Author]; exists {
			return opTime <= localTime
		}
	}
	return false
}

func (ce *CollaborationEngine) applyTransformedOperation(op Operation) {
	// Apply the operation to the document
	// This would integrate with the editor's content management
}

func (ce *CollaborationEngine) updateCollaboratorFromOperation(op Operation) {
	if collaborator, exists := ce.collaborators[op.Author]; exists {
		collaborator.Active = true
		if op.Type == OpCursorMove {
			if line, ok := op.Metadata["cursor_line"].(int); ok {
				collaborator.Cursor.Line = line
			}
			if column, ok := op.Metadata["cursor_column"].(int); ok {
				collaborator.Cursor.Column = column
			}
		}
	} else {
		// Create new collaborator
		ce.collaborators[op.Author] = &Collaborator{
			ID:     op.Author,
			Name:   fmt.Sprintf("User-%s", op.Author[:8]),
			Color:  generateUserColor(op.Author),
			Active: true,
		}
	}
}

func (ce *CollaborationEngine) sendOperationEvent(op Operation) {
	event := events.StreamEvent{
		ID:       fmt.Sprintf("collab_op_%s", op.ID),
		Type:     "collaboration_operation",
		Category: events.CategoryUser,
		Priority: events.PriorityNormal,
		Payload:  op,
		Metadata: map[string]interface{}{
			"document_id": ce.documentID,
			"author":      op.Author,
			"op_type":     op.Type,
		},
		Timestamp: op.Timestamp,
		Source:    "collaboration_engine",
	}
	
	ce.eventStream.ProcessEvent(event)
}

func (ce *CollaborationEngine) processJoinResponse(data map[string]interface{}) {
	// Process collaborators
	if collaborators, ok := data["collaborators"].(map[string]interface{}); ok {
		for id, collabData := range collaborators {
			if collabMap, ok := collabData.(map[string]interface{}); ok {
				collaborator := &Collaborator{
					ID:     id,
					Active: true,
				}
				if name, ok := collabMap["name"].(string); ok {
					collaborator.Name = name
				}
				if color, ok := collabMap["color"].(string); ok {
					collaborator.Color = color
				}
				ce.collaborators[id] = collaborator
			}
		}
	}
}

func (ce *CollaborationEngine) processOperationAck(op Operation, ackData map[string]interface{}) {
	// Move operation from pending to acknowledged
	ce.ackedOps = append(ce.ackedOps, op)
	
	// Remove from pending
	for i, pendingOp := range ce.pendingOps {
		if pendingOp.ID == op.ID {
			ce.pendingOps = append(ce.pendingOps[:i], ce.pendingOps[i+1:]...)
			break
		}
	}
}

func (ce *CollaborationEngine) handleSendFailure(op Operation, err error) {
	// Add operation to retry queue or handle failure
}

// Utility functions
func generateUserID() string {
	return fmt.Sprintf("user_%d", time.Now().UnixNano())
}

func generateOperationID() string {
	return fmt.Sprintf("op_%d", time.Now().UnixNano())
}

func generateUserColor(userID string) string {
	colors := []string{"#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8"}
	hash := 0
	for _, char := range userID {
		hash += int(char)
	}
	return colors[hash%len(colors)]
}

// Placeholder implementations for supporting types
type ConflictResolver struct{}
func NewConflictResolver() *ConflictResolver { return &ConflictResolver{} }

type TransformEngine struct{}
func NewTransformEngine() *TransformEngine { return &TransformEngine{} }

func (te *TransformEngine) TransformOperation(op Operation, pendingOps []Operation) (Operation, error) {
	// Implementation for operational transform
	return op, nil
}
