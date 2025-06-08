use ratatui::{
    prelude::*,
    widgets::{
        Block, Borders, List, ListItem, Paragraph, Scrollbar,
        ScrollbarOrientation, ScrollbarState, Wrap, Clear,
    },
};

use crate::state::{AppState, Pane, MessageType, ContextItem, QuickAction};

/// Main chat-focused UI rendering function
pub fn render_chat_ui(frame: &mut Frame, state: &AppState) {
    // Main layout structure
    let main_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),  // Header
            Constraint::Fill(1),    // Main content
            Constraint::Length(3),  // Input area
            Constraint::Length(1),  // Status bar
        ])
        .split(frame.area());

    // Render header
    render_header(frame, main_layout[0], state);

    // Main content area with optional side panels
    render_main_content(frame, main_layout[1], state);

    // Input area
    render_input_area(frame, main_layout[2], state);

    // Status bar
    render_status_bar(frame, main_layout[3], state);
}

fn render_header(frame: &mut Frame, area: Rect, _state: &AppState) {
    let title = "AI Coding Assistant - Chat Mode";
    let help_text = "F1: Context | F2: Actions | Tab: Focus | Ctrl+Q: Quit | Ctrl+Enter: Send";
    
    let header_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(1), Constraint::Length(1)])
        .split(area.inner(Margin { vertical: 1, horizontal: 2 }));

    let title_paragraph = Paragraph::new(title)
        .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
        .alignment(Alignment::Center);
    frame.render_widget(title_paragraph, header_layout[0]);

    let help_paragraph = Paragraph::new(help_text)
        .style(Style::default().fg(Color::Gray))
        .alignment(Alignment::Center);
    frame.render_widget(help_paragraph, header_layout[1]);

    let header_block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Blue));
    frame.render_widget(header_block, area);
}

fn render_main_content(frame: &mut Frame, area: Rect, state: &AppState) {
    let mut constraints = vec![Constraint::Fill(1)];
    let mut has_side_panels = false;

    // Add constraints for side panels
    if state.layout_state.show_context_panel {
        constraints.insert(0, Constraint::Length(state.layout_state.context_panel_width));
        has_side_panels = true;
    }
    if state.layout_state.show_quick_actions {
        constraints.push(Constraint::Length(state.layout_state.quick_actions_width));
        has_side_panels = true;
    }

    let content_layout = Layout::default()
        .direction(Direction::Horizontal)
        .constraints(constraints)
        .split(area);

    let mut chat_area_index = 0;
    
    // Context panel
    if state.layout_state.show_context_panel {
        render_context_panel(frame, content_layout[0], state);
        chat_area_index = 1;
    }

    // Main chat area
    let chat_area = content_layout[chat_area_index];
    render_chat_area(frame, chat_area, state);

    // Quick actions panel
    if state.layout_state.show_quick_actions {
        let actions_index = if state.layout_state.show_context_panel { 2 } else { 1 };
        render_quick_actions_panel(frame, content_layout[actions_index], state);
    }
}

fn render_chat_area(frame: &mut Frame, area: Rect, state: &AppState) {
    // Split chat area: 70% for history, 30% for current status
    let chat_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage(state.layout_state.conversation_history_height_percent),
            Constraint::Percentage(state.layout_state.current_status_height_percent),
        ])
        .split(area);
    
    render_conversation_history(frame, chat_layout[0], state);
    render_current_status(frame, chat_layout[1], state);
}

fn render_conversation_history(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::ConversationHistory);
    let border_style = if is_focused {
        Style::default().fg(Color::Yellow)
    } else {
        Style::default().fg(Color::Blue)
    };

    let visible_messages = state.chat_state.get_visible_messages();
    let messages: Vec<ListItem> = visible_messages
        .iter()
        .map(|msg| {
            let timestamp = msg.timestamp.format("%H:%M:%S");

            let (prefix, style) = match msg.message_type {
                MessageType::User => ("You", Style::default().fg(Color::Green)),
                MessageType::Assistant => ("AI", Style::default().fg(Color::Cyan)),
                MessageType::System => ("System", Style::default().fg(Color::Yellow)),
                MessageType::Error => ("Error", Style::default().fg(Color::Red)),
            };

            let header = format!("[{}] {}", timestamp, prefix);
            let mut lines = vec![Line::from(Span::styled(header, style))];
            
            // Add message content with wrapping
            for line in msg.content.lines() {
                lines.push(Line::from(line));
            }

            // Add token usage if available
            if let Some(tokens) = msg.tokens_used {
                lines.push(Line::from(Span::styled(
                    format!("Tokens: {}", tokens),
                    Style::default().fg(Color::Gray).add_modifier(Modifier::ITALIC),
                )));
            }

            lines.push(Line::from(""));  // Empty line between messages
            ListItem::new(Text::from(lines))
        })
        .collect();

    // Add search indicator to title if search is active
    let title = if !state.chat_state.search_query.is_empty() {
        format!("Conversation History (Search: \"{}\")", state.chat_state.search_query)
    } else {
        "Conversation History".to_string()
    };

    let messages_list = List::new(messages)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(title)
                .border_style(border_style),
        )
        .highlight_style(Style::default().add_modifier(Modifier::BOLD));

    frame.render_widget(messages_list, area);

    // Render scrollbar if needed
    if state.chat_state.messages.len() > 1 {
        let scrollbar = Scrollbar::default()
            .orientation(ScrollbarOrientation::VerticalRight)
            .begin_symbol(Some("↑"))
            .end_symbol(Some("↓"));
        
        let mut scrollbar_state = ScrollbarState::default()
            .content_length(state.chat_state.messages.len())
            .position(state.chat_state.scroll_position);
        
        frame.render_stateful_widget(
            scrollbar,
            area.inner(Margin { vertical: 1, horizontal: 0 }),
            &mut scrollbar_state,
        );
    }
}

fn render_current_status(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::CurrentStatus);
    let border_style = if is_focused {
        Style::default().fg(Color::Yellow)
    } else {
        Style::default().fg(Color::Blue)
    };

    let status_text = if state.chat_state.is_processing {
        "🤔 AI is thinking...\n\nProcessing your request and analyzing the codebase.\nPlease wait for the response."
    } else {
        "💡 Current Context\n\nReady for your next question or command.\nType your message below and press Ctrl+Enter to send."
    };

    let context_paragraph = Paragraph::new(status_text)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title("Current Status")
                .border_style(border_style),
        )
        .wrap(Wrap { trim: true })
        .style(Style::default().fg(Color::White));

    frame.render_widget(context_paragraph, area);
}

fn render_context_panel(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::Context);
    let border_style = if is_focused {
        Style::default().fg(Color::Yellow)
    } else {
        Style::default().fg(Color::Blue)
    };

    let items: Vec<ListItem> = state
        .layout_state
        .context_items
        .iter()
        .enumerate()
        .map(|(i, item)| {
            let content = match item {
                ContextItem::File { path, status } => {
                    format!("📄 {}\n   Status: {}", path, status)
                }
                ContextItem::Function { name, file, line } => {
                    if let Some(line_num) = line {
                        format!("⚡ {}\n   {}:{}", name, file, line_num)
                    } else {
                        format!("⚡ {}\n   {}", name, file)
                    }
                }
                ContextItem::Error { message, file, line } => {
                    if let Some(line_num) = line {
                        format!("❌ {}\n   {}:{}", message, file, line_num)
                    } else {
                        format!("❌ {}\n   {}", message, file)
                    }
                }
                ContextItem::BuildStatus { status, timestamp } => {
                    format!("🔨 Build: {}\n   {}", status, timestamp.format("%H:%M:%S"))
                }
            };

            let item_style = if i == state.layout_state.context_scroll && is_focused {
                Style::default().bg(Color::DarkGray)
            } else {
                Style::default()
            };

            ListItem::new(content).style(item_style)
        })
        .collect();

    let context_list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title("Context Panel")
                .border_style(border_style),
        )
        .highlight_style(Style::default().bg(Color::DarkGray))
        .highlight_symbol("► ");

    frame.render_widget(context_list, area);
}

fn render_quick_actions_panel(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::QuickActions);
    let border_style = if is_focused {
        Style::default().fg(Color::Yellow)
    } else {
        Style::default().fg(Color::Blue)
    };

    let items: Vec<ListItem> = state
        .layout_state
        .quick_actions
        .iter()
        .enumerate()
        .map(|(i, action)| {
            let content = format!("{} ({})\n{}", action.label(), action.key(), action.description());
            
            let item_style = if i == state.layout_state.actions_scroll && is_focused {
                Style::default().bg(Color::DarkGray)
            } else {
                Style::default()
            };

            ListItem::new(content).style(item_style)
        })
        .collect();

    let actions_list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title("Quick Actions")
                .border_style(border_style),
        )
        .highlight_style(Style::default().bg(Color::DarkGray))
        .highlight_symbol("► ");

    frame.render_widget(actions_list, area);
}

fn render_input_area(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::MessageInput);
    let border_style = if is_focused {
        Style::default().fg(Color::Yellow)
    } else {
        Style::default().fg(Color::Blue)
    };

    let input_text = if state.chat_state.current_input.is_empty() {
        "Type your message here... (Ctrl+Enter to send)"
    } else {
        &state.chat_state.current_input
    };

    let input_style = if state.chat_state.current_input.is_empty() {
        Style::default().fg(Color::Gray)
    } else {
        Style::default().fg(Color::White)
    };

    let input_paragraph = Paragraph::new(input_text)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title("Message Input")
                .border_style(border_style),
        )
        .style(input_style)
        .wrap(Wrap { trim: false });

    frame.render_widget(input_paragraph, area);

    // Show cursor if focused
    if is_focused {
        let cursor_x = area.x + 1 + state.chat_state.current_input.len() as u16;
        let cursor_y = area.y + 1;
        if cursor_x < area.x + area.width - 1 && cursor_y < area.y + area.height - 1 {
            frame.set_cursor(cursor_x, cursor_y);
        }
    }
}

fn render_status_bar(frame: &mut Frame, area: Rect, state: &AppState) {
    let stats = state.get_conversation_stats();
    let status_text = format!(
        " Status: {:?} | Project: {} | Messages: {} | Tokens: {} | Focus: {:?} | {}",
        state.connection_status,
        state.project_dir.split('/').last().unwrap_or("Unknown"),
        stats.total_messages,
        stats.total_tokens,
        state.current_pane,
        if state.chat_state.is_processing { "⏳ Processing" } else { "✅ Ready" }
    );

    let status_paragraph = Paragraph::new(status_text)
        .style(Style::default().bg(Color::Blue).fg(Color::White))
        .alignment(Alignment::Left);

    frame.render_widget(status_paragraph, area);
}