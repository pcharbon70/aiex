defmodule Aiex.CLI.Commands.AI.ProgressReporter do
  @moduledoc """
  Progress reporting for long-running AI operations in the CLI.
  
  Provides visual feedback for AI tasks including status updates,
  completion notifications, and error reporting.
  """

  use GenServer
  
  @spinner_frames ["|", "/", "-", "\\"]
  @update_interval 100

  # Client API

  @doc """
  Starts progress reporting for a task.
  """
  def start(message, opts \\ []) do
    case GenServer.start_link(__MODULE__, {message, opts}, name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> 
        GenServer.call(__MODULE__, {:update, message, opts})
        :ok
      error -> error
    end
  end

  @doc """
  Updates the progress message.
  """
  def update(message, opts \\ []) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:update, message, opts})
    else
      :ok
    end
  end

  @doc """
  Completes progress reporting with success message.
  """
  def complete(message \\ "Done!") do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:complete, message})
      GenServer.stop(__MODULE__)
    end
    :ok
  end

  @doc """
  Reports an error and stops progress reporting.
  """
  def error(message) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:error, message})
      GenServer.stop(__MODULE__)
    end
    :ok
  end

  # Server implementation

  @impl true
  def init({message, opts}) do
    schedule_update()
    
    state = %{
      message: message,
      opts: opts,
      spinner_index: 0,
      started_at: System.monotonic_time(:millisecond)
    }
    
    display_progress(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:update, message, opts}, _from, state) do
    new_state = %{state | message: message, opts: Keyword.merge(state.opts, opts)}
    display_progress(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:complete, message}, _from, state) do
    IO.write("\r\e[K")  # Clear line
    IO.puts("✅ #{message}")
    {:reply, :ok, state}
  end

  def handle_call({:error, message}, _from, state) do
    IO.write("\r\e[K")  # Clear line
    IO.puts("❌ #{message}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:update_progress, state) do
    new_index = rem(state.spinner_index + 1, length(@spinner_frames))
    new_state = %{state | spinner_index: new_index}
    
    display_progress(new_state)
    schedule_update()
    
    {:noreply, new_state}
  end

  # Private functions

  defp schedule_update do
    Process.send_after(self(), :update_progress, @update_interval)
  end

  defp display_progress(state) do
    spinner = Enum.at(@spinner_frames, state.spinner_index)
    elapsed = System.monotonic_time(:millisecond) - state.started_at
    time_str = format_elapsed_time(elapsed)
    
    progress_line = "#{spinner} #{state.message} (#{time_str})"
    
    IO.write("\r\e[K#{progress_line}")
  end

  defp format_elapsed_time(milliseconds) when milliseconds < 1000 do
    "#{milliseconds}ms"
  end
  
  defp format_elapsed_time(milliseconds) when milliseconds < 60_000 do
    seconds = div(milliseconds, 1000)
    "#{seconds}s"
  end
  
  defp format_elapsed_time(milliseconds) do
    minutes = div(milliseconds, 60_000)
    seconds = div(rem(milliseconds, 60_000), 1000)
    "#{minutes}m #{seconds}s"
  end

  # Pipeline-specific functions
  
  def start_pipeline(step_count, mode) do
    start("Executing #{step_count}-step AI pipeline (#{mode} mode)...")
  end
  
  def update_pipeline_step(step_name, step_number, total_steps) do
    update("Step #{step_number}/#{total_steps}: #{step_name}")
  end
end