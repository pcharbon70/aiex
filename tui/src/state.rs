use std::collections::{HashMap, VecDeque};
use chrono::{DateTime, Utc};

use crate::config::Config;

/// Application state following immutable update patterns
#[derive(Debug, Clone)]
pub struct AppState {
    pub project_dir: String,
    pub config: Config,
    pub current_pane: Pane,
    
    // Chat interface state
    pub chat_state: ChatState,
    pub layout_state: LayoutState,
    
    // Legacy state (keeping for backwards compatibility)
    pub file_tree: FileTree,
    pub current_file: Option<FileContent>,
    pub diff_view: Option<DiffView>,
    pub event_log: Vec<EventLogEntry>,
    pub terminal_size: (u16, u16),
    pub build_status: BuildStatus,
    pub connection_status: ConnectionStatus,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Pane {
    ConversationHistory,
    CurrentStatus,
    Context,
    QuickActions,
    MessageInput,
}

/// Maximum number of messages to keep in history
const MAX_MESSAGES: usize = 1000;

#[derive(Debug, Clone)]
pub enum MessageType {
    User,
    Assistant,
    System,
    Error,
}

#[derive(Debug, Clone)]
pub struct ChatMessage {
    pub content: String,
    pub message_type: MessageType,
    pub timestamp: DateTime<Utc>,
    pub tokens_used: Option<u32>,
}

impl ChatMessage {
    pub fn new(content: String, message_type: MessageType) -> Self {
        Self {
            content,
            message_type,
            timestamp: Utc::now(),
            tokens_used: None,
        }
    }

    pub fn with_tokens(mut self, tokens: u32) -> Self {
        self.tokens_used = Some(tokens);
        self
    }
}

#[derive(Debug, Clone)]
pub enum ContextItem {
    File { path: String, status: String },
    Function { name: String, file: String, line: Option<u32> },
    Error { message: String, file: String, line: Option<u32> },
    BuildStatus { status: String, timestamp: DateTime<Utc> },
}

#[derive(Debug, Clone)]
pub enum QuickAction {
    ExplainCode,
    FixError,
    GenerateTests,
    Refactor,
    AddComments,
    CreateFile,
}

impl QuickAction {
    pub fn label(&self) -> &'static str {
        match self {
            Self::ExplainCode => "Explain Code",
            Self::FixError => "Fix Error",
            Self::GenerateTests => "Generate Tests",
            Self::Refactor => "Refactor",
            Self::AddComments => "Add Comments",
            Self::CreateFile => "Create File",
        }
    }

    pub fn key(&self) -> &'static str {
        match self {
            Self::ExplainCode => "e",
            Self::FixError => "f",
            Self::GenerateTests => "t",
            Self::Refactor => "r",
            Self::AddComments => "c",
            Self::CreateFile => "n",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Self::ExplainCode => "Get AI explanation of selected code",
            Self::FixError => "Ask AI to help fix current errors",
            Self::GenerateTests => "Generate unit tests for current function",
            Self::Refactor => "Suggest refactoring improvements",
            Self::AddComments => "Add documentation comments",
            Self::CreateFile => "Help create a new file",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ChatState {
    pub messages: VecDeque<ChatMessage>,
    pub current_input: String,
    pub scroll_position: usize,
    pub auto_scroll: bool,
    pub is_processing: bool,
    pub session_tokens: u32,
    pub current_conversation_id: Option<String>,
}

impl ChatState {
    pub fn new() -> Self {
        Self {
            messages: VecDeque::new(),
            current_input: String::new(),
            scroll_position: 0,
            auto_scroll: true,
            is_processing: false,
            session_tokens: 0,
            current_conversation_id: None,
        }
    }

    pub fn add_message(&mut self, message: ChatMessage) {
        if let Some(tokens) = message.tokens_used {
            self.session_tokens += tokens;
        }
        
        self.messages.push_back(message);
        
        // Keep only the last MAX_MESSAGES
        if self.messages.len() > MAX_MESSAGES {
            self.messages.pop_front();
        }
        
        // Auto-scroll to bottom if enabled
        if self.auto_scroll {
            self.scroll_position = self.messages.len().saturating_sub(1);
        }
    }

    pub fn clear_input(&mut self) {
        self.current_input.clear();
    }

    pub fn scroll_up(&mut self) {
        if self.scroll_position > 0 {
            self.scroll_position -= 1;
            self.auto_scroll = false;
        }
    }

    pub fn scroll_down(&mut self) {
        if self.scroll_position < self.messages.len().saturating_sub(1) {
            self.scroll_position += 1;
            
            // Re-enable auto-scroll if at bottom
            if self.scroll_position == self.messages.len().saturating_sub(1) {
                self.auto_scroll = true;
            }
        }
    }

    pub fn scroll_to_bottom(&mut self) {
        self.scroll_position = self.messages.len().saturating_sub(1);
        self.auto_scroll = true;
    }

    pub fn scroll_to_top(&mut self) {
        self.scroll_position = 0;
        self.auto_scroll = false;
    }
}

#[derive(Debug, Clone)]
pub struct LayoutState {
    pub show_context_panel: bool,
    pub show_quick_actions: bool,
    pub context_panel_width: u16,
    pub quick_actions_width: u16,
    pub conversation_history_height_percent: u8,
    pub current_status_height_percent: u8,
    pub context_items: Vec<ContextItem>,
    pub quick_actions: Vec<QuickAction>,
    pub context_scroll: usize,
    pub actions_scroll: usize,
}

impl LayoutState {
    pub fn new() -> Self {
        Self {
            show_context_panel: true,
            show_quick_actions: true,
            context_panel_width: 25,
            quick_actions_width: 20,
            conversation_history_height_percent: 70,
            current_status_height_percent: 30,
            context_items: vec![
                ContextItem::File {
                    path: "lib/my_module.ex".to_string(),
                    status: "modified".to_string(),
                },
                ContextItem::Function {
                    name: "calculate_sum".to_string(),
                    file: "lib/math.ex".to_string(),
                    line: Some(42),
                },
                ContextItem::Error {
                    message: "unused variable `temp`".to_string(),
                    file: "lib/utils.ex".to_string(),
                    line: Some(15),
                },
            ],
            quick_actions: vec![
                QuickAction::ExplainCode,
                QuickAction::FixError,
                QuickAction::GenerateTests,
                QuickAction::Refactor,
                QuickAction::AddComments,
                QuickAction::CreateFile,
            ],
            context_scroll: 0,
            actions_scroll: 0,
        }
    }

    pub fn toggle_context_panel(&mut self) {
        self.show_context_panel = !self.show_context_panel;
    }

    pub fn toggle_quick_actions(&mut self) {
        self.show_quick_actions = !self.show_quick_actions;
    }

    pub fn scroll_context_up(&mut self) {
        if self.context_scroll > 0 {
            self.context_scroll -= 1;
        }
    }

    pub fn scroll_context_down(&mut self) {
        if self.context_scroll < self.context_items.len().saturating_sub(1) {
            self.context_scroll += 1;
        }
    }

    pub fn scroll_actions_up(&mut self) {
        if self.actions_scroll > 0 {
            self.actions_scroll -= 1;
        }
    }

    pub fn scroll_actions_down(&mut self) {
        if self.actions_scroll < self.quick_actions.len().saturating_sub(1) {
            self.actions_scroll += 1;
        }
    }

    pub fn get_selected_context_item(&self) -> Option<&ContextItem> {
        self.context_items.get(self.context_scroll)
    }

    pub fn get_selected_quick_action(&self) -> Option<&QuickAction> {
        self.quick_actions.get(self.actions_scroll)
    }
}

#[derive(Debug, Clone)]
pub struct FileTree {
    pub entries: Vec<FileEntry>,
    pub selected_index: usize,
    pub expanded_dirs: HashMap<String, bool>,
}

#[derive(Debug, Clone)]
pub struct FileEntry {
    pub path: String,
    pub name: String,
    pub is_directory: bool,
    pub size: Option<u64>,
    pub modified: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone)]
pub struct FileContent {
    pub path: String,
    pub content: String,
    pub language: Option<String>,
    pub cursor_position: (usize, usize), // (line, column)
    pub scroll_offset: usize,
}

#[derive(Debug, Clone)]
pub struct DiffView {
    pub old_content: String,
    pub new_content: String,
    pub diff_lines: Vec<DiffLine>,
}

#[derive(Debug, Clone)]
pub struct DiffLine {
    pub line_type: DiffLineType,
    pub old_line_number: Option<usize>,
    pub new_line_number: Option<usize>,
    pub content: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum DiffLineType {
    Added,
    Removed,
    Modified,
    Context,
}

#[derive(Debug, Clone)]
pub struct EventLogEntry {
    pub timestamp: DateTime<Utc>,
    pub level: LogLevel,
    pub message: String,
    pub category: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LogLevel {
    Info,
    Warning,
    Error,
    Debug,
}

#[derive(Debug, Clone)]
pub struct BuildStatus {
    pub is_building: bool,
    pub last_build_time: Option<DateTime<Utc>>,
    pub last_status: Option<String>,
    pub output: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ConnectionStatus {
    Connected,
    Connecting,
    Disconnected,
    Error(String),
}

impl AppState {
    pub fn new(project_dir: String, config: Config) -> Self {
        let mut chat_state = ChatState::new();
        
        // Add a welcome message
        chat_state.add_message(ChatMessage::new(
            "Welcome to Aiex AI Coding Assistant! How can I help you today?".to_string(),
            MessageType::Assistant,
        ));

        Self {
            project_dir,
            config,
            current_pane: Pane::MessageInput,
            chat_state,
            layout_state: LayoutState::new(),
            file_tree: FileTree::new(),
            current_file: None,
            diff_view: None,
            event_log: Vec::new(),
            terminal_size: (80, 24),
            build_status: BuildStatus::new(),
            connection_status: ConnectionStatus::Connecting,
        }
    }

    // Navigation methods for new chat interface
    pub fn navigate_up(&mut self) {
        match self.current_pane {
            Pane::ConversationHistory => {
                self.chat_state.scroll_up();
            }
            Pane::Context => {
                self.layout_state.scroll_context_up();
            }
            Pane::QuickActions => {
                self.layout_state.scroll_actions_up();
            }
            _ => {}
        }
    }

    pub fn navigate_down(&mut self) {
        match self.current_pane {
            Pane::ConversationHistory => {
                self.chat_state.scroll_down();
            }
            Pane::Context => {
                self.layout_state.scroll_context_down();
            }
            Pane::QuickActions => {
                self.layout_state.scroll_actions_down();
            }
            _ => {}
        }
    }

    pub fn switch_pane(&mut self) {
        self.current_pane = match self.current_pane {
            Pane::MessageInput => {
                if self.layout_state.show_context_panel {
                    Pane::Context
                } else if self.layout_state.show_quick_actions {
                    Pane::QuickActions
                } else {
                    Pane::ConversationHistory
                }
            }
            Pane::Context => {
                if self.layout_state.show_quick_actions {
                    Pane::QuickActions
                } else {
                    Pane::ConversationHistory
                }
            }
            Pane::QuickActions => Pane::ConversationHistory,
            Pane::ConversationHistory => Pane::CurrentStatus,
            Pane::CurrentStatus => Pane::MessageInput,
        };
    }

    // Panel management methods
    pub fn toggle_context_panel(&mut self) {
        self.layout_state.toggle_context_panel();
    }

    pub fn toggle_quick_actions(&mut self) {
        self.layout_state.toggle_quick_actions();
    }

    // Chat methods
    pub fn send_message(&mut self, content: String) {
        if !content.trim().is_empty() {
            let message = ChatMessage::new(content, MessageType::User);
            self.chat_state.add_message(message);
            self.chat_state.clear_input();
            self.chat_state.is_processing = true;
        }
    }

    pub fn add_ai_response(&mut self, content: String, tokens: Option<u32>) {
        let mut message = ChatMessage::new(content, MessageType::Assistant);
        if let Some(t) = tokens {
            message = message.with_tokens(t);
        }
        self.chat_state.add_message(message);
        self.chat_state.is_processing = false;
    }

    pub fn add_system_message(&mut self, content: String) {
        let message = ChatMessage::new(content, MessageType::System);
        self.chat_state.add_message(message);
    }

    pub fn add_error_message(&mut self, content: String) {
        let message = ChatMessage::new(content, MessageType::Error);
        self.chat_state.add_message(message);
        self.chat_state.is_processing = false;
    }

    pub fn execute_quick_action(&mut self, action: &QuickAction) -> String {
        let message_content = match action {
            QuickAction::ExplainCode => "Please explain the currently selected code.".to_string(),
            QuickAction::FixError => "Help me fix the errors in my code.".to_string(),
            QuickAction::GenerateTests => "Generate unit tests for the current function.".to_string(),
            QuickAction::Refactor => "Suggest refactoring improvements for this code.".to_string(),
            QuickAction::AddComments => "Add documentation comments to this code.".to_string(),
            QuickAction::CreateFile => "Help me create a new file. What should it contain?".to_string(),
        };

        self.send_message(message_content.clone());
        message_content
    }

    // File operations
    pub fn get_selected_file(&self) -> Option<String> {
        if self.file_tree.selected_index < self.file_tree.entries.len() {
            let entry = &self.file_tree.entries[self.file_tree.selected_index];
            if !entry.is_directory {
                return Some(entry.path.clone());
            }
        }
        None
    }

    pub fn update_file_content(&mut self, path: String, content: String) {
        let language = detect_language(&path);
        
        self.current_file = Some(FileContent {
            path,
            content,
            language,
            cursor_position: (0, 0),
            scroll_offset: 0,
        });

        self.add_event_log(format!("File content updated"));
    }

    pub fn update_file_tree(&mut self, entries: Vec<FileEntry>) {
        self.file_tree.entries = entries;
        // Preserve selection if possible
        if self.file_tree.selected_index >= self.file_tree.entries.len() {
            self.file_tree.selected_index = self.file_tree.entries.len().saturating_sub(1);
        }
    }

    // Event logging
    pub fn add_event_log(&mut self, message: String) {
        let entry = EventLogEntry {
            timestamp: Utc::now(),
            level: LogLevel::Info,
            message,
            category: "system".to_string(),
        };

        self.event_log.push(entry);

        // Keep only recent entries
        if self.event_log.len() > 1000 {
            self.event_log.drain(0..100);
        }
    }

    pub fn add_error_log(&mut self, message: String) {
        let entry = EventLogEntry {
            timestamp: Utc::now(),
            level: LogLevel::Error,
            message,
            category: "error".to_string(),
        };

        self.event_log.push(entry);
    }

    // Build status
    pub fn update_build_status(&mut self, status: String, output: String) {
        self.build_status.last_build_time = Some(Utc::now());
        self.build_status.last_status = Some(status);
        self.build_status.output = output;
        self.build_status.is_building = false;
    }

    pub fn start_build(&mut self) {
        self.build_status.is_building = true;
        self.add_event_log("Build started".to_string());
    }

    // Terminal management
    pub fn update_terminal_size(&mut self, width: u16, height: u16) {
        self.terminal_size = (width, height);
    }

    // Connection status
    pub fn set_connection_status(&mut self, status: ConnectionStatus) {
        self.connection_status = status;
    }
}

impl FileTree {
    fn new() -> Self {
        Self {
            entries: Vec::new(),
            selected_index: 0,
            expanded_dirs: HashMap::new(),
        }
    }
}

impl BuildStatus {
    fn new() -> Self {
        Self {
            is_building: false,
            last_build_time: None,
            last_status: None,
            output: String::new(),
        }
    }
}

fn detect_language(path: &str) -> Option<String> {
    match path.split('.').last() {
        Some("ex") => Some("elixir".to_string()),
        Some("exs") => Some("elixir".to_string()),
        Some("rs") => Some("rust".to_string()),
        Some("py") => Some("python".to_string()),
        Some("js") => Some("javascript".to_string()),
        Some("ts") => Some("typescript".to_string()),
        Some("json") => Some("json".to_string()),
        Some("toml") => Some("toml".to_string()),
        Some("md") => Some("markdown".to_string()),
        _ => None,
    }
}