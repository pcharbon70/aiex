defmodule Aiex.Tui.Panels.ContextPanel do
  @moduledoc """
  Context Panel for project awareness and quick actions.
  
  This panel displays project context, file information, available actions,
  and provides quick access to common development tasks.
  """

  @behaviour Aiex.Tui.Panels.PanelBehaviour

  defstruct [
    :project_context,
    :current_files,
    :quick_actions,
    :selected_action,
    :viewport_height,
    :scroll_position,
    :show_files,
    :show_actions,
    :expanded_sections
  ]

  @type t :: %__MODULE__{
    project_context: map(),
    current_files: [map()],
    quick_actions: [map()],
    selected_action: integer(),
    viewport_height: integer(),
    scroll_position: integer(),
    show_files: boolean(),
    show_actions: boolean(),
    expanded_sections: MapSet.t(atom())
  }

  @doc """
  Initialize the context panel.
  """
  @spec init(map()) :: t()
  def init(opts \\ %{}) do
    %__MODULE__{
      project_context: Map.get(opts, :project_context, %{}),
      current_files: Map.get(opts, :current_files, []),
      quick_actions: default_quick_actions(),
      selected_action: 0,
      viewport_height: Map.get(opts, :height, 20),
      scroll_position: 0,
      show_files: Map.get(opts, :show_files, true),
      show_actions: Map.get(opts, :show_actions, true),
      expanded_sections: MapSet.new([:project, :actions])
    }
  end

  @doc """
  Update project context information.
  """
  @spec update_project_context(t(), map()) :: t()
  def update_project_context(panel, context) do
    Map.put(panel, :project_context, context)
  end

  @doc """
  Update current files list.
  """
  @spec update_current_files(t(), [map()]) :: t()
  def update_current_files(panel, files) do
    Map.put(panel, :current_files, files)
  end

  @doc """
  Toggle section expansion.
  """
  @spec toggle_section(t(), atom()) :: t()
  def toggle_section(panel, section) do
    expanded = 
      if MapSet.member?(panel.expanded_sections, section) do
        MapSet.delete(panel.expanded_sections, section)
      else
        MapSet.put(panel.expanded_sections, section)
      end
    
    Map.put(panel, :expanded_sections, expanded)
  end

  @doc """
  Select next action.
  """
  @spec select_next_action(t()) :: t()
  def select_next_action(panel) do
    max_index = length(panel.quick_actions) - 1
    new_index = min(panel.selected_action + 1, max_index)
    Map.put(panel, :selected_action, new_index)
  end

  @doc """
  Select previous action.
  """
  @spec select_previous_action(t()) :: t()
  def select_previous_action(panel) do
    new_index = max(panel.selected_action - 1, 0)
    Map.put(panel, :selected_action, new_index)
  end

  @doc """
  Get currently selected action.
  """
  @spec get_selected_action(t()) :: map() | nil
  def get_selected_action(panel) do
    Enum.at(panel.quick_actions, panel.selected_action)
  end

  @doc """
  Scroll the panel by a number of lines.
  """
  @spec scroll(t(), integer()) :: t()
  def scroll(panel, delta) do
    # Calculate total rendered lines to determine scroll limits
    total_lines = calculate_total_lines(panel)
    max_scroll = max(0, total_lines - panel.viewport_height)
    
    new_position = max(0, min(panel.scroll_position + delta, max_scroll))
    Map.put(panel, :scroll_position, new_position)
  end

  # PanelBehaviour implementation

  @impl true
  def resize(panel, _width, height) do
    Map.put(panel, :viewport_height, height)
  end

  @impl true
  def render(panel) do
    content_lines = build_content_lines(panel)
    
    # Apply scrolling
    visible_lines = apply_scrolling(content_lines, panel)
    
    # Pad to viewport height
    pad_to_viewport(visible_lines, panel.viewport_height)
  end

  @impl true
  def get_state(panel) do
    %{
      project_name: get_project_name(panel.project_context),
      file_count: length(panel.current_files),
      action_count: length(panel.quick_actions),
      selected_action: panel.selected_action,
      expanded_sections: MapSet.to_list(panel.expanded_sections)
    }
  end

  @impl true
  def handle_input(panel, input) do
    case input do
      {:key, :up} -> select_previous_action(panel)
      {:key, :down} -> select_next_action(panel)
      {:key, :space} -> toggle_current_section(panel)
      {:char, "f"} -> Map.put(panel, :show_files, !panel.show_files)
      {:char, "a"} -> Map.put(panel, :show_actions, !panel.show_actions)
      _ -> panel
    end
  end

  # Private functions

  defp default_quick_actions do
    [
      %{
        id: :analyze_file,
        title: "Analyze Current File",
        description: "Analyze the currently open file",
        icon: "🔍",
        shortcut: "Ctrl+A"
      },
      %{
        id: :explain_code,
        title: "Explain Code",
        description: "Get explanation of selected code",
        icon: "💡",
        shortcut: "Ctrl+E"
      },
      %{
        id: :generate_tests,
        title: "Generate Tests",
        description: "Generate tests for current file",
        icon: "🧪",
        shortcut: "Ctrl+T"
      },
      %{
        id: :refactor_code,
        title: "Refactor Code",
        description: "Suggest refactoring improvements",
        icon: "🔧",
        shortcut: "Ctrl+R"
      },
      %{
        id: :generate_docs,
        title: "Generate Documentation",
        description: "Generate documentation for code",
        icon: "📝",
        shortcut: "Ctrl+D"
      },
      %{
        id: :review_code,
        title: "Code Review",
        description: "Perform automated code review",
        icon: "👁️",
        shortcut: "Ctrl+Shift+R"
      }
    ]
  end

  defp build_content_lines(panel) do
    lines = []
    
    # Project section
    lines = if MapSet.member?(panel.expanded_sections, :project) do
      lines ++ build_project_section(panel)
    else
      lines ++ ["▶ Project Info"]
    end
    
    # Files section
    lines = if panel.show_files do
      if MapSet.member?(panel.expanded_sections, :files) do
        lines ++ [""] ++ build_files_section(panel)
      else
        lines ++ ["", "▶ Current Files (#{length(panel.current_files)})"]
      end
    else
      lines
    end
    
    # Actions section
    lines = if panel.show_actions do
      if MapSet.member?(panel.expanded_sections, :actions) do
        lines ++ [""] ++ build_actions_section(panel)
      else
        lines ++ ["", "▶ Quick Actions (#{length(panel.quick_actions)})"]
      end
    else
      lines
    end
    
    lines
  end

  defp build_project_section(panel) do
    context = panel.project_context
    lines = ["▼ Project Info"]
    
    lines = if Map.has_key?(context, :name) do
      lines ++ ["  Name: #{context.name}"]
    else
      lines
    end
    
    lines = if Map.has_key?(context, :type) do
      lines ++ ["  Type: #{context.type}"]
    else
      lines
    end
    
    lines = if Map.has_key?(context, :version) do
      lines ++ ["  Version: #{context.version}"]
    else
      lines
    end
    
    lines = if Map.has_key?(context, :description) do
      description = String.slice(context.description, 0, 30) <> "..."
      lines ++ ["  Desc: #{description}"]
    else
      lines
    end
    
    lines
  end

  defp build_files_section(panel) do
    lines = ["▼ Current Files (#{length(panel.current_files)})"]
    
    file_lines = panel.current_files
    |> Enum.take(10) # Limit to 10 files
    |> Enum.map(&format_file_entry/1)
    
    lines ++ file_lines
  end

  defp build_actions_section(panel) do
    lines = ["▼ Quick Actions"]
    
    action_lines = panel.quick_actions
    |> Enum.with_index()
    |> Enum.map(fn {action, index} ->
      format_action_entry(action, index, panel.selected_action)
    end)
    
    lines ++ action_lines
  end

  defp format_file_entry(file) do
    name = Map.get(file, :name, "unknown")
    type = Map.get(file, :type, "")
    
    # Add type indicator
    icon = case type do
      "elixir" -> "💎"
      "test" -> "🧪"
      "config" -> "⚙️"
      "markdown" -> "📝"
      _ -> "📄"
    end
    
    # Truncate name if too long
    display_name = if String.length(name) > 20 do
      String.slice(name, 0, 17) <> "..."
    else
      name
    end
    
    "  #{icon} #{display_name}"
  end

  defp format_action_entry(action, index, selected_index) do
    icon = Map.get(action, :icon, "•")
    title = Map.get(action, :title, "Action")
    shortcut = Map.get(action, :shortcut, "")
    
    # Add selection indicator
    indicator = if index == selected_index, do: "►", else: " "
    
    # Format with shortcut if available
    if shortcut != "" do
      "#{indicator} #{icon} #{title} (#{shortcut})"
    else
      "#{indicator} #{icon} #{title}"
    end
  end

  defp toggle_current_section(panel) do
    # This is a simplified implementation
    # In a full implementation, we'd need to track which section is currently focused
    toggle_section(panel, :actions)
  end

  defp calculate_total_lines(panel) do
    # Estimate total lines that would be rendered
    base_lines = 1 # Project header
    
    base_lines = if MapSet.member?(panel.expanded_sections, :project) do
      base_lines + map_size(panel.project_context) + 1
    else
      base_lines
    end
    
    base_lines = if panel.show_files do
      if MapSet.member?(panel.expanded_sections, :files) do
        base_lines + min(length(panel.current_files), 10) + 2
      else
        base_lines + 2
      end
    else
      base_lines
    end
    
    base_lines = if panel.show_actions do
      if MapSet.member?(panel.expanded_sections, :actions) do
        base_lines + length(panel.quick_actions) + 2
      else
        base_lines + 2
      end
    else
      base_lines
    end
    
    base_lines
  end

  defp apply_scrolling(lines, panel) do
    start_line = panel.scroll_position
    end_line = start_line + panel.viewport_height - 1
    
    if start_line < length(lines) do
      Enum.slice(lines, start_line..end_line)
    else
      []
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

  defp get_project_name(%{name: name}), do: name
  defp get_project_name(%{root: root}) when is_binary(root), do: Path.basename(root)
  defp get_project_name(_), do: "Unknown Project"
end