use ratatui::{prelude::*, DefaultTerminal};

/// TUI wrapper and utilities
pub struct Tui {
    terminal: DefaultTerminal,
}

impl Tui {
    pub fn new(terminal: DefaultTerminal) -> Self {
        Self { terminal }
    }

    pub fn draw<F>(&mut self, render_fn: F) -> std::io::Result<()>
    where
        F: FnOnce(&mut Frame),
    {
        self.terminal.draw(render_fn)?;
        Ok(())
    }
}