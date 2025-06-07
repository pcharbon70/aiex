use anyhow::Result;
use chrono;
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
    otp_client::OtpClient,
    state::AppState,
    ui::render_ui,
};

/// Main application following The Elm Architecture (TEA) pattern
pub struct App {
    state: AppState,
    otp_client: OtpClient,
    event_handler: EventHandler,
    event_tx: mpsc::UnboundedSender<Message>,
    event_rx: mpsc::UnboundedReceiver<Message>,
    last_render: Instant,
    should_quit: bool,
}

impl App {
    pub async fn new(config: Config, otp_addr: String, project_dir: String) -> Result<Self> {
        let (event_tx, event_rx) = mpsc::unbounded_channel();

        // Initialize OTP connection
        let otp_client = OtpClient::new(otp_addr, event_tx.clone()).await?;

        // Initialize application state
        let state = AppState::new(project_dir, config.clone());

        // Initialize event handler
        let event_handler = EventHandler::new(event_tx.clone());

        Ok(Self {
            state,
            otp_client,
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
        // Create a new OTP client for background processing
        // (we keep the original for potential direct operations)
        let mut otp_client = OtpClient::new(
            self.otp_client.server_addr.clone(),
            self.event_tx.clone(),
        ).await?;
        
        tokio::spawn(async move {
            if let Err(e) = otp_client.run().await {
                error!("OTP client error: {}", e);
            }
        });

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
            Message::ConnectionStatus { connected, details } => {
                self.handle_connection_status(connected, details).await
            }
            Message::OtpEvent { event_type, data } => self.handle_otp_event(event_type, data).await,
            Message::CommandResult { request_id, result } => {
                self.handle_command_result(request_id, result).await
            }
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

    async fn handle_connection_status(&mut self, connected: bool, details: String) -> Result<()> {
        debug!("Connection status changed: connected={}, details={}", connected, details);
        
        if connected {
            self.state.add_event_log("Connected to OTP server".to_string());
        } else {
            self.state.add_event_log(format!("Disconnected from OTP server: {}", details));
        }
        
        self.mark_for_render();
        Ok(())
    }

    async fn handle_command_result(&mut self, request_id: String, result: serde_json::Value) -> Result<()> {
        debug!("Command result for {}: {:?}", request_id, result);
        self.state.add_event_log(format!("Command {} completed", request_id));
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

    async fn handle_otp_event(&mut self, event_type: String, data: serde_json::Value) -> Result<()> {
        debug!("Handling OTP event: {} - {:?}", event_type, data);
        self.state.add_event_log(format!("OTP Event: {}", event_type));
        Ok(())
    }

    async fn refresh_project(&mut self) -> Result<()> {
        info!("Refreshing project data");

        // Send request to OTP application for project refresh
        let request = serde_json::json!({
            "action": "refresh_project",
            "timestamp": chrono::Utc::now().timestamp_millis()
        });

        // Note: OtpClient was moved in start_background_tasks, so we can't call it directly
        // We'll send the event through the event channel instead
        let _ = self.event_tx.send(crate::message::Message::CommandResult {
            request_id: "refresh_project".to_string(),
            result: request,
        });

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

            // Note: OtpClient was moved in start_background_tasks, so we can't call it directly
            // We'll send the event through the event channel instead
            let _ = self.event_tx.send(crate::message::Message::CommandResult {
                request_id: format!("open_file_{}", selected_file),
                result: request,
            });

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