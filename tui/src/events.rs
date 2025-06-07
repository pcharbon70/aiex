use anyhow::Result;
use crossterm::event::{self, Event};
use tokio::sync::mpsc;
use tracing::debug;

use crate::message::{Message, TuiEvent};

/// Handles terminal events and forwards them as messages
pub struct EventHandler {
    event_tx: mpsc::UnboundedSender<Message>,
}

impl EventHandler {
    pub fn new(event_tx: mpsc::UnboundedSender<Message>) -> Self {
        Self { event_tx }
    }

    pub async fn start_terminal_events(&self) -> Result<()> {
        let event_tx = self.event_tx.clone();

        tokio::spawn(async move {
            loop {
                match event::read() {
                    Ok(Event::Key(key)) => {
                        debug!("Key event: {:?}", key);
                        let _ = event_tx.send(Message::TuiEvent(TuiEvent::Key(key)));
                    }
                    Ok(Event::Resize(width, height)) => {
                        debug!("Resize event: {}x{}", width, height);
                        let _ = event_tx.send(Message::TuiEvent(TuiEvent::Resize(width, height)));
                    }
                    Ok(_) => {} // Ignore other events
                    Err(e) => {
                        tracing::error!("Error reading terminal event: {}", e);
                        break;
                    }
                }
            }
        });

        Ok(())
    }
}