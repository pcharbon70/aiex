defmodule AiexWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use AiexWeb, :controller` and
  `use AiexWeb, :live_view`.
  """
  use AiexWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders flash messages.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div class="fixed top-4 right-4 z-50 space-y-2">
      <div
        :for={{kind, message} <- @flash}
        class={
          [
            "rounded-lg px-6 py-4 shadow-lg backdrop-blur-sm border",
            if(kind == :info, do: "bg-blue-100/90 border-blue-200 text-blue-900"),
            if(kind == :error, do: "bg-red-100/90 border-red-200 text-red-900")
          ]
        }
      >
        <%= message %>
      </div>
    </div>
    """
  end
end