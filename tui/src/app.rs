use anyhow::Result;
use crossterm::{
    event::{DisableMouseCapture, EnableMouseCapture, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{prelude::*, DefaultTerminal};
use serde_json;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tracing::{debug, error, info};

use crate::{
    config::Config,
    events::EventHandler,
    message::{Message, TuiEvent},
    nats_client::NatsManager,
    state::AppState,
    ui::render_ui,
};

/// Main application following The Elm Architecture (TEA) pattern
pub struct App {
    state: AppState,
    nats_manager: NatsManager,
    event_handler: EventHandler,
    event_tx: mpsc::UnboundedSender<Message>,
    event_rx: mpsc::UnboundedReceiver<Message>,
    last_render: Instant,
    should_quit: bool,
}

impl App {
    pub async fn new(config: Config, nats_url: String, project_dir: String) -> Result<Self> {
        let (event_tx, event_rx) = mpsc::unbounded_channel();

        // Initialize NATS connection
        let nats_manager = NatsManager::new(nats_url, event_tx.clone()).await?;

        // Initialize application state
        let state = AppState::new(project_dir, config.clone());

        // Initialize event handler
        let event_handler = EventHandler::new(event_tx.clone());

        Ok(Self {
            state,
            nats_manager,
            event_handler,
            event_tx,
            event_rx,
            last_render: Instant::now(),
            should_quit: false,
        })
    }

    pub async fn run(&mut self) -> Result<()> {
        // Setup terminal
        enable_raw_mode()?;
        let mut stdout = std::io::stdout();
        execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
        let backend = CrosstermBackend::new(stdout);
        let mut terminal = Terminal::new(backend)?;

        info!("TUI initialized, starting main loop");

        // Start background tasks
        self.start_background_tasks().await?;

        // Main event loop
        let result = self.run_event_loop(&mut terminal).await;

        // Cleanup terminal
        disable_raw_mode()?;
        execute!(
            terminal.backend_mut(),
            LeaveAlternateScreen,
            DisableMouseCapture
        )?;
        terminal.show_cursor()?;

        result
    }

    async fn start_background_tasks(&mut self) -> Result<()> {
        // Start NATS message processing
        self.nats_manager.start_message_processing().await?;

        // Start terminal event handling
        self.event_handler.start_terminal_events().await?;

        info!("Background tasks started");
        Ok(())
    }

    async fn run_event_loop(&mut self, terminal: &mut DefaultTerminal) -> Result<()> {
        // Initial render
        terminal.draw(|f| render_ui(f, &self.state))?;

        loop {
            // Handle events with controlled frame rate
            tokio::select! {
                // Handle messages from various sources
                Some(message) = self.event_rx.recv() => {
                    if let Err(e) = self.handle_message(message).await {
                        error!("Error handling message: {}", e);
                    }
                }

                // Handle terminal events
                _ = tokio::time::sleep(Duration::from_millis(16)) => {
                    // 60 FPS cap
                    if self.should_render() {
                        terminal.draw(|f| render_ui(f, &self.state))?;
                        self.last_render = Instant::now();
                    }
                }
            }

            if self.should_quit {
                break;
            }
        }

        Ok(())
    }

    async fn handle_message(&mut self, message: Message) -> Result<()> {
        debug!("Handling message: {:?}", message);

        match message {
            Message::TuiEvent(event) => self.handle_tui_event(event).await,
            Message::NatsMessage { topic, data } => self.handle_nats_message(topic, data).await,
            Message::FileChanged { path, content } => self.handle_file_changed(path, content).await,
            Message::BuildCompleted { status, output } => {
                self.handle_build_completed(status, output).await
            }
            Message::Quit => {
                self.should_quit = true;
                Ok(())
            }
        }
    }

    async fn handle_tui_event(&mut self, event: TuiEvent) -> Result<()> {
        match event {
            TuiEvent::Key(key) => {
                match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => {
                        self.should_quit = true;
                    }
                    KeyCode::Char('r') => {
                        self.refresh_project().await?;
                    }
                    KeyCode::Up => {
                        self.state.navigate_up();
                    }
                    KeyCode::Down => {
                        self.state.navigate_down();
                    }
                    KeyCode::Enter => {
                        self.handle_selection().await?;
                    }
                    KeyCode::Tab => {
                        self.state.switch_pane();
                    }
                    _ => {}
                }
            }
            TuiEvent::Resize(width, height) => {
                self.state.update_terminal_size(width, height);
            }
        }

        self.mark_for_render();
        Ok(())
    }

    async fn handle_nats_message(&mut self, topic: String, data: Vec<u8>) -> Result<()> {
        debug!("Received NATS message on topic: {}", topic);

        // Deserialize message
        let message: serde_json::Value = rmp_serde::from_slice(&data)?;

        // Route message based on topic
        if topic.starts_with("otp.event.") {
            self.handle_otp_event(topic, message).await?;
        } else if topic.starts_with("otp.response.") {
            self.handle_otp_response(topic, message).await?;
        }

        self.mark_for_render();
        Ok(())
    }

    async fn handle_file_changed(&mut self, path: String, content: String) -> Result<()> {
        info!("File changed: {}", path);
        self.state.update_file_content(path, content);
        self.mark_for_render();
        Ok(())
    }

    async fn handle_build_completed(&mut self, status: String, output: String) -> Result<()> {
        info!("Build completed with status: {}", status);
        self.state.update_build_status(status, output);
        self.mark_for_render();
        Ok(())
    }

    async fn handle_otp_event(&mut self, topic: String, message: serde_json::Value) -> Result<()> {
        debug!("Handling OTP event: {} - {:?}", topic, message);
        self.state.add_event_log(format!("OTP Event: {}", topic));
        Ok(())
    }

    async fn handle_otp_response(&mut self, topic: String, message: serde_json::Value) -> Result<()> {
        debug!("Handling OTP response: {} - {:?}", topic, message);
        self.state.add_event_log(format!("OTP Response: {}", topic));
        Ok(())
    }

    async fn refresh_project(&mut self) -> Result<()> {
        info!("Refreshing project data");

        // Send request to OTP application for project refresh
        let request = serde_json::json!({
            "action": "refresh_project",
            "timestamp": chrono::Utc::now().timestamp_millis()
        });

        self.nats_manager
            .publish("tui.command.project.refresh".to_string(), request)
            .await?;

        self.state.add_event_log("Project refresh requested".to_string());
        Ok(())
    }

    async fn handle_selection(&mut self) -> Result<()> {
        if let Some(selected_file) = self.state.get_selected_file() {
            info!("Opening file: {}", selected_file);

            // Send file open request to OTP application
            let request = serde_json::json!({
                "action": "open",
                "path": selected_file,
                "timestamp": chrono::Utc::now().timestamp_millis()
            });

            self.nats_manager
                .publish("tui.command.file.open".to_string(), request)
                .await?;

            self.state
                .add_event_log(format!("Requested to open: {}", selected_file));
        }

        Ok(())
    }

    fn should_render(&self) -> bool {
        self.last_render.elapsed() >= Duration::from_millis(16) // 60 FPS cap
    }

    fn mark_for_render(&mut self) {
        // Force render on next cycle by setting last_render to past
        self.last_render = Instant::now() - Duration::from_millis(20);
    }
}