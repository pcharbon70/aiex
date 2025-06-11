package types

// Common types used across the TUI application

// PanelType represents different types of panels in the UI
type PanelType int

const (
	PanelFileExplorer PanelType = iota
	PanelCodeEditor
	PanelChat
	PanelStatus
)

// String returns the string representation of a PanelType
func (p PanelType) String() string {
	switch p {
	case PanelFileExplorer:
		return "file_explorer"
	case PanelCodeEditor:
		return "code_editor"
	case PanelChat:
		return "chat"
	case PanelStatus:
		return "status"
	default:
		return "unknown"
	}
}

// MessageType represents different types of messages
type MessageType int

const (
	MessageInfo MessageType = iota
	MessageWarning
	MessageError
	MessageSuccess
)


// ChatMessage represents a chat message
type ChatMessage struct {
	ID        string      `json:"id"`
	Type      MessageType `json:"type"`
	Content   string      `json:"content"`
	Timestamp int64       `json:"timestamp"`
	Role      string      `json:"role"` // "user" or "assistant"
}

// RPCRequest represents a JSON-RPC request
type RPCRequest struct {
	Method string      `json:"method"`
	Params interface{} `json:"params"`
	ID     string      `json:"id"`
}

// RPCResponse represents a JSON-RPC response
type RPCResponse struct {
	Result interface{} `json:"result,omitempty"`
	Error  *RPCError   `json:"error,omitempty"`
	ID     string      `json:"id"`
}

// RPCError represents a JSON-RPC error
type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}