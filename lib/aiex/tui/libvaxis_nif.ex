defmodule Aiex.Tui.LibvaxisNif do
  @moduledoc """
  Native Implemented Functions (NIFs) for Libvaxis terminal UI integration.
  
  This module provides the Zig/Libvaxis bridge for terminal user interface
  functionality, integrated directly into the BEAM VM via Zigler NIFs.
  """
  
  # Disabled temporarily due to missing Libvaxis dependency
  # use Zig, 
  #   otp_app: :aiex,
  #   resources: [:VaxisInstance],
  #   nifs: [
  #     init_vaxis: [:dirty_io],
  #     cleanup_vaxis: [:dirty_io],
  #     start_event_loop: [:dirty_io],
  #     render_chat_layout: [:dirty_io],
  #     handle_input: [:dirty_io],
  #     get_terminal_size: [:dirty_io]
  #   ]

  # Zig code disabled until Libvaxis is available
  # ~Z"""
  # // Code will be enabled when Libvaxis dependency is available
  # """
  
  # Elixir API functions
  
  @doc """
  Initialize the Vaxis terminal interface.
  
  Returns `{:ok, resource}` on success or `{:error, reason}` on failure.
  """
  @spec init() :: {:ok, term()} | {:error, term()}
  def init do
    case init_vaxis(self()) do
      {:error, _} = error -> error
      resource -> {:ok, resource}
    end
  end
  
  @doc """
  Start the event loop for handling terminal events.
  """
  @spec start_event_loop(term()) :: :ok | {:error, term()}
  def start_event_loop(resource) do
    case start_event_loop_nif(resource) do
      :ok -> :ok
      error -> {:error, error}
    end
  end
  
  @doc """
  Render the chat layout with messages, input, and status.
  """
  @spec render(term(), list(), String.t(), map()) :: :ok | {:error, term()}
  def render(resource, messages, input, status) do
    case render_chat_layout(resource, messages, input, status) do
      :ok -> :ok
      error -> {:error, error}
    end
  end
  
  @doc """
  Get the current terminal size.
  """
  @spec terminal_size(term()) :: {:ok, {width :: integer(), height :: integer()}} | {:error, term()}
  def terminal_size(resource) do
    get_terminal_size(resource)
  end
  
  # NIF stubs (temporarily disabled - use LibvaxisNifMinimal instead)
  defp init_vaxis(_pid), do: {:error, :libvaxis_not_available}
  defp start_event_loop_nif(_resource), do: {:error, :libvaxis_not_available}
  defp render_chat_layout(_resource, _messages, _input, _status), do: {:error, :libvaxis_not_available}
  defp handle_input(_resource, _key_event), do: {:error, :libvaxis_not_available}
  defp get_terminal_size(_resource), do: {:error, :libvaxis_not_available}
end