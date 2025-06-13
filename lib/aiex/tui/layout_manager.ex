defmodule Aiex.Tui.LayoutManager do
  @moduledoc """
  Layout Manager for coordinating multi-panel layout with constraint-based positioning.
  
  This module manages the hierarchical layout system, handles panel resizing,
  focus management, and coordinates rendering across all panels using the
  Libvaxis constraint system through NIFs.
  """

  alias Aiex.Tui.LibvaxisNif
  alias Aiex.Tui.Panels.{ChatHistoryPanel, InputPanel, StatusPanel, ContextPanel}

  defstruct [
    :layout_spec,
    :panels,
    :focused_panel,
    :terminal_size,
    :layout_mode,
    :panel_visibility,
    :resize_mode
  ]

  @type layout_mode :: :default | :chat_focus | :code_focus | :full_screen
  @type resize_mode :: :fixed | :dynamic | :manual
  @type panel_id :: :chat_history | :input | :status | :context
  
  @type t :: %__MODULE__{
    layout_spec: map(),
    panels: %{panel_id() => struct()},
    focused_panel: panel_id(),
    terminal_size: {integer(), integer()},
    layout_mode: layout_mode(),
    panel_visibility: %{panel_id() => boolean()},
    resize_mode: resize_mode()
  }

  @doc """
  Initialize the layout manager with terminal dimensions.
  """
  @spec init(integer(), integer(), map()) :: t()
  def init(width, height, opts \\ %{}) do
    layout_mode = Map.get(opts, :layout_mode, :default)
    
    # Create initial layout specification
    {:ok, layout_spec} = LibvaxisNif.create_layout(width, height)
    
    # Initialize all panels
    panels = %{
      chat_history: ChatHistoryPanel.init(%{
        messages: Map.get(opts, :messages, []),
        height: get_panel_height(layout_spec, :chat_panel)
      }),
      input: InputPanel.init(%{
        width: get_panel_width(layout_spec, :input_panel),
        height: get_panel_height(layout_spec, :input_panel),
        mode: :single_line
      }),
      status: StatusPanel.init(%{
        width: get_panel_width(layout_spec, :status_panel),
        connection_status: Map.get(opts, :connection_status, :disconnected)
      }),
      context: ContextPanel.init(%{
        height: get_panel_height(layout_spec, :context_panel),
        project_context: Map.get(opts, :project_context, %{})
      })
    }
    
    %__MODULE__{
      layout_spec: layout_spec,
      panels: panels,
      focused_panel: :input,
      terminal_size: {width, height},
      layout_mode: layout_mode,
      panel_visibility: %{
        chat_history: true,
        input: true,
        status: true,
        context: true
      },
      resize_mode: :dynamic
    }
  end

  @doc """
  Handle terminal resize event.
  """
  @spec handle_resize(t(), integer(), integer()) :: t()
  def handle_resize(layout, new_width, new_height) do
    # Recalculate layout with new dimensions
    {:ok, new_layout_spec} = LibvaxisNif.create_layout(new_width, new_height)
    
    # Resize all panels
    new_panels = 
      layout.panels
      |> update_panels_map(:chat_history, fn panel ->
        ChatHistoryPanel.resize(panel, 
          get_panel_width(new_layout_spec, :chat_panel),
          get_panel_height(new_layout_spec, :chat_panel)
        )
      end)
      |> update_panels_map(:input, fn panel ->
        InputPanel.resize(panel,
          get_panel_width(new_layout_spec, :input_panel),
          get_panel_height(new_layout_spec, :input_panel)
        )
      end)
      |> update_panels_map(:status, fn panel ->
        StatusPanel.resize(panel,
          get_panel_width(new_layout_spec, :status_panel),
          get_panel_height(new_layout_spec, :status_panel)
        )
      end)
      |> update_panels_map(:context, fn panel ->
        ContextPanel.resize(panel,
          get_panel_width(new_layout_spec, :context_panel),
          get_panel_height(new_layout_spec, :context_panel)
        )
      end)
    
    layout
    |> Map.put(:layout_spec, new_layout_spec)
    |> Map.put(:panels, new_panels)
    |> Map.put(:terminal_size, {new_width, new_height})
  end

  @doc """
  Change focus to specified panel.
  """
  @spec change_focus(t(), panel_id()) :: t()
  def change_focus(layout, new_focus) do
    # Handle focus lost for current panel
    current_panel = Map.get(layout.panels, layout.focused_panel)
    updated_current = 
      if function_exported?(current_panel.__struct__, :handle_focus_lost, 1) do
        current_panel.__struct__.handle_focus_lost(current_panel)
      else
        current_panel
      end
    
    # Handle focus gained for new panel
    new_panel = Map.get(layout.panels, new_focus)
    updated_new = 
      if function_exported?(new_panel.__struct__, :handle_focus_gained, 1) do
        new_panel.__struct__.handle_focus_gained(new_panel)
      else
        new_panel
      end
    
    # Update focus in NIF
    LibvaxisNif.handle_focus_change(layout.focused_panel, new_focus)
    
    layout
    |> put_in([:panels, layout.focused_panel], updated_current)
    |> put_in([:panels, new_focus], updated_new)
    |> Map.put(:focused_panel, new_focus)
  end

  @doc """
  Cycle focus to next panel.
  """
  @spec cycle_focus_next(t()) :: t()
  def cycle_focus_next(layout) do
    visible_panels = get_visible_panels(layout)
    current_index = Enum.find_index(visible_panels, &(&1 == layout.focused_panel))
    
    next_index = 
      case current_index do
        nil -> 0
        index -> rem(index + 1, length(visible_panels))
      end
    
    next_panel = Enum.at(visible_panels, next_index)
    change_focus(layout, next_panel)
  end

  @doc """
  Cycle focus to previous panel.
  """
  @spec cycle_focus_previous(t()) :: t()
  def cycle_focus_previous(layout) do
    visible_panels = get_visible_panels(layout)
    current_index = Enum.find_index(visible_panels, &(&1 == layout.focused_panel))
    
    prev_index = 
      case current_index do
        nil -> 0
        0 -> length(visible_panels) - 1
        index -> index - 1
      end
    
    prev_panel = Enum.at(visible_panels, prev_index)
    change_focus(layout, prev_panel)
  end

  @doc """
  Handle input for the currently focused panel.
  """
  @spec handle_input(t(), term()) :: t()
  def handle_input(layout, input) do
    focused_panel = Map.get(layout.panels, layout.focused_panel)
    
    updated_panel = 
      if function_exported?(focused_panel.__struct__, :handle_input, 2) do
        focused_panel.__struct__.handle_input(focused_panel, input)
      else
        focused_panel
      end
    
    put_in(layout, [:panels, layout.focused_panel], updated_panel)
  end

  @doc """
  Toggle panel visibility.
  """
  @spec toggle_panel_visibility(t(), panel_id()) :: t()
  def toggle_panel_visibility(layout, panel_id) do
    current_visibility = Map.get(layout.panel_visibility, panel_id, true)
    new_visibility = Map.put(layout.panel_visibility, panel_id, !current_visibility)
    
    Map.put(layout, :panel_visibility, new_visibility)
  end

  @doc """
  Change layout mode.
  """
  @spec change_layout_mode(t(), layout_mode()) :: t()
  def change_layout_mode(layout, new_mode) do
    # Recalculate layout for new mode
    {width, height} = layout.terminal_size
    {:ok, new_layout_spec} = create_layout_for_mode(width, height, new_mode)
    
    # Update panel visibilities based on mode
    new_visibility = get_visibility_for_mode(new_mode)
    
    layout
    |> Map.put(:layout_mode, new_mode)
    |> Map.put(:layout_spec, new_layout_spec)
    |> Map.put(:panel_visibility, new_visibility)
    |> handle_resize(width, height) # Resize panels for new layout
  end

  @doc """
  Render all visible panels.
  """
  @spec render(t()) :: {:ok, map()} | {:error, term()}
  def render(layout) do
    # Prepare panel data for rendering
    panels_data = %{
      chat_history: prepare_panel_data(:chat_history, layout),
      input: prepare_panel_data(:input, layout),
      status: prepare_panel_data(:status, layout),
      context: prepare_panel_data(:context, layout)
    }
    
    # Render through NIF
    case LibvaxisNif.render_panels(layout.layout_spec, panels_data, layout.focused_panel) do
      :ok -> {:ok, get_layout_state(layout)}
      error -> error
    end
  end

  @doc """
  Get current layout state.
  """
  @spec get_layout_state(t()) :: map()
  def get_layout_state(layout) do
    %{
      terminal_size: layout.terminal_size,
      focused_panel: layout.focused_panel,
      layout_mode: layout.layout_mode,
      panel_visibility: layout.panel_visibility,
      panel_states: %{
        chat_history: get_panel_state(:chat_history, layout),
        input: get_panel_state(:input, layout),
        status: get_panel_state(:status, layout),
        context: get_panel_state(:context, layout)
      }
    }
  end

  @doc """
  Update a specific panel.
  """
  @spec update_panel(t(), panel_id(), (struct() -> struct())) :: t()
  def update_panel(layout, panel_id, update_func) do
    current_panel = Map.get(layout.panels, panel_id)
    updated_panel = update_func.(current_panel)
    put_in(layout, [:panels, panel_id], updated_panel)
  end

  # Private functions

  defp update_panels_map(panels, panel_id, update_func) when is_map(panels) do
    current_panel = Map.get(panels, panel_id)
    updated_panel = update_func.(current_panel)
    Map.put(panels, panel_id, updated_panel)
  end

  defp get_panel_width(layout_spec, panel_key) do
    case Map.get(layout_spec, panel_key) do
      %{width: width} -> width
      _ -> 80 # Default width
    end
  end

  defp get_panel_height(layout_spec, panel_key) do
    case Map.get(layout_spec, panel_key) do
      %{height: height} -> height
      _ -> 20 # Default height
    end
  end

  defp get_visible_panels(layout) do
    layout.panel_visibility
    |> Enum.filter(fn {_panel, visible} -> visible end)
    |> Enum.map(fn {panel, _} -> panel end)
    |> Enum.sort()
  end

  defp create_layout_for_mode(width, height, mode) do
    # For now, use the same layout for all modes
    # In full implementation, different modes would have different layouts
    _ = mode
    LibvaxisNif.create_layout(width, height)
  end

  defp get_visibility_for_mode(:chat_focus) do
    %{chat_history: true, input: true, status: true, context: false}
  end
  defp get_visibility_for_mode(:code_focus) do
    %{chat_history: false, input: true, status: true, context: true}
  end
  defp get_visibility_for_mode(:full_screen) do
    %{chat_history: true, input: false, status: false, context: false}
  end
  defp get_visibility_for_mode(_default) do
    %{chat_history: true, input: true, status: true, context: true}
  end

  defp prepare_panel_data(panel_id, layout) do
    panel = Map.get(layout.panels, panel_id)
    visible = Map.get(layout.panel_visibility, panel_id, true)
    
    if visible do
      %{
        content: panel.__struct__.render(panel),
        focused: layout.focused_panel == panel_id,
        state: panel.__struct__.get_state(panel)
      }
    else
      %{content: [], focused: false, state: %{}}
    end
  end

  defp get_panel_state(panel_id, layout) do
    panel = Map.get(layout.panels, panel_id)
    panel.__struct__.get_state(panel)
  end
end