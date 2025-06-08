defmodule Aiex.CLI.Commands.AI.ProgressReporter do
  @moduledoc """
  Progress reporting for long-running AI operations in the CLI.
  
  Provides visual feedback for AI tasks including status updates,
  completion notifications, and error reporting.
  """

  use GenServer
  
  @spinner_frames ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  @update_interval 100

  # Client API

  @doc """
  Start progress reporting with an initial message.
  """
  def start(message) do
    case GenServer.start_link(__MODULE__, {message, :running}, name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} ->
        # Update existing reporter
        update(message)
    end
  end

  @doc """
  Update the progress message.
  """
  def update(message) do
    GenServer.cast(__MODULE__, {:update, message})
  end

  @doc """
  Complete the progress reporting with success message.
  """
  def complete(message) do
    GenServer.cast(__MODULE__, {:complete, message})
  end

  @doc """
  Complete the progress reporting with error message.
  """
  def error(message) do
    GenServer.cast(__MODULE__, {:error, message})
  end

  @doc """
  Stop progress reporting.
  """
  def stop do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.stop(__MODULE__)
    end
  end

  # Server Implementation

  @impl true
  def init({message, status}) do
    # Clear the current line and start fresh
    IO.write("\r\e[K")
    
    state = %{
      message: message,
      status: status,
      frame_index: 0,
      start_time: System.monotonic_time(:millisecond)
    }
    
    # Start the spinner timer
    schedule_update()
    
    {:ok, state}
  end

  @impl true
  def handle_cast({:update, message}, state) do
    new_state = %{state | message: message}
    render_progress(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:complete, message}, state) do
    # Clear the spinner line and show completion
    IO.write("\r\e[K")
    elapsed = System.monotonic_time(:millisecond) - state.start_time
    IO.puts("✅ #{message} (#{format_duration(elapsed)})")
    
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:error, message}, state) do
    # Clear the spinner line and show error
    IO.write("\r\e[K")
    elapsed = System.monotonic_time(:millisecond) - state.start_time
    IO.puts("❌ #{message} (#{format_duration(elapsed)})")
    
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:update_spinner, %{status: :running} = state) do
    new_frame_index = rem(state.frame_index + 1, length(@spinner_frames))
    new_state = %{state | frame_index: new_frame_index}
    
    render_progress(new_state)
    schedule_update()
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:update_spinner, state) do
    # Don't update spinner if not running
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    # Ensure we clear the line on termination
    IO.write("\r\e[K")
    :ok
  end

  # Private Functions

  defp render_progress(%{status: :running} = state) do
    spinner = Enum.at(@spinner_frames, state.frame_index)
    elapsed = System.monotonic_time(:millisecond) - state.start_time
    duration_str = format_duration(elapsed)
    
    # Format: [spinner] message (duration)
    progress_line = "#{spinner} #{state.message} (#{duration_str})"
    
    # Use carriage return to overwrite the current line
    IO.write("\r#{progress_line}")
  end

  defp render_progress(state) do
    # For non-running states, just show the message
    IO.write("\r#{state.message}")
  end

  defp schedule_update do
    Process.send_after(self(), :update_spinner, @update_interval)
  end

  defp format_duration(milliseconds) do
    cond do
      milliseconds < 1000 ->
        "#{milliseconds}ms"
      
      milliseconds < 60_000 ->
        seconds = div(milliseconds, 1000)
        "#{seconds}s"
      
      true ->
        minutes = div(milliseconds, 60_000)
        seconds = div(rem(milliseconds, 60_000), 1000)
        "#{minutes}m #{seconds}s"
    end
  end
end