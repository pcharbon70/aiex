use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::{fs, path::PathBuf};

/// TUI configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// NATS connection settings
    pub nats: NatsConfig,

    /// UI appearance settings
    pub ui: UiConfig,

    /// Key bindings
    pub keys: KeyBindings,

    /// Editor settings
    pub editor: EditorConfig,

    /// Project settings
    pub project: ProjectConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NatsConfig {
    /// NATS server URL
    pub server_url: String,

    /// Connection timeout in seconds
    pub connection_timeout: u64,

    /// Message timeout in seconds
    pub message_timeout: u64,

    /// Reconnect interval in milliseconds
    pub reconnect_interval: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UiConfig {
    /// Theme colors
    pub theme: Theme,

    /// Frame rate limit
    pub fps_limit: u16,

    /// Show line numbers
    pub show_line_numbers: bool,

    /// Show status bar
    pub show_status_bar: bool,

    /// File tree width percentage
    pub file_tree_width: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Theme {
    /// Primary colors
    pub primary: String,
    pub secondary: String,
    pub background: String,
    pub foreground: String,

    /// Syntax highlighting
    pub syntax: SyntaxTheme,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyntaxTheme {
    pub keyword: String,
    pub string: String,
    pub comment: String,
    pub function: String,
    pub variable: String,
    pub constant: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyBindings {
    /// Navigation
    pub quit: Vec<String>,
    pub up: Vec<String>,
    pub down: Vec<String>,
    pub left: Vec<String>,
    pub right: Vec<String>,
    pub select: Vec<String>,
    pub back: Vec<String>,

    /// File operations
    pub open_file: Vec<String>,
    pub save_file: Vec<String>,
    pub new_file: Vec<String>,
    pub refresh: Vec<String>,

    /// Project operations
    pub build: Vec<String>,
    pub test: Vec<String>,
    pub format: Vec<String>,

    /// UI operations
    pub switch_pane: Vec<String>,
    pub toggle_tree: Vec<String>,
    pub toggle_log: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EditorConfig {
    /// Tab size
    pub tab_size: usize,

    /// Use spaces instead of tabs
    pub use_spaces: bool,

    /// Show whitespace
    pub show_whitespace: bool,

    /// Word wrap
    pub word_wrap: bool,

    /// Auto-save interval in seconds (0 = disabled)
    pub auto_save_interval: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Auto-refresh project structure
    pub auto_refresh: bool,

    /// Refresh interval in seconds
    pub refresh_interval: u64,

    /// Ignore patterns for file tree
    pub ignore_patterns: Vec<String>,

    /// Watch for file changes
    pub watch_files: bool,
}

impl Config {
    pub fn load(config_path: Option<&str>) -> Result<Self> {
        let config_file = match config_path {
            Some(path) => PathBuf::from(path),
            None => Self::default_config_path()?,
        };

        if config_file.exists() {
            let content = fs::read_to_string(&config_file)
                .context("Failed to read config file")?;

            toml::from_str(&content)
                .context("Failed to parse config file")
        } else {
            // Create default config
            let config = Self::default();
            config.save(&config_file)?;
            Ok(config)
        }
    }

    pub fn save(&self, path: &PathBuf) -> Result<()> {
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .context("Failed to create config directory")?;
        }

        let content = toml::to_string_pretty(self)
            .context("Failed to serialize config")?;

        fs::write(path, content)
            .context("Failed to write config file")
    }

    fn default_config_path() -> Result<PathBuf> {
        let config_dir = dirs::config_dir()
            .context("Failed to get config directory")?
            .join("aiex-tui");

        Ok(config_dir.join("config.toml"))
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            nats: NatsConfig::default(),
            ui: UiConfig::default(),
            keys: KeyBindings::default(),
            editor: EditorConfig::default(),
            project: ProjectConfig::default(),
        }
    }
}

impl Default for NatsConfig {
    fn default() -> Self {
        Self {
            server_url: "nats://localhost:4222".to_string(),
            connection_timeout: 10,
            message_timeout: 5,
            reconnect_interval: 1000,
        }
    }
}

impl Default for UiConfig {
    fn default() -> Self {
        Self {
            theme: Theme::default(),
            fps_limit: 60,
            show_line_numbers: true,
            show_status_bar: true,
            file_tree_width: 25,
        }
    }
}

impl Default for Theme {
    fn default() -> Self {
        Self {
            primary: "#61afef".to_string(),
            secondary: "#c678dd".to_string(),
            background: "#282c34".to_string(),
            foreground: "#abb2bf".to_string(),
            syntax: SyntaxTheme::default(),
        }
    }
}

impl Default for SyntaxTheme {
    fn default() -> Self {
        Self {
            keyword: "#c678dd".to_string(),
            string: "#98c379".to_string(),
            comment: "#5c6370".to_string(),
            function: "#61afef".to_string(),
            variable: "#e06c75".to_string(),
            constant: "#d19a66".to_string(),
        }
    }
}

impl Default for KeyBindings {
    fn default() -> Self {
        Self {
            quit: vec!["q".to_string(), "Ctrl+c".to_string(), "Esc".to_string()],
            up: vec!["k".to_string(), "Up".to_string()],
            down: vec!["j".to_string(), "Down".to_string()],
            left: vec!["h".to_string(), "Left".to_string()],
            right: vec!["l".to_string(), "Right".to_string()],
            select: vec!["Enter".to_string(), "Space".to_string()],
            back: vec!["Backspace".to_string(), "Esc".to_string()],
            open_file: vec!["o".to_string()],
            save_file: vec!["Ctrl+s".to_string()],
            new_file: vec!["n".to_string()],
            refresh: vec!["r".to_string(), "F5".to_string()],
            build: vec!["b".to_string(), "F6".to_string()],
            test: vec!["t".to_string(), "F7".to_string()],
            format: vec!["f".to_string(), "F8".to_string()],
            switch_pane: vec!["Tab".to_string()],
            toggle_tree: vec!["Ctrl+t".to_string()],
            toggle_log: vec!["Ctrl+l".to_string()],
        }
    }
}

impl Default for EditorConfig {
    fn default() -> Self {
        Self {
            tab_size: 2,
            use_spaces: true,
            show_whitespace: false,
            word_wrap: true,
            auto_save_interval: 0,
        }
    }
}

impl Default for ProjectConfig {
    fn default() -> Self {
        Self {
            auto_refresh: true,
            refresh_interval: 5,
            ignore_patterns: vec![
                "_build".to_string(),
                "deps".to_string(),
                ".git".to_string(),
                "node_modules".to_string(),
                "target".to_string(),
                "*.beam".to_string(),
                "*.o".to_string(),
                "*.so".to_string(),
                ".DS_Store".to_string(),
            ],
            watch_files: true,
        }
    }
}