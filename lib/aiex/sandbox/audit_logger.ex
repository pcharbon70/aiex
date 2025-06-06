defmodule Aiex.Sandbox.AuditLogger do
  @moduledoc """
  Provides audit logging for all sandbox file operations.

  Logs access attempts, operation results, and security events with
  configurable verbosity levels.
  """

  use GenServer
  require Logger

  @log_file_name "aiex_sandbox_audit.log"
  # 10MB
  @max_log_size 10_485_760
  @max_log_files 5

  @type audit_event :: %{
          timestamp: DateTime.t(),
          operation: atom(),
          path: String.t() | {String.t(), String.t()},
          result: atom() | {atom(), any()},
          user: String.t() | nil,
          pid: pid(),
          metadata: map()
        }

  # Client API

  @doc """
  Starts the audit logger.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Logs an access attempt.
  """
  @spec log_access_attempt(String.t(), atom(), atom() | {atom(), any()}, Aiex.Sandbox.Config.t()) ::
          :ok
  def log_access_attempt(path, operation, result, config) do
    if should_log?(:access_attempt, config) do
      event = build_event(path, operation, result, %{type: :access_attempt})
      GenServer.cast(__MODULE__, {:log, event, config})
    end

    :ok
  end

  @doc """
  Logs an operation result.
  """
  @spec log_operation_result(
          String.t() | {String.t(), String.t()},
          atom(),
          atom() | {atom(), any()},
          Aiex.Sandbox.Config.t()
        ) :: :ok
  def log_operation_result(path, operation, result, config) do
    if should_log?(:operation_result, config) do
      event = build_event(path, operation, result, %{type: :operation_result})
      GenServer.cast(__MODULE__, {:log, event, config})
    end

    :ok
  end

  @doc """
  Logs a security event.
  """
  @spec log_security_event(String.t(), atom(), map()) :: :ok
  def log_security_event(path, event_type, details) do
    event = build_event(path, :security_event, event_type, details)
    GenServer.cast(__MODULE__, {:log_security, event})

    # Also log to system logger for security events
    Logger.warning("Security event: #{event_type} on path: #{path}", details)
    :ok
  end

  @doc """
  Gets recent audit entries.
  """
  @spec get_recent_entries(pos_integer()) :: [audit_event()]
  def get_recent_entries(count \\ 100) do
    GenServer.call(__MODULE__, {:get_recent, count})
  end

  @doc """
  Searches audit logs.
  """
  @spec search(keyword()) :: [audit_event()]
  def search(criteria) do
    GenServer.call(__MODULE__, {:search, criteria})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    log_dir = Keyword.get(opts, :log_dir, "priv/logs")
    File.mkdir_p!(log_dir)

    state = %{
      log_dir: log_dir,
      log_file: Path.join(log_dir, @log_file_name),
      current_size: 0,
      buffer: [],
      recent_entries: :queue.new(),
      max_recent: 1000
    }

    # Initialize log file
    initialize_log_file(state.log_file)

    # Schedule periodic flush
    schedule_flush()

    {:ok, state}
  end

  @impl true
  def handle_cast({:log, event, config}, state) do
    formatted = format_event(event, config.audit_level)
    new_state = buffer_event(formatted, event, state)

    # Flush immediately for security events
    if event.metadata[:type] == :security_event do
      {:noreply, flush_buffer(new_state)}
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:log_security, event}, state) do
    formatted = format_event(event, :verbose)
    new_state = buffer_event(formatted, event, state)
    {:noreply, flush_buffer(new_state)}
  end

  @impl true
  def handle_call({:get_recent, count}, _from, state) do
    recent =
      :queue.to_list(state.recent_entries)
      |> Enum.take(-count)

    {:reply, recent, state}
  end

  @impl true
  def handle_call({:search, criteria}, _from, state) do
    # Simple in-memory search of recent entries
    # For production, would integrate with log parsing or database
    results =
      :queue.to_list(state.recent_entries)
      |> Enum.filter(fn event ->
        matches_criteria?(event, criteria)
      end)

    {:reply, results, state}
  end

  @impl true
  def handle_info(:flush, state) do
    new_state = flush_buffer(state)
    schedule_flush()
    {:noreply, new_state}
  end

  # Private functions

  defp should_log?(event_type, config) do
    config.audit_enabled and
      case config.audit_level do
        :minimal -> event_type == :security_event
        :normal -> event_type in [:access_attempt, :security_event]
        :verbose -> true
      end
  end

  defp build_event(path, operation, result, metadata) do
    %{
      timestamp: DateTime.utc_now(),
      operation: operation,
      path: path,
      result: result,
      user: System.get_env("USER"),
      pid: self(),
      metadata: metadata
    }
  end

  defp format_event(event, level) do
    timestamp = DateTime.to_iso8601(event.timestamp)

    path_str =
      case event.path do
        {source, dest} -> "#{source} -> #{dest}"
        path -> path
      end

    base = "[#{timestamp}] #{event.operation} #{path_str} => #{inspect(event.result)}"

    case level do
      :minimal ->
        base

      :normal ->
        "#{base} (pid: #{inspect(event.pid)})"

      :verbose ->
        meta_str =
          event.metadata
          |> Map.drop([:type])
          |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
          |> Enum.join(", ")

        "#{base} (pid: #{inspect(event.pid)}, user: #{event.user || "unknown"}, #{meta_str})"
    end
  end

  defp buffer_event(formatted_event, raw_event, state) do
    # Add to buffer
    new_buffer = [formatted_event <> "\n" | state.buffer]

    # Add to recent entries queue
    new_recent = :queue.in(raw_event, state.recent_entries)

    new_recent =
      if :queue.len(new_recent) > state.max_recent do
        {_, queue} = :queue.out(new_recent)
        queue
      else
        new_recent
      end

    # Check if we should flush
    if length(new_buffer) >= 100 do
      flush_buffer(%{state | buffer: new_buffer, recent_entries: new_recent})
    else
      %{state | buffer: new_buffer, recent_entries: new_recent}
    end
  end

  defp flush_buffer(state) do
    if state.buffer != [] do
      content = state.buffer |> Enum.reverse() |> IO.iodata_to_binary()

      # Check if we need to rotate
      new_state =
        if state.current_size + byte_size(content) > @max_log_size do
          rotate_logs(state)
        else
          state
        end

      # Write to file
      File.write!(new_state.log_file, content, [:append])

      %{new_state | buffer: [], current_size: new_state.current_size + byte_size(content)}
    else
      state
    end
  end

  defp rotate_logs(state) do
    # Rotate existing logs
    for i <- (@max_log_files - 1)..1 do
      old_file = "#{state.log_file}.#{i}"
      new_file = "#{state.log_file}.#{i + 1}"

      if File.exists?(old_file) do
        if i + 1 <= @max_log_files do
          File.rename(old_file, new_file)
        else
          File.rm(old_file)
        end
      end
    end

    # Move current to .1
    if File.exists?(state.log_file) do
      File.rename(state.log_file, "#{state.log_file}.1")
    end

    # Create new file
    File.touch!(state.log_file)

    %{state | current_size: 0}
  end

  defp initialize_log_file(log_file) do
    if File.exists?(log_file) do
      {:ok, stat} = File.stat(log_file)
      stat.size
    else
      File.touch!(log_file)
      0
    end
  end

  defp schedule_flush do
    # Flush every 5 seconds
    Process.send_after(self(), :flush, 5_000)
  end

  defp matches_criteria?(event, criteria) do
    Enum.all?(criteria, fn
      {:operation, op} -> event.operation == op
      {:path, path} -> String.contains?(to_string(event.path), path)
      {:result, result} -> event.result == result
      {:after, datetime} -> DateTime.compare(event.timestamp, datetime) == :gt
      {:before, datetime} -> DateTime.compare(event.timestamp, datetime) == :lt
      _ -> true
    end)
  end
end
