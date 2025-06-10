package chat

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"aiex-tui/internal/events"
	"aiex-tui/internal/rpc"
	"aiex-tui/pkg/types"
)

// StreamingEngine handles real-time AI response streaming
type StreamingEngine struct {
	// Core components
	rpcClient    *rpc.Client
	eventStream  *events.EventStreamManager

	// Streaming state
	activeStreams map[string]*StreamSession
	streamBuffer  *StreamBuffer

	// Configuration
	config       StreamingConfig

	// Synchronization
	mutex        sync.RWMutex
	running      bool

	// Context
	ctx          context.Context
	cancel       context.CancelFunc
}

// StreamingConfig configures the streaming engine
type StreamingConfig struct {
	BufferSize       int           `json:"buffer_size"`
	FlushInterval    time.Duration `json:"flush_interval"`
	Timeout          time.Duration `json:"timeout"`
	MaxConcurrentStreams int       `json:"max_concurrent_streams"`
	RetryAttempts    int           `json:"retry_attempts"`
	RetryDelay       time.Duration `json:"retry_delay"`
	EnableMetrics    bool          `json:"enable_metrics"`
}

// StreamSession represents an active streaming session
type StreamSession struct {
	ID             string                 `json:"id"`
	ConversationID string                 `json:"conversation_id"`
	Provider       string                 `json:"provider"`
	Message        types.Message          `json:"message"`
	StartTime      time.Time              `json:"start_time"`
	LastUpdate     time.Time              `json:"last_update"`
	Status         StreamStatus           `json:"status"`
	Content        string                 `json:"content"`
	Metadata       map[string]interface{} `json:"metadata"`
	Error          error                  `json:"error,omitempty"`
	mutex          sync.RWMutex
}

// StreamStatus represents the status of a streaming session
type StreamStatus int

const (
	StreamStatusPending StreamStatus = iota
	StreamStatusActive
	StreamStatusComplete
	StreamStatusError
	StreamStatusCancelled
)

// StreamBuffer manages buffered streaming content
type StreamBuffer struct {
	buffers   map[string]*ContentBuffer
	flushInterval time.Duration
	mutex     sync.RWMutex
}

// ContentBuffer buffers streaming content for smooth display
type ContentBuffer struct {
	Content      string
	Deltas       []string
	LastFlush    time.Time
	PendingFlush bool
}

// StreamingResponse represents a streaming response chunk
type StreamingResponse struct {
	ID           string                 `json:"id"`
	Delta        string                 `json:"delta"`
	Content      string                 `json:"content"`
	Finished     bool                   `json:"finished"`
	Metadata     map[string]interface{} `json:"metadata,omitempty"`
	Error        string                 `json:"error,omitempty"`
	Timestamp    time.Time              `json:"timestamp"`
}

// NewStreamingEngine creates a new streaming engine
func NewStreamingEngine(rpcClient *rpc.Client, eventStream *events.EventStreamManager) *StreamingEngine {
	ctx, cancel := context.WithCancel(context.Background())

	config := StreamingConfig{
		BufferSize:           1024,
		FlushInterval:        50 * time.Millisecond,
		Timeout:              30 * time.Second,
		MaxConcurrentStreams: 5,
		RetryAttempts:        3,
		RetryDelay:           1 * time.Second,
		EnableMetrics:        true,
	}

	se := &StreamingEngine{
		rpcClient:     rpcClient,
		eventStream:   eventStream,
		activeStreams: make(map[string]*StreamSession),
		streamBuffer:  NewStreamBuffer(config.FlushInterval),
		config:        config,
		ctx:           ctx,
		cancel:        cancel,
	}

	return se
}

// Start begins streaming services
func (se *StreamingEngine) Start() error {
	se.mutex.Lock()
	defer se.mutex.Unlock()

	if se.running {
		return fmt.Errorf("streaming engine already running")
	}

	se.running = true

	// Start buffer flushing
	go se.bufferFlushLoop()

	// Start stream monitoring
	go se.streamMonitoringLoop()

	return nil
}

// Stop ends streaming services
func (se *StreamingEngine) Stop() error {
	se.mutex.Lock()
	defer se.mutex.Unlock()

	if !se.running {
		return fmt.Errorf("streaming engine not running")
	}

	se.running = false
	se.cancel()

	// Cancel all active streams
	for _, session := range se.activeStreams {
		se.cancelStream(session.ID)
	}

	return nil
}

// SendStreamingMessage initiates a streaming AI response
func (se *StreamingEngine) SendStreamingMessage(message types.Message, providerID string) tea.Cmd {
	return func() tea.Msg {
		se.mutex.Lock()
		defer se.mutex.Unlock()

		// Check concurrent stream limit
		if len(se.activeStreams) >= se.config.MaxConcurrentStreams {
			return StreamingErrorMsg{
				Error: fmt.Errorf("maximum concurrent streams reached"),
			}
		}

		// Create stream session
		sessionID := se.generateStreamID()
		session := &StreamSession{
			ID:             sessionID,
			ConversationID: message.ConversationID,
			Provider:       providerID,
			Message:        message,
			StartTime:      time.Now(),
			LastUpdate:     time.Now(),
			Status:         StreamStatusPending,
			Content:        "",
			Metadata:       make(map[string]interface{}),
		}

		se.activeStreams[sessionID] = session

		// Start streaming
		go se.processStreamingRequest(session)

		return StreamingStartedMsg{
			SessionID:      sessionID,
			ConversationID: message.ConversationID,
		}
	}
}

// processStreamingRequest handles the actual streaming request
func (se *StreamingEngine) processStreamingRequest(session *StreamSession) {
	ctx, cancel := context.WithTimeout(se.ctx, se.config.Timeout)
	defer cancel()

	// Update session status
	session.mutex.Lock()
	session.Status = StreamStatusActive
	session.mutex.Unlock()

	// Build streaming request
	request := map[string]interface{}{
		"message":         session.Message,
		"provider":        session.Provider,
		"conversation_id": session.ConversationID,
		"stream":          true,
		"session_id":      session.ID,
	}

	// Send streaming request to Elixir backend
	responseStream, err := se.rpcClient.CallStream(ctx, "ai.stream_message", request)
	if err != nil {
		se.handleStreamError(session.ID, err)
		return
	}

	// Process streaming responses
	for {
		select {
		case <-ctx.Done():
			se.handleStreamTimeout(session.ID)
			return

		case response, ok := <-responseStream:
			if !ok {
				// Stream closed
				se.completeStream(session.ID)
				return
			}

			// Process response chunk
			se.processStreamChunk(session.ID, response)
		}
	}
}

// processStreamChunk processes a single streaming response chunk
func (se *StreamingEngine) processStreamChunk(sessionID string, rawResponse []byte) {
	var response StreamingResponse
	if err := json.Unmarshal(rawResponse, &response); err != nil {
		se.handleStreamError(sessionID, err)
		return
	}

	session, exists := se.activeStreams[sessionID]
	if !exists {
		return
	}

	// Handle error in response
	if response.Error != "" {
		se.handleStreamError(sessionID, fmt.Errorf("stream error: %s", response.Error))
		return
	}

	// Update session content
	session.mutex.Lock()
	if response.Delta != "" {
		session.Content += response.Delta
	} else if response.Content != "" {
		session.Content = response.Content
	}
	session.LastUpdate = time.Now()
	session.mutex.Unlock()

	// Add to buffer for smooth display
	se.streamBuffer.AddDelta(sessionID, response.Delta)

	// Send streaming update event
	se.sendStreamingEvent(sessionID, response)

	// Check if stream is finished
	if response.Finished {
		se.completeStream(sessionID)
	}
}

// completeStream marks a stream as completed
func (se *StreamingEngine) completeStream(sessionID string) {
	se.mutex.Lock()
	defer se.mutex.Unlock()

	session, exists := se.activeStreams[sessionID]
	if !exists {
		return
	}

	session.mutex.Lock()
	session.Status = StreamStatusComplete
	session.mutex.Unlock()

	// Send completion event
	se.sendCompletionEvent(session)

	// Clean up
	delete(se.activeStreams, sessionID)
	se.streamBuffer.Remove(sessionID)
}

// handleStreamError handles streaming errors
func (se *StreamingEngine) handleStreamError(sessionID string, err error) {
	se.mutex.Lock()
	defer se.mutex.Unlock()

	session, exists := se.activeStreams[sessionID]
	if !exists {
		return
	}

	session.mutex.Lock()
	session.Status = StreamStatusError
	session.Error = err
	session.mutex.Unlock()

	// Send error event
	se.sendErrorEvent(session, err)

	// Clean up
	delete(se.activeStreams, sessionID)
	se.streamBuffer.Remove(sessionID)
}

// handleStreamTimeout handles streaming timeouts
func (se *StreamingEngine) handleStreamTimeout(sessionID string) {
	se.handleStreamError(sessionID, fmt.Errorf("stream timeout"))
}

// cancelStream cancels an active stream
func (se *StreamingEngine) cancelStream(sessionID string) {
	se.mutex.Lock()
	defer se.mutex.Unlock()

	session, exists := se.activeStreams[sessionID]
	if !exists {
		return
	}

	session.mutex.Lock()
	session.Status = StreamStatusCancelled
	session.mutex.Unlock()

	// Send cancellation event
	se.sendCancellationEvent(session)

	// Clean up
	delete(se.activeStreams, sessionID)
	se.streamBuffer.Remove(sessionID)
}

// Event sending methods
func (se *StreamingEngine) sendStreamingEvent(sessionID string, response StreamingResponse) {
	if se.eventStream != nil {
		event := events.StreamEvent{
			ID:       fmt.Sprintf("stream_update_%s", sessionID),
			Type:     "ai_streaming_update",
			Category: events.CategoryAIResponse,
			Priority: events.PriorityHigh,
			Payload: StreamingMessageMsg{
				ID:             sessionID,
				ConversationID: se.activeStreams[sessionID].ConversationID,
				Content:        se.activeStreams[sessionID].Content,
				Delta:          response.Delta,
				Complete:       response.Finished,
				Timestamp:      response.Timestamp,
				Metadata:       response.Metadata,
			},
			Timestamp: response.Timestamp,
			Source:    "streaming_engine",
		}

		se.eventStream.ProcessEvent(event)
	}
}

func (se *StreamingEngine) sendCompletionEvent(session *StreamSession) {
	if se.eventStream != nil {
		event := events.StreamEvent{
			ID:       fmt.Sprintf("stream_complete_%s", session.ID),
			Type:     "ai_streaming_complete",
			Category: events.CategoryAIResponse,
			Priority: events.PriorityNormal,
			Payload: StreamingMessageMsg{
				ID:             session.ID,
				ConversationID: session.ConversationID,
				Content:        session.Content,
				Complete:       true,
				Timestamp:      time.Now(),
				Metadata:       session.Metadata,
			},
			Timestamp: time.Now(),
			Source:    "streaming_engine",
		}

		se.eventStream.ProcessEvent(event)
	}
}

func (se *StreamingEngine) sendErrorEvent(session *StreamSession, err error) {
	if se.eventStream != nil {
		event := events.StreamEvent{
			ID:       fmt.Sprintf("stream_error_%s", session.ID),
			Type:     "ai_streaming_error",
			Category: events.CategoryError,
			Priority: events.PriorityHigh,
			Payload: map[string]interface{}{
				"session_id":      session.ID,
				"conversation_id": session.ConversationID,
				"error":           err.Error(),
				"provider":        session.Provider,
			},
			Timestamp: time.Now(),
			Source:    "streaming_engine",
		}

		se.eventStream.ProcessEvent(event)
	}
}

func (se *StreamingEngine) sendCancellationEvent(session *StreamSession) {
	if se.eventStream != nil {
		event := events.StreamEvent{
			ID:       fmt.Sprintf("stream_cancel_%s", session.ID),
			Type:     "ai_streaming_cancelled",
			Category: events.CategorySystem,
			Priority: events.PriorityNormal,
			Payload: map[string]interface{}{
				"session_id":      session.ID,
				"conversation_id": session.ConversationID,
				"provider":        session.Provider,
			},
			Timestamp: time.Now(),
			Source:    "streaming_engine",
		}

		se.eventStream.ProcessEvent(event)
	}
}

// Background loops
func (se *StreamingEngine) bufferFlushLoop() {
	ticker := time.NewTicker(se.config.FlushInterval)
	defer ticker.Stop()

	for {
		select {
		case <-se.ctx.Done():
			return
		case <-ticker.C:
			se.streamBuffer.FlushPending()
		}
	}
}

func (se *StreamingEngine) streamMonitoringLoop() {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-se.ctx.Done():
			return
		case <-ticker.C:
			se.monitorActiveStreams()
		}
	}
}

func (se *StreamingEngine) monitorActiveStreams() {
	se.mutex.RLock()
	defer se.mutex.RUnlock()

	now := time.Now()
	for sessionID, session := range se.activeStreams {
		session.mutex.RLock()
		lastUpdate := session.LastUpdate
		status := session.Status
		session.mutex.RUnlock()

		// Check for stale streams
		if status == StreamStatusActive && now.Sub(lastUpdate) > se.config.Timeout {
			go se.handleStreamTimeout(sessionID)
		}
	}
}

// Utility methods
func (se *StreamingEngine) IsStreaming() bool {
	se.mutex.RLock()
	defer se.mutex.RUnlock()
	return len(se.activeStreams) > 0
}

func (se *StreamingEngine) GetActiveStreamCount() int {
	se.mutex.RLock()
	defer se.mutex.RUnlock()
	return len(se.activeStreams)
}

func (se *StreamingEngine) generateStreamID() string {
	return fmt.Sprintf("stream_%d", time.Now().UnixNano())
}

// StreamBuffer implementation
func NewStreamBuffer(flushInterval time.Duration) *StreamBuffer {
	return &StreamBuffer{
		buffers:       make(map[string]*ContentBuffer),
		flushInterval: flushInterval,
	}
}

func (sb *StreamBuffer) AddDelta(sessionID, delta string) {
	sb.mutex.Lock()
	defer sb.mutex.Unlock()

	buffer, exists := sb.buffers[sessionID]
	if !exists {
		buffer = &ContentBuffer{
			Content:      "",
			Deltas:       make([]string, 0),
			LastFlush:    time.Now(),
			PendingFlush: false,
		}
		sb.buffers[sessionID] = buffer
	}

	buffer.Content += delta
	buffer.Deltas = append(buffer.Deltas, delta)
	buffer.PendingFlush = true
}

func (sb *StreamBuffer) FlushPending() {
	sb.mutex.Lock()
	defer sb.mutex.Unlock()

	for sessionID, buffer := range sb.buffers {
		if buffer.PendingFlush && time.Since(buffer.LastFlush) >= sb.flushInterval {
			buffer.LastFlush = time.Now()
			buffer.PendingFlush = false
			// In a real implementation, this would trigger a UI update
			_ = sessionID // Use sessionID to trigger update
		}
	}
}

func (sb *StreamBuffer) Remove(sessionID string) {
	sb.mutex.Lock()
	defer sb.mutex.Unlock()
	delete(sb.buffers, sessionID)
}

func (sb *StreamBuffer) GetContent(sessionID string) string {
	sb.mutex.RLock()
	defer sb.mutex.RUnlock()

	if buffer, exists := sb.buffers[sessionID]; exists {
		return buffer.Content
	}
	return ""
}

// Message types
type StreamingStartedMsg struct {
	SessionID      string
	ConversationID string
}

type StreamingErrorMsg struct {
	Error error
}
