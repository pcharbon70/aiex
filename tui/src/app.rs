use anyhow::{Context, Result};
use chrono;
use crossterm::event::KeyCode;
use ratatui::prelude::*;
use serde_json;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

use crate::{
    config::Config,
    events::EventHandler,
    message::{Message, TuiEvent},
    otp_client::OtpClient,
    state::AppState,
    terminal::{TerminalManager, handle_terminal_error},
    ui::render_ui,
};

/// Main application following The Elm Architecture (TEA) pattern
pub struct App {
    state: AppState,
    otp_client: OtpClient,
    event_handler: EventHandler,
    terminal_manager: TerminalManager,
    event_tx: mpsc::UnboundedSender<Message>,
    event_rx: mpsc::UnboundedReceiver<Message>,
    last_render: Instant,
    should_quit: bool,
    frame_count: u64,
    start_time: Instant,
}

impl App {
    pub async fn new(config: Config, otp_addr: String, project_dir: String) -> Result<Self> {
        let (event_tx, event_rx) = mpsc::unbounded_channel();

        // Initialize terminal manager with capability detection
        let terminal_manager = TerminalManager::new()
            .context("Failed to initialize terminal manager")?;

        // Check terminal capabilities
        if let Some(warning) = terminal_manager.capabilities.get_fallback_message() {
            warn!("Terminal capability warning: {}", warning);
        }

        // Initialize OTP connection
        let otp_client = OtpClient::new(otp_addr, event_tx.clone()).await
            .context("Failed to connect to OTP server")?;

        // Initialize application state with terminal capabilities
        let mut state = AppState::new(project_dir, config.clone());
        state.update_terminal_size(
            terminal_manager.capabilities.width, 
            terminal_manager.capabilities.height
        );

        // Initialize event handler
        let event_handler = EventHandler::new(event_tx.clone());

        let now = Instant::now();

        Ok(Self {
            state,
            otp_client,
            event_handler,
            terminal_manager,
            event_tx,
            event_rx,
            last_render: now,
            should_quit: false,
            frame_count: 0,
            start_time: now,
        })
    }

    pub async fn run(&mut self) -> Result<()> {
        // Initialize terminal with graceful error handling
        if let Err(e) = self.terminal_manager.initialize() {
            handle_terminal_error(e);
        }

        info!("TUI initialized successfully with terminal capabilities: {:?}", 
               self.terminal_manager.capabilities);

        // Start background tasks
        self.start_background_tasks().await
            .context("Failed to start background tasks")?;

        // Main event loop with comprehensive error handling
        let result = self.run_event_loop().await;

        // Cleanup terminal (always happens, even on error)
        if let Err(cleanup_err) = self.terminal_manager.cleanup() {
            error!("Failed to cleanup terminal: {}", cleanup_err);
        }

        // Return the result from event loop
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

    async fn run_event_loop(&mut self) -> Result<()> {
        // Get terminal reference
        let terminal = self.terminal_manager.terminal_mut()
            .context("Terminal not properly initialized")?;

        // Initial render with error handling
        if let Err(e) = terminal.draw(|f| render_ui(f, &self.state)) {
            error!("Failed to render initial UI: {}", e);
            return Err(e.into());
        }

        info!("Starting main event loop");

        loop {
            // Handle events with controlled frame rate (60 FPS)
            tokio::select! {
                // Handle messages from various sources
                Some(message) = self.event_rx.recv() => {
                    if let Err(e) = self.handle_message(message).await {
                        error!("Error handling message: {}", e);
                        // Continue running unless it's a critical error
                        if e.to_string().contains("critical") {
                            break;
                        }
                    }
                }

                // Controlled rendering with frame rate limiting
                _ = tokio::time::sleep(Duration::from_millis(16)) => {
                    if self.should_render() {
                        match terminal.draw(|f| render_ui(f, &self.state)) {
                            Ok(_) => {
                                self.last_render = Instant::now();
                                self.frame_count += 1;
                                
                                // Log performance stats periodically
                                if self.frame_count % 600 == 0 { // Every 10 seconds at 60 FPS
                                    let elapsed = self.start_time.elapsed();
                                    let fps = self.frame_count as f64 / elapsed.as_secs_f64();
                                    debug!("Average FPS: {:.1}, Total frames: {}", fps, self.frame_count);
                                }
                            }
                            Err(e) => {
                                error!("Failed to render frame: {}", e);
                                // Try to continue, but if rendering keeps failing, exit
                                static mut RENDER_ERRORS: u32 = 0;
                                unsafe {
                                    RENDER_ERRORS += 1;
                                    if RENDER_ERRORS > 10 {
                                        return Err(anyhow::anyhow!("Too many consecutive render errors"));
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if self.should_quit {
                info!("Application shutdown requested");
                break;
            }
        }

        info!("Event loop completed. Total frames rendered: {}", self.frame_count);
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
                // Handle resize with terminal manager
                if let Err(e) = self.terminal_manager.handle_resize(width, height) {
                    error!("Terminal resize error: {}", e);
                    // For critical resize errors (too small), we might want to quit
                    if e.to_string().contains("too small") {
                        self.should_quit = true;
                    }
                } else {
                    self.state.update_terminal_size(width, height);
                    info!("Terminal resized to {}x{}", width, height);
                }
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