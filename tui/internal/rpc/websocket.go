package rpc

import (
	"net/url"
	"time"

	"github.com/gorilla/websocket"
)

// WebSocketStream implements jrpc2.Channel for WebSocket communication
type WebSocketStream struct {
	conn *websocket.Conn
}

// Send implements the jrpc2.Sender interface
func (ws *WebSocketStream) Send(data []byte) error {
	return ws.conn.WriteMessage(websocket.TextMessage, data)
}

// Recv implements the jrpc2.Receiver interface
func (ws *WebSocketStream) Recv() ([]byte, error) {
	_, data, err := ws.conn.ReadMessage()
	if err != nil {
		return nil, err
	}
	return data, nil
}

// Close implements the io.Closer interface
func (ws *WebSocketStream) Close() error {
	return ws.conn.Close()
}

// ReconnectionManager handles automatic reconnection with failover
type ReconnectionManager struct {
	nodes        []string
	currentNode  int
	retryBackoff *ExponentialBackoff
}

// NewReconnectionManager creates a new reconnection manager
func NewReconnectionManager(nodes []string) *ReconnectionManager {
	return &ReconnectionManager{
		nodes:        nodes,
		currentNode:  0,
		retryBackoff: NewExponentialBackoff(),
	}
}

// ConnectWithFailover attempts to connect to available nodes with failover
func (rm *ReconnectionManager) ConnectWithFailover() (*websocket.Conn, error) {
	var lastErr error

	// Try all nodes
	for i := 0; i < len(rm.nodes); i++ {
		nodeURL := rm.nodes[(rm.currentNode+i)%len(rm.nodes)]
		
		u, err := url.Parse(nodeURL)
		if err != nil {
			lastErr = err
			continue
		}

		dialer := websocket.Dialer{
			HandshakeTimeout: rm.retryBackoff.GetTimeout(),
		}

		conn, _, err := dialer.Dial(u.String(), nil)
		if err != nil {
			lastErr = err
			continue
		}

		// Success - update current node and reset backoff
		rm.currentNode = (rm.currentNode + i) % len(rm.nodes)
		rm.retryBackoff.Reset()
		
		return conn, nil
	}

	// All nodes failed, increment backoff
	rm.retryBackoff.Increment()
	return nil, lastErr
}

// CircuitBreaker implements circuit breaker pattern for fault tolerance
type CircuitBreaker struct {
	failureCount    int
	successCount    int
	failureThreshold int
	successThreshold int
	state           CircuitState
	lastFailureTime int64
	timeout         int64 // milliseconds
}

type CircuitState int

const (
	CircuitClosed CircuitState = iota
	CircuitOpen
	CircuitHalfOpen
)

// NewCircuitBreaker creates a new circuit breaker
func NewCircuitBreaker() *CircuitBreaker {
	return &CircuitBreaker{
		failureThreshold: 5,
		successThreshold: 3,
		timeout:         30000, // 30 seconds
		state:           CircuitClosed,
	}
}

// IsOpen returns true if the circuit breaker is open
func (cb *CircuitBreaker) IsOpen() bool {
	if cb.state == CircuitOpen {
		// Check if timeout has passed
		if getCurrentTimeMillis()-cb.lastFailureTime > cb.timeout {
			cb.state = CircuitHalfOpen
			cb.failureCount = 0
			return false
		}
		return true
	}
	return false
}

// RecordSuccess records a successful operation
func (cb *CircuitBreaker) RecordSuccess() {
	cb.successCount++
	
	if cb.state == CircuitHalfOpen && cb.successCount >= cb.successThreshold {
		cb.state = CircuitClosed
		cb.failureCount = 0
	}
}

// RecordFailure records a failed operation
func (cb *CircuitBreaker) RecordFailure() {
	cb.failureCount++
	cb.lastFailureTime = getCurrentTimeMillis()
	
	if cb.failureCount >= cb.failureThreshold {
		cb.state = CircuitOpen
	}
}

// ExponentialBackoff implements exponential backoff for retries
type ExponentialBackoff struct {
	baseDelay   int64 // milliseconds
	maxDelay    int64 // milliseconds
	multiplier  float64
	retryCount  int
}

// NewExponentialBackoff creates a new exponential backoff
func NewExponentialBackoff() *ExponentialBackoff {
	return &ExponentialBackoff{
		baseDelay:  1000, // 1 second
		maxDelay:   30000, // 30 seconds
		multiplier: 2.0,
		retryCount: 0,
	}
}

// GetDelay returns the current delay
func (eb *ExponentialBackoff) GetDelay() int64 {
	delay := float64(eb.baseDelay)
	for i := 0; i < eb.retryCount; i++ {
		delay *= eb.multiplier
	}
	
	if int64(delay) > eb.maxDelay {
		return eb.maxDelay
	}
	
	return int64(delay)
}

// GetTimeout returns timeout for connection attempts
func (eb *ExponentialBackoff) GetTimeout() time.Duration {
	return time.Duration(eb.GetDelay()) * time.Millisecond
}

// Increment increases the retry count
func (eb *ExponentialBackoff) Increment() {
	eb.retryCount++
}

// Reset resets the backoff state
func (eb *ExponentialBackoff) Reset() {
	eb.retryCount = 0
}

// Helper function to get current time in milliseconds
func getCurrentTimeMillis() int64 {
	return time.Now().UnixNano() / int64(time.Millisecond)
}