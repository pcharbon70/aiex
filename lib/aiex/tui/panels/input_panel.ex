defmodule Aiex.Tui.Panels.InputPanel do
  @moduledoc """
  Input Panel with multi-line editing and cursor tracking.
  
  This panel manages text input with support for multi-line editing, cursor 
  positioning, copy/paste operations, and keyboard shortcuts for a rich editing experience.
  """

  @behaviour Aiex.Tui.Panels.PanelBehaviour

  defstruct [
    :buffer,
    :cursor_line,
    :cursor_col,
    :lines,
    :viewport_width,
    :viewport_height,
    :scroll_offset,
    :history,
    :history_index,
    :mode,
    :placeholder,
    :focused
  ]

  @type mode :: :single_line | :multi_line
  @type t :: %__MODULE__{
    buffer: String.t(),
    cursor_line: integer(),
    cursor_col: integer(),
    lines: [String.t()],
    viewport_width: integer(),
    viewport_height: integer(),
    scroll_offset: integer(),
    history: [String.t()],
    history_index: integer(),
    mode: mode(),
    placeholder: String.t(),
    focused: boolean()
  }

  @doc """
  Initialize the input panel.
  """
  @spec init(map()) :: t()
  def init(opts \\ %{}) do
    %__MODULE__{
      buffer: "",
      cursor_line: 0,
      cursor_col: 0,
      lines: [""],
      viewport_width: Map.get(opts, :width, 80),
      viewport_height: Map.get(opts, :height, 4),
      scroll_offset: 0,
      history: [],
      history_index: 0,
      mode: Map.get(opts, :mode, :single_line),
      placeholder: Map.get(opts, :placeholder, "Type your message..."),
      focused: false
    }
  end

  @doc """
  Insert text at the current cursor position.
  """
  @spec insert_text(t(), String.t()) :: t()
  def insert_text(panel, text) do
    case panel.mode do
      :single_line -> insert_single_line(panel, text)
      :multi_line -> insert_multi_line(panel, text)
    end
  end

  @doc """
  Delete character at cursor (backspace).
  """
  @spec delete_char(t()) :: t()
  def delete_char(panel) do
    if panel.cursor_col > 0 do
      current_line = Enum.at(panel.lines, panel.cursor_line)
      {before, after_cursor} = String.split_at(current_line, panel.cursor_col - 1)
      new_line = before <> String.slice(after_cursor, 1..-1)
      
      new_lines = List.replace_at(panel.lines, panel.cursor_line, new_line)
      
      panel
      |> Map.put(:lines, new_lines)
      |> Map.put(:cursor_col, panel.cursor_col - 1)
      |> update_buffer()
    else
      # Handle backspace at beginning of line (join with previous line)
      if panel.cursor_line > 0 and panel.mode == :multi_line do
        current_line = Enum.at(panel.lines, panel.cursor_line)
        previous_line = Enum.at(panel.lines, panel.cursor_line - 1)
        
        new_line = previous_line <> current_line
        new_cursor_col = String.length(previous_line)
        
        new_lines = 
          panel.lines
          |> List.replace_at(panel.cursor_line - 1, new_line)
          |> List.delete_at(panel.cursor_line)
        
        panel
        |> Map.put(:lines, new_lines)
        |> Map.put(:cursor_line, panel.cursor_line - 1)
        |> Map.put(:cursor_col, new_cursor_col)
        |> update_buffer()
      else
        panel
      end
    end
  end

  @doc """
  Move cursor to new position.
  """
  @spec move_cursor(t(), :up | :down | :left | :right | :home | :end) :: t()
  def move_cursor(panel, direction) do
    case direction do
      :left -> move_cursor_left(panel)
      :right -> move_cursor_right(panel)
      :up -> move_cursor_up(panel)
      :down -> move_cursor_down(panel)
      :home -> move_cursor_home(panel)
      :end -> move_cursor_end(panel)
    end
  end

  @doc """
  Get the content as a single string.
  """
  @spec get_content(t()) :: String.t()
  def get_content(panel) do
    panel.buffer
  end

  @doc """
  Clear the input buffer.
  """
  @spec clear(t()) :: t()
  def clear(panel) do
    panel
    |> Map.put(:buffer, "")
    |> Map.put(:lines, [""])
    |> Map.put(:cursor_line, 0)
    |> Map.put(:cursor_col, 0)
  end

  @doc """
  Set the content of the input buffer.
  """
  @spec set_content(t(), String.t()) :: t()
  def set_content(panel, content) do
    lines = String.split(content, "\n")
    
    panel
    |> Map.put(:buffer, content)
    |> Map.put(:lines, lines)
    |> Map.put(:cursor_line, length(lines) - 1)
    |> Map.put(:cursor_col, String.length(List.last(lines)))
  end

  @doc """
  Add content to history.
  """
  @spec add_to_history(t(), String.t()) :: t()
  def add_to_history(panel, content) do
    new_history = [content | panel.history] |> Enum.take(100) # Keep last 100 entries
    
    panel
    |> Map.put(:history, new_history)
    |> Map.put(:history_index, 0)
  end

  @doc """
  Navigate through history.
  """
  @spec navigate_history(t(), :up | :down) :: t()
  def navigate_history(panel, direction) do
    case direction do
      :up -> 
        if panel.history_index < length(panel.history) do
          new_index = panel.history_index + 1
          content = Enum.at(panel.history, new_index - 1, "")
          
          panel
          |> Map.put(:history_index, new_index)
          |> set_content(content)
        else
          panel
        end
      
      :down ->
        if panel.history_index > 0 do
          new_index = panel.history_index - 1
          content = if new_index == 0, do: "", else: Enum.at(panel.history, new_index - 1, "")
          
          panel
          |> Map.put(:history_index, new_index)
          |> set_content(content)
        else
          panel
        end
    end
  end

  @doc """
  Toggle between single-line and multi-line mode.
  """
  @spec toggle_mode(t()) :: t()
  def toggle_mode(panel) do
    new_mode = if panel.mode == :single_line, do: :multi_line, else: :single_line
    Map.put(panel, :mode, new_mode)
  end

  # PanelBehaviour implementation

  @impl true
  def resize(panel, width, height) do
    panel
    |> Map.put(:viewport_width, width)
    |> Map.put(:viewport_height, height)
  end

  @impl true
  def render(panel) do
    if panel.buffer == "" and not panel.focused do
      render_placeholder(panel)
    else
      render_content(panel)
    end
  end

  @impl true
  def get_state(panel) do
    %{
      content: panel.buffer,
      cursor_position: {panel.cursor_line, panel.cursor_col},
      mode: panel.mode,
      focused: panel.focused,
      line_count: length(panel.lines),
      history_count: length(panel.history)
    }
  end

  @impl true
  def handle_focus_gained(panel) do
    Map.put(panel, :focused, true)
  end

  @impl true
  def handle_focus_lost(panel) do
    Map.put(panel, :focused, false)
  end

  @impl true
  def handle_input(panel, input) do
    case input do
      {:char, char} -> insert_text(panel, char)
      {:key, :backspace} -> delete_char(panel)
      {:key, :enter} -> handle_enter(panel)
      {:key, :tab} -> insert_text(panel, "  ") # Insert spaces for tab
      {:key, :up} -> 
        if panel.mode == :multi_line do
          move_cursor(panel, :up)
        else
          navigate_history(panel, :up)
        end
      {:key, :down} ->
        if panel.mode == :multi_line do
          move_cursor(panel, :down)
        else
          navigate_history(panel, :down)
        end
      {:key, :left} -> move_cursor(panel, :left)
      {:key, :right} -> move_cursor(panel, :right)
      {:key, :home} -> move_cursor(panel, :home)
      {:key, :end} -> move_cursor(panel, :end)
      _ -> panel
    end
  end

  # Private functions

  defp insert_single_line(panel, text) do
    # Filter out newlines in single-line mode
    clean_text = String.replace(text, ~r/[\r\n]/, "")
    
    current_line = Enum.at(panel.lines, 0)
    {before, after_cursor} = String.split_at(current_line, panel.cursor_col)
    new_line = before <> clean_text <> after_cursor
    
    panel
    |> Map.put(:lines, [new_line])
    |> Map.put(:cursor_col, panel.cursor_col + String.length(clean_text))
    |> update_buffer()
  end

  defp insert_multi_line(panel, text) do
    current_line = Enum.at(panel.lines, panel.cursor_line)
    {before, after_cursor} = String.split_at(current_line, panel.cursor_col)
    
    case String.split(text, "\n") do
      [single_part] ->
        # No newlines, simple insertion
        new_line = before <> single_part <> after_cursor
        new_lines = List.replace_at(panel.lines, panel.cursor_line, new_line)
        
        panel
        |> Map.put(:lines, new_lines)
        |> Map.put(:cursor_col, panel.cursor_col + String.length(single_part))
        |> update_buffer()
      
      [first | rest] ->
        # Has newlines, split current line
        first_line = before <> first
        last_part = List.last(rest)
        middle_lines = Enum.drop(rest, -1)
        last_line = last_part <> after_cursor
        
        new_lines = 
          List.replace_at(panel.lines, panel.cursor_line, first_line)
          |> insert_lines_after(panel.cursor_line, middle_lines ++ [last_line])
        
        panel
        |> Map.put(:lines, new_lines)
        |> Map.put(:cursor_line, panel.cursor_line + length(rest))
        |> Map.put(:cursor_col, String.length(last_part))
        |> update_buffer()
    end
  end

  defp handle_enter(panel) do
    case panel.mode do
      :single_line -> panel # Don't insert newlines in single-line mode
      :multi_line -> insert_text(panel, "\n")
    end
  end

  defp move_cursor_left(panel) do
    if panel.cursor_col > 0 do
      Map.put(panel, :cursor_col, panel.cursor_col - 1)
    else
      if panel.cursor_line > 0 and panel.mode == :multi_line do
        previous_line = Enum.at(panel.lines, panel.cursor_line - 1)
        panel
        |> Map.put(:cursor_line, panel.cursor_line - 1)
        |> Map.put(:cursor_col, String.length(previous_line))
      else
        panel
      end
    end
  end

  defp move_cursor_right(panel) do
    current_line = Enum.at(panel.lines, panel.cursor_line)
    line_length = String.length(current_line)
    
    if panel.cursor_col < line_length do
      Map.put(panel, :cursor_col, panel.cursor_col + 1)
    else
      if panel.cursor_line < length(panel.lines) - 1 and panel.mode == :multi_line do
        panel
        |> Map.put(:cursor_line, panel.cursor_line + 1)
        |> Map.put(:cursor_col, 0)
      else
        panel
      end
    end
  end

  defp move_cursor_up(panel) do
    if panel.cursor_line > 0 do
      new_line = panel.cursor_line - 1
      new_line_length = String.length(Enum.at(panel.lines, new_line))
      new_col = min(panel.cursor_col, new_line_length)
      
      panel
      |> Map.put(:cursor_line, new_line)
      |> Map.put(:cursor_col, new_col)
    else
      panel
    end
  end

  defp move_cursor_down(panel) do
    if panel.cursor_line < length(panel.lines) - 1 do
      new_line = panel.cursor_line + 1
      new_line_length = String.length(Enum.at(panel.lines, new_line))
      new_col = min(panel.cursor_col, new_line_length)
      
      panel
      |> Map.put(:cursor_line, new_line)
      |> Map.put(:cursor_col, new_col)
    else
      panel
    end
  end

  defp move_cursor_home(panel) do
    Map.put(panel, :cursor_col, 0)
  end

  defp move_cursor_end(panel) do
    current_line = Enum.at(panel.lines, panel.cursor_line)
    Map.put(panel, :cursor_col, String.length(current_line))
  end

  defp update_buffer(panel) do
    buffer = Enum.join(panel.lines, "\n")
    Map.put(panel, :buffer, buffer)
  end

  defp insert_lines_after(lines, index, new_lines) do
    {before, after_lines} = Enum.split(lines, index + 1)
    before ++ new_lines ++ after_lines
  end

  defp render_placeholder(panel) do
    placeholder_line = "💬 #{panel.placeholder}"
    padding_lines = max(0, panel.viewport_height - 1)
    
    [placeholder_line] ++ List.duplicate("", padding_lines)
  end

  defp render_content(panel) do
    visible_lines = get_visible_lines(panel)
    
    visible_lines
    |> add_cursor_indicator(panel)
    |> pad_to_viewport(panel.viewport_height)
  end

  defp get_visible_lines(panel) do
    start_line = panel.scroll_offset
    end_line = min(start_line + panel.viewport_height - 1, length(panel.lines) - 1)
    
    if start_line <= end_line do
      Enum.slice(panel.lines, start_line..end_line)
    else
      []
    end
  end

  defp add_cursor_indicator(lines, panel) do
    if panel.focused and panel.cursor_line >= panel.scroll_offset and 
       panel.cursor_line < panel.scroll_offset + panel.viewport_height do
      
      relative_line = panel.cursor_line - panel.scroll_offset
      
      case Enum.at(lines, relative_line) do
        nil -> lines
        line ->
          {before, after_cursor} = String.split_at(line, panel.cursor_col)
          cursor_line = before <> "│" <> after_cursor  # Cursor indicator
          List.replace_at(lines, relative_line, cursor_line)
      end
    else
      lines
    end
  end

  defp pad_to_viewport(lines, viewport_height) do
    current_count = length(lines)
    
    if current_count < viewport_height do
      lines ++ List.duplicate("", viewport_height - current_count)
    else
      lines
    end
  end
end