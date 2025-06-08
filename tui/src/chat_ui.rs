use ratatui::{
    prelude::*,
    widgets::{
        Block, Borders, List, ListItem, Paragraph, Scrollbar,
        ScrollbarOrientation, ScrollbarState, Wrap, Clear,
    },
};

use crate::state::{AppState, Pane, MessageType, ContextItem, QuickAction};
use crate::rich_text::{RichTextRenderer, extract_code_blocks, looks_like_code, looks_like_diff};

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

fn render_header(frame: &mut Frame, area: Rect, state: &AppState) {
    let title = "AI Coding Assistant - Chat Mode";
    
    // Dynamic help text based on current focus
    let help_text = match state.current_pane {
        Pane::MessageInput => "Ctrl+Enter: Send | Shift+Enter: New Line | Tab/Shift+Tab: Navigate | Ctrl+Arrows: Quick Focus",
        Pane::ConversationHistory => "↑↓: Scroll | Home/End: Top/Bottom | PgUp/PgDown: Fast Scroll | Enter: Focus Input | /: Search | n: New Chat",
        Pane::Context => "↑↓: Navigate | Enter/Space: Select | Home/End: Top/Bottom | Ctrl+Arrows: Quick Focus",
        Pane::QuickActions => "↑↓: Navigate | Enter/Space: Execute | Letter Keys: Quick Execute | Ctrl+Arrows: Quick Focus",
        Pane::CurrentStatus => "Arrow Keys: Navigate to Other Panels | Enter: Focus Input",
    };
    
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

    // Enhanced border color based on focus state
    let border_color = match state.current_pane {
        Pane::MessageInput => Color::Green,
        Pane::ConversationHistory => Color::Cyan,
        Pane::Context => Color::Magenta,
        Pane::QuickActions => Color::Yellow,
        Pane::CurrentStatus => Color::Blue,
    };

    let header_block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(border_color));
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
        Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::Blue)
    };

    // Create rich text renderer for syntax highlighting
    let rich_text_renderer = RichTextRenderer::new();

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
            
            // Enhanced message content rendering with rich text support
            let rendered_content = render_message_content(&msg.content, &rich_text_renderer);
            lines.extend(rendered_content.lines);

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

    // Enhanced scrollbar with progress indicator
    if state.chat_state.messages.len() > 1 {
        render_enhanced_scrollbar(
            frame,
            area,
            state.chat_state.messages.len(),
            state.chat_state.scroll_position,
            Some(ScrollbarStyle::Messages),
        );
    }
}

fn render_current_status(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::CurrentStatus);
    let border_style = if is_focused {
        Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
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
        Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
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

    // Add scrollbar for context panel if needed
    if state.layout_state.context_items.len() > 5 {
        render_enhanced_scrollbar(
            frame,
            area,
            state.layout_state.context_items.len(),
            state.layout_state.context_scroll,
            Some(ScrollbarStyle::Context),
        );
    }
}

fn render_quick_actions_panel(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::QuickActions);
    let border_style = if is_focused {
        Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
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

    // Add scrollbar for quick actions if needed
    if state.layout_state.quick_actions.len() > 5 {
        render_enhanced_scrollbar(
            frame,
            area,
            state.layout_state.quick_actions.len(),
            state.layout_state.actions_scroll,
            Some(ScrollbarStyle::Actions),
        );
    }
}

fn render_input_area(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::MessageInput);
    let border_style = if is_focused {
        Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
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
    
    // Create comprehensive status with navigation hints
    let left_status = format!(
        " Status: {:?} | Project: {} | Messages: {} | Tokens: {}",
        state.connection_status,
        state.project_dir.split('/').last().unwrap_or("Unknown"),
        stats.total_messages,
        stats.total_tokens,
    );
    
    let right_status = format!(
        "Focus: {:?} | {} | F1: Context | F2: Actions | Alt+1-4: Quick Focus | Ctrl+Q: Quit ",
        state.current_pane,
        if state.chat_state.is_processing { "⏳ Processing" } else { "✅ Ready" }
    );

    // Split the status bar into left and right sections
    let status_layout = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(60), Constraint::Percentage(40)])
        .split(area);

    let left_paragraph = Paragraph::new(left_status)
        .style(Style::default().bg(Color::Blue).fg(Color::White))
        .alignment(Alignment::Left);
    frame.render_widget(left_paragraph, status_layout[0]);

    let right_paragraph = Paragraph::new(right_status)
        .style(Style::default().bg(Color::Blue).fg(Color::White))
        .alignment(Alignment::Right);
    frame.render_widget(right_paragraph, status_layout[1]);
}

/// Render message content with rich text support including syntax highlighting and markdown
fn render_message_content(content: &str, renderer: &RichTextRenderer) -> Text {
    // First, check if the content has code blocks
    let code_blocks = extract_code_blocks(content);
    
    if !code_blocks.is_empty() {
        // Content has fenced code blocks - render with mixed markdown and code
        return render_mixed_content(content, renderer);
    }
    
    // Check if content is a diff
    if looks_like_diff(content) {
        // Detect language from diff context and render as diff
        let language = renderer.detect_language(content, None);
        return renderer.render_diff(content, language.as_deref());
    }
    
    // Check if the entire content looks like code
    if looks_like_code(content) {
        // Detect language and render as code
        let language = renderer.detect_language(content, None);
        return renderer.render_code_block(content, language.as_deref());
    }
    
    // Default to markdown rendering for natural text
    renderer.render_markdown(content)
}

/// Render content that has both markdown and code blocks
fn render_mixed_content(content: &str, renderer: &RichTextRenderer) -> Text {
    let mut lines = Vec::new();
    let mut current_pos = 0;
    let content_lines: Vec<&str> = content.lines().collect();
    let mut i = 0;
    
    while i < content_lines.len() {
        let line = content_lines[i];
        
        // Check for fenced code blocks
        if line.starts_with("```") {
            // Process any markdown content before the code block
            if i > current_pos {
                let markdown_text = content_lines[current_pos..i].join("\n");
                let markdown_rendered = renderer.render_markdown(&markdown_text);
                lines.extend(markdown_rendered.lines);
            }
            
            // Extract language from code fence
            let language = if line.len() > 3 {
                Some(line[3..].trim())
            } else {
                None
            };
            
            // Find the end of the code block
            i += 1;
            let code_start = i;
            while i < content_lines.len() && !content_lines[i].starts_with("```") {
                i += 1;
            }
            
            // Render the code block
            if i > code_start {
                let code_content = content_lines[code_start..i].join("\n");
                let code_rendered = renderer.render_code_block(&code_content, language);
                
                // Add a visual separator for code blocks
                lines.push(Line::from(Span::styled(
                    "┌─ Code Block ─┐",
                    Style::default().fg(Color::DarkGray)
                )));
                lines.extend(code_rendered.lines);
                lines.push(Line::from(Span::styled(
                    "└──────────────┘",
                    Style::default().fg(Color::DarkGray)
                )));
            }
            
            current_pos = i + 1;
        }
        
        i += 1;
    }
    
    // Process any remaining markdown content
    if current_pos < content_lines.len() {
        let markdown_text = content_lines[current_pos..].join("\n");
        let markdown_rendered = renderer.render_markdown(&markdown_text);
        lines.extend(markdown_rendered.lines);
    }
    
    Text::from(lines)
}

/// Scrollbar styles for different UI components
#[derive(Debug, Clone)]
enum ScrollbarStyle {
    Messages,
    Context,
    Actions,
}

impl ScrollbarStyle {
    fn get_symbols(&self) -> (&'static str, &'static str, &'static str) {
        match self {
            ScrollbarStyle::Messages => ("▲", "▼", "█"),
            ScrollbarStyle::Context => ("↑", "↓", "■"),
            ScrollbarStyle::Actions => ("▲", "▼", "●"),
        }
    }

    fn get_track_color(&self) -> Color {
        match self {
            ScrollbarStyle::Messages => Color::DarkGray,
            ScrollbarStyle::Context => Color::Blue,
            ScrollbarStyle::Actions => Color::Yellow,
        }
    }

    fn get_thumb_color(&self) -> Color {
        match self {
            ScrollbarStyle::Messages => Color::Cyan,
            ScrollbarStyle::Context => Color::Magenta,
            ScrollbarStyle::Actions => Color::Yellow,
        }
    }
}

/// Render an enhanced scrollbar with progress indicator and styling
fn render_enhanced_scrollbar(
    frame: &mut Frame,
    area: Rect,
    content_length: usize,
    position: usize,
    style: Option<ScrollbarStyle>,
) {
    let scrollbar_style = style.unwrap_or(ScrollbarStyle::Messages);
    let (begin_symbol, end_symbol, _track_symbol) = scrollbar_style.get_symbols();
    
    let scrollbar = Scrollbar::default()
        .orientation(ScrollbarOrientation::VerticalRight)
        .begin_symbol(Some(begin_symbol))
        .end_symbol(Some(end_symbol))
        .track_symbol(Some("│"))
        .thumb_symbol("█")
        .style(Style::default().fg(scrollbar_style.get_track_color()))
        .thumb_style(Style::default().fg(scrollbar_style.get_thumb_color()));
    
    let mut scrollbar_state = ScrollbarState::default()
        .content_length(content_length)
        .position(position);
    
    // Render scrollbar with margin to avoid border overlap
    let scrollbar_area = area.inner(Margin { vertical: 1, horizontal: 0 });
    frame.render_stateful_widget(scrollbar, scrollbar_area, &mut scrollbar_state);
    
    // Add progress indicator in the top-right corner
    if content_length > 0 {
        let progress_percent = ((position + 1) * 100) / content_length;
        let progress_text = format!("{}%", progress_percent);
        
        // Calculate position for progress indicator
        let progress_area = Rect {
            x: area.x + area.width.saturating_sub(progress_text.len() as u16 + 2),
            y: area.y,
            width: progress_text.len() as u16 + 1,
            height: 1,
        };
        
        // Only render if there's space
        if progress_area.x > area.x && progress_area.y < area.y + area.height {
            let progress_paragraph = Paragraph::new(progress_text)
                .style(Style::default()
                    .fg(scrollbar_style.get_thumb_color())
                    .add_modifier(Modifier::BOLD))
                .alignment(Alignment::Right);
            
            frame.render_widget(Clear, progress_area);
            frame.render_widget(progress_paragraph, progress_area);
        }
    }
}

/// Enhanced scrollbar for text content with line-based scrolling
fn render_text_scrollbar(
    frame: &mut Frame,
    area: Rect,
    total_lines: usize,
    visible_lines: usize,
    scroll_offset: usize,
) {
    if total_lines <= visible_lines {
        return; // No need for scrollbar
    }
    
    let scrollbar = Scrollbar::default()
        .orientation(ScrollbarOrientation::VerticalRight)
        .begin_symbol(Some("▲"))
        .end_symbol(Some("▼"))
        .track_symbol(Some("│"))
        .thumb_symbol("█")
        .style(Style::default().fg(Color::DarkGray))
        .thumb_style(Style::default().fg(Color::White));
    
    let mut scrollbar_state = ScrollbarState::default()
        .content_length(total_lines.saturating_sub(visible_lines))
        .position(scroll_offset);
    
    frame.render_stateful_widget(
        scrollbar,
        area.inner(Margin { vertical: 1, horizontal: 0 }),
        &mut scrollbar_state,
    );
}