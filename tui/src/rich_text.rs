use ratatui::{
    prelude::*,
    text::{Line, Span, Text},
};
use std::collections::HashMap;

/// Rich text rendering support for syntax highlighting and markdown formatting
pub struct RichTextRenderer {
    /// Color scheme for syntax highlighting
    pub color_scheme: ColorScheme,
    /// Language-specific syntax rules
    pub syntax_rules: HashMap<String, LanguageSyntax>,
}

/// Color scheme for syntax highlighting
#[derive(Debug, Clone)]
pub struct ColorScheme {
    pub keyword: Color,
    pub string: Color,
    pub comment: Color,
    pub function: Color,
    pub variable: Color,
    pub number: Color,
    pub operator: Color,
    pub type_name: Color,
    pub macro_name: Color,
    pub constant: Color,
    pub background: Color,
    pub foreground: Color,
    pub selection: Color,
    pub line_number: Color,
}

impl Default for ColorScheme {
    fn default() -> Self {
        Self::dark_theme()
    }
}

impl ColorScheme {
    /// Dark theme (default)
    pub fn dark_theme() -> Self {
        Self {
            keyword: Color::Magenta,
            string: Color::Green,
            comment: Color::Gray,
            function: Color::Blue,
            variable: Color::White,
            number: Color::Cyan,
            operator: Color::Yellow,
            type_name: Color::LightBlue,
            macro_name: Color::LightMagenta,
            constant: Color::LightCyan,
            background: Color::Black,
            foreground: Color::White,
            selection: Color::DarkGray,
            line_number: Color::DarkGray,
        }
    }

    /// Light theme
    pub fn light_theme() -> Self {
        Self {
            keyword: Color::Blue,
            string: Color::DarkGreen,
            comment: Color::Gray,
            function: Color::DarkBlue,
            variable: Color::Black,
            number: Color::DarkCyan,
            operator: Color::DarkYellow,
            type_name: Color::DarkBlue,
            macro_name: Color::DarkMagenta,
            constant: Color::DarkCyan,
            background: Color::White,
            foreground: Color::Black,
            selection: Color::LightGray,
            line_number: Color::Gray,
        }
    }

    /// Monokai-inspired theme
    pub fn monokai_theme() -> Self {
        Self {
            keyword: Color::Rgb(249, 38, 114), // Pink
            string: Color::Rgb(230, 219, 116), // Yellow
            comment: Color::Rgb(117, 113, 94),  // Gray
            function: Color::Rgb(166, 226, 46), // Green
            variable: Color::White,
            number: Color::Rgb(174, 129, 255), // Purple
            operator: Color::Rgb(249, 38, 114), // Pink
            type_name: Color::Rgb(102, 217, 239), // Cyan
            macro_name: Color::Rgb(166, 226, 46), // Green
            constant: Color::Rgb(174, 129, 255), // Purple
            background: Color::Rgb(39, 40, 34),
            foreground: Color::Rgb(248, 248, 242),
            selection: Color::Rgb(73, 72, 62),
            line_number: Color::Rgb(90, 89, 85),
        }
    }

    /// GitHub-inspired theme
    pub fn github_theme() -> Self {
        Self {
            keyword: Color::Rgb(215, 58, 73),   // Red
            string: Color::Rgb(3, 47, 98),      // Dark blue
            comment: Color::Rgb(106, 115, 125), // Gray
            function: Color::Rgb(111, 66, 193), // Purple
            variable: Color::Rgb(36, 41, 46),   // Dark gray
            number: Color::Rgb(0, 92, 197),     // Blue
            operator: Color::Rgb(215, 58, 73),  // Red
            type_name: Color::Rgb(111, 66, 193), // Purple
            macro_name: Color::Rgb(227, 98, 9), // Orange
            constant: Color::Rgb(0, 92, 197),   // Blue
            background: Color::White,
            foreground: Color::Rgb(36, 41, 46),
            selection: Color::Rgb(255, 251, 240),
            line_number: Color::Rgb(106, 115, 125),
        }
    }

    /// Solarized Dark theme
    pub fn solarized_dark_theme() -> Self {
        Self {
            keyword: Color::Rgb(181, 137, 0),   // Yellow
            string: Color::Rgb(42, 161, 152),   // Cyan
            comment: Color::Rgb(88, 110, 117),  // Base01
            function: Color::Rgb(38, 139, 210), // Blue
            variable: Color::Rgb(131, 148, 150), // Base0
            number: Color::Rgb(220, 50, 47),    // Red
            operator: Color::Rgb(203, 75, 22),  // Orange
            type_name: Color::Rgb(108, 113, 196), // Violet
            macro_name: Color::Rgb(133, 153, 0), // Green
            constant: Color::Rgb(211, 54, 130), // Magenta
            background: Color::Rgb(0, 43, 54),
            foreground: Color::Rgb(131, 148, 150),
            selection: Color::Rgb(7, 54, 66),
            line_number: Color::Rgb(88, 110, 117),
        }
    }
}

/// Language-specific syntax highlighting rules
#[derive(Debug, Clone)]
pub struct LanguageSyntax {
    pub keywords: Vec<&'static str>,
    pub operators: Vec<&'static str>,
    pub string_delimiters: Vec<(&'static str, &'static str)>,
    pub comment_patterns: Vec<CommentPattern>,
    pub function_pattern: Option<&'static str>,
    pub number_pattern: &'static str,
}

#[derive(Debug, Clone)]
pub enum CommentPattern {
    Line(&'static str),
    Block(&'static str, &'static str),
}

impl RichTextRenderer {
    pub fn new() -> Self {
        let mut syntax_rules = HashMap::new();
        
        // Add Elixir syntax rules
        syntax_rules.insert("elixir".to_string(), LanguageSyntax {
            keywords: vec![
                "def", "defp", "defmodule", "defmacro", "defstruct", "defprotocol", "defimpl",
                "do", "end", "if", "unless", "case", "cond", "with", "for", "try", "catch", "rescue", "after",
                "true", "false", "nil", "when", "and", "or", "not", "in", "fn", "receive", "send",
                "import", "require", "alias", "use", "quote", "unquote", "super",
            ],
            operators: vec![
                "=", "+", "-", "*", "/", "++", "--", "==", "!=", "===", "!==", 
                "<", ">", "<=", ">=", "&&", "||", "!", "&", "|", "^", "<<<", ">>>",
                "=~", "<>", "::", "=>", "<-", "->", "|>", "...", "..",
            ],
            string_delimiters: vec![
                ("\"", "\""),
                ("'", "'"),
                ("~r/", "/"),
                ("~s/", "/"),
                ("~w/", "/"),
            ],
            comment_patterns: vec![CommentPattern::Line("#")],
            function_pattern: Some(r"def\s+(\w+)"),
            number_pattern: r"\b\d+\.?\d*\b",
        });

        // Add Rust syntax rules
        syntax_rules.insert("rust".to_string(), LanguageSyntax {
            keywords: vec![
                "fn", "let", "mut", "const", "static", "if", "else", "match", "while", "for", "loop",
                "break", "continue", "return", "struct", "enum", "impl", "trait", "mod", "use", "pub",
                "true", "false", "self", "Self", "super", "crate", "where", "async", "await", "move",
                "ref", "in", "type", "as", "unsafe", "extern", "dyn", "box",
            ],
            operators: vec![
                "=", "+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">=",
                "&&", "||", "!", "&", "|", "^", "<<", ">>", "+=", "-=", "*=", "/=",
                "=>", "->", "::", "..", "..=", "?",
            ],
            string_delimiters: vec![
                ("\"", "\""),
                ("'", "'"),
                ("r\"", "\""),
                ("r#\"", "\"#"),
            ],
            comment_patterns: vec![
                CommentPattern::Line("//"),
                CommentPattern::Block("/*", "*/"),
            ],
            function_pattern: Some(r"fn\s+(\w+)"),
            number_pattern: r"\b\d+\.?\d*\b",
        });

        // Add JSON syntax rules
        syntax_rules.insert("json".to_string(), LanguageSyntax {
            keywords: vec!["true", "false", "null"],
            operators: vec![":", ","],
            string_delimiters: vec![("\"", "\"")],
            comment_patterns: vec![], // JSON doesn't have comments
            function_pattern: None,
            number_pattern: r"-?\b\d+\.?\d*([eE][+-]?\d+)?\b",
        });

        // Add Markdown syntax rules
        syntax_rules.insert("markdown".to_string(), LanguageSyntax {
            keywords: vec![], // Markdown doesn't have traditional keywords
            operators: vec!["*", "_", "`", "#", "-", "+", ">", "|"],
            string_delimiters: vec![
                ("`", "`"),
                ("```", "```"),
                ("**", "**"),
                ("__", "__"),
                ("*", "*"),
                ("_", "_"),
            ],
            comment_patterns: vec![CommentPattern::Block("<!--", "-->")],
            function_pattern: None,
            number_pattern: r"\b\d+\.?\d*\b",
        });

        Self {
            color_scheme: ColorScheme::default(),
            syntax_rules,
        }
    }

    /// Create renderer with specific color theme
    pub fn with_theme(theme_name: &str) -> Self {
        let mut renderer = Self::new();
        renderer.set_theme(theme_name);
        renderer
    }

    /// Set color theme
    pub fn set_theme(&mut self, theme_name: &str) {
        self.color_scheme = match theme_name.to_lowercase().as_str() {
            "light" => ColorScheme::light_theme(),
            "monokai" => ColorScheme::monokai_theme(),
            "github" => ColorScheme::github_theme(),
            "solarized" | "solarized-dark" => ColorScheme::solarized_dark_theme(),
            _ => ColorScheme::dark_theme(), // default
        };
    }

    /// Get available theme names
    pub fn available_themes() -> Vec<&'static str> {
        vec!["dark", "light", "monokai", "github", "solarized-dark"]
    }

    /// Render text with syntax highlighting
    pub fn render_code_block(&self, content: &str, language: Option<&str>) -> Text {
        if let Some(lang) = language {
            if let Some(syntax) = self.syntax_rules.get(lang) {
                return self.highlight_syntax(content, syntax);
            }
        }
        
        // Fallback to plain text
        Text::from(content)
    }

    /// Apply syntax highlighting to text based on language rules
    fn highlight_syntax(&self, content: &str, syntax: &LanguageSyntax) -> Text {
        let mut lines = Vec::new();
        
        for line_content in content.lines() {
            let spans = self.highlight_line(line_content, syntax);
            lines.push(Line::from(spans));
        }
        
        Text::from(lines)
    }

    /// Highlight a single line of code
    fn highlight_line(&self, line: &str, syntax: &LanguageSyntax) -> Vec<Span> {
        let mut spans = Vec::new();
        let mut chars: Vec<char> = line.chars().collect();
        let mut i = 0;

        while i < chars.len() {
            let remaining: String = chars[i..].iter().collect();
            
            // Check for comments first (highest priority)
            if let Some((comment_end, is_line_comment)) = self.find_comment_start(&remaining, syntax) {
                let comment_text: String = if is_line_comment {
                    chars[i..].iter().collect()
                } else {
                    chars[i..i + comment_end].iter().collect()
                };
                
                spans.push(Span::styled(comment_text, Style::default().fg(self.color_scheme.comment)));
                
                if is_line_comment {
                    break; // Line comment goes to end of line
                } else {
                    i += comment_end;
                }
                continue;
            }

            // Check for strings
            if let Some((string_content, string_len)) = self.find_string(&remaining, syntax) {
                spans.push(Span::styled(string_content, Style::default().fg(self.color_scheme.string)));
                i += string_len;
                continue;
            }

            // Check for numbers
            if let Some((number, number_len)) = self.find_number(&remaining, syntax) {
                spans.push(Span::styled(number, Style::default().fg(self.color_scheme.number)));
                i += number_len;
                continue;
            }

            // Check for keywords
            if let Some((keyword, keyword_len)) = self.find_keyword(&remaining, syntax) {
                spans.push(Span::styled(keyword, Style::default().fg(self.color_scheme.keyword)));
                i += keyword_len;
                continue;
            }

            // Check for operators
            if let Some((operator, operator_len)) = self.find_operator(&remaining, syntax) {
                spans.push(Span::styled(operator, Style::default().fg(self.color_scheme.operator)));
                i += operator_len;
                continue;
            }

            // Default: single character
            spans.push(Span::styled(
                chars[i].to_string(),
                Style::default().fg(self.color_scheme.foreground)
            ));
            i += 1;
        }

        spans
    }

    fn find_comment_start(&self, text: &str, syntax: &LanguageSyntax) -> Option<(usize, bool)> {
        for pattern in &syntax.comment_patterns {
            match pattern {
                CommentPattern::Line(start) => {
                    if text.starts_with(start) {
                        return Some((text.len(), true));
                    }
                }
                CommentPattern::Block(start, end) => {
                    if text.starts_with(start) {
                        if let Some(end_pos) = text.find(end) {
                            return Some((end_pos + end.len(), false));
                        } else {
                            return Some((text.len(), false));
                        }
                    }
                }
            }
        }
        None
    }

    fn find_string(&self, text: &str, syntax: &LanguageSyntax) -> Option<(String, usize)> {
        for (start_delim, end_delim) in &syntax.string_delimiters {
            if text.starts_with(start_delim) {
                let search_start = start_delim.len();
                if let Some(end_pos) = text[search_start..].find(end_delim) {
                    let total_len = search_start + end_pos + end_delim.len();
                    return Some((text[..total_len].to_string(), total_len));
                } else {
                    // Unclosed string goes to end of line
                    return Some((text.to_string(), text.len()));
                }
            }
        }
        None
    }

    fn find_number(&self, text: &str, syntax: &LanguageSyntax) -> Option<(String, usize)> {
        // Simple number detection - could be improved with regex
        let chars: Vec<char> = text.chars().collect();
        if chars.is_empty() || !chars[0].is_ascii_digit() {
            return None;
        }

        let mut len = 0;
        let mut has_dot = false;

        for &ch in &chars {
            if ch.is_ascii_digit() {
                len += 1;
            } else if ch == '.' && !has_dot {
                has_dot = true;
                len += 1;
            } else {
                break;
            }
        }

        if len > 0 {
            Some((chars[..len].iter().collect(), len))
        } else {
            None
        }
    }

    fn find_keyword(&self, text: &str, syntax: &LanguageSyntax) -> Option<(String, usize)> {
        for keyword in &syntax.keywords {
            if text.starts_with(keyword) {
                // Check that it's a complete word (not part of another word)
                let after_keyword = &text[keyword.len()..];
                if after_keyword.is_empty() || 
                   !after_keyword.chars().next().unwrap().is_alphanumeric() &&
                   after_keyword.chars().next().unwrap() != '_' {
                    return Some((keyword.to_string(), keyword.len()));
                }
            }
        }
        None
    }

    fn find_operator(&self, text: &str, syntax: &LanguageSyntax) -> Option<(String, usize)> {
        // Sort operators by length (longest first) to match longest operators first
        let mut sorted_operators = syntax.operators.clone();
        sorted_operators.sort_by(|a, b| b.len().cmp(&a.len()));
        
        for operator in sorted_operators {
            if text.starts_with(operator) {
                return Some((operator.to_string(), operator.len()));
            }
        }
        None
    }

    /// Render markdown-style text with formatting
    pub fn render_markdown(&self, content: &str) -> Text {
        let mut lines = Vec::new();
        
        for line_content in content.lines() {
            let spans = self.parse_markdown_line(line_content);
            lines.push(Line::from(spans));
        }
        
        Text::from(lines)
    }

    /// Parse a single line of markdown text
    fn parse_markdown_line(&self, line: &str) -> Vec<Span> {
        let mut spans = Vec::new();
        let mut chars: Vec<char> = line.chars().collect();
        let mut i = 0;

        // Check for headers
        if line.starts_with('#') {
            let header_level = line.chars().take_while(|&c| c == '#').count();
            let header_content = line.trim_start_matches('#').trim();
            let header_style = match header_level {
                1 => Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD | Modifier::UNDERLINED),
                2 => Style::default().fg(Color::Blue).add_modifier(Modifier::BOLD),
                3 => Style::default().fg(Color::Magenta).add_modifier(Modifier::BOLD),
                _ => Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
            };
            
            // Add header prefix with different styling
            let prefix = "#".repeat(header_level);
            spans.push(Span::styled(prefix, Style::default().fg(Color::DarkGray)));
            spans.push(Span::styled(" ", Style::default()));
            spans.push(Span::styled(header_content.to_string(), header_style));
            return spans;
        }

        // Check for blockquotes
        if line.starts_with('>') {
            let quote_content = line.trim_start_matches('>').trim();
            spans.push(Span::styled("▎ ", Style::default().fg(Color::DarkGray)));
            spans.push(Span::styled(quote_content.to_string(), 
                Style::default().fg(Color::Gray).add_modifier(Modifier::ITALIC)));
            return spans;
        }

        // Check for lists
        if line.trim_start().starts_with("- ") || line.trim_start().starts_with("* ") || line.trim_start().starts_with("+ ") {
            let indent = line.len() - line.trim_start().len();
            let list_content = line.trim_start().trim_start_matches(['-', '*', '+']).trim();
            
            spans.push(Span::styled(" ".repeat(indent), Style::default()));
            spans.push(Span::styled("• ", Style::default().fg(Color::Yellow)));
            spans.extend(self.parse_inline_markdown(list_content));
            return spans;
        }

        // Check for numbered lists
        if let Some(captures) = line.trim_start().strip_prefix(char::is_numeric) {
            if let Some(rest) = captures.strip_prefix(". ") {
                let indent = line.len() - line.trim_start().len();
                let number_part = &line.trim_start()[..line.trim_start().len() - rest.len() - 2];
                
                spans.push(Span::styled(" ".repeat(indent), Style::default()));
                spans.push(Span::styled(format!("{}. ", number_part), Style::default().fg(Color::Cyan)));
                spans.extend(self.parse_inline_markdown(rest));
                return spans;
            }
        }

        // Default to inline markdown parsing for regular text
        spans.extend(self.parse_inline_markdown(line));
        spans
    }

    /// Parse inline markdown formatting (bold, italic, code, etc.)
    fn parse_inline_markdown(&self, text: &str) -> Vec<Span> {
        let mut spans = Vec::new();
        let mut chars: Vec<char> = text.chars().collect();
        let mut i = 0;

        while i < chars.len() {
            let remaining: String = chars[i..].iter().collect();

            // Check for code spans (`code`)
            if remaining.starts_with('`') {
                if let Some(end_pos) = remaining[1..].find('`') {
                    let code_content = &remaining[1..end_pos + 1];
                    spans.push(Span::styled(
                        format!("`{}`", code_content),
                        Style::default().fg(self.color_scheme.string)
                            .bg(Color::DarkGray)
                            .add_modifier(Modifier::ITALIC)
                    ));
                    i += end_pos + 2;
                    continue;
                }
            }

            // Check for bold (**text** or __text__)
            if remaining.starts_with("**") || remaining.starts_with("__") {
                let delimiter = if remaining.starts_with("**") { "**" } else { "__" };
                if let Some(end_pos) = remaining[2..].find(delimiter) {
                    let bold_content = &remaining[2..end_pos + 2];
                    spans.push(Span::styled(
                        bold_content.to_string(),
                        Style::default().fg(Color::White).add_modifier(Modifier::BOLD)
                    ));
                    i += end_pos + 4;
                    continue;
                }
            }

            // Check for italic (*text* or _text_)
            if (remaining.starts_with('*') && !remaining.starts_with("**")) ||
               (remaining.starts_with('_') && !remaining.starts_with("__")) {
                let delimiter = if remaining.starts_with('*') { "*" } else { "_" };
                if let Some(end_pos) = remaining[1..].find(delimiter) {
                    let italic_content = &remaining[1..end_pos + 1];
                    spans.push(Span::styled(
                        italic_content.to_string(),
                        Style::default().fg(Color::White).add_modifier(Modifier::ITALIC)
                    ));
                    i += end_pos + 2;
                    continue;
                }
            }

            // Check for strikethrough (~~text~~)
            if remaining.starts_with("~~") {
                if let Some(end_pos) = remaining[2..].find("~~") {
                    let strike_content = &remaining[2..end_pos + 2];
                    spans.push(Span::styled(
                        strike_content.to_string(),
                        Style::default().fg(Color::DarkGray).add_modifier(Modifier::CROSSED_OUT)
                    ));
                    i += end_pos + 4;
                    continue;
                }
            }

            // Check for links [text](url) - simplified rendering
            if remaining.starts_with('[') {
                if let Some(close_bracket) = remaining.find(']') {
                    if let Some(paren_start) = remaining[close_bracket..].find('(') {
                        if let Some(paren_end) = remaining[close_bracket + paren_start..].find(')') {
                            let link_text = &remaining[1..close_bracket];
                            spans.push(Span::styled(
                                link_text.to_string(),
                                Style::default().fg(Color::Blue).add_modifier(Modifier::UNDERLINED)
                            ));
                            i += close_bracket + paren_start + paren_end + 1;
                            continue;
                        }
                    }
                }
            }

            // Default: single character
            spans.push(Span::styled(
                chars[i].to_string(),
                Style::default().fg(self.color_scheme.foreground)
            ));
            i += 1;
        }

        spans
    }

    /// Detect language from content or filename
    pub fn detect_language(&self, content: &str, filename: Option<&str>) -> Option<String> {
        // First try to detect from filename extension
        if let Some(name) = filename {
            if let Some(extension) = name.split('.').last() {
                let lang = match extension.to_lowercase().as_str() {
                    "ex" | "exs" => Some("elixir"),
                    "rs" => Some("rust"),
                    "js" | "jsx" => Some("javascript"),
                    "ts" | "tsx" => Some("typescript"),
                    "py" => Some("python"),
                    "json" => Some("json"),
                    "md" | "markdown" => Some("markdown"),
                    "toml" => Some("toml"),
                    "yaml" | "yml" => Some("yaml"),
                    _ => None,
                };
                if lang.is_some() {
                    return lang.map(|s| s.to_string());
                }
            }
        }

        // Try to detect from content patterns
        if content.contains("defmodule") || content.contains("def ") {
            return Some("elixir".to_string());
        }
        if content.contains("fn ") && content.contains("->") {
            return Some("rust".to_string());
        }
        if content.starts_with('{') && content.contains("\":") {
            return Some("json".to_string());
        }
        if content.contains("# ") || content.contains("## ") {
            return Some("markdown".to_string());
        }

        None
    }
}

/// Extract code blocks from markdown-style text
pub fn extract_code_blocks(content: &str) -> Vec<(Option<String>, String)> {
    let mut blocks = Vec::new();
    let lines: Vec<&str> = content.lines().collect();
    let mut i = 0;

    while i < lines.len() {
        let line = lines[i];
        
        // Check for fenced code blocks (```)
        if line.starts_with("```") {
            let language = if line.len() > 3 {
                Some(line[3..].trim().to_string())
            } else {
                None
            };
            
            i += 1;
            let mut code_lines = Vec::new();
            
            while i < lines.len() && !lines[i].starts_with("```") {
                code_lines.push(lines[i]);
                i += 1;
            }
            
            blocks.push((language, code_lines.join("\n")));
        }
        
        i += 1;
    }
    
    blocks
}

/// Check if content looks like code based on common patterns
pub fn looks_like_code(content: &str) -> bool {
    let code_indicators = [
        "fn ", "def ", "function ", "class ", "import ", "require ",
        "{", "}", "[", "]", "(", ")", ";", "=", "->", "=>",
        "if ", "else ", "for ", "while ", "match ", "case ",
        "pub ", "const ", "let ", "var ", "impl ", "struct ",
    ];
    
    let lines: Vec<&str> = content.lines().collect();
    if lines.len() < 2 {
        return false;
    }
    
    let mut code_score = 0;
    for line in lines.iter().take(10) { // Check first 10 lines
        for indicator in &code_indicators {
            if line.contains(indicator) {
                code_score += 1;
                break;
            }
        }
    }
    
    // If more than 30% of lines (max 10) have code indicators, consider it code
    code_score as f32 / lines.len().min(10) as f32 > 0.3
}

/// Diff visualization support
#[derive(Debug, Clone)]
pub enum DiffLineType {
    Added,
    Removed,
    Modified,
    Context,
    Header,
}

#[derive(Debug, Clone)]
pub struct DiffLine {
    pub line_type: DiffLineType,
    pub content: String,
    pub old_line_number: Option<usize>,
    pub new_line_number: Option<usize>,
}

impl RichTextRenderer {
    /// Render diff content with syntax highlighting
    pub fn render_diff(&self, diff_content: &str, language: Option<&str>) -> Text {
        let diff_lines = self.parse_diff(diff_content);
        let mut rendered_lines = Vec::new();
        
        for diff_line in diff_lines {
            let rendered_line = self.render_diff_line(&diff_line, language);
            rendered_lines.push(rendered_line);
        }
        
        Text::from(rendered_lines)
    }

    /// Parse unified diff format
    fn parse_diff(&self, content: &str) -> Vec<DiffLine> {
        let mut diff_lines = Vec::new();
        let mut old_line_number = 0;
        let mut new_line_number = 0;
        
        for line in content.lines() {
            if line.starts_with("@@") {
                // Hunk header
                diff_lines.push(DiffLine {
                    line_type: DiffLineType::Header,
                    content: line.to_string(),
                    old_line_number: None,
                    new_line_number: None,
                });
                
                // Parse line numbers from hunk header
                if let Some(captures) = parse_hunk_header(line) {
                    old_line_number = captures.0;
                    new_line_number = captures.1;
                }
            } else if line.starts_with('+') && !line.starts_with("+++") {
                // Added line
                diff_lines.push(DiffLine {
                    line_type: DiffLineType::Added,
                    content: line[1..].to_string(),
                    old_line_number: None,
                    new_line_number: Some(new_line_number),
                });
                new_line_number += 1;
            } else if line.starts_with('-') && !line.starts_with("---") {
                // Removed line
                diff_lines.push(DiffLine {
                    line_type: DiffLineType::Removed,
                    content: line[1..].to_string(),
                    old_line_number: Some(old_line_number),
                    new_line_number: None,
                });
                old_line_number += 1;
            } else if line.starts_with(' ') {
                // Context line
                diff_lines.push(DiffLine {
                    line_type: DiffLineType::Context,
                    content: line[1..].to_string(),
                    old_line_number: Some(old_line_number),
                    new_line_number: Some(new_line_number),
                });
                old_line_number += 1;
                new_line_number += 1;
            } else if line.starts_with("---") || line.starts_with("+++") {
                // File headers
                diff_lines.push(DiffLine {
                    line_type: DiffLineType::Header,
                    content: line.to_string(),
                    old_line_number: None,
                    new_line_number: None,
                });
            } else {
                // Other content (treat as context)
                diff_lines.push(DiffLine {
                    line_type: DiffLineType::Context,
                    content: line.to_string(),
                    old_line_number: Some(old_line_number),
                    new_line_number: Some(new_line_number),
                });
                if !line.is_empty() {
                    old_line_number += 1;
                    new_line_number += 1;
                }
            }
        }
        
        diff_lines
    }

    /// Render a single diff line with appropriate styling
    fn render_diff_line(&self, diff_line: &DiffLine, language: Option<&str>) -> Line {
        let mut spans = Vec::new();
        
        // Add line number prefix
        let line_number_style = Style::default().fg(self.color_scheme.line_number);
        match (&diff_line.old_line_number, &diff_line.new_line_number) {
            (Some(old), Some(new)) => {
                spans.push(Span::styled(format!("{:4} {:4} ", old, new), line_number_style));
            }
            (Some(old), None) => {
                spans.push(Span::styled(format!("{:4} {:4} ", old, ""), line_number_style));
            }
            (None, Some(new)) => {
                spans.push(Span::styled(format!("{:4} {:4} ", "", new), line_number_style));
            }
            (None, None) => {
                spans.push(Span::styled("         ", line_number_style));
            }
        }
        
        // Add diff indicator and content with appropriate styling
        match diff_line.line_type {
            DiffLineType::Added => {
                spans.push(Span::styled("+ ", Style::default().fg(Color::Green)));
                
                // Apply syntax highlighting to added content
                if let Some(lang) = language {
                    if let Some(syntax) = self.syntax_rules.get(lang) {
                        let highlighted_spans = self.highlight_line(&diff_line.content, syntax);
                        for span in highlighted_spans {
                            spans.push(Span::styled(
                                span.content,
                                span.style.bg(Color::DarkGreen),
                            ));
                        }
                    } else {
                        spans.push(Span::styled(
                            &diff_line.content,
                            Style::default().fg(Color::Green).bg(Color::DarkGreen),
                        ));
                    }
                } else {
                    spans.push(Span::styled(
                        &diff_line.content,
                        Style::default().fg(Color::Green).bg(Color::DarkGreen),
                    ));
                }
            }
            DiffLineType::Removed => {
                spans.push(Span::styled("- ", Style::default().fg(Color::Red)));
                
                // Apply syntax highlighting to removed content
                if let Some(lang) = language {
                    if let Some(syntax) = self.syntax_rules.get(lang) {
                        let highlighted_spans = self.highlight_line(&diff_line.content, syntax);
                        for span in highlighted_spans {
                            spans.push(Span::styled(
                                span.content,
                                span.style.bg(Color::DarkRed),
                            ));
                        }
                    } else {
                        spans.push(Span::styled(
                            &diff_line.content,
                            Style::default().fg(Color::Red).bg(Color::DarkRed),
                        ));
                    }
                } else {
                    spans.push(Span::styled(
                        &diff_line.content,
                        Style::default().fg(Color::Red).bg(Color::DarkRed),
                    ));
                }
            }
            DiffLineType::Context => {
                spans.push(Span::styled("  ", Style::default()));
                
                // Apply syntax highlighting to context
                if let Some(lang) = language {
                    if let Some(syntax) = self.syntax_rules.get(lang) {
                        spans.extend(self.highlight_line(&diff_line.content, syntax));
                    } else {
                        spans.push(Span::styled(&diff_line.content, Style::default()));
                    }
                } else {
                    spans.push(Span::styled(&diff_line.content, Style::default()));
                }
            }
            DiffLineType::Header => {
                spans.push(Span::styled(
                    &diff_line.content,
                    Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
                ));
            }
            DiffLineType::Modified => {
                spans.push(Span::styled("~ ", Style::default().fg(Color::Yellow)));
                spans.push(Span::styled(
                    &diff_line.content,
                    Style::default().fg(Color::Yellow).bg(Color::DarkYellow),
                ));
            }
        }
        
        Line::from(spans)
    }
}

/// Parse hunk header to extract line numbers
fn parse_hunk_header(header: &str) -> Option<(usize, usize)> {
    // Parse format: @@ -old_start,old_count +new_start,new_count @@
    if let Some(start) = header.find(" -") {
        if let Some(plus) = header[start..].find(" +") {
            let old_part = &header[start + 2..start + plus];
            let new_part = &header[start + plus + 2..];
            
            if let Some(space) = new_part.find(' ') {
                let new_part = &new_part[..space];
                
                let old_start = old_part.split(',').next()?.parse().ok()?;
                let new_start = new_part.split(',').next()?.parse().ok()?;
                
                return Some((old_start, new_start));
            }
        }
    }
    None
}

/// Detect if content is a diff based on common patterns
pub fn looks_like_diff(content: &str) -> bool {
    let diff_indicators = [
        "diff --git",
        "@@",
        "---",
        "+++",
        "index ",
    ];
    
    let lines: Vec<&str> = content.lines().collect();
    if lines.len() < 3 {
        return false;
    }
    
    // Check first few lines for diff indicators
    for line in lines.iter().take(5) {
        for indicator in &diff_indicators {
            if line.starts_with(indicator) {
                return true;
            }
        }
        
        // Check for diff line patterns
        if line.starts_with('+') || line.starts_with('-') || line.starts_with(' ') {
            return true;
        }
    }
    
    false
}