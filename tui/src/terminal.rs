use anyhow::{Context, Result};
use crossterm::{
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{
        disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
        size, supports_color, Clear, ClearType,
    },
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io::{self, Stdout};
use tracing::{debug, info, warn};

/// Terminal capabilities and management
#[derive(Debug, Clone)]
pub struct TerminalCapabilities {
    pub supports_color: bool,
    pub supports_unicode: bool,
    pub width: u16,
    pub height: u16,
    pub supports_mouse: bool,
    pub supports_keyboard_enhancement: bool,
}

impl TerminalCapabilities {
    /// Detect terminal capabilities with fallbacks
    pub fn detect() -> Result<Self> {
        let (width, height) = size().unwrap_or((80, 24));
        
        // Basic color support detection
        let supports_color = supports_color();
        
        // Unicode support detection (basic heuristic)
        let supports_unicode = std::env::var("LC_ALL")
            .or_else(|_| std::env::var("LC_CTYPE"))
            .or_else(|_| std::env::var("LANG"))
            .map(|s| s.to_lowercase().contains("utf"))
            .unwrap_or(true); // Default to true
        
        // Mouse support detection (assume supported, will fallback if needed)
        let supports_mouse = true;
        
        // Keyboard enhancement detection (modern terminal features)
        let supports_keyboard_enhancement = std::env::var("TERM")
            .map(|term| {
                term.contains("xterm") || 
                term.contains("screen") || 
                term.contains("tmux") ||
                term.contains("alacritty") ||
                term.contains("wezterm")
            })
            .unwrap_or(false);

        let capabilities = Self {
            supports_color,
            supports_unicode,
            width,
            height,
            supports_mouse,
            supports_keyboard_enhancement,
        };

        info!("Terminal capabilities detected: {:?}", capabilities);
        Ok(capabilities)
    }

    /// Check if terminal size is adequate for the TUI
    pub fn is_size_adequate(&self) -> bool {
        self.width >= 80 && self.height >= 24
    }

    /// Get recommended fallback message if terminal is inadequate
    pub fn get_fallback_message(&self) -> Option<String> {
        if !self.is_size_adequate() {
            Some(format!(
                "Terminal size {}x{} is too small. Minimum recommended: 80x24",
                self.width, self.height
            ))
        } else if !self.supports_color {
            Some("Color support not detected. TUI will use monochrome mode.".to_string())
        } else {
            None
        }
    }
}

/// Enhanced terminal manager with capability handling
pub struct TerminalManager {
    pub capabilities: TerminalCapabilities,
    terminal: Option<Terminal<CrosstermBackend<Stdout>>>,
    raw_mode_enabled: bool,
    alternate_screen_enabled: bool,
    mouse_enabled: bool,
}

impl TerminalManager {
    /// Create new terminal manager with capability detection
    pub fn new() -> Result<Self> {
        let capabilities = TerminalCapabilities::detect()
            .context("Failed to detect terminal capabilities")?;

        Ok(Self {
            capabilities,
            terminal: None,
            raw_mode_enabled: false,
            alternate_screen_enabled: false,
            mouse_enabled: false,
        })
    }

    /// Initialize terminal with graceful fallbacks
    pub fn initialize(&mut self) -> Result<()> {
        info!("Initializing terminal with capabilities: {:?}", self.capabilities);

        // Check if we can provide a good experience
        if let Some(fallback_msg) = self.capabilities.get_fallback_message() {
            warn!("Terminal limitation detected: {}", fallback_msg);
        }

        // Ensure minimum terminal size
        if !self.capabilities.is_size_adequate() {
            return Err(anyhow::anyhow!(
                "Terminal size {}x{} is inadequate. Please resize to at least 80x24.",
                self.capabilities.width, self.capabilities.height
            ));
        }

        // Setup raw mode with error handling
        self.setup_raw_mode()
            .context("Failed to enable raw mode")?;

        // Setup alternate screen with error handling
        self.setup_alternate_screen()
            .context("Failed to setup alternate screen")?;

        // Setup mouse capture if supported
        if self.capabilities.supports_mouse {
            self.setup_mouse_capture()
                .context("Failed to setup mouse capture (continuing without mouse support)")?;
        } else {
            debug!("Mouse support disabled due to terminal limitations");
        }

        // Initialize the terminal backend
        let backend = CrosstermBackend::new(io::stdout());
        let terminal = Terminal::new(backend)
            .context("Failed to create terminal")?;

        self.terminal = Some(terminal);

        info!("Terminal initialized successfully");
        Ok(())
    }

    /// Get mutable reference to terminal
    pub fn terminal_mut(&mut self) -> Result<&mut Terminal<CrosstermBackend<Stdout>>> {
        self.terminal.as_mut()
            .ok_or_else(|| anyhow::anyhow!("Terminal not initialized"))
    }

    /// Cleanup terminal state
    pub fn cleanup(&mut self) -> Result<()> {
        info!("Cleaning up terminal");

        // Clear the screen first
        if let Some(ref mut terminal) = self.terminal {
            let _ = terminal.clear();
            let _ = execute!(terminal.backend_mut(), Clear(ClearType::All));
        }

        // Cleanup in reverse order of setup
        if self.mouse_enabled {
            self.cleanup_mouse_capture()?;
        }

        if self.alternate_screen_enabled {
            self.cleanup_alternate_screen()?;
        }

        if self.raw_mode_enabled {
            self.cleanup_raw_mode()?;
        }

        // Show cursor
        if let Some(ref mut terminal) = self.terminal {
            let _ = terminal.show_cursor();
        }

        info!("Terminal cleanup completed");
        Ok(())
    }

    /// Setup raw mode with error handling
    fn setup_raw_mode(&mut self) -> Result<()> {
        enable_raw_mode()
            .context("Failed to enable raw mode")?;
        self.raw_mode_enabled = true;
        debug!("Raw mode enabled");
        Ok(())
    }

    /// Setup alternate screen
    fn setup_alternate_screen(&mut self) -> Result<()> {
        execute!(io::stdout(), EnterAlternateScreen)
            .context("Failed to enter alternate screen")?;
        self.alternate_screen_enabled = true;
        debug!("Alternate screen enabled");
        Ok(())
    }

    /// Setup mouse capture with graceful fallback
    fn setup_mouse_capture(&mut self) -> Result<()> {
        match execute!(io::stdout(), EnableMouseCapture) {
            Ok(_) => {
                self.mouse_enabled = true;
                debug!("Mouse capture enabled");
                Ok(())
            }
            Err(e) => {
                warn!("Failed to enable mouse capture: {}. Continuing without mouse support.", e);
                self.mouse_enabled = false;
                Ok(()) // Continue without mouse support
            }
        }
    }

    /// Cleanup mouse capture
    fn cleanup_mouse_capture(&mut self) -> Result<()> {
        if self.mouse_enabled {
            execute!(io::stdout(), DisableMouseCapture)
                .context("Failed to disable mouse capture")?;
            self.mouse_enabled = false;
            debug!("Mouse capture disabled");
        }
        Ok(())
    }

    /// Cleanup alternate screen
    fn cleanup_alternate_screen(&mut self) -> Result<()> {
        if self.alternate_screen_enabled {
            execute!(io::stdout(), LeaveAlternateScreen)
                .context("Failed to leave alternate screen")?;
            self.alternate_screen_enabled = false;
            debug!("Alternate screen disabled");
        }
        Ok(())
    }

    /// Cleanup raw mode
    fn cleanup_raw_mode(&mut self) -> Result<()> {
        if self.raw_mode_enabled {
            disable_raw_mode()
                .context("Failed to disable raw mode")?;
            self.raw_mode_enabled = false;
            debug!("Raw mode disabled");
        }
        Ok(())
    }

    /// Handle terminal resize
    pub fn handle_resize(&mut self, width: u16, height: u16) -> Result<()> {
        self.capabilities.width = width;
        self.capabilities.height = height;
        
        debug!("Terminal resized to {}x{}", width, height);
        
        // Check if new size is adequate
        if !self.capabilities.is_size_adequate() {
            warn!("Terminal resized to inadequate size: {}x{}", width, height);
            return Err(anyhow::anyhow!(
                "Terminal too small after resize: {}x{}. Minimum: 80x24",
                width, height
            ));
        }

        Ok(())
    }

    /// Check if terminal is properly initialized
    pub fn is_initialized(&self) -> bool {
        self.terminal.is_some() && self.raw_mode_enabled
    }

    /// Get current terminal size
    pub fn size(&self) -> (u16, u16) {
        (self.capabilities.width, self.capabilities.height)
    }
}

impl Drop for TerminalManager {
    fn drop(&mut self) {
        // Ensure cleanup happens even if not called explicitly
        let _ = self.cleanup();
    }
}

/// Utility function for graceful terminal error handling
pub fn handle_terminal_error(error: anyhow::Error) -> ! {
    // Try to cleanup terminal state before showing error
    let _ = disable_raw_mode();
    let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);
    
    eprintln!("Terminal error: {}", error);
    eprintln!("\nPossible solutions:");
    eprintln!("  - Ensure your terminal supports ANSI escape sequences");
    eprintln!("  - Try resizing your terminal to at least 80x24");
    eprintln!("  - Check that your TERM environment variable is set correctly");
    eprintln!("  - Use a modern terminal emulator (Alacritty, WezTerm, iTerm2, etc.)");
    
    std::process::exit(1);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_terminal_capabilities_detection() {
        let caps = TerminalCapabilities::detect().unwrap();
        
        // Basic sanity checks
        assert!(caps.width > 0);
        assert!(caps.height > 0);
        
        // Should have reasonable default values
        if caps.width < 80 || caps.height < 24 {
            assert!(!caps.is_size_adequate());
        }
    }

    #[test]
    fn test_size_adequacy() {
        let caps = TerminalCapabilities {
            supports_color: true,
            supports_unicode: true,
            width: 79,
            height: 23,
            supports_mouse: true,
            supports_keyboard_enhancement: false,
        };
        
        assert!(!caps.is_size_adequate());
        
        let caps_adequate = TerminalCapabilities {
            width: 80,
            height: 24,
            ..caps
        };
        
        assert!(caps_adequate.is_size_adequate());
    }

    #[test]
    fn test_fallback_messages() {
        let small_caps = TerminalCapabilities {
            supports_color: true,
            supports_unicode: true,
            width: 60,
            height: 20,
            supports_mouse: true,
            supports_keyboard_enhancement: false,
        };
        
        assert!(small_caps.get_fallback_message().is_some());
        
        let no_color_caps = TerminalCapabilities {
            supports_color: false,
            supports_unicode: true,
            width: 80,
            height: 24,
            supports_mouse: true,
            supports_keyboard_enhancement: false,
        };
        
        assert!(no_color_caps.get_fallback_message().is_some());
        
        let good_caps = TerminalCapabilities {
            supports_color: true,
            supports_unicode: true,
            width: 120,
            height: 40,
            supports_mouse: true,
            supports_keyboard_enhancement: true,
        };
        
        assert!(good_caps.get_fallback_message().is_none());
    }
}