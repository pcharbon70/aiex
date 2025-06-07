use ratatui::{
    prelude::*,
    widgets::{
        Block, Borders, Gauge, List, ListItem, Paragraph, 
        Sparkline, Table, Row, Cell, Tabs, Wrap
    },
};

use crate::state::{AppState, Pane};

/// Main UI rendering function
pub fn render_ui(frame: &mut Frame, state: &AppState) {
    // Main layout with header for tabs
    let main_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Header with tabs
            Constraint::Min(0),    // Main content
            Constraint::Length(1), // Status bar
        ])
        .split(frame.area());

    // Render header with tabs
    render_header_tabs(frame, main_chunks[0], state);

    // Split main content area
    let content_chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(30), // File tree
            Constraint::Percentage(70), // Main content
        ])
        .split(main_chunks[1]);

    // Render file tree with scrollbar
    render_file_tree(frame, content_chunks[0], state);

    // Split right side
    let right_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage(60), // Code view
            Constraint::Percentage(40), // Info/logs with tabs
        ])
        .split(content_chunks[1]);

    // Render main content
    render_main_content(frame, right_chunks[0], state);

    // Render bottom panel with enhanced widgets
    render_enhanced_bottom_panel(frame, right_chunks[1], state);

    // Render status bar
    render_status_bar(frame, main_chunks[2], state);
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

fn render_header_tabs(frame: &mut Frame, area: Rect, _state: &AppState) {
    let tab_titles = vec!["Explorer", "Search", "Git", "Extensions", "Settings"];
    let selected_tab = 0; // For now, always select first tab
    
    let tabs = Tabs::new(tab_titles)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title("Aiex TUI")
        )
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD))
        .select(selected_tab);
    
    frame.render_widget(tabs, area);
}

fn render_enhanced_bottom_panel(frame: &mut Frame, area: Rect, state: &AppState) {
    // Create tabs for different bottom panel views
    let panel_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Tabs
            Constraint::Min(0),    // Content
        ])
        .split(area);
    
    // Bottom panel tabs
    let tab_titles = vec!["Event Log", "Build Output", "Debug", "Performance"];
    let selected_tab = 0; // Default to Event Log
    
    let tabs = Tabs::new(tab_titles)
        .block(Block::default().borders(Borders::ALL))
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
        .select(selected_tab);
    
    frame.render_widget(tabs, panel_chunks[0]);
    
    // Render content based on selected tab
    match selected_tab {
        0 => render_event_log_panel(frame, panel_chunks[1], state),
        1 => render_build_output_panel(frame, panel_chunks[1], state),
        2 => render_debug_panel(frame, panel_chunks[1], state),
        3 => render_performance_panel(frame, panel_chunks[1], state),
        _ => render_event_log_panel(frame, panel_chunks[1], state),
    }
}

fn render_event_log_panel(frame: &mut Frame, area: Rect, state: &AppState) {
    let is_focused = matches!(state.current_pane, Pane::EventLog);
    let border_style = if is_focused {
        Style::default().fg(Color::Blue)
    } else {
        Style::default()
    };

    // Enhanced event log with table format
    let header = Row::new(vec!["Time", "Level", "Message"])
        .style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD));
    
    let rows: Vec<Row> = state
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
            
            Row::new(vec![
                Cell::from(entry.timestamp.format("%H:%M:%S").to_string()),
                Cell::from(format!("{:?}", entry.level)),
                Cell::from(entry.message.clone()),
            ]).style(style)
        })
        .collect();

    let table = Table::new(rows, [
        Constraint::Length(8),  // Time
        Constraint::Length(8),  // Level
        Constraint::Min(0),     // Message
    ])
    .header(header)
    .block(
        Block::default()
            .title("Event Log")
            .borders(Borders::ALL)
            .border_style(border_style),
    );

    frame.render_widget(table, area);
}

fn render_build_output_panel(frame: &mut Frame, area: Rect, _state: &AppState) {
    let build_info = vec![
        "mix compile",
        "Compiling 45 files (.ex)",
        "Generated aiex app",
        "Build completed successfully",
    ];
    
    let items: Vec<ListItem> = build_info
        .iter()
        .map(|line| ListItem::new(*line))
        .collect();
    
    let list = List::new(items)
        .block(
            Block::default()
                .title("Build Output")
                .borders(Borders::ALL)
        );
    
    frame.render_widget(list, area);
}

fn render_debug_panel(frame: &mut Frame, area: Rect, state: &AppState) {
    let debug_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Memory usage gauge
            Constraint::Min(0),    // Debug info
        ])
        .split(area);
    
    // Memory usage gauge
    let memory_usage = 45; // Mock data - in real app, get from system
    let gauge = Gauge::default()
        .block(Block::default().title("Memory Usage").borders(Borders::ALL))
        .gauge_style(Style::default().fg(Color::Cyan))
        .percent(memory_usage)
        .label(format!("{}%", memory_usage));
    
    frame.render_widget(gauge, debug_chunks[0]);
    
    // Debug information
    let debug_info = format!(
        "Connection Status: {:?}\nProject Directory: {}\nEvent Count: {}",
        state.connection_status,
        state.project_dir,
        state.event_log.len()
    );
    
    let paragraph = Paragraph::new(debug_info)
        .block(
            Block::default()
                .title("Debug Info")
                .borders(Borders::ALL)
        )
        .wrap(Wrap { trim: true });
    
    frame.render_widget(paragraph, debug_chunks[1]);
}

fn render_performance_panel(frame: &mut Frame, area: Rect, _state: &AppState) {
    let perf_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4), // CPU usage sparkline
            Constraint::Min(0),    // Performance metrics
        ])
        .split(area);
    
    // Mock performance data
    let cpu_data = vec![10, 15, 20, 25, 30, 35, 25, 20, 15, 10, 8, 12];
    let sparkline = Sparkline::default()
        .block(
            Block::default()
                .title("CPU Usage History")
                .borders(Borders::ALL)
        )
        .data(&cpu_data)
        .style(Style::default().fg(Color::Green));
    
    frame.render_widget(sparkline, perf_chunks[0]);
    
    // Performance metrics table
    let header = Row::new(vec!["Metric", "Value", "Status"])
        .style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD));
    
    let rows = vec![
        Row::new(vec!["Response Time", "245ms", "Good"]),
        Row::new(vec!["Throughput", "1.2k req/s", "Excellent"]),
        Row::new(vec!["Error Rate", "0.1%", "Good"]),
        Row::new(vec!["Memory", "128MB", "Normal"]),
    ];
    
    let table = Table::new(rows, [
        Constraint::Length(15),
        Constraint::Length(10), 
        Constraint::Length(10),
    ])
    .header(header)
    .block(
        Block::default()
            .title("Performance Metrics")
            .borders(Borders::ALL)
    );
    
    frame.render_widget(table, perf_chunks[1]);
}

fn render_status_bar(frame: &mut Frame, area: Rect, state: &AppState) {
    let status_info = format!(
        " Status: {:?} | Project: {} | Events: {} | Memory: 45% | [q]uit [Tab]switch [r]efresh ",
        state.connection_status,
        state.project_dir,
        state.event_log.len()
    );
    
    let status_bar = Paragraph::new(status_info)
        .style(Style::default().bg(Color::DarkGray).fg(Color::White))
        .wrap(Wrap { trim: true });
    
    frame.render_widget(status_bar, area);
}