defmodule Aiex.Telemetry.StructuredLogger do
  @moduledoc """
  Distributed structured logging with correlation IDs and OpenTelemetry integration.
  
  Provides consistent structured logging across the cluster with automatic correlation
  ID propagation and distributed trace integration.
  """
  
  @behaviour :gen_event
  require Logger
  
  alias Aiex.Telemetry.DistributedAggregator
  
  @default_fields [:timestamp, :level, :message, :node, :pid, :module, :function, :line]
  @correlation_key :aiex_correlation_id
  @trace_key :aiex_trace_id
  @span_key :aiex_span_id
  
  defstruct [
    :output_format,
    :correlation_enabled,
    :trace_enabled,
    :metrics_enabled,
    :fields,
    :filters
  ]
  
  # Client API
  
  @doc "Start structured logging with the given configuration"
  def start_logging(opts \\ []) do
    config = %__MODULE__{
      output_format: Keyword.get(opts, :output_format, :json),
      correlation_enabled: Keyword.get(opts, :correlation_enabled, true),
      trace_enabled: Keyword.get(opts, :trace_enabled, true),
      metrics_enabled: Keyword.get(opts, :metrics_enabled, true),
      fields: Keyword.get(opts, :fields, @default_fields),
      filters: Keyword.get(opts, :filters, [])
    }
    
    :logger.add_handler(:aiex_structured_logger, __MODULE__, config)
  end
  
  @doc "Stop structured logging"
  def stop_logging do
    :logger.remove_handler(:aiex_structured_logger)
  end
  
  @doc "Set correlation ID for current process"
  def set_correlation_id(correlation_id) do
    Process.put(@correlation_key, correlation_id)
  end
  
  @doc "Get correlation ID for current process"
  def get_correlation_id do
    Process.get(@correlation_key)
  end
  
  @doc "Generate a new correlation ID"
  def generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  @doc "Set trace context for current process"
  def set_trace_context(trace_id, span_id) do
    Process.put(@trace_key, trace_id)
    Process.put(@span_key, span_id)
  end
  
  @doc "Get trace context for current process"
  def get_trace_context do
    {Process.get(@trace_key), Process.get(@span_key)}
  end
  
  @doc "Log with automatic correlation and trace context"
  def log_with_context(level, message, metadata \\ []) do
    enhanced_metadata = enhance_metadata(metadata)
    Logger.log(level, message, enhanced_metadata)
  end
  
  @doc "Log an event with structured data"
  def log_event(event_name, data \\ %{}, metadata \\ []) do
    enhanced_metadata = metadata
    |> Keyword.put(:event_name, event_name)
    |> Keyword.put(:event_data, data)
    |> enhance_metadata()
    
    Logger.info("Event: #{event_name}", enhanced_metadata)
  end
  
  @doc "Log a metric with automatic aggregation"
  def log_metric(key, value, metadata \\ []) do
    enhanced_metadata = enhance_metadata(metadata)
    
    # Record in distributed aggregator if enabled
    if Application.get_env(:aiex, :telemetry, [])[:metrics_enabled] do
      DistributedAggregator.record_metric(key, value, Map.new(enhanced_metadata))
    end
    
    Logger.debug("Metric: #{key}=#{value}", enhanced_metadata)
  end
  
  # Logger handler callbacks
  
  @impl true
  def log(log_event, config) do
    case should_log?(log_event, config) do
      true ->
        formatted = format_log_event(log_event, config)
        IO.puts(formatted)
        
        # Record logging metrics if enabled
        if config.metrics_enabled do
          record_logging_metrics(log_event)
        end
        
      false ->
        :ok
    end
  end
  
  @impl true
  def adding_handler(config) do
    {:ok, config}
  end
  
  @impl true
  def removing_handler(_config) do
    :ok
  end
  
  @impl true
  def changing_config(_old_config, new_config) do
    {:ok, new_config}
  end
  
  # Private functions
  
  defp enhance_metadata(metadata) do
    base_metadata = [
      correlation_id: get_correlation_id(),
      node: Node.self(),
      timestamp: System.system_time(:microsecond)
    ]
    
    trace_metadata = case get_trace_context() do
      {nil, nil} -> []
      {trace_id, span_id} -> [trace_id: trace_id, span_id: span_id]
    end
    
    Keyword.merge(base_metadata ++ trace_metadata, metadata)
  end
  
  defp should_log?(log_event, config) do
    # Apply filters
    Enum.all?(config.filters, fn filter ->
      apply_filter(filter, log_event)
    end)
  end
  
  defp apply_filter({:level, min_level}, log_event) do
    Logger.compare_levels(log_event.level, min_level) != :lt
  end
  
  defp apply_filter({:module, module_pattern}, log_event) do
    case log_event.meta[:mfa] do
      {module, _, _} -> String.contains?(to_string(module), to_string(module_pattern))
      _ -> true
    end
  end
  
  defp apply_filter(_filter, _log_event), do: true
  
  defp format_log_event(log_event, config) do
    case config.output_format do
      :json -> format_json(log_event, config)
      :logfmt -> format_logfmt(log_event, config)
      :human -> format_human(log_event, config)
    end
  end
  
  defp format_json(log_event, config) do
    fields = extract_fields(log_event, config.fields)
    Jason.encode!(fields)
  end
  
  defp format_logfmt(log_event, config) do
    fields = extract_fields(log_event, config.fields)
    
    fields
    |> Enum.map(fn {key, value} -> "#{key}=#{format_value(value)}" end)
    |> Enum.join(" ")
  end
  
  defp format_human(log_event, config) do
    fields = extract_fields(log_event, config.fields)
    
    timestamp = fields[:timestamp] |> format_timestamp()
    level = fields[:level] |> String.upcase() |> String.pad_trailing(5)
    message = fields[:message]
    correlation_id = fields[:correlation_id]
    
    base = "#{timestamp} [#{level}] #{message}"
    
    if correlation_id do
      "#{base} (correlation_id=#{correlation_id})"
    else
      base
    end
  end
  
  defp extract_fields(log_event, field_list) do
    base_fields = %{
      timestamp: log_event.meta[:time],
      level: log_event.level,
      message: to_string(log_event.msg),
      node: Node.self(),
      pid: inspect(log_event.meta[:pid])
    }
    
    # Add MFA info if available
    mfa_fields = case log_event.meta[:mfa] do
      {module, function, arity} ->
        %{
          module: module,
          function: "#{function}/#{arity}",
          line: log_event.meta[:line]
        }
      _ -> %{}
    end
    
    # Add correlation and trace info
    process_fields = %{
      correlation_id: Process.get(@correlation_key),
      trace_id: Process.get(@trace_key),
      span_id: Process.get(@span_key)
    }
    
    # Merge all fields and filter by requested fields
    all_fields = Map.merge(base_fields, Map.merge(mfa_fields, process_fields))
    
    field_list
    |> Enum.map(fn field -> {field, Map.get(all_fields, field)} end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end
  
  defp format_value(value) when is_binary(value) do
    if String.contains?(value, " ") do
      "\"#{value}\""
    else
      value
    end
  end
  
  defp format_value(value), do: inspect(value)
  
  defp format_timestamp(timestamp) when is_integer(timestamp) do
    timestamp
    |> DateTime.from_unix!(:native)
    |> DateTime.to_iso8601()
  end
  
  defp format_timestamp(_), do: DateTime.utc_now() |> DateTime.to_iso8601()
  
  defp record_logging_metrics(log_event) do
    try do
      DistributedAggregator.record_metric(
        "logs.#{log_event.level}",
        1,
        %{node: Node.self()}
      )
    rescue
      _ -> :ok  # Ignore if aggregator is not available
    end
  end
end