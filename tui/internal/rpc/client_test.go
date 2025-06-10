package rpc

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Mock WebSocket server for testing
type MockWSServer struct {
	listener   net.Listener
	upgrader   websocket.Upgrader
	connections map[*websocket.Conn]bool
	handlers   map[string]func([]byte) (interface{}, error)
	mutex      sync.RWMutex
	running    bool
}

func NewMockWSServer() *MockWSServer {
	return &MockWSServer{
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		},
		connections: make(map[*websocket.Conn]bool),
		handlers:    make(map[string]func([]byte) (interface{}, error)),
	}
}

func (s *MockWSServer) Start(addr string) error {
	var err error
	s.listener, err = net.Listen("tcp", addr)
	if err != nil {
		return err
	}

	s.running = true
	go s.acceptConnections()
	return nil
}

func (s *MockWSServer) Stop() error {
	s.running = false
	if s.listener != nil {
		return s.listener.Close()
	}
	return nil
}

func (s *MockWSServer) GetAddr() string {
	if s.listener != nil {
		return s.listener.Addr().String()
	}
	return ""
}

func (s *MockWSServer) SetHandler(method string, handler func([]byte) (interface{}, error)) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.handlers[method] = handler
}

func (s *MockWSServer) acceptConnections() {
	for s.running {
		conn, err := s.listener.Accept()
		if err != nil {
			continue
		}

		ws, err := s.upgrader.Upgrade(&mockResponseWriter{}, &mockRequest{}, nil)
		if err != nil {
			continue
		}

		s.mutex.Lock()
		s.connections[ws] = true
		s.mutex.Unlock()

		go s.handleConnection(ws)
	}
}

func (s *MockWSServer) handleConnection(ws *websocket.Conn) {
	defer func() {
		s.mutex.Lock()
		delete(s.connections, ws)
		s.mutex.Unlock()
		ws.Close()
	}()

	for {
		_, message, err := ws.ReadMessage()
		if err != nil {
			break
		}

		var request JSONRPCRequest
		if err := json.Unmarshal(message, &request); err != nil {
			continue
		}

		response := s.processRequest(request)
		responseData, _ := json.Marshal(response)
		ws.WriteMessage(websocket.TextMessage, responseData)
	}
}

func (s *MockWSServer) processRequest(request JSONRPCRequest) JSONRPCResponse {
	s.mutex.RLock()
	handler, exists := s.handlers[request.Method]
	s.mutex.RUnlock()

	if !exists {
		return JSONRPCResponse{
			ID:      request.ID,
			JSONRPC: "2.0",
			Error: &JSONRPCError{
				Code:    -32601,
				Message: "Method not found",
			},
		}
	}

	params, _ := json.Marshal(request.Params)
	result, err := handler(params)
	if err != nil {
		return JSONRPCResponse{
			ID:      request.ID,
			JSONRPC: "2.0",
			Error: &JSONRPCError{
				Code:    -32603,
				Message: err.Error(),
			},
		}
	}

	return JSONRPCResponse{
		ID:      request.ID,
		JSONRPC: "2.0",
		Result:  result,
	}
}

// Mock HTTP types for websocket upgrade
import "net/http"

type mockResponseWriter struct {
	header http.Header
	body   []byte
	status int
}

func (w *mockResponseWriter) Header() http.Header {
	if w.header == nil {
		w.header = make(http.Header)
	}
	return w.header
}

func (w *mockResponseWriter) Write(data []byte) (int, error) {
	w.body = append(w.body, data...)
	return len(data), nil
}

func (w *mockResponseWriter) WriteHeader(statusCode int) {
	w.status = statusCode
}

type mockRequest struct{}

func (r *mockRequest) Header() http.Header { return make(http.Header) }

// Test functions
func TestNewClient(t *testing.T) {
	config := ClientConfig{
		URL:              "ws://localhost:8080",
		Timeout:          5 * time.Second,
		ReconnectDelay:   1 * time.Second,
		MaxReconnects:    3,
		EnableHeartbeat:  true,
		HeartbeatInterval: 30 * time.Second,
	}

	client := NewClient(config)
	assert.NotNil(t, client)
	assert.Equal(t, config.URL, client.config.URL)
	assert.Equal(t, config.Timeout, client.config.Timeout)
	assert.NotNil(t, client.circuitBreaker)
	assert.NotNil(t, client.pendingCalls)
}

func TestClientConnect(t *testing.T) {
	// Start mock server
	server := NewMockWSServer()
	require.NoError(t, server.Start("localhost:0"))
	defer server.Stop()

	// Create client
	config := ClientConfig{
		URL:     fmt.Sprintf("ws://%s", server.GetAddr()),
		Timeout: 5 * time.Second,
	}
	client := NewClient(config)

	// Test successful connection
	err := client.Connect()
	assert.NoError(t, err)
	assert.True(t, client.IsConnected())

	// Test disconnect
	client.Disconnect()
	assert.False(t, client.IsConnected())
}

func TestClientConnectFailure(t *testing.T) {
	// Create client with invalid URL
	config := ClientConfig{
		URL:     "ws://invalid:99999",
		Timeout: 1 * time.Second,
	}
	client := NewClient(config)

	// Test connection failure
	err := client.Connect()
	assert.Error(t, err)
	assert.False(t, client.IsConnected())
}

func TestClientCall(t *testing.T) {
	// Start mock server
	server := NewMockWSServer()
	require.NoError(t, server.Start("localhost:0"))
	defer server.Stop()

	// Set up handler
	server.SetHandler("test.echo", func(params []byte) (interface{}, error) {
		var request map[string]interface{}
		json.Unmarshal(params, &request)
		return map[string]interface{}{
			"echo": request["message"],
		}, nil
	})

	// Create and connect client
	config := ClientConfig{
		URL:     fmt.Sprintf("ws://%s", server.GetAddr()),
		Timeout: 5 * time.Second,
	}
	client := NewClient(config)
	require.NoError(t, client.Connect())
	defer client.Disconnect()

	// Test successful call
	ctx := context.Background()
	params := map[string]interface{}{"message": "hello"}
	result, err := client.Call(ctx, "test.echo", params)

	assert.NoError(t, err)
	assert.NotNil(t, result)

	resultMap, ok := result.(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, "hello", resultMap["echo"])
}

func TestClientCallTimeout(t *testing.T) {
	// Start mock server
	server := NewMockWSServer()
	require.NoError(t, server.Start("localhost:0"))
	defer server.Stop()

	// Set up slow handler
	server.SetHandler("test.slow", func(params []byte) (interface{}, error) {
		time.Sleep(2 * time.Second)
		return "result", nil
	})

	// Create and connect client with short timeout
	config := ClientConfig{
		URL:     fmt.Sprintf("ws://%s", server.GetAddr()),
		Timeout: 500 * time.Millisecond,
	}
	client := NewClient(config)
	require.NoError(t, client.Connect())
	defer client.Disconnect()

	// Test timeout
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	_, err := client.Call(ctx, "test.slow", nil)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "timeout")
}

func TestClientCallMethodNotFound(t *testing.T) {
	// Start mock server
	server := NewMockWSServer()
	require.NoError(t, server.Start("localhost:0"))
	defer server.Stop()

	// Create and connect client
	config := ClientConfig{
		URL:     fmt.Sprintf("ws://%s", server.GetAddr()),
		Timeout: 5 * time.Second,
	}
	client := NewClient(config)
	require.NoError(t, client.Connect())
	defer client.Disconnect()

	// Test method not found
	ctx := context.Background()
	_, err := client.Call(ctx, "test.nonexistent", nil)

	assert.Error(t, err)
	assert.Contains(t, err.Error(), "Method not found")
}

func TestClientNotify(t *testing.T) {
	// Start mock server
	server := NewMockWSServer()
	require.NoError(t, server.Start("localhost:0"))
	defer server.Stop()

	notificationReceived := make(chan bool, 1)
	server.SetHandler("test.notify", func(params []byte) (interface{}, error) {
		notificationReceived <- true
		return nil, nil
	})

	// Create and connect client
	config := ClientConfig{
		URL:     fmt.Sprintf("ws://%s", server.GetAddr()),
		Timeout: 5 * time.Second,
	}
	client := NewClient(config)
	require.NoError(t, client.Connect())
	defer client.Disconnect()

	// Test notification
	err := client.Notify("test.notify", map[string]interface{}{"data": "test"})
	assert.NoError(t, err)

	// Wait for notification to be received
	select {
	case <-notificationReceived:
		// Success
	case <-time.After(1 * time.Second):
		t.Fatal("Notification not received")
	}
}

func TestClientReconnect(t *testing.T) {
	// Start mock server
	server := NewMockWSServer()
	require.NoError(t, server.Start("localhost:0"))

	// Create client with reconnect enabled
	config := ClientConfig{
		URL:            fmt.Sprintf("ws://%s", server.GetAddr()),
		Timeout:        5 * time.Second,
		ReconnectDelay: 100 * time.Millisecond,
		MaxReconnects:  3,
	}
	client := NewClient(config)
	require.NoError(t, client.Connect())

	// Verify initial connection
	assert.True(t, client.IsConnected())

	// Stop server to simulate connection loss
	server.Stop()
	time.Sleep(200 * time.Millisecond)

	// Restart server
	server = NewMockWSServer()
	require.NoError(t, server.Start(server.GetAddr()))
	defer server.Stop()

	// Wait for reconnection
	time.Sleep(500 * time.Millisecond)

	// Verify reconnection (implementation would need to handle this)
	client.Disconnect()
}

func TestCircuitBreaker(t *testing.T) {
	// Create circuit breaker
	config := CircuitBreakerConfig{
		FailureThreshold: 3,
		RecoveryTimeout:  100 * time.Millisecond,
		MaxRequests:      2,
	}
	cb := NewCircuitBreaker(config)

	// Test initial state
	assert.Equal(t, StateClosed, cb.GetState())

	// Test successful calls
	err := cb.Call(func() error { return nil })
	assert.NoError(t, err)

	// Test failing calls to trigger opening
	for i := 0; i < 3; i++ {
		err = cb.Call(func() error { return fmt.Errorf("test error") })
		assert.Error(t, err)
	}

	// Circuit should be open now
	assert.Equal(t, StateOpen, cb.GetState())

	// Calls should fail fast
	err = cb.Call(func() error { return nil })
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "circuit breaker is open")

	// Wait for recovery timeout
	time.Sleep(150 * time.Millisecond)

	// Circuit should be half-open
	assert.Equal(t, StateHalfOpen, cb.GetState())

	// Successful call should close circuit
	err = cb.Call(func() error { return nil })
	assert.NoError(t, err)
	assert.Equal(t, StateClosed, cb.GetState())
}

func TestCircuitBreakerConcurrency(t *testing.T) {
	config := CircuitBreakerConfig{
		FailureThreshold: 5,
		RecoveryTimeout:  50 * time.Millisecond,
		MaxRequests:      3,
	}
	cb := NewCircuitBreaker(config)

	// Run concurrent operations
	var wg sync.WaitGroup
	errorCount := int32(0)
	successCount := int32(0)

	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			err := cb.Call(func() error {
				if index%3 == 0 {
					return fmt.Errorf("error %d", index)
				}
				return nil
			})

			if err != nil {
				atomic.AddInt32(&errorCount, 1)
			} else {
				atomic.AddInt32(&successCount, 1)
			}
		}(i)
	}

	wg.Wait()

	// Verify that circuit breaker handled concurrent access properly
	assert.True(t, atomic.LoadInt32(&errorCount) > 0)
	assert.True(t, atomic.LoadInt32(&successCount) > 0)
}

func TestJSONRPCRequestGeneration(t *testing.T) {
	client := &Client{
		callID: 1,
	}

	request := client.createRequest("test.method", map[string]interface{}{"key": "value"}, false)

	assert.Equal(t, "2.0", request.JSONRPC)
	assert.Equal(t, "test.method", request.Method)
	assert.Equal(t, uint64(1), request.ID)
	assert.NotNil(t, request.Params)
}

func TestJSONRPCNotificationGeneration(t *testing.T) {
	client := &Client{}

	request := client.createRequest("test.notify", map[string]interface{}{"key": "value"}, true)

	assert.Equal(t, "2.0", request.JSONRPC)
	assert.Equal(t, "test.notify", request.Method)
	assert.Equal(t, uint64(0), request.ID) // Notifications have no ID
	assert.NotNil(t, request.Params)
}

func TestClientCleanup(t *testing.T) {
	// Start mock server
	server := NewMockWSServer()
	require.NoError(t, server.Start("localhost:0"))
	defer server.Stop()

	// Create client
	config := ClientConfig{
		URL:     fmt.Sprintf("ws://%s", server.GetAddr()),
		Timeout: 5 * time.Second,
	}
	client := NewClient(config)
	require.NoError(t, client.Connect())

	// Add some pending calls
	client.pendingCalls.Store(uint64(1), &PendingCall{
		ID:        1,
		Response:  make(chan JSONRPCResponse, 1),
		CreatedAt: time.Now(),
	})

	// Test cleanup
	client.cleanupPendingCalls()

	// Disconnect should clean up resources
	client.Disconnect()
	assert.False(t, client.IsConnected())
}

import "sync/atomic"

func BenchmarkClientCall(b *testing.B) {
	// Start mock server
	server := NewMockWSServer()
	server.Start("localhost:0")
	defer server.Stop()

	server.SetHandler("benchmark.test", func(params []byte) (interface{}, error) {
		return map[string]interface{}{"result": "ok"}, nil
	})

	// Create client
	config := ClientConfig{
		URL:     fmt.Sprintf("ws://%s", server.GetAddr()),
		Timeout: 5 * time.Second,
	}
	client := NewClient(config)
	client.Connect()
	defer client.Disconnect()

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			ctx := context.Background()
			_, err := client.Call(ctx, "benchmark.test", map[string]interface{}{"data": "test"})
			if err != nil {
				b.Error(err)
			}
		}
	})
}

func BenchmarkCircuitBreaker(b *testing.B) {
	config := CircuitBreakerConfig{
		FailureThreshold: 1000, // High threshold to avoid opening during benchmark
		RecoveryTimeout:  1 * time.Second,
		MaxRequests:      100,
	}
	cb := NewCircuitBreaker(config)

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			err := cb.Call(func() error {
				return nil // Always succeed
			})
			if err != nil {
				b.Error(err)
			}
		}
	})
}