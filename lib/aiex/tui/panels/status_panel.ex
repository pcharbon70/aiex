defmodule Aiex.Tui.Panels.StatusPanel do
  @moduledoc """
  Status Panel with real-time connection and AI provider information.
  
  This panel displays system status, connection information, current AI provider,
  model details, and other relevant real-time information about the system state.
  """

  @behaviour Aiex.Tui.Panels.PanelBehaviour

  defstruct [
    :connection_status,
    :ai_provider,
    :current_model,
    :session_info,
    :performance_metrics,
    :project_info,
    :layout_mode,
    :last_updated,
    :viewport_width,
    :show_detailed
  ]

  @type connection_status :: :connected | :disconnected | :connecting | :error
  @type t :: %__MODULE__{
    connection_status: connection_status(),
    ai_provider: String.t() | nil,
    current_model: String.t() | nil,
    session_info: map(),
    performance_metrics: map(),
    project_info: map(),
    layout_mode: :compact | :detailed,
    last_updated: DateTime.t(),
    viewport_width: integer(),
    show_detailed: boolean()
  }

  @doc """
  Initialize the status panel.
  """
  @spec init(map()) :: t()
  def init(opts \\ %{}) do
    %__MODULE__{
      connection_status: Map.get(opts, :connection_status, :disconnected),
      ai_provider: Map.get(opts, :ai_provider),
      current_model: Map.get(opts, :current_model),
      session_info: Map.get(opts, :session_info, %{}),
      performance_metrics: Map.get(opts, :performance_metrics, %{}),
      project_info: Map.get(opts, :project_info, %{}),
      layout_mode: Map.get(opts, :layout_mode, :compact),
      last_updated: DateTime.utc_now(),
      viewport_width: Map.get(opts, :width, 80),
      show_detailed: Map.get(opts, :show_detailed, false)
    }
  end

  @doc """
  Update connection status.
  """
  @spec update_connection_status(t(), connection_status()) :: t()
  def update_connection_status(panel, status) do
    panel
    |> Map.put(:connection_status, status)
    |> Map.put(:last_updated, DateTime.utc_now())
  end

  @doc """
  Update AI provider information.
  """
  @spec update_ai_provider(t(), String.t(), String.t()) :: t()
  def update_ai_provider(panel, provider, model) do
    panel
    |> Map.put(:ai_provider, provider)
    |> Map.put(:current_model, model)
    |> Map.put(:last_updated, DateTime.utc_now())
  end

  @doc """
  Update session information.
  """
  @spec update_session_info(t(), map()) :: t()
  def update_session_info(panel, session_info) do
    panel
    |> Map.put(:session_info, session_info)
    |> Map.put(:last_updated, DateTime.utc_now())
  end

  @doc """
  Update performance metrics.
  """
  @spec update_performance_metrics(t(), map()) :: t()
  def update_performance_metrics(panel, metrics) do
    panel
    |> Map.put(:performance_metrics, metrics)
    |> Map.put(:last_updated, DateTime.utc_now())
  end

  @doc """
  Update project information.
  """
  @spec update_project_info(t(), map()) :: t()
  def update_project_info(panel, project_info) do
    panel
    |> Map.put(:project_info, project_info)
    |> Map.put(:last_updated, DateTime.utc_now())
  end

  @doc """
  Toggle between compact and detailed layout modes.
  """
  @spec toggle_layout_mode(t()) :: t()
  def toggle_layout_mode(panel) do
    new_mode = if panel.layout_mode == :compact, do: :detailed, else: :compact
    Map.put(panel, :layout_mode, new_mode)
  end

  @doc """
  Toggle detailed information display.
  """
  @spec toggle_detailed(t()) :: t()
  def toggle_detailed(panel) do
    Map.put(panel, :show_detailed, !panel.show_detailed)
  end

  # PanelBehaviour implementation

  @impl true
  def resize(panel, width, _height) do
    Map.put(panel, :viewport_width, width)
  end

  @impl true
  def render(panel) do
    case panel.layout_mode do
      :compact -> render_compact(panel)
      :detailed -> render_detailed(panel)
    end
  end

  @impl true
  def get_state(panel) do
    %{
      connection_status: panel.connection_status,
      ai_provider: panel.ai_provider,
      current_model: panel.current_model,
      layout_mode: panel.layout_mode,
      last_updated: panel.last_updated,
      session_active: map_size(panel.session_info) > 0
    }
  end

  # Private functions

  defp render_compact(panel) do
    status_line = build_status_line(panel)
    info_line = build_info_line(panel)
    
    [status_line, info_line]
  end

  defp render_detailed(panel) do
    lines = [
      build_status_line(panel),
      build_info_line(panel)
    ]
    
    lines = if panel.show_detailed do
      lines ++ build_detailed_lines(panel)
    else
      lines
    end
    
    lines
  end

  defp build_status_line(panel) do
    status_indicator = get_status_indicator(panel.connection_status)
    provider_info = format_provider_info(panel.ai_provider, panel.current_model)
    project_name = get_project_name(panel.project_info)
    
    left_part = "#{status_indicator} #{provider_info}"
    right_part = "Project: #{project_name}"
    
    build_justified_line(left_part, right_part, panel.viewport_width)
  end

  defp build_info_line(panel) do
    session_info = format_session_info(panel.session_info)
    time_info = format_time_info(panel.last_updated)
    performance_info = format_performance_info(panel.performance_metrics)
    
    parts = [session_info, performance_info, time_info]
    |> Enum.reject(&(&1 == ""))
    
    case parts do
      [] -> ""
      [single] -> single
      multiple -> Enum.join(multiple, " | ")
    end
  end

  defp build_detailed_lines(panel) do
    lines = []
    
    # Add session details
    lines = if map_size(panel.session_info) > 0 do
      lines ++ format_session_details(panel.session_info)
    else
      lines
    end
    
    # Add performance details
    lines = if map_size(panel.performance_metrics) > 0 do
      lines ++ format_performance_details(panel.performance_metrics)
    else
      lines
    end
    
    # Add project details
    lines = if map_size(panel.project_info) > 0 do
      lines ++ format_project_details(panel.project_info)
    else
      lines
    end
    
    lines
  end

  defp get_status_indicator(:connected), do: "✅ Connected"
  defp get_status_indicator(:disconnected), do: "❌ Disconnected"
  defp get_status_indicator(:connecting), do: "🔄 Connecting"
  defp get_status_indicator(:error), do: "⚠️ Error"

  defp format_provider_info(nil, _), do: "No Provider"
  defp format_provider_info(provider, nil), do: provider
  defp format_provider_info(provider, model) do
    short_model = 
      model
      |> String.split("/")
      |> List.last()
      |> String.slice(0, 15)
    
    "#{provider}/#{short_model}"
  end

  defp get_project_name(%{name: name}), do: name
  defp get_project_name(%{root: root}) when is_binary(root), do: Path.basename(root)
  defp get_project_name(_), do: "Unknown"

  defp format_session_info(%{message_count: count}) when count > 0 do
    "#{count} messages"
  end
  defp format_session_info(%{active: true}), do: "Active session"
  defp format_session_info(_), do: ""

  defp format_time_info(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_performance_info(%{response_time: time}) when is_number(time) do
    "#{round(time)}ms"
  end
  defp format_performance_info(%{memory_usage: memory}) when is_number(memory) do
    "#{format_memory(memory)}"
  end
  defp format_performance_info(_), do: ""

  defp format_session_details(session_info) do
    details = []
    
    details = if Map.has_key?(session_info, :session_id) do
      ["Session: #{String.slice(session_info.session_id, 0, 8)}..."] ++ details
    else
      details
    end
    
    details = if Map.has_key?(session_info, :user_id) do
      ["User: #{session_info.user_id}"] ++ details
    else
      details
    end
    
    details = if Map.has_key?(session_info, :start_time) do
      duration = DateTime.diff(DateTime.utc_now(), session_info.start_time, :second)
      ["Duration: #{format_duration(duration)}"] ++ details
    else
      details
    end
    
    details
  end

  defp format_performance_details(metrics) do
    details = []
    
    details = if Map.has_key?(metrics, :total_requests) do
      ["Requests: #{metrics.total_requests}"] ++ details
    else
      details
    end
    
    details = if Map.has_key?(metrics, :avg_response_time) do
      ["Avg Response: #{round(metrics.avg_response_time)}ms"] ++ details
    else
      details
    end
    
    details = if Map.has_key?(metrics, :error_rate) do
      rate = Float.round(metrics.error_rate * 100, 1)
      ["Error Rate: #{rate}%"] ++ details
    else
      details
    end
    
    details
  end

  defp format_project_details(project_info) do
    details = []
    
    details = if Map.has_key?(project_info, :type) do
      ["Type: #{project_info.type}"] ++ details
    else
      details
    end
    
    details = if Map.has_key?(project_info, :version) do
      ["Version: #{project_info.version}"] ++ details
    else
      details
    end
    
    details = if Map.has_key?(project_info, :file_count) do
      ["Files: #{project_info.file_count}"] ++ details
    else
      details
    end
    
    details
  end

  defp build_justified_line(left, right, width) do
    left_length = String.length(left)
    right_length = String.length(right)
    
    if left_length + right_length >= width - 1 do
      # Not enough space, just show left part
      String.slice(left, 0, width)
    else
      # Add padding to justify
      padding = String.duplicate(" ", width - left_length - right_length)
      left <> padding <> right
    end
  end

  defp format_memory(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_memory(bytes) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 1)}KB"
  end
  defp format_memory(bytes) when bytes < 1024 * 1024 * 1024 do
    "#{Float.round(bytes / (1024 * 1024), 1)}MB"
  end
  defp format_memory(bytes) do
    "#{Float.round(bytes / (1024 * 1024 * 1024), 1)}GB"
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m#{secs}s"
  end
  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h#{minutes}m"
  end
end