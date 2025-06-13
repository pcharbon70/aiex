defmodule Aiex.Tui.Panels.PanelBehaviour do
  @moduledoc """
  Behaviour defining the interface that all TUI panels must implement.
  
  This behaviour ensures consistent API across all panel types and provides
  the foundation for the hierarchical layout system and focus management.
  """

  @doc """
  Initialize the panel with given options.
  """
  @callback init(map()) :: struct()

  @doc """
  Resize the panel to new dimensions.
  """
  @callback resize(struct(), width :: integer(), height :: integer()) :: struct()

  @doc """
  Render the panel content for display.
  """
  @callback render(struct()) :: [String.t()]

  @doc """
  Get the current state for external consumers.
  """
  @callback get_state(struct()) :: map()

  @doc """
  Handle focus gained event (optional).
  """
  @callback handle_focus_gained(struct()) :: struct()

  @doc """
  Handle focus lost event (optional).
  """
  @callback handle_focus_lost(struct()) :: struct()

  @doc """
  Handle keyboard input when focused (optional).
  """
  @callback handle_input(struct(), term()) :: struct()

  @optional_callbacks [handle_focus_gained: 1, handle_focus_lost: 1, handle_input: 2]
end