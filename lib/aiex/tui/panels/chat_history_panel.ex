defmodule Aiex.Tui.Panels.ChatHistoryPanel do
  @moduledoc """
  Chat History Panel with virtual scrolling support for efficient message display.
  
  This panel manages the display of conversation history with virtual scrolling
  to handle large numbers of messages efficiently, syntax highlighting for code blocks,
  and proper message formatting with timestamps and type indicators.
  """

  @behaviour Aiex.Tui.Panels.PanelBehaviour

  defstruct [
    :messages,
    :scroll_position,
    :visible_lines,
    :total_lines,
    :viewport_height,
    :search_term,
    :filtered_messages,
    :highlight_ranges
  ]

  @type t :: %__MODULE__{
    messages: [map()],
    scroll_position: integer(),
    visible_lines: [String.t()],
    total_lines: integer(),
    viewport_height: integer(),
    search_term: String.t() | nil,
    filtered_messages: [map()] | nil,
    highlight_ranges: [{integer(), integer()}]
  }

  @doc """
  Initialize the chat history panel.
  """
  @spec init(map()) :: t()
  def init(opts \\ %{}) do
    %__MODULE__{
      messages: Map.get(opts, :messages, []),
      scroll_position: 0,
      visible_lines: [],
      total_lines: 0,
      viewport_height: Map.get(opts, :height, 20),
      search_term: nil,
      filtered_messages: nil,
      highlight_ranges: []
    }
  end

  @doc """
  Update the panel with new messages.
  """
  @spec update_messages(t(), [map()]) :: t()
  def update_messages(panel, messages) do
    panel
    |> Map.put(:messages, messages)
    |> Map.put(:filtered_messages, nil)
    |> recalculate_content()
    |> auto_scroll_to_bottom()
  end

  @doc """
  Scroll the panel by a number of lines.
  """
  @spec scroll(t(), integer()) :: t()
  def scroll(panel, delta) do
    new_position = max(0, min(panel.scroll_position + delta, max_scroll_position(panel)))
    
    panel
    |> Map.put(:scroll_position, new_position)
    |> update_visible_lines()
  end

  @doc """
  Search for messages containing the given term.
  """
  @spec search(t(), String.t()) :: t()
  def search(panel, term) do
    filtered = filter_messages(panel.messages, term)
    highlights = find_highlight_ranges(filtered, term)
    
    panel
    |> Map.put(:search_term, term)
    |> Map.put(:filtered_messages, filtered)
    |> Map.put(:highlight_ranges, highlights)
    |> Map.put(:scroll_position, 0)
    |> recalculate_content()
  end

  @doc """
  Clear search and show all messages.
  """
  @spec clear_search(t()) :: t()
  def clear_search(panel) do
    panel
    |> Map.put(:search_term, nil)
    |> Map.put(:filtered_messages, nil)
    |> Map.put(:highlight_ranges, [])
    |> recalculate_content()
  end

  @doc """
  Resize the panel to new dimensions.
  """
  @spec resize(t(), integer(), integer()) :: t()
  def resize(panel, _width, height) do
    panel
    |> Map.put(:viewport_height, height)
    |> update_visible_lines()
  end

  @doc """
  Render the panel content for display.
  """
  @spec render(t()) :: [String.t()]
  def render(panel) do
    case panel.visible_lines do
      [] -> 
        ["No messages yet. Start a conversation!"]
      lines ->
        lines
        |> apply_highlighting(panel.highlight_ranges)
        |> pad_to_viewport(panel.viewport_height)
    end
  end

  @doc """
  Get the current state for external consumers.
  """
  @spec get_state(t()) :: map()
  def get_state(panel) do
    %{
      message_count: length(panel.messages),
      scroll_position: panel.scroll_position,
      total_lines: panel.total_lines,
      viewport_height: panel.viewport_height,
      search_active: panel.search_term != nil,
      search_term: panel.search_term
    }
  end

  # Private functions

  defp recalculate_content(panel) do
    messages = panel.filtered_messages || panel.messages
    lines = format_messages_to_lines(messages)
    
    panel
    |> Map.put(:visible_lines, lines)
    |> Map.put(:total_lines, length(lines))
    |> update_visible_lines()
  end

  defp format_messages_to_lines(messages) do
    messages
    |> Enum.flat_map(&format_message/1)
  end

  defp format_message(message) do
    timestamp = format_timestamp(message.timestamp)
    icon = get_message_icon(message.type)
    content_lines = format_content(message.content)
    
    header = "#{timestamp} #{icon}"
    
    case content_lines do
      [single_line] -> ["#{header} #{single_line}"]
      [first | rest] -> 
        ["#{header} #{first}"] ++ Enum.map(rest, &("    #{&1}"))
    end
  end

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%H:%M")
  end

  defp get_message_icon(:user), do: "👤"
  defp get_message_icon(:assistant), do: "🤖"
  defp get_message_icon(:system), do: "ℹ️"
  defp get_message_icon(:error), do: "❌"
  defp get_message_icon(_), do: "💬"

  defp format_content(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp auto_scroll_to_bottom(panel) do
    max_scroll = max_scroll_position(panel)
    Map.put(panel, :scroll_position, max_scroll)
  end

  defp max_scroll_position(panel) do
    max(0, panel.total_lines - panel.viewport_height)
  end

  defp update_visible_lines(panel) do
    start_line = panel.scroll_position
    end_line = min(start_line + panel.viewport_height - 1, panel.total_lines - 1)
    
    visible = 
      if start_line <= end_line and panel.total_lines > 0 do
        Enum.slice(panel.visible_lines, start_line..end_line)
      else
        []
      end
    
    Map.put(panel, :visible_lines, visible)
  end

  defp filter_messages(messages, term) do
    term_lower = String.downcase(term)
    
    Enum.filter(messages, fn message ->
      String.contains?(String.downcase(message.content), term_lower)
    end)
  end

  defp find_highlight_ranges(messages, term) do
    # For now, return empty ranges - will implement highlighting later
    # In full implementation, this would find character ranges to highlight
    _ = messages
    _ = term
    []
  end

  defp apply_highlighting(lines, _highlight_ranges) do
    # For now, just return lines as-is
    # In full implementation, this would apply ANSI color codes
    lines
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