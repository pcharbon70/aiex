defmodule Aiex.CLI.Commands.AI.ProgressReporter do
  @moduledoc """
  Progress reporting system for long-running AI operations.
  
  Provides visual feedback including spinners, progress bars, timers,
  and status updates for AI workflows and pipeline executions.
  """
  
  use GenServer
  require Logger
  
  # Spinner animation frames
  @spinner_frames ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  @progress_chars ["█", "▉", "▊", "▋", "▌", "▍", "▎", "▏", " "]
  
  # Progress update intervals
  @spinner_interval 100  # milliseconds
  @status_update_interval 1000  # milliseconds
  
  @type progress_state :: %{
    message: String.t(),
    started_at: DateTime.t(),
    spinner_index: integer(),
    status: :running | :completed | :error | :paused,
    current_step: integer(),
    total_steps: integer(),
    substeps: map(),
    show_timer: boolean(),
    show_percentage: boolean(),
    custom_format: String.t() | nil
  }
  
  # Public API
  
  @doc """
  Start progress reporting with a message.
  
  ## Examples
  
      ProgressReporter.start("Analyzing code quality...")
      ProgressReporter.start("Processing 5 files...", total_steps: 5)
  """
  def start(message, opts \\ []) do
    total_steps = Keyword.get(opts, :total_steps, 0)
    show_timer = Keyword.get(opts, :show_timer, true)
    show_percentage = Keyword.get(opts, :show_percentage, total_steps > 0)
    custom_format = Keyword.get(opts, :format)
    
    case GenServer.start_link(__MODULE__, %{
      message: message,
      started_at: DateTime.utc_now(),
      spinner_index: 0,
      status: :running,
      current_step: 0,
      total_steps: total_steps,
      substeps: %{},
      show_timer: show_timer,
      show_percentage: show_percentage,
      custom_format: custom_format
    }, name: __MODULE__) do
      {:ok, pid} -> 
        schedule_update()
        pid
      {:error, {:already_started, pid}} -> 
        GenServer.call(pid, {:restart, message, opts})
        pid
    end
  end
  
  @doc """
  Update progress with a new message and optionally current step.
  
  ## Examples
  
      ProgressReporter.update("Processing file 3/5...")
      ProgressReporter.update("Refactoring code...", step: 2)
  """
  def update(message, opts \\ []) do
    if GenServer.whereis(__MODULE__) do
      step = Keyword.get(opts, :step)
      substep = Keyword.get(opts, :substep)
      
      GenServer.cast(__MODULE__, {:update, message, step, substep})
    end
  end
  
  @doc """
  Update the current step number for progress tracking.
  """
  def step(current_step) when is_integer(current_step) do
    if GenServer.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:set_step, current_step})
    end
  end
  
  @doc """
  Add or update a substep for detailed progress tracking.
  
  ## Examples
  
      ProgressReporter.substep("parsing", "Parsing AST...", 0.7)
      ProgressReporter.substep("analysis", "Running analysis...", 0.3)
  """
  def substep(key, message, progress \\ nil) do
    if GenServer.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:substep, key, message, progress})
    end
  end
  
  @doc """
  Complete progress reporting with success message.
  """
  def complete(message \\ "Completed successfully!") do
    if GenServer.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:complete, message})
    end
  end
  
  @doc """
  Complete progress reporting with error message.
  """
  def error(message) do
    if GenServer.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:error, message})
    end
  end
  
  @doc """
  Pause progress reporting (stops spinner but keeps display).
  """
  def pause do
    if GenServer.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :pause)
    end
  end
  
  @doc """
  Resume progress reporting after pause.
  """
  def resume do
    if GenServer.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :resume)
    end
  end
  
  @doc """
  Stop progress reporting and clear display.
  """
  def stop do
    if GenServer.whereis(__MODULE__) do
      GenServer.stop(__MODULE__, :normal)
    end
  end
  
  @doc """
  Check if progress reporter is currently running.
  """
  def running? do
    case GenServer.whereis(__MODULE__) do
      nil -> false
      _pid -> true
    end
  end
  
  # GenServer callbacks
  
  @impl true
  def init(state) do
    # Hide cursor and start spinner
    IO.write("\e[?25l")
    render_progress(state)
    schedule_spinner_update()
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:restart, message, opts}, _from, _state) do
    total_steps = Keyword.get(opts, :total_steps, 0)
    show_timer = Keyword.get(opts, :show_timer, true) 
    show_percentage = Keyword.get(opts, :show_percentage, total_steps > 0)
    custom_format = Keyword.get(opts, :format)
    
    new_state = %{
      message: message,
      started_at: DateTime.utc_now(),
      spinner_index: 0,
      status: :running,
      current_step: 0,
      total_steps: total_steps,
      substeps: %{},
      show_timer: show_timer,
      show_percentage: show_percentage,
      custom_format: custom_format
    }
    
    render_progress(new_state)
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:complete, message}, _from, state) do
    final_state = %{state | status: :completed, message: message}
    render_final(final_state, "✅")
    cleanup()
    
    {:stop, :normal, :ok, final_state}
  end
  
  @impl true
  def handle_call({:error, message}, _from, state) do
    final_state = %{state | status: :error, message: message}
    render_final(final_state, "❌")
    cleanup()
    
    {:stop, :normal, :ok, final_state}
  end
  
  @impl true
  def handle_cast({:update, message, step, substep}, state) do
    new_state = %{state | message: message}
    new_state = if step, do: %{new_state | current_step: step}, else: new_state
    
    new_state = if substep do
      Map.put(new_state, :substeps, Map.put(state.substeps, :current, substep))
    else
      new_state
    end
    
    render_progress(new_state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:set_step, step}, state) do
    new_state = %{state | current_step: step}
    render_progress(new_state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:substep, key, message, progress}, state) do
    substep_data = %{message: message, progress: progress}
    new_substeps = Map.put(state.substeps, key, substep_data)
    new_state = %{state | substeps: new_substeps}
    
    render_progress(new_state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast(:pause, state) do
    new_state = %{state | status: :paused}
    render_progress(new_state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast(:resume, state) do
    new_state = %{state | status: :running}
    render_progress(new_state)
    schedule_spinner_update()
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:spinner_update, %{status: :running} = state) do
    new_index = rem(state.spinner_index + 1, length(@spinner_frames))
    new_state = %{state | spinner_index: new_index}
    
    render_progress(new_state)
    schedule_spinner_update()
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:spinner_update, state) do
    # Don't update spinner when paused or completed
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:status_update, state) do
    # Periodic status updates for long-running operations
    render_progress(state)
    schedule_status_update()
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, _state) do
    cleanup()
    :ok
  end
  
  # Private helper functions
  
  defp schedule_update do
    schedule_spinner_update()
    schedule_status_update()
  end
  
  defp schedule_spinner_update do
    Process.send_after(self(), :spinner_update, @spinner_interval)
  end
  
  defp schedule_status_update do
    Process.send_after(self(), :status_update, @status_update_interval)
  end
  
  defp render_progress(state) do
    # Clear current line and move to beginning
    IO.write("\r\e[K")
    
    case state.custom_format do
      nil -> render_default_progress(state)
      format -> render_custom_progress(state, format)
    end
  end
  
  defp render_default_progress(state) do
    spinner = get_spinner_char(state)
    timer = if state.show_timer, do: " #{format_elapsed_time(state.started_at)}", else: ""
    progress = format_progress_info(state)
    substeps = format_substeps(state.substeps)
    
    output = "#{spinner} #{state.message}#{progress}#{timer}#{substeps}"
    IO.write(output)
  end
  
  defp render_custom_progress(state, format) do
    # Allow custom formatting with placeholders
    output = format
    |> String.replace("%spinner%", get_spinner_char(state))
    |> String.replace("%message%", state.message)
    |> String.replace("%timer%", format_elapsed_time(state.started_at))
    |> String.replace("%progress%", format_progress_info(state))
    |> String.replace("%percentage%", format_percentage(state))
    
    IO.write(output)
  end
  
  defp render_final(state, icon) do
    IO.write("\r\e[K")
    
    timer = if state.show_timer, do: " (#{format_elapsed_time(state.started_at)})", else: ""
    progress = if state.show_percentage and state.total_steps > 0, do: " (#{state.total_steps}/#{state.total_steps})", else: ""
    
    output = "#{icon} #{state.message}#{progress}#{timer}\n"
    IO.write(output)
  end
  
  defp get_spinner_char(%{status: :running, spinner_index: index}) do
    Enum.at(@spinner_frames, index)
  end
  defp get_spinner_char(%{status: :paused}), do: "⏸"
  defp get_spinner_char(_), do: "●"
  
  defp format_progress_info(%{show_percentage: false}), do: ""
  defp format_progress_info(%{total_steps: 0}), do: ""
  defp format_progress_info(state) do
    percentage = format_percentage(state)
    step_info = "(#{state.current_step}/#{state.total_steps})"
    " #{percentage} #{step_info}"
  end
  
  defp format_percentage(%{total_steps: 0}), do: ""
  defp format_percentage(%{current_step: current, total_steps: total}) do
    percentage = if total > 0, do: round(current / total * 100), else: 0
    "#{percentage}%"
  end
  
  defp format_substeps(substeps) when map_size(substeps) == 0, do: ""
  defp format_substeps(substeps) do
    active_substeps = substeps
    |> Enum.filter(fn {_key, %{progress: progress}} -> progress && progress > 0 end)
    |> Enum.take(3)  # Show max 3 substeps
    
    if length(active_substeps) > 0 do
      substep_text = active_substeps
      |> Enum.map(fn {_key, %{message: msg, progress: prog}} ->
        "#{msg} (#{round(prog * 100)}%)"
      end)
      |> Enum.join(", ")
      
      "\n  └── #{substep_text}"
    else
      ""
    end
  end
  
  defp format_elapsed_time(started_at) do
    elapsed_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
    
    cond do
      elapsed_ms < 1000 -> "#{elapsed_ms}ms"
      elapsed_ms < 60_000 -> "#{Float.round(elapsed_ms / 1000, 1)}s"
      elapsed_ms < 3_600_000 -> 
        minutes = div(elapsed_ms, 60_000)
        seconds = div(rem(elapsed_ms, 60_000), 1000)
        "#{minutes}m #{seconds}s"
      true ->
        hours = div(elapsed_ms, 3_600_000)
        minutes = div(rem(elapsed_ms, 3_600_000), 60_000)
        "#{hours}h #{minutes}m"
    end
  end
  
  defp cleanup do
    # Show cursor and move to new line
    IO.write("\e[?25h")
  end
  
  # Convenience functions for common progress patterns
  
  @doc """
  Progress reporter for file processing operations.
  
  ## Examples
  
      ProgressReporter.start_file_processing(["file1.ex", "file2.ex", "file3.ex"])
      ProgressReporter.update_file_processing("file2.ex", 2)
  """
  def start_file_processing(files) when is_list(files) do
    count = length(files)
    start("Processing #{count} files...", total_steps: count, show_percentage: true)
  end
  
  def update_file_processing(filename, current_index) do
    update("Processing #{Path.basename(filename)}...", step: current_index)
  end
  
  @doc """
  Progress reporter for AI analysis operations.
  """
  def start_analysis(analysis_type, target) do
    start("Running #{analysis_type} analysis on #{target}...", show_timer: true)
  end
  
  def update_analysis(stage, details \\ nil) do
    message = if details, do: "#{stage}: #{details}", else: stage
    update(message)
  end
  
  @doc """
  Progress reporter for code generation operations.
  """
  def start_generation(generation_type) do
    start("Generating #{generation_type}...", show_timer: true)
    
    # Add typical generation substeps
    substep("planning", "Planning structure...", 0.1)
    substep("generation", "Generating code...", 0.0)
    substep("validation", "Validating output...", 0.0)
  end
  
  def update_generation_stage(stage, progress) do
    case stage do
      :planning -> substep("planning", "Planning complete", 1.0)
      :generation -> substep("generation", "Generating code...", progress)
      :validation -> substep("validation", "Validating output...", progress)
      :complete -> substep("validation", "Validation complete", 1.0)
    end
  end
  
  @doc """
  Progress reporter for pipeline operations.
  """
  def start_pipeline(step_count, mode) do
    start("Executing #{step_count}-step AI pipeline (#{mode} mode)...", 
          total_steps: step_count, show_percentage: true)
  end
  
  def update_pipeline_step(step_name, step_number, total_steps) do
    update("Step #{step_number}/#{total_steps}: #{step_name}", step: step_number)
  end
end