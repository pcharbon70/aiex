use crossterm::event::KeyEvent;

/// Messages in The Elm Architecture (TEA) pattern
/// All state changes flow through these messages
#[derive(Debug, Clone)]
pub enum Message {
    /// Terminal UI events (keyboard, mouse, resize)
    TuiEvent(TuiEvent),

    /// Connection status updates
    ConnectionStatus { connected: bool, details: String },

    /// OTP events from TCP connection
    OtpEvent { event_type: String, data: serde_json::Value },

    /// Command responses from OTP application
    CommandResult { request_id: String, result: serde_json::Value },

    /// File system events
    FileChanged { path: String, content: String },

    /// Build system events
    BuildCompleted { status: String, output: String },

    /// Application control
    Quit,
}

/// Terminal-specific events
#[derive(Debug, Clone)]
pub enum TuiEvent {
    /// Key press events
    Key(KeyEvent),

    /// Terminal resize events
    Resize(u16, u16),
}

/// Commands that can be sent to the OTP application via NATS
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum OtpCommand {
    /// File operations
    FileOperation {
        action: FileAction,
        path: String,
        content: Option<String>,
    },

    /// Project operations
    ProjectOperation { action: ProjectAction },

    /// LLM operations
    LlmOperation {
        action: LlmAction,
        prompt: String,
        context: Option<serde_json::Value>,
    },

    /// State queries
    StateQuery { query: StateQueryType },
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum FileAction {
    Open,
    Save,
    List,
    Create,
    Delete,
    Watch,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum ProjectAction {
    Refresh,
    Build,
    Test,
    Format,
    Analyze,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum LlmAction {
    Complete,
    Explain,
    Generate,
    Refactor,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum StateQueryType {
    ProjectStructure,
    FileTree,
    BuildStatus,
    Configuration,
}

/// Responses from the OTP application
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "status")]
pub enum OtpResponse {
    Success {
        data: serde_json::Value,
        timestamp: i64,
    },
    Error {
        message: String,
        code: Option<String>,
        timestamp: i64,
    },
    Progress {
        message: String,
        percentage: Option<f32>,
        timestamp: i64,
    },
}

/// Events published by the OTP application
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "event_type")]
pub enum OtpEvent {
    FileChanged {
        path: String,
        change_type: FileChangeType,
        content: Option<String>,
    },
    BuildStarted {
        project: String,
        target: Option<String>,
    },
    BuildCompleted {
        project: String,
        status: BuildResult,
        output: String,
        duration_ms: u64,
    },
    LlmResponse {
        request_id: String,
        response: String,
        model: String,
        tokens_used: Option<u32>,
    },
    SystemEvent {
        event: String,
        data: serde_json::Value,
    },
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum FileChangeType {
    Created,
    Modified,
    Deleted,
    Renamed,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum BuildResult {
    Success,
    Failed,
    Warning,
    Cancelled,
}