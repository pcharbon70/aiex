package rpc

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/creachadair/jrpc2"
	"github.com/creachadair/jrpc2/channel"
	"github.com/gorilla/websocket"
	"aiex-tui/pkg/types"
)

// Client represents the JSON-RPC client for communicating with Elixir backend
type Client struct {
	nodes          []string
	currentNode    int
	conn           *websocket.Conn
	rpcConn        *jrpc2.Client
	handlers       map[string]NotificationHandler
	reconnector    *ReconnectionManager
	circuitBreaker *CircuitBreaker
	mutex          sync.RWMutex
	connected      bool
	program        *tea.Program
}

// NotificationHandler defines the interface for handling server notifications
type NotificationHandler func(params json.RawMessage) tea.Cmd

// NewClient creates a new JSON-RPC client
func NewClient(nodes []string) *Client {
	client := &Client{
		nodes:          nodes,
		handlers:       make(map[string]NotificationHandler),
		reconnector:    NewReconnectionManager(nodes),
		circuitBreaker: NewCircuitBreaker(),
		connected:      false,
	}

	// Register default notification handlers
	client.RegisterHandler("ai.response", client.handleAIResponse)
	client.RegisterHandler("ai.streaming_chunk", client.handleStreamingChunk)
	client.RegisterHandler("code.suggestion", client.handleCodeSuggestion)
	client.RegisterHandler("state.update", client.handleStateUpdate)
	client.RegisterHandler("file.changed", client.handleFileChanged)
	client.RegisterHandler("context.updated", client.handleContextUpdate)

	return client
}

// Connect establishes connection to the Elixir backend
func (c *Client) Connect(ctx context.Context) error {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	if c.circuitBreaker.IsOpen() {
		return fmt.Errorf("circuit breaker is open")
	}

	conn, err := c.reconnector.ConnectWithFailover()
	if err != nil {
		c.circuitBreaker.RecordFailure()
		return fmt.Errorf("failed to connect: %w", err)
	}

	c.conn = conn
	
	// Create bidirectional RPC connection
	stream := &WebSocketStream{conn: conn}
	ch := channel.RawJSON(stream, stream)
	c.rpcConn = jrpc2.NewClient(ch, nil)

	c.connected = true
	c.circuitBreaker.RecordSuccess()

	// Send connection established message to UI
	if c.program != nil {
		c.program.Send(ConnectionEstablishedMsg{})
	}

	return nil
}

// Disconnect closes the connection
func (c *Client) Disconnect() error {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	c.connected = false

	if c.rpcConn != nil {
		c.rpcConn.Close()
		c.rpcConn = nil
	}

	if c.conn != nil {
		c.conn.Close()
		c.conn = nil
	}

	return nil
}

// Call makes a synchronous RPC call
func (c *Client) Call(ctx context.Context, method string, params interface{}) (json.RawMessage, error) {
	c.mutex.RLock()
	defer c.mutex.RUnlock()

	if !c.connected || c.rpcConn == nil {
		return nil, fmt.Errorf("not connected")
	}

	if c.circuitBreaker.IsOpen() {
		return nil, fmt.Errorf("circuit breaker is open")
	}

	var result json.RawMessage
	err := c.rpcConn.CallResult(ctx, method, params, &result)
	if err != nil {
		c.circuitBreaker.RecordFailure()
		return nil, err
	}

	c.circuitBreaker.RecordSuccess()
	return result, nil
}

// Notify sends a notification (fire-and-forget)
func (c *Client) Notify(ctx context.Context, method string, params interface{}) error {
	c.mutex.RLock()
	defer c.mutex.RUnlock()

	if !c.connected || c.rpcConn == nil {
		return fmt.Errorf("not connected")
	}

	return c.rpcConn.Notify(ctx, method, params)
}

// RegisterHandler registers a notification handler
func (c *Client) RegisterHandler(method string, handler NotificationHandler) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.handlers[method] = handler
}

// StartEventStream starts the event stream processing
func (c *Client) StartEventStream(ctx context.Context, program *tea.Program) error {
	c.program = program

	// Connect to backend
	if err := c.Connect(ctx); err != nil {
		return err
	}

	// Start reconnection monitoring
	go c.monitorConnection(ctx)

	return nil
}

// handleNotification processes incoming notifications from the server
func (c *Client) handleNotification(method string, params json.RawMessage) {
	// method parameter is already provided
	
	c.mutex.RLock()
	handler, exists := c.handlers[method]
	c.mutex.RUnlock()

	if !exists {
		log.Printf("No handler for notification: %s", method)
		return
	}

	// params are already provided as parameter

	// Execute handler and send command to UI
	if cmd := handler(params); cmd != nil && c.program != nil {
		c.program.Send(cmd)
	}
}

// Default notification handlers
func (c *Client) handleAIResponse(params json.RawMessage) tea.Cmd {
	var response types.AIResponse
	if err := json.Unmarshal(params, &response); err != nil {
		log.Printf("Failed to unmarshal AI response: %v", err)
		return nil
	}

	return func() tea.Msg {
		return AIResponseMsg{Response: response}
	}
}

func (c *Client) handleStreamingChunk(params json.RawMessage) tea.Cmd {
	var chunk types.StreamingChunk
	if err := json.Unmarshal(params, &chunk); err != nil {
		log.Printf("Failed to unmarshal streaming chunk: %v", err)
		return nil
	}

	return func() tea.Msg {
		return StreamingChunkMsg{Chunk: chunk}
	}
}

func (c *Client) handleCodeSuggestion(params json.RawMessage) tea.Cmd {
	var suggestion types.CodeSuggestion
	if err := json.Unmarshal(params, &suggestion); err != nil {
		log.Printf("Failed to unmarshal code suggestion: %v", err)
		return nil
	}

	return func() tea.Msg {
		return CodeSuggestionMsg{Suggestion: suggestion}
	}
}

func (c *Client) handleStateUpdate(params json.RawMessage) tea.Cmd {
	var update types.StateUpdate
	if err := json.Unmarshal(params, &update); err != nil {
		log.Printf("Failed to unmarshal state update: %v", err)
		return nil
	}

	return func() tea.Msg {
		return StateUpdateMsg{Update: update}
	}
}

func (c *Client) handleFileChanged(params json.RawMessage) tea.Cmd {
	var change types.FileChange
	if err := json.Unmarshal(params, &change); err != nil {
		log.Printf("Failed to unmarshal file change: %v", err)
		return nil
	}

	return func() tea.Msg {
		return FileChangedMsg{Change: change}
	}
}

func (c *Client) handleContextUpdate(params json.RawMessage) tea.Cmd {
	var context types.ContextUpdate
	if err := json.Unmarshal(params, &context); err != nil {
		log.Printf("Failed to unmarshal context update: %v", err)
		return nil
	}

	return func() tea.Msg {
		return ContextUpdateMsg{Context: context}
	}
}

// monitorConnection handles automatic reconnection
func (c *Client) monitorConnection(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			c.mutex.RLock()
			connected := c.connected
			c.mutex.RUnlock()

			if !connected {
				log.Println("Connection lost, attempting to reconnect...")
				if c.program != nil {
					c.program.Send(ConnectionLostMsg{})
				}

				if err := c.Connect(ctx); err != nil {
					log.Printf("Reconnection failed: %v", err)
				}
			}
		}
	}
}

// Message types for UI updates
type ConnectionEstablishedMsg struct{}
type ConnectionLostMsg struct{}
type AIResponseMsg struct {
	Response types.AIResponse
}
type StreamingChunkMsg struct {
	Chunk types.StreamingChunk
}
type CodeSuggestionMsg struct {
	Suggestion types.CodeSuggestion
}
type StateUpdateMsg struct {
	Update types.StateUpdate
}
type FileChangedMsg struct {
	Change types.FileChange
}
type ContextUpdateMsg struct {
	Context types.ContextUpdate
}