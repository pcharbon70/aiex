defmodule Aiex.TUI.View do
  @moduledoc """
  View rendering stub for the Aiex TUI application.
  
  This module provides a placeholder implementation when Ratatouille is not available.
  The actual TUI functionality is provided by Ratatouille when it's properly installed.
  """
  
  alias Aiex.TUI.State
  
  @doc """
  Main render function for the TUI application.
  Falls back to mock rendering when Ratatouille is not available.
  """
  def render(state) do
    # Return a simple representation when Ratatouille is not available
    %{
      type: :mock_view,
      state: state,
      layout: state.layout_mode,
      messages: state.messages,
      message: "Ratatouille TUI not available - using mock view"
    }
  end
  
  # Placeholder functions to maintain compatibility
  def view(_opts, _content), do: %{type: :mock_view}
  def row(_opts \\ [], _content), do: %{type: :mock_row}
  def column(_opts, _content), do: %{type: :mock_column}
  def panel(_opts, _content), do: %{type: :mock_panel}
  def text(_opts), do: %{type: :mock_text}
  def label(_opts), do: %{type: :mock_label}
  def bar(_content), do: %{type: :mock_bar}
  def viewport(_opts, _content), do: %{type: :mock_viewport}
  def text_input(_opts), do: %{type: :mock_text_input}
end