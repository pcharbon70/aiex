use std::collections::HashMap;
use chrono::{DateTime, Utc};

use crate::config::Config;

/// Application state following immutable update patterns
#[derive(Debug, Clone)]
pub struct AppState {
    pub project_dir: String,
    pub config: Config,
    pub current_pane: Pane,
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
    FileTree,
    CodeView,
    DiffView,
    EventLog,
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
        Self {
            project_dir,
            config,
            current_pane: Pane::FileTree,
            file_tree: FileTree::new(),
            current_file: None,
            diff_view: None,
            event_log: Vec::new(),
            terminal_size: (80, 24),
            build_status: BuildStatus::new(),
            connection_status: ConnectionStatus::Connecting,
        }
    }

    // Navigation methods
    pub fn navigate_up(&mut self) {
        match self.current_pane {
            Pane::FileTree => {
                if self.file_tree.selected_index > 0 {
                    self.file_tree.selected_index -= 1;
                }
            }
            Pane::CodeView => {
                if let Some(ref mut file) = self.current_file {
                    if file.cursor_position.0 > 0 {
                        file.cursor_position.0 -= 1;
                    }
                }
            }
            _ => {}
        }
    }

    pub fn navigate_down(&mut self) {
        match self.current_pane {
            Pane::FileTree => {
                if self.file_tree.selected_index < self.file_tree.entries.len().saturating_sub(1) {
                    self.file_tree.selected_index += 1;
                }
            }
            Pane::CodeView => {
                if let Some(ref mut file) = self.current_file {
                    let lines = file.content.lines().count();
                    if file.cursor_position.0 < lines.saturating_sub(1) {
                        file.cursor_position.0 += 1;
                    }
                }
            }
            _ => {}
        }
    }

    pub fn switch_pane(&mut self) {
        self.current_pane = match self.current_pane {
            Pane::FileTree => Pane::CodeView,
            Pane::CodeView => Pane::DiffView,
            Pane::DiffView => Pane::EventLog,
            Pane::EventLog => Pane::FileTree,
        };
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