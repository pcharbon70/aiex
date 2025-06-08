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
    chat_ui::render_chat_ui,
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

        // Request initial context updates from OTP backend
        self.request_initial_context().await
            .context("Failed to request initial context")?;

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
        if let Err(e) = terminal.draw(|f| render_chat_ui(f, &self.state)) {
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
                        match terminal.draw(|f| render_chat_ui(f, &self.state)) {
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
                // Save conversation before quitting
                if let Err(e) = self.state.save_conversation() {
                    error!("Failed to save conversation on quit: {}", e);
                }
                self.should_quit = true;
                Ok(())
            }
        }
    }

    async fn handle_tui_event(&mut self, event: TuiEvent) -> Result<()> {
        match event {
            TuiEvent::Key(key) => {
                // Handle global shortcuts first
                match (key.code, key.modifiers) {
                    // Global shortcuts
                    (KeyCode::Char('q'), crossterm::event::KeyModifiers::CONTROL) => {
                        self.should_quit = true;
                        return Ok(());
                    }
                    (KeyCode::F(1), _) => {
                        self.state.toggle_context_panel();
                        self.mark_for_render();
                        return Ok(());
                    }
                    (KeyCode::F(2), _) => {
                        self.state.toggle_quick_actions();
                        self.mark_for_render();
                        return Ok(());
                    }
                    (KeyCode::F(3), _) => {
                        // Focus on conversation history
                        self.state.focus_conversation_history();
                        self.mark_for_render();
                        return Ok(());
                    }
                    (KeyCode::F(4), _) => {
                        // Focus on message input
                        self.state.focus_message_input();
                        self.mark_for_render();
                        return Ok(());
                    }
                    // Tab navigation (forward and backward)
                    (KeyCode::Tab, crossterm::event::KeyModifiers::SHIFT) => {
                        self.state.switch_pane_backward();
                        self.mark_for_render();
                        return Ok(());
                    }
                    (KeyCode::Tab, _) => {
                        self.state.switch_pane_forward();
                        self.mark_for_render();
                        return Ok(());
                    }
                    (KeyCode::BackTab, _) => {
                        // Alternative for Shift+Tab on some terminals
                        self.state.switch_pane_backward();
                        self.mark_for_render();
                        return Ok(());
                    }
                    // Quick focus shortcuts
                    (KeyCode::Char('1'), crossterm::event::KeyModifiers::ALT) => {
                        self.state.focus_message_input();
                        self.mark_for_render();
                        return Ok(());
                    }
                    (KeyCode::Char('2'), crossterm::event::KeyModifiers::ALT) => {
                        self.state.focus_conversation_history();
                        self.mark_for_render();
                        return Ok(());
                    }
                    (KeyCode::Char('3'), crossterm::event::KeyModifiers::ALT) => {
                        self.state.focus_context_panel();
                        self.mark_for_render();
                        return Ok(());
                    }
                    (KeyCode::Char('4'), crossterm::event::KeyModifiers::ALT) => {
                        self.state.focus_quick_actions();
                        self.mark_for_render();
                        return Ok(());
                    }
                    _ => {}
                }

                // Handle panel-specific shortcuts
                match self.state.current_pane {
                    crate::state::Pane::MessageInput => {
                        match (key.code, key.modifiers) {
                            // Message sending
                            (KeyCode::Enter, crossterm::event::KeyModifiers::CONTROL) => {
                                let content = self.state.chat_state.current_input.clone();
                                if !content.trim().is_empty() {
                                    self.send_user_message(content).await?;
                                }
                            }
                            (KeyCode::Enter, crossterm::event::KeyModifiers::SHIFT) => {
                                // Shift+Enter adds a newline
                                self.state.chat_state.current_input.push('\n');
                            }
                            // Text input
                            (KeyCode::Char(c), crossterm::event::KeyModifiers::NONE) => {
                                self.state.chat_state.current_input.push(c);
                            }
                            (KeyCode::Char(c), crossterm::event::KeyModifiers::SHIFT) => {
                                self.state.chat_state.current_input.push(c);
                            }
                            // Text navigation and editing
                            (KeyCode::Backspace, _) => {
                                self.state.chat_state.current_input.pop();
                            }
                            (KeyCode::Delete, _) => {
                                // For now, same as backspace
                                self.state.chat_state.current_input.pop();
                            }
                            (KeyCode::Esc, _) => {
                                self.state.chat_state.current_input.clear();
                            }
                            // Quick shortcuts from input
                            (KeyCode::Up, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_conversation_history();
                            }
                            (KeyCode::Left, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_context_panel();
                            }
                            (KeyCode::Right, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_quick_actions();
                            }
                            _ => {}
                        }
                    }
                    crate::state::Pane::ConversationHistory => {
                        match (key.code, key.modifiers) {
                            // Navigation
                            (KeyCode::Up, _) => {
                                self.state.navigate_up();
                            }
                            (KeyCode::Down, _) => {
                                self.state.navigate_down();
                            }
                            (KeyCode::Home, _) => {
                                self.state.chat_state.scroll_to_top();
                            }
                            (KeyCode::End, _) => {
                                self.state.chat_state.scroll_to_bottom();
                            }
                            (KeyCode::PageUp, _) => {
                                // Scroll up by 5 messages
                                for _ in 0..5 {
                                    self.state.navigate_up();
                                }
                            }
                            (KeyCode::PageDown, _) => {
                                // Scroll down by 5 messages
                                for _ in 0..5 {
                                    self.state.navigate_down();
                                }
                            }
                            // Quick actions
                            (KeyCode::Enter, _) => {
                                // Focus back to input for response
                                self.state.focus_message_input();
                            }
                            (KeyCode::Char('/'), _) => {
                                // Start search mode (placeholder - would need search input handling)
                                info!("Search mode activated");
                            }
                            (KeyCode::Char('n'), _) => {
                                // New conversation
                                let conversation_id = self.state.start_new_conversation();
                                info!("Started new conversation: {}", conversation_id);
                            }
                            (KeyCode::Char('s'), crossterm::event::KeyModifiers::CONTROL) => {
                                // Save conversation
                                if let Err(e) = self.state.save_conversation() {
                                    error!("Failed to save conversation: {}", e);
                                } else {
                                    info!("Conversation saved successfully");
                                }
                            }
                            // Quick focus shortcuts from conversation
                            (KeyCode::Down, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_message_input();
                            }
                            (KeyCode::Left, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_context_panel();
                            }
                            (KeyCode::Right, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_quick_actions();
                            }
                            _ => {}
                        }
                    }
                    crate::state::Pane::Context => {
                        match (key.code, key.modifiers) {
                            // Navigation
                            (KeyCode::Up, _) => {
                                self.state.navigate_up();
                            }
                            (KeyCode::Down, _) => {
                                self.state.navigate_down();
                            }
                            (KeyCode::Home, _) => {
                                self.state.layout_state.context_scroll = 0;
                            }
                            (KeyCode::End, _) => {
                                self.state.layout_state.context_scroll = 
                                    self.state.layout_state.context_items.len().saturating_sub(1);
                            }
                            (KeyCode::PageUp, _) => {
                                for _ in 0..3 {
                                    self.state.navigate_up();
                                }
                            }
                            (KeyCode::PageDown, _) => {
                                for _ in 0..3 {
                                    self.state.navigate_down();
                                }
                            }
                            // Actions
                            (KeyCode::Enter, _) => {
                                if let Some(item) = self.state.layout_state.get_selected_context_item() {
                                    self.handle_context_selection(item).await?;
                                }
                            }
                            (KeyCode::Space, _) => {
                                // Alternative selection
                                if let Some(item) = self.state.layout_state.get_selected_context_item() {
                                    self.handle_context_selection(item).await?;
                                }
                            }
                            // Quick focus shortcuts from context
                            (KeyCode::Right, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_quick_actions();
                            }
                            (KeyCode::Up, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_conversation_history();
                            }
                            (KeyCode::Down, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_message_input();
                            }
                            _ => {}
                        }
                    }
                    crate::state::Pane::QuickActions => {
                        match (key.code, key.modifiers) {
                            // Navigation
                            (KeyCode::Up, _) => {
                                self.state.navigate_up();
                            }
                            (KeyCode::Down, _) => {
                                self.state.navigate_down();
                            }
                            (KeyCode::Home, _) => {
                                self.state.layout_state.actions_scroll = 0;
                            }
                            (KeyCode::End, _) => {
                                self.state.layout_state.actions_scroll = 
                                    self.state.layout_state.quick_actions.len().saturating_sub(1);
                            }
                            (KeyCode::PageUp, _) => {
                                for _ in 0..3 {
                                    self.state.navigate_up();
                                }
                            }
                            (KeyCode::PageDown, _) => {
                                for _ in 0..3 {
                                    self.state.navigate_down();
                                }
                            }
                            // Actions
                            (KeyCode::Enter, _) => {
                                if let Some(action) = self.state.layout_state.get_selected_quick_action() {
                                    let action_clone = action.clone();
                                    self.execute_quick_action(&action_clone).await?;
                                }
                            }
                            (KeyCode::Space, _) => {
                                // Alternative execution
                                if let Some(action) = self.state.layout_state.get_selected_quick_action() {
                                    let action_clone = action.clone();
                                    self.execute_quick_action(&action_clone).await?;
                                }
                            }
                            // Quick key shortcuts (letter keys)
                            (KeyCode::Char(c), crossterm::event::KeyModifiers::NONE) => {
                                for action in &self.state.layout_state.quick_actions {
                                    if action.key() == &c.to_string() {
                                        let action_clone = action.clone();
                                        self.execute_quick_action(&action_clone).await?;
                                        break;
                                    }
                                }
                            }
                            // Quick focus shortcuts from actions
                            (KeyCode::Left, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_context_panel();
                            }
                            (KeyCode::Up, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_conversation_history();
                            }
                            (KeyCode::Down, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_message_input();
                            }
                            _ => {}
                        }
                    }
                    crate::state::Pane::CurrentStatus => {
                        match (key.code, key.modifiers) {
                            // Navigation away from status panel
                            (KeyCode::Up, _) => {
                                self.state.focus_conversation_history();
                            }
                            (KeyCode::Down, _) => {
                                self.state.focus_message_input();
                            }
                            (KeyCode::Left, _) => {
                                self.state.focus_context_panel();
                            }
                            (KeyCode::Right, _) => {
                                self.state.focus_quick_actions();
                            }
                            (KeyCode::Enter, _) => {
                                // Focus back to input
                                self.state.focus_message_input();
                            }
                            // Quick focus shortcuts from status
                            (KeyCode::Up, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_conversation_history();
                            }
                            (KeyCode::Down, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_message_input();
                            }
                            (KeyCode::Left, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_context_panel();
                            }
                            (KeyCode::Right, crossterm::event::KeyModifiers::CONTROL) => {
                                self.state.focus_quick_actions();
                            }
                            _ => {}
                        }
                    }
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
        
        // Check if this is an AI response
        if request_id.starts_with("chat_message_") || request_id.starts_with("quick_action_") {
            // Simulate AI response (in a real implementation, this would come from the OTP application)
            let ai_response = match result.get("action").and_then(|v| v.as_str()) {
                Some("chat_message") => {
                    format!("I understand you're asking about: {}. Let me help you with that. This is a simulated AI response that would normally come from the Elixir OTP application through the LLM integration.", 
                           result.get("content").and_then(|v| v.as_str()).unwrap_or("your message"))
                }
                Some("quick_action") => {
                    let action_type = result.get("action_type").and_then(|v| v.as_str()).unwrap_or("action");
                    format!("I'll help you with {}. Here's what I can do:\n\n1. Analyze your current code context\n2. Provide specific recommendations\n3. Generate code examples\n\nThis is a simulated response that would normally be processed by the distributed AI system.", action_type.to_lowercase())
                }
                _ => "I've processed your request. This is a simulated AI response.".to_string()
            };

            // Add AI response with simulated token count
            self.state.add_ai_response(ai_response, Some(50));
        } else {
            self.state.add_event_log(format!("Command {} completed", request_id));
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

    async fn handle_otp_event(&mut self, event_type: String, data: serde_json::Value) -> Result<()> {
        debug!("Handling OTP event: {} - {:?}", event_type, data);
        
        // Route events based on type to update context awareness
        match event_type.as_str() {
            // File system events
            "otp.event.file.changed" => {
                if let (Some(path), Some(change_type)) = (
                    data.get("file_path").and_then(|v| v.as_str()),
                    data.get("change_type").and_then(|v| v.as_str()),
                ) {
                    self.handle_file_system_event(path.to_string(), change_type.to_string(), data).await?;
                }
            }
            
            // Build events
            "otp.event.build.started" => {
                if let Some(project) = data.get("project").and_then(|v| v.as_str()) {
                    self.state.start_build();
                    self.state.add_system_message(format!("Build started for project: {}", project));
                }
            }
            "otp.event.build.completed" => {
                if let (Some(status), Some(output)) = (
                    data.get("status").and_then(|v| v.as_str()),
                    data.get("output").and_then(|v| v.as_str()),
                ) {
                    self.handle_build_completed(status.to_string(), output.to_string()).await?;
                }
            }
            
            // Error detection events
            "otp.event.error.detected" => {
                if let (Some(message), Some(file), line) = (
                    data.get("message").and_then(|v| v.as_str()),
                    data.get("file").and_then(|v| v.as_str()),
                    data.get("line").and_then(|v| v.as_u64()),
                ) {
                    self.handle_error_detected(message.to_string(), file.to_string(), line.map(|l| l as u32)).await?;
                }
            }
            
            // Context updates from Elixir backend
            "otp.event.pg.context_updates.join" => {
                self.handle_context_update(data).await?;
            }
            
            // LLM responses
            "otp.event.pg.model_responses.join" => {
                self.handle_llm_response(data).await?;
            }
            
            // Interface events
            "otp.event.pg.interface_events.join" => {
                self.handle_interface_event(data).await?;
            }
            
            _ => {
                debug!("Unhandled OTP event type: {}", event_type);
                self.state.add_event_log(format!("OTP Event: {}", event_type));
            }
        }
        
        self.mark_for_render();
        Ok(())
    }

    async fn handle_file_system_event(&mut self, path: String, change_type: String, data: serde_json::Value) -> Result<()> {
        info!("File system event: {} - {}", path, change_type);
        
        // Update context items based on file changes
        let status = match change_type.as_str() {
            "Created" => "new",
            "Modified" => "modified",
            "Deleted" => "deleted",
            "Renamed" => "renamed",
            _ => "changed",
        };
        
        // Add or update context item
        let context_item = crate::state::ContextItem::File {
            path: path.clone(),
            status: status.to_string(),
        };
        
        // Find and update existing item or add new one
        let context_items = &mut self.state.layout_state.context_items;
        if let Some(pos) = context_items.iter().position(|item| {
            matches!(item, crate::state::ContextItem::File { path: p, .. } if p == &path)
        }) {
            context_items[pos] = context_item;
        } else {
            context_items.push(context_item);
        }
        
        // If file has content, update it
        if let Some(content) = data.get("content").and_then(|v| v.as_str()) {
            self.state.update_file_content(path.clone(), content.to_string());
        }
        
        self.state.add_system_message(format!("File {}: {}", change_type.to_lowercase(), path));
        Ok(())
    }

    async fn handle_error_detected(&mut self, message: String, file: String, line: Option<u32>) -> Result<()> {
        info!("Error detected: {} in {} at line {:?}", message, file, line);
        
        // Add error to context items
        let error_item = crate::state::ContextItem::Error {
            message: message.clone(),
            file: file.clone(),
            line,
        };
        
        // Add to context (limit to last 10 errors)
        let context_items = &mut self.state.layout_state.context_items;
        context_items.push(error_item);
        
        // Keep only recent errors
        let error_count = context_items.iter().filter(|item| matches!(item, crate::state::ContextItem::Error { .. })).count();
        if error_count > 10 {
            if let Some(pos) = context_items.iter().position(|item| matches!(item, crate::state::ContextItem::Error { .. })) {
                context_items.remove(pos);
            }
        }
        
        self.state.add_error_message(format!("Error in {}: {}", file, message));
        Ok(())
    }

    async fn handle_context_update(&mut self, data: serde_json::Value) -> Result<()> {
        debug!("Context update received: {:?}", data);
        
        // Handle different types of context updates
        if let Some(update_type) = data.get("type").and_then(|v| v.as_str()) {
            match update_type {
                "file_structure" => {
                    if let Some(files) = data.get("files").and_then(|v| v.as_array()) {
                        self.update_file_structure(files).await?;
                    }
                }
                "function_list" => {
                    if let Some(functions) = data.get("functions").and_then(|v| v.as_array()) {
                        self.update_function_list(functions).await?;
                    }
                }
                "project_info" => {
                    if let Some(info) = data.get("info") {
                        self.update_project_info(info).await?;
                    }
                }
                _ => {
                    debug!("Unknown context update type: {}", update_type);
                }
            }
        }
        
        Ok(())
    }

    async fn handle_llm_response(&mut self, data: serde_json::Value) -> Result<()> {
        debug!("LLM response received: {:?}", data);
        
        if let (Some(response), Some(request_id)) = (
            data.get("response").and_then(|v| v.as_str()),
            data.get("request_id").and_then(|v| v.as_str()),
        ) {
            let tokens = data.get("tokens_used").and_then(|v| v.as_u64()).map(|t| t as u32);
            self.state.add_ai_response(response.to_string(), tokens);
            
            if let Some(model) = data.get("model").and_then(|v| v.as_str()) {
                self.state.add_event_log(format!("Response from {} (tokens: {:?})", model, tokens));
            }
        }
        
        Ok(())
    }

    async fn handle_interface_event(&mut self, data: serde_json::Value) -> Result<()> {
        debug!("Interface event received: {:?}", data);
        
        if let Some(event) = data.get("event").and_then(|v| v.as_str()) {
            match event {
                "focus_file" => {
                    if let Some(path) = data.get("path").and_then(|v| v.as_str()) {
                        // Update context to highlight the focused file
                        self.focus_file_in_context(path.to_string()).await?;
                    }
                }
                "build_status_update" => {
                    if let (Some(status), Some(timestamp)) = (
                        data.get("status").and_then(|v| v.as_str()),
                        data.get("timestamp").and_then(|v| v.as_u64()),
                    ) {
                        let build_item = crate::state::ContextItem::BuildStatus {
                            status: status.to_string(),
                            timestamp: chrono::DateTime::from_timestamp(timestamp as i64 / 1000, 0)
                                .unwrap_or_else(|| chrono::Utc::now()),
                        };
                        
                        // Update or add build status in context
                        let context_items = &mut self.state.layout_state.context_items;
                        if let Some(pos) = context_items.iter().position(|item| {
                            matches!(item, crate::state::ContextItem::BuildStatus { .. })
                        }) {
                            context_items[pos] = build_item;
                        } else {
                            context_items.push(build_item);
                        }
                    }
                }
                _ => {
                    debug!("Unknown interface event: {}", event);
                }
            }
        }
        
        Ok(())
    }

    async fn update_file_structure(&mut self, files: &[serde_json::Value]) -> Result<()> {
        debug!("Updating file structure with {} files", files.len());
        
        for file_data in files {
            if let Some(path) = file_data.get("path").and_then(|v| v.as_str()) {
                let status = file_data.get("status").and_then(|v| v.as_str()).unwrap_or("tracked");
                
                let context_item = crate::state::ContextItem::File {
                    path: path.to_string(),
                    status: status.to_string(),
                };
                
                // Update or add file in context
                let context_items = &mut self.state.layout_state.context_items;
                if let Some(pos) = context_items.iter().position(|item| {
                    matches!(item, crate::state::ContextItem::File { path: p, .. } if p == path)
                }) {
                    context_items[pos] = context_item;
                } else {
                    context_items.push(context_item);
                }
            }
        }
        
        Ok(())
    }

    async fn update_function_list(&mut self, functions: &[serde_json::Value]) -> Result<()> {
        debug!("Updating function list with {} functions", functions.len());
        
        // Remove old function entries
        self.state.layout_state.context_items.retain(|item| {
            !matches!(item, crate::state::ContextItem::Function { .. })
        });
        
        for func_data in functions {
            if let (Some(name), Some(file)) = (
                func_data.get("name").and_then(|v| v.as_str()),
                func_data.get("file").and_then(|v| v.as_str()),
            ) {
                let line = func_data.get("line").and_then(|v| v.as_u64()).map(|l| l as u32);
                
                let context_item = crate::state::ContextItem::Function {
                    name: name.to_string(),
                    file: file.to_string(),
                    line,
                };
                
                self.state.layout_state.context_items.push(context_item);
            }
        }
        
        Ok(())
    }

    async fn update_project_info(&mut self, info: &serde_json::Value) -> Result<()> {
        debug!("Updating project info: {:?}", info);
        
        if let Some(name) = info.get("name").and_then(|v| v.as_str()) {
            self.state.add_event_log(format!("Project: {}", name));
        }
        
        if let Some(version) = info.get("version").and_then(|v| v.as_str()) {
            self.state.add_event_log(format!("Version: {}", version));
        }
        
        Ok(())
    }

    async fn focus_file_in_context(&mut self, path: String) -> Result<()> {
        debug!("Focusing file in context: {}", path);
        
        // Find the file in context and move to top or highlight
        let context_items = &mut self.state.layout_state.context_items;
        if let Some(pos) = context_items.iter().position(|item| {
            matches!(item, crate::state::ContextItem::File { path: p, .. } if p == &path)
        }) {
            // Move file to top of context for visibility
            let item = context_items.remove(pos);
            context_items.insert(0, item);
            
            // Reset scroll to show the focused file
            self.state.layout_state.context_scroll = 0;
            
            self.state.add_system_message(format!("Focused on file: {}", path));
        }
        
        Ok(())
    }

    async fn request_initial_context(&mut self) -> Result<()> {
        info!("Requesting initial context from OTP backend");
        
        // Request file system monitoring
        self.request_file_system_monitoring().await?;
        
        // Request project structure
        self.request_project_context().await?;
        
        // Request current build status
        self.request_build_status().await?;
        
        Ok(())
    }

    async fn request_file_system_monitoring(&mut self) -> Result<()> {
        debug!("Requesting file system monitoring");
        
        let request = serde_json::json!({
            "action": "start_file_monitoring",
            "path": self.state.project_dir,
            "patterns": ["*.ex", "*.exs", "*.rs", "*.toml", "*.md", "*.json"],
            "timestamp": chrono::Utc::now().timestamp_millis()
        });

        // Send request to OTP backend via TUI server
        self.send_otp_request("start_file_monitoring".to_string(), "file.monitor".to_string(), request).await?;

        self.state.add_event_log("File system monitoring requested".to_string());
        Ok(())
    }

    async fn request_project_context(&mut self) -> Result<()> {
        debug!("Requesting project context");
        
        let request = serde_json::json!({
            "action": "get_project_context",
            "path": self.state.project_dir,
            "include_functions": true,
            "include_errors": true,
            "timestamp": chrono::Utc::now().timestamp_millis()
        });

        self.send_otp_request("get_project_context".to_string(), "project.context".to_string(), request).await?;

        self.state.add_event_log("Project context requested".to_string());
        Ok(())
    }

    async fn request_build_status(&mut self) -> Result<()> {
        debug!("Requesting build status");
        
        let request = serde_json::json!({
            "action": "get_build_status",
            "path": self.state.project_dir,
            "timestamp": chrono::Utc::now().timestamp_millis()
        });

        self.send_otp_request("get_build_status".to_string(), "build.status".to_string(), request).await?;

        self.state.add_event_log("Build status requested".to_string());
        Ok(())
    }

    async fn send_otp_request(&mut self, request_id: String, command: String, params: serde_json::Value) -> Result<()> {
        debug!("Sending OTP request: {} - {}", command, request_id);
        
        // Convert serde_json::Value to HashMap<String, serde_json::Value>
        let params_map = match params {
            serde_json::Value::Object(map) => map.into_iter().collect(),
            _ => {
                let mut map = std::collections::HashMap::new();
                map.insert("data".to_string(), params);
                map
            }
        };

        // Create a separate OTP client just for this request
        // (since the main client is moved to background task)
        match OtpClient::new(self.otp_client.server_addr.clone(), self.event_tx.clone()).await {
            Ok(mut client) => {
                tokio::spawn(async move {
                    if let Err(e) = client.send_request(request_id, command, params_map).await {
                        error!("Failed to send OTP request: {}", e);
                    }
                });
            }
            Err(e) => {
                warn!("Failed to create OTP client for request: {}", e);
                // Fall back to sending via event channel
                let _ = self.event_tx.send(crate::message::Message::CommandResult {
                    request_id: format!("fallback_{}", chrono::Utc::now().timestamp_millis()),
                    result: params,
                });
            }
        }
        
        Ok(())
    }

    async fn refresh_project(&mut self) -> Result<()> {
        info!("Refreshing project data");

        // Send request to OTP application for project refresh
        let request = serde_json::json!({
            "action": "refresh_project",
            "path": self.state.project_dir,
            "timestamp": chrono::Utc::now().timestamp_millis()
        });

        self.send_otp_request("refresh_project".to_string(), "project.refresh".to_string(), request).await?;

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

            self.send_otp_request(
                format!("open_file_{}", selected_file),
                "file.open".to_string(),
                request
            ).await?;

            self.state
                .add_event_log(format!("Requested to open: {}", selected_file));
        }

        Ok(())
    }

    fn get_current_context(&self) -> serde_json::Value {
        let context_items: Vec<serde_json::Value> = self.state.layout_state.context_items
            .iter()
            .map(|item| {
                match item {
                    crate::state::ContextItem::File { path, status } => {
                        serde_json::json!({
                            "type": "file",
                            "path": path,
                            "status": status
                        })
                    }
                    crate::state::ContextItem::Function { name, file, line } => {
                        serde_json::json!({
                            "type": "function", 
                            "name": name,
                            "file": file,
                            "line": line
                        })
                    }
                    crate::state::ContextItem::Error { message, file, line } => {
                        serde_json::json!({
                            "type": "error",
                            "message": message,
                            "file": file,
                            "line": line
                        })
                    }
                    crate::state::ContextItem::BuildStatus { status, timestamp } => {
                        serde_json::json!({
                            "type": "build_status",
                            "status": status,
                            "timestamp": timestamp.timestamp()
                        })
                    }
                }
            })
            .collect();

        serde_json::json!({
            "project_dir": self.state.project_dir,
            "current_file": self.state.current_file.as_ref().map(|f| &f.path),
            "context_items": context_items,
            "build_status": {
                "is_building": self.state.build_status.is_building,
                "last_status": self.state.build_status.last_status,
                "last_build_time": self.state.build_status.last_build_time.map(|t| t.timestamp())
            }
        })
    }

    fn should_render(&self) -> bool {
        self.last_render.elapsed() >= Duration::from_millis(16) // 60 FPS cap
    }

    fn mark_for_render(&mut self) {
        // Force render on next cycle by setting last_render to past
        self.last_render = Instant::now() - Duration::from_millis(20);
    }

    async fn send_user_message(&mut self, content: String) -> Result<()> {
        info!("Sending user message: {}", content);

        // Add user message to chat
        self.state.send_message(content.clone());

        // Send message to OTP application for AI processing
        let request = serde_json::json!({
            "action": "chat_message",
            "content": content,
            "context": self.get_current_context(),
            "timestamp": chrono::Utc::now().timestamp_millis()
        });

        let request_id = format!("chat_message_{}", chrono::Utc::now().timestamp_millis());
        self.send_otp_request(request_id, "llm.chat".to_string(), request).await?;

        self.mark_for_render();
        Ok(())
    }

    async fn execute_quick_action(&mut self, action: &crate::state::QuickAction) -> Result<()> {
        info!("Executing quick action: {:?}", action);

        let message_content = self.state.execute_quick_action(action);

        // Send to OTP application for processing with full context
        let request = serde_json::json!({
            "action": "quick_action",
            "action_type": action.label(),
            "action_key": action.key(),
            "content": message_content,
            "context": self.get_current_context(),
            "timestamp": chrono::Utc::now().timestamp_millis()
        });

        let request_id = format!("quick_action_{}_{}", action.key(), chrono::Utc::now().timestamp_millis());
        self.send_otp_request(request_id, "llm.quick_action".to_string(), request).await?;

        self.mark_for_render();
        Ok(())
    }

    async fn handle_context_selection(&mut self, item: &crate::state::ContextItem) -> Result<()> {
        info!("Handling context selection: {:?}", item);

        match item {
            crate::state::ContextItem::File { path, .. } => {
                let request = serde_json::json!({
                    "action": "open_file",
                    "path": path,
                    "timestamp": chrono::Utc::now().timestamp_millis()
                });

                let _ = self.event_tx.send(crate::message::Message::CommandResult {
                    request_id: format!("open_file_{}", path.replace('/', "_")),
                    result: request,
                });

                self.state.add_system_message(format!("Opening file: {}", path));
            }
            crate::state::ContextItem::Function { name, file, line } => {
                let location = if let Some(line_num) = line {
                    format!("{}:{}", file, line_num)
                } else {
                    file.clone()
                };

                self.state.add_system_message(format!("Navigating to function {} in {}", name, location));
            }
            crate::state::ContextItem::Error { message, file, line } => {
                let location = if let Some(line_num) = line {
                    format!("{}:{}", file, line_num)
                } else {
                    file.clone()
                };

                let fix_message = format!("Please help me fix this error: {} in {}", message, location);
                self.state.send_message(fix_message);
            }
            crate::state::ContextItem::BuildStatus { status, .. } => {
                self.state.add_system_message(format!("Build status: {}", status));
            }
        }

        self.mark_for_render();
        Ok(())
    }
}