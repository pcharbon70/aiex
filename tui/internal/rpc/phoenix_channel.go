package rpc

import (
	"encoding/json"
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

// PhoenixMessage represents a Phoenix channel message
type PhoenixMessage struct {
	JoinRef string          `json:"join_ref,omitempty"`
	Ref     string          `json:"ref,omitempty"`
	Topic   string          `json:"topic"`
	Event   string          `json:"event"`
	Payload json.RawMessage `json:"payload"`
}

// PhoenixChannel handles Phoenix channel protocol
type PhoenixChannel struct {
	conn      *WebSocketStream
	topic     string
	joinRef   string
	ref       int64
	callbacks map[string]chan json.RawMessage
	pushCallbacks map[string]func(json.RawMessage)
	mutex     sync.RWMutex
	joined    bool
}

// NewPhoenixChannel creates a new Phoenix channel handler
func NewPhoenixChannel(conn *WebSocketStream, topic string) *PhoenixChannel {
	return &PhoenixChannel{
		conn:          conn,
		topic:         topic,
		joinRef:       "1",
		callbacks:     make(map[string]chan json.RawMessage),
		pushCallbacks: make(map[string]func(json.RawMessage)),
		joined:        false,
	}
}

// Join joins the channel
func (pc *PhoenixChannel) Join(params map[string]interface{}) error {
	msg := PhoenixMessage{
		JoinRef: pc.joinRef,
		Ref:     pc.nextRef(),
		Topic:   pc.topic,
		Event:   "phx_join",
		Payload: mustMarshal(params),
	}

	// Register callback for join response
	respChan := make(chan json.RawMessage, 1)
	pc.registerCallback(msg.Ref, respChan)
	defer pc.unregisterCallback(msg.Ref)

	// Send join message
	if err := pc.send(msg); err != nil {
		return fmt.Errorf("failed to send join message: %w", err)
	}

	// Wait for response
	select {
	case resp := <-respChan:
		var result struct {
			Status   string          `json:"status"`
			Response json.RawMessage `json:"response"`
		}
		if err := json.Unmarshal(resp, &result); err != nil {
			return fmt.Errorf("failed to parse join response: %w", err)
		}
		if result.Status != "ok" {
			return fmt.Errorf("join failed: %s", result.Status)
		}
		pc.joined = true
		return nil
	case <-time.After(5 * time.Second):
		return fmt.Errorf("join timeout")
	}
}

// Push sends a message and waits for response
func (pc *PhoenixChannel) Push(event string, payload interface{}) (json.RawMessage, error) {
	if !pc.joined {
		return nil, fmt.Errorf("channel not joined")
	}

	ref := pc.nextRef()
	msg := PhoenixMessage{
		JoinRef: pc.joinRef,
		Ref:     ref,
		Topic:   pc.topic,
		Event:   event,
		Payload: mustMarshal(payload),
	}

	// Register callback for response
	respChan := make(chan json.RawMessage, 1)
	pc.registerCallback(ref, respChan)
	defer pc.unregisterCallback(ref)

	// Send message
	if err := pc.send(msg); err != nil {
		return nil, fmt.Errorf("failed to send message: %w", err)
	}

	// Wait for response
	select {
	case resp := <-respChan:
		return resp, nil
	case <-time.After(30 * time.Second):
		return nil, fmt.Errorf("request timeout")
	}
}

// PushAsync sends a message without waiting for response
func (pc *PhoenixChannel) PushAsync(event string, payload interface{}) error {
	if !pc.joined {
		return fmt.Errorf("channel not joined")
	}

	msg := PhoenixMessage{
		JoinRef: pc.joinRef,
		Ref:     pc.nextRef(),
		Topic:   pc.topic,
		Event:   event,
		Payload: mustMarshal(payload),
	}

	return pc.send(msg)
}

// OnPush registers a handler for server-pushed events
func (pc *PhoenixChannel) OnPush(event string, handler func(json.RawMessage)) {
	pc.mutex.Lock()
	defer pc.mutex.Unlock()
	pc.pushCallbacks[event] = handler
}

// HandleMessage processes incoming Phoenix messages
func (pc *PhoenixChannel) HandleMessage(data []byte) error {
	var msg PhoenixMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return fmt.Errorf("failed to parse Phoenix message: %w", err)
	}

	// Handle reply messages
	if msg.Event == "phx_reply" {
		pc.mutex.RLock()
		if ch, ok := pc.callbacks[msg.Ref]; ok {
			pc.mutex.RUnlock()
			select {
			case ch <- msg.Payload:
			default:
			}
		} else {
			pc.mutex.RUnlock()
		}
		return nil
	}

	// Handle push messages
	pc.mutex.RLock()
	if handler, ok := pc.pushCallbacks[msg.Event]; ok {
		pc.mutex.RUnlock()
		handler(msg.Payload)
	} else {
		pc.mutex.RUnlock()
	}

	return nil
}

// Leave leaves the channel
func (pc *PhoenixChannel) Leave() error {
	if !pc.joined {
		return nil
	}

	msg := PhoenixMessage{
		JoinRef: pc.joinRef,
		Ref:     pc.nextRef(),
		Topic:   pc.topic,
		Event:   "phx_leave",
		Payload: json.RawMessage("{}"),
	}

	pc.joined = false
	return pc.send(msg)
}

// Private methods

func (pc *PhoenixChannel) send(msg PhoenixMessage) error {
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	return pc.conn.Send(data)
}

func (pc *PhoenixChannel) nextRef() string {
	return fmt.Sprintf("%d", atomic.AddInt64(&pc.ref, 1))
}

func (pc *PhoenixChannel) registerCallback(ref string, ch chan json.RawMessage) {
	pc.mutex.Lock()
	defer pc.mutex.Unlock()
	pc.callbacks[ref] = ch
}

func (pc *PhoenixChannel) unregisterCallback(ref string) {
	pc.mutex.Lock()
	defer pc.mutex.Unlock()
	delete(pc.callbacks, ref)
}

func mustMarshal(v interface{}) json.RawMessage {
	data, _ := json.Marshal(v)
	return json.RawMessage(data)
}