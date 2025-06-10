package types

import "time"

// AIResponse represents a response from the AI assistant
type AIResponse struct {
	ID            string                 `json:"id"`
	Content       string                 `json:"content"`
	Role          string                 `json:"role"`
	Model         string                 `json:"model,omitempty"`
	TokensUsed    int                    `json:"tokens_used,omitempty"`
	ResponseTime  int64                  `json:"response_time,omitempty"`
	Timestamp     time.Time              `json:"timestamp"`
	Metadata      map[string]interface{} `json:"metadata,omitempty"`
	Conversation  string                 `json:"conversation_id,omitempty"`
}

// StreamingChunk represents a chunk of streaming response
type StreamingChunk struct {
	ID           string    `json:"id"`
	Content      string    `json:"content"`
	Delta        string    `json:"delta"`
	IsComplete   bool      `json:"is_complete"`
	Timestamp    time.Time `json:"timestamp"`
	ChunkIndex   int       `json:"chunk_index"`
}

// CodeSuggestion represents an AI code suggestion
type CodeSuggestion struct {
	ID          string                 `json:"id"`
	FilePath    string                 `json:"file_path"`
	StartLine   int                    `json:"start_line"`
	EndLine     int                    `json:"end_line"`
	StartColumn int                    `json:"start_column"`
	EndColumn   int                    `json:"end_column"`
	Suggestion  string                 `json:"suggestion"`
	Description string                 `json:"description"`
	Type        string                 `json:"type"` // completion, refactor, fix, etc.
	Confidence  float64                `json:"confidence"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

// StateUpdate represents a state change notification
type StateUpdate struct {
	Type      string                 `json:"type"`
	Component string                 `json:"component"`
	Data      map[string]interface{} `json:"data"`
	Timestamp time.Time              `json:"timestamp"`
	Version   int64                  `json:"version"`
}

// FileChange represents a file system change
type FileChange struct {
	Path      string    `json:"path"`
	Type      string    `json:"type"` // created, modified, deleted, renamed
	OldPath   string    `json:"old_path,omitempty"`
	Content   string    `json:"content,omitempty"`
	Timestamp time.Time `json:"timestamp"`
	Size      int64     `json:"size,omitempty"`
	Hash      string    `json:"hash,omitempty"`
}

// ContextUpdate represents project context changes
type ContextUpdate struct {
	Type        string                 `json:"type"`
	ProjectInfo map[string]interface{} `json:"project_info"`
	FileTree    []FileInfo             `json:"file_tree,omitempty"`
	OpenFiles   []string               `json:"open_files,omitempty"`
	ActiveFile  string                 `json:"active_file,omitempty"`
	Timestamp   time.Time              `json:"timestamp"`
}

// FileInfo represents file metadata
type FileInfo struct {
	Path         string    `json:"path"`
	Name         string    `json:"name"`
	Type         string    `json:"type"` // file, directory
	Size         int64     `json:"size"`
	ModifiedTime time.Time `json:"modified_time"`
	Language     string    `json:"language,omitempty"`
	Children     []FileInfo `json:"children,omitempty"`
}

// Message represents a chat message
type Message struct {
	ID          string                 `json:"id"`
	Role        string                 `json:"role"` // user, assistant, system
	Content     string                 `json:"content"`
	Timestamp   time.Time              `json:"timestamp"`
	TokenCount  int                    `json:"token_count,omitempty"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
	References  []Reference            `json:"references,omitempty"`
}

// Reference represents a code or file reference in a message
type Reference struct {
	Type     string `json:"type"` // file, function, class, variable
	Name     string `json:"name"`
	FilePath string `json:"file_path"`
	Line     int    `json:"line,omitempty"`
	Column   int    `json:"column,omitempty"`
	Context  string `json:"context,omitempty"`
}

// Project represents project information
type Project struct {
	Name        string                 `json:"name"`
	Path        string                 `json:"path"`
	Language    string                 `json:"language"`
	Framework   string                 `json:"framework,omitempty"`
	Version     string                 `json:"version,omitempty"`
	Description string                 `json:"description,omitempty"`
	Dependencies []Dependency          `json:"dependencies,omitempty"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

// Dependency represents a project dependency
type Dependency struct {
	Name    string `json:"name"`
	Version string `json:"version"`
	Type    string `json:"type"` // runtime, dev, test, etc.
	Source  string `json:"source,omitempty"`
}

// Command represents a UI command or action
type Command struct {
	Type       string                 `json:"type"`
	Target     string                 `json:"target"`
	Action     string                 `json:"action"`
	Parameters map[string]interface{} `json:"parameters,omitempty"`
	Timestamp  time.Time              `json:"timestamp"`
}

// Notification represents a system notification
type Notification struct {
	ID        string    `json:"id"`
	Type      string    `json:"type"` // info, warning, error, success
	Title     string    `json:"title"`
	Message   string    `json:"message"`
	Timestamp time.Time `json:"timestamp"`
	Duration  int       `json:"duration,omitempty"` // milliseconds, 0 for persistent
	Actions   []Action  `json:"actions,omitempty"`
}

// Action represents a notification action
type Action struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Type  string `json:"type"` // button, link, dismiss
}

// Performance represents performance metrics
type Performance struct {
	Component   string  `json:"component"`
	Operation   string  `json:"operation"`
	Duration    int64   `json:"duration"` // microseconds
	MemoryUsage int64   `json:"memory_usage,omitempty"`
	CPUUsage    float64 `json:"cpu_usage,omitempty"`
	Timestamp   time.Time `json:"timestamp"`
}

// Error represents an error with context
type Error struct {
	ID        string                 `json:"id"`
	Type      string                 `json:"type"`
	Message   string                 `json:"message"`
	Component string                 `json:"component"`
	Stack     string                 `json:"stack,omitempty"`
	Context   map[string]interface{} `json:"context,omitempty"`
	Timestamp time.Time              `json:"timestamp"`
	Severity  string                 `json:"severity"` // low, medium, high, critical
}