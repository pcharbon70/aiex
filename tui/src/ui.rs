use ratatui::{
    prelude::*,
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
};

use crate::state::{AppState, Pane};

/// Main UI rendering function
pub fn render_ui(frame: &mut Frame, state: &AppState) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(30), // File tree
            Constraint::Percentage(70), // Main content
        ])
        .split(frame.area());

    // Render file tree
    render_file_tree(frame, chunks[0], state);

    // Split main content area
    let main_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage(60), // Code view
            Constraint::Percentage(40), // Info/logs
        ])
        .split(chunks[1]);

    // Render main content
    render_main_content(frame, main_chunks[0], state);

    // Render bottom panel
    render_bottom_panel(frame, main_chunks[1], state);
}

fn render_file_tree(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::FileTree);
    let border_style = if is_focused {
        Style::default().fg(Color::Blue)
    } else {
        Style::default()
    };

    let items: Vec<ListItem> = state
        .file_tree
        .entries
        .iter()
        .enumerate()
        .map(|(i, entry)| {
            let icon = if entry.is_directory { "📁 " } else { "📄 " };
            let style = if i == state.file_tree.selected_index && is_focused {
                Style::default().bg(Color::DarkGray).fg(Color::White)
            } else {
                Style::default()
            };

            ListItem::new(format!("{}{}", icon, entry.name)).style(style)
        })
        .collect();

    let list = List::new(items)
        .block(
            Block::default()
                .title("Files")
                .borders(Borders::ALL)
                .border_style(border_style),
        )
        .highlight_style(Style::default().bg(Color::DarkGray));

    frame.render_widget(list, area);
}

fn render_main_content(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::CodeView);
    let border_style = if is_focused {
        Style::default().fg(Color::Blue)
    } else {
        Style::default()
    };

    let content = if let Some(ref file) = state.current_file {
        format!("File: {}\n\n{}", file.path, file.content)
    } else {
        "No file selected\n\nUse the file tree to open a file.".to_string()
    };

    let paragraph = Paragraph::new(content)
        .block(
            Block::default()
                .title("Code View")
                .borders(Borders::ALL)
                .border_style(border_style),
        )
        .wrap(Wrap { trim: true });

    frame.render_widget(paragraph, area);
}

fn render_bottom_panel(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::EventLog);
    let border_style = if is_focused {
        Style::default().fg(Color::Blue)
    } else {
        Style::default()
    };

    // Show recent event log entries
    let log_items: Vec<ListItem> = state
        .event_log
        .iter()
        .rev()
        .take(10)
        .map(|entry| {
            let style = match entry.level {
                crate::state::LogLevel::Error => Style::default().fg(Color::Red),
                crate::state::LogLevel::Warning => Style::default().fg(Color::Yellow),
                crate::state::LogLevel::Info => Style::default().fg(Color::Green),
                crate::state::LogLevel::Debug => Style::default().fg(Color::Gray),
            };

            ListItem::new(format!(
                "[{}] {}",
                entry.timestamp.format("%H:%M:%S"),
                entry.message
            ))
            .style(style)
        })
        .collect();

    let status_info = format!(
        "Status: {:?} | Project: {} | Events: {}",
        state.connection_status,
        state.project_dir,
        state.event_log.len()
    );

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(1), Constraint::Length(1)])
        .split(area);

    // Event log
    let list = List::new(log_items).block(
        Block::default()
            .title("Event Log")
            .borders(Borders::ALL)
            .border_style(border_style),
    );

    frame.render_widget(list, chunks[0]);

    // Status bar
    let status_bar = Paragraph::new(status_info)
        .style(Style::default().bg(Color::DarkGray))
        .wrap(Wrap { trim: true });

    frame.render_widget(status_bar, chunks[1]);
}