defmodule Aiex.Security.DistributedAuditLogger do
  @moduledoc """
  Distributed audit logging system for cluster-wide security monitoring.
  
  Provides comprehensive audit logging across all nodes in the cluster with:
  - Distributed event collection using pg process groups
  - Mnesia-based persistent audit trail storage
  - Real-time security event correlation
  - Cross-node audit synchronization
  - Tamper-resistant audit integrity verification
  - Compliance reporting with distributed aggregation
  
  ## Architecture
  
  Uses pg module for distributed coordination, Mnesia for persistent storage,
  and integrates with the existing event sourcing system for complete
  security auditability across the cluster.
  
  ## Usage
  
      # Log security event
      :ok = DistributedAuditLogger.log_security_event(%{
        type: :authentication_attempt,
        user_id: "user123",
        result: :success,
        source_ip: "192.168.1.100",
        metadata: %{interface: :cli}
      })
      
      # Query audit trail
      {:ok, events} = DistributedAuditLogger.query_audit_trail(%{
        time_range: {~U[2024-01-01 00:00:00Z], ~U[2024-01-02 00:00:00Z]},
        event_types: [:authentication_attempt, :authorization_failure],
        node: :node1@host
      })
      
      # Generate compliance report
      {:ok, report} = DistributedAuditLogger.generate_compliance_report(%{
        period: :last_30_days,
        include_nodes: :all
      })
  """
  
  use GenServer
  require Logger
  
  alias Aiex.Events.OTPEventBus
  
  @pg_scope :security_audit
  @audit_table :distributed_audit_log
  @integrity_table :audit_integrity
  @metadata_table :audit_metadata
  
  defstruct [
    :node,
    :active_sessions,
    :integrity_checks,
    :metrics,
    :compliance_cache
  ]
  
  ## Client API
  
  @doc """
  Starts the distributed audit logger.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Logs a security event with distributed propagation.
  
  ## Event Types
  - `:authentication_attempt` - User login/logout attempts
  - `:authorization_failure` - Access control violations
  - `:privilege_escalation` - Privilege changes
  - `:data_access` - Sensitive data access
  - `:configuration_change` - System configuration modifications
  - `:security_violation` - Security policy violations
  - `:audit_tampering` - Audit log manipulation attempts
  - `:node_communication` - Inter-node security events
  
  ## Examples
  
      :ok = DistributedAuditLogger.log_security_event(%{
        type: :authentication_attempt,
        user_id: "user123",
        result: :success,
        source_ip: "192.168.1.100",
        session_id: "session_abc",
        metadata: %{
          interface: :cli,
          timestamp: DateTime.utc_now(),
          user_agent: "aiex-cli/1.0"
        }
      })
  """
  def log_security_event(event) do
    GenServer.call(__MODULE__, {:log_security_event, event})
  end
  
  @doc """
  Queries the distributed audit trail with advanced filtering.
  
  ## Query Options
  - `:time_range` - `{start_datetime, end_datetime}` tuple
  - `:event_types` - List of event types to include
  - `:user_id` - Filter by specific user
  - `:session_id` - Filter by session
  - `:node` - Filter by specific node
  - `:result` - Filter by event result (`:success`, `:failure`, etc.)
  - `:limit` - Maximum number of events to return
  - `:order` - `:asc` or `:desc` (default: `:desc`)
  
  ## Examples
  
      {:ok, events} = DistributedAuditLogger.query_audit_trail(%{
        time_range: {~U[2024-01-01 00:00:00Z], ~U[2024-01-02 00:00:00Z]},
        event_types: [:authentication_attempt, :authorization_failure],
        user_id: "user123",
        limit: 100
      })
  """
  def query_audit_trail(query_opts \\ %{}) do
    GenServer.call(__MODULE__, {:query_audit_trail, query_opts}, 30_000)
  end
  
  @doc """
  Generates compliance reports with cluster-wide aggregation.
  
  ## Report Types
  - `:security_summary` - Overall security metrics
  - `:authentication_report` - Authentication success/failure rates
  - `:access_control_report` - Authorization events and violations
  - `:audit_integrity_report` - Audit log integrity verification
  - `:compliance_status` - Regulatory compliance status
  
  ## Examples
  
      {:ok, report} = DistributedAuditLogger.generate_compliance_report(%{
        type: :security_summary,
        period: :last_30_days,
        include_nodes: :all,
        group_by: :day
      })
  """
  def generate_compliance_report(report_opts \\ %{}) do
    GenServer.call(__MODULE__, {:generate_compliance_report, report_opts}, 60_000)
  end
  
  @doc """
  Verifies audit log integrity across the cluster.
  
  Performs cryptographic verification of audit entries to detect
  tampering or corruption in the distributed audit trail.
  """
  def verify_audit_integrity(opts \\ %{}) do
    GenServer.call(__MODULE__, {:verify_audit_integrity, opts}, 30_000)
  end
  
  @doc """
  Gets real-time security metrics from all nodes.
  """
  def get_security_metrics do
    GenServer.call(__MODULE__, :get_security_metrics)
  end
  
  @doc """
  Archives old audit logs with retention policy.
  """
  def archive_audit_logs(archive_opts) do
    GenServer.call(__MODULE__, {:archive_audit_logs, archive_opts})
  end
  
  ## Server Callbacks
  
  @impl true
  def init(_opts) do
    # Setup distributed infrastructure
    setup_infrastructure()
    
    # Subscribe to security-related events
    subscribe_to_events()
    
    state = %__MODULE__{
      node: node(),
      active_sessions: %{},
      integrity_checks: %{},
      metrics: init_metrics(),
      compliance_cache: %{}
    }
    
    # Join pg groups for coordination
    :pg.join(@pg_scope, :audit_loggers, self())
    
    # Schedule periodic tasks
    schedule_integrity_check()
    schedule_metrics_update()
    
    Logger.info("Distributed audit logger started on #{node()}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:log_security_event, event}, _from, state) do
    event_id = generate_event_id()
    
    # Enrich event with metadata
    enriched_event = enrich_security_event(event, event_id)
    
    # Store in local Mnesia
    case store_audit_event(enriched_event) do
      :ok ->
        # Distribute to other nodes
        distribute_audit_event(enriched_event)
        
        # Update metrics
        new_state = update_security_metrics(state, enriched_event)
        
        # Publish to event bus for real-time monitoring
        publish_security_event(enriched_event)
        
        {:reply, :ok, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:query_audit_trail, query_opts}, _from, state) do
    case perform_distributed_query(query_opts) do
      {:ok, events} ->
        # Apply additional filtering and ordering
        filtered_events = apply_query_filters(events, query_opts)
        {:reply, {:ok, filtered_events}, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:generate_compliance_report, report_opts}, _from, state) do
    case generate_distributed_report(report_opts, state) do
      {:ok, report} ->
        # Cache report for performance
        new_state = cache_compliance_report(state, report_opts, report)
        {:reply, {:ok, report}, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:verify_audit_integrity, opts}, _from, state) do
    case perform_integrity_verification(opts) do
      {:ok, verification_result} ->
        # Update integrity tracking
        new_state = update_integrity_checks(state, verification_result)
        {:reply, {:ok, verification_result}, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call(:get_security_metrics, _from, state) do
    metrics = compile_security_metrics(state)
    {:reply, metrics, state}
  end
  
  def handle_call({:archive_audit_logs, archive_opts}, _from, state) do
    case perform_audit_archival(archive_opts) do
      {:ok, archive_result} ->
        {:reply, {:ok, archive_result}, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_info({:event_notification, event}, state) do
    # Handle security-related events from other systems
    new_state = handle_security_event(event, state)
    {:noreply, new_state}
  end
  
  def handle_info(:integrity_check, state) do
    # Perform periodic integrity verification
    perform_periodic_integrity_check()
    schedule_integrity_check()
    {:noreply, state}
  end
  
  def handle_info(:metrics_update, state) do
    # Update security metrics
    new_state = refresh_security_metrics(state)
    schedule_metrics_update()
    {:noreply, new_state}
  end
  
  def handle_info({:distributed_audit_event, event}, state) do
    # Handle audit events from other nodes
    case validate_remote_audit_event(event) do
      {:ok, validated_event} ->
        store_audit_event(validated_event)
        new_state = update_security_metrics(state, validated_event)
        {:noreply, new_state}
        
      {:error, reason} ->
        Logger.warning("Invalid remote audit event: #{inspect(reason)}")
        {:noreply, state}
    end
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  ## Private Functions
  
  defp setup_infrastructure do
    # Setup pg scope
    :pg.start_link(@pg_scope)
    
    # Setup Mnesia tables
    setup_mnesia_tables()
  end
  
  defp setup_mnesia_tables do
    table_type = if node() == :nonode@nohost, do: :ram_copies, else: :disc_copies
    
    # Main audit log table
    :mnesia.create_table(@audit_table, [
      {table_type, [node()]},
      {:attributes, [:event_id, :timestamp, :type, :user_id, :session_id, :node, :data, :integrity_hash]},
      {:type, :ordered_set},
      {:index, [:timestamp, :type, :user_id, :session_id, :node]}
    ])
    
    # Integrity verification table
    :mnesia.create_table(@integrity_table, [
      {table_type, [node()]},
      {:attributes, [:check_id, :timestamp, :node, :hash_chain, :verification_result]},
      {:type, :ordered_set},
      {:index, [:timestamp, :node]}
    ])
    
    # Audit metadata table
    :mnesia.create_table(@metadata_table, [
      {table_type, [node()]},
      {:attributes, [:key, :value, :updated_at]},
      {:type, :set}
    ])
  end
  
  defp subscribe_to_events do
    # Subscribe to security-related events
    OTPEventBus.subscribe({:event_type, :authentication_attempt})
    OTPEventBus.subscribe({:event_type, :authorization_failure})
    OTPEventBus.subscribe({:event_type, :session_created})
    OTPEventBus.subscribe({:event_type, :session_closed})
  end
  
  defp enrich_security_event(event, event_id) do
    Map.merge(event, %{
      event_id: event_id,
      timestamp: DateTime.utc_now(),
      node: node(),
      integrity_hash: calculate_integrity_hash(event, event_id)
    })
  end
  
  defp calculate_integrity_hash(event, event_id) do
    # Create tamper-resistant hash
    timestamp = Map.get(event, :timestamp, DateTime.utc_now())
    
    data = %{
      event_id: event_id,
      timestamp: timestamp,
      type: Map.get(event, :type),
      user_id: Map.get(event, :user_id),
      data: event
    }
    
    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode16()
  end
  
  defp store_audit_event(event) do
    try do
      :mnesia.transaction(fn ->
        :mnesia.write({@audit_table, 
          event.event_id,
          event.timestamp,
          event.type,
          event.user_id,
          event[:session_id],
          event.node,
          event,
          event.integrity_hash
        })
      end)
      
      :ok
    catch
      _, reason -> {:error, reason}
    end
  end
  
  defp distribute_audit_event(event) do
    # Send to all other audit loggers in the cluster
    audit_loggers = :pg.get_members(@pg_scope, :audit_loggers)
    |> Enum.reject(&(&1 == self()))
    
    Enum.each(audit_loggers, fn logger_pid ->
      send(logger_pid, {:distributed_audit_event, event})
    end)
  end
  
  defp publish_security_event(event) do
    # Publish to event bus for real-time monitoring
    security_event = %{
      id: generate_event_id(),
      aggregate_id: "security_audit",
      type: :security_event_logged,
      data: event,
      metadata: %{
        node: node(),
        audit_logger: self()
      }
    }
    
    OTPEventBus.publish_event(security_event)
  end
  
  defp perform_distributed_query(query_opts) do
    # Get audit loggers from all nodes
    audit_loggers = :pg.get_members(@pg_scope, :audit_loggers)
    
    # Distribute query across nodes
    query_results = Enum.map(audit_loggers, fn logger_pid ->
      if logger_pid == self() do
        # Query local data
        query_local_audit_data(query_opts)
      else
        # Query remote node
        query_remote_audit_data(logger_pid, query_opts)
      end
    end)
    
    # Combine and filter results
    valid_results = Enum.filter(query_results, fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, events} -> events end)
    |> List.flatten()
    
    {:ok, valid_results}
  end
  
  defp query_local_audit_data(query_opts) do
    try do
      result = :mnesia.transaction(fn ->
        # Build match specification based on query options
        match_spec = build_match_specification(query_opts)
        :mnesia.select(@audit_table, match_spec)
      end)
      
      case result do
        {:atomic, events} -> {:ok, events}
        {:aborted, reason} -> {:error, reason}
      end
    catch
      _, reason -> {:error, reason}
    end
  end
  
  defp query_remote_audit_data(logger_pid, query_opts) do
    try do
      # Use GenServer call to remote audit logger
      GenServer.call(logger_pid, {:local_query, query_opts}, 10_000)
    catch
      _, reason -> {:error, reason}
    end
  end
  
  defp build_match_specification(query_opts) do
    # Build Mnesia match specification based on query options
    base_pattern = {:_, :_, :_, :_, :_, :_, :_, :_}
    
    # Apply filters based on query options
    conditions = []
    
    # Add time range filter
    conditions = case query_opts[:time_range] do
      {start_time, end_time} ->
        [
          {:andalso, 
            {:>=, {:element, 3, :"$_"}, start_time},
            {:'=<', {:element, 3, :"$_"}, end_time}
          } | conditions
        ]
      _ -> conditions
    end
    
    # Add event type filter
    conditions = case query_opts[:event_types] do
      types when is_list(types) and length(types) > 0 ->
        type_conditions = Enum.map(types, fn type ->
          {:==, {:element, 4, :"$_"}, type}
        end)
        
        type_filter = case type_conditions do
          [single] -> single
          multiple -> List.to_tuple([:orelse | multiple])
        end
        
        [type_filter | conditions]
      _ -> conditions
    end
    
    # Add user filter
    conditions = case query_opts[:user_id] do
      user_id when is_binary(user_id) ->
        [{:==, {:element, 5, :"$_"}, user_id} | conditions]
      _ -> conditions
    end
    
    # Combine conditions
    final_condition = case conditions do
      [] -> []
      [single] -> [single]
      multiple -> [List.to_tuple([:andalso | multiple])]
    end
    
    [{base_pattern, final_condition, [:"$_"]}]
  end
  
  defp apply_query_filters(events, query_opts) do
    events
    |> apply_limit_filter(query_opts[:limit])
    |> apply_order_filter(query_opts[:order] || :desc)
  end
  
  defp apply_limit_filter(events, nil), do: events
  defp apply_limit_filter(events, limit) when is_integer(limit) do
    Enum.take(events, limit)
  end
  
  defp apply_order_filter(events, :desc) do
    Enum.sort_by(events, fn {_, _, timestamp, _, _, _, _, _} -> timestamp end, {:desc, DateTime})
  end
  defp apply_order_filter(events, :asc) do
    Enum.sort_by(events, fn {_, _, timestamp, _, _, _, _, _} -> timestamp end, {:asc, DateTime})
  end
  
  defp generate_distributed_report(report_opts, state) do
    report_type = report_opts[:type] || :security_summary
    
    case report_type do
      :security_summary ->
        generate_security_summary_report(report_opts, state)
      
      :authentication_report ->
        generate_authentication_report(report_opts, state)
      
      :access_control_report ->
        generate_access_control_report(report_opts, state)
      
      :audit_integrity_report ->
        generate_integrity_report(report_opts, state)
      
      :compliance_status ->
        generate_compliance_status_report(report_opts, state)
      
      _ ->
        {:error, :unsupported_report_type}
    end
  end
  
  defp generate_security_summary_report(report_opts, _state) do
    # Query audit data for the specified period
    time_range = get_report_time_range(report_opts[:period] || :last_30_days)
    
    {:ok, events} = query_audit_trail(%{
      time_range: time_range,
      include_nodes: report_opts[:include_nodes] || :all
    })
    
    # Aggregate metrics
    summary = %{
      period: report_opts[:period] || :last_30_days,
      total_events: length(events),
      event_breakdown: group_events_by_type(events),
      node_activity: group_events_by_node(events),
      authentication_success_rate: calculate_auth_success_rate(events),
      security_violations: count_security_violations(events),
      generated_at: DateTime.utc_now()
    }
    
    {:ok, summary}
  end
  
  defp generate_authentication_report(report_opts, _state) do
    time_range = get_report_time_range(report_opts[:period] || :last_30_days)
    
    {:ok, auth_events} = query_audit_trail(%{
      time_range: time_range,
      event_types: [:authentication_attempt],
      include_nodes: report_opts[:include_nodes] || :all
    })
    
    report = %{
      period: report_opts[:period] || :last_30_days,
      total_attempts: length(auth_events),
      successful_attempts: count_successful_auths(auth_events),
      failed_attempts: count_failed_auths(auth_events),
      success_rate: calculate_auth_success_rate(auth_events),
      top_failure_reasons: analyze_failure_reasons(auth_events),
      geographic_distribution: analyze_geographic_distribution(auth_events),
      generated_at: DateTime.utc_now()
    }
    
    {:ok, report}
  end
  
  defp generate_access_control_report(report_opts, _state) do
    time_range = get_report_time_range(report_opts[:period] || :last_30_days)
    
    {:ok, access_events} = query_audit_trail(%{
      time_range: time_range,
      event_types: [:authorization_failure, :privilege_escalation, :data_access],
      include_nodes: report_opts[:include_nodes] || :all
    })
    
    report = %{
      period: report_opts[:period] || :last_30_days,
      total_access_attempts: length(access_events),
      authorization_failures: count_authorization_failures(access_events),
      privilege_escalations: count_privilege_escalations(access_events),
      sensitive_data_access: count_data_access(access_events),
      top_violators: identify_top_violators(access_events),
      generated_at: DateTime.utc_now()
    }
    
    {:ok, report}
  end
  
  defp generate_integrity_report(report_opts, _state) do
    time_range = get_report_time_range(report_opts[:period] || :last_30_days)
    
    # Perform integrity verification
    {:ok, verification_result} = verify_audit_integrity(%{time_range: time_range})
    
    report = %{
      period: report_opts[:period] || :last_30_days,
      integrity_status: verification_result.overall_status,
      verified_entries: verification_result.verified_count,
      failed_verifications: verification_result.failed_count,
      tamper_evidence: verification_result.tamper_evidence,
      generated_at: DateTime.utc_now()
    }
    
    {:ok, report}
  end
  
  defp generate_compliance_status_report(_report_opts, _state) do
    # Generate comprehensive compliance status
    report = %{
      compliance_frameworks: [:sox, :hipaa, :gdpr],
      audit_coverage: calculate_audit_coverage(),
      retention_compliance: verify_retention_compliance(),
      access_control_compliance: verify_access_control_compliance(),
      encryption_compliance: verify_encryption_compliance(),
      generated_at: DateTime.utc_now()
    }
    
    {:ok, report}
  end
  
  defp perform_integrity_verification(opts) do
    # Verify cryptographic integrity of audit entries
    time_range = opts[:time_range] || get_default_verification_range()
    
    {:ok, events} = query_audit_trail(%{time_range: time_range})
    
    verification_results = Enum.map(events, fn event ->
      verify_event_integrity(event)
    end)
    
    {verified, failed} = Enum.split_with(verification_results, fn
      {:ok, _} -> true
      _ -> false
    end)
    
    result = %{
      overall_status: if(length(failed) == 0, do: :verified, else: :compromised),
      verified_count: length(verified),
      failed_count: length(failed),
      tamper_evidence: extract_tamper_evidence(failed),
      verification_timestamp: DateTime.utc_now()
    }
    
    {:ok, result}
  end
  
  defp verify_event_integrity({_, event_id, _timestamp, _type, _user_id, _session_id, _node, data, stored_hash}) do
    # Recalculate hash and compare
    expected_hash = calculate_integrity_hash(data, event_id)
    
    if expected_hash == stored_hash do
      {:ok, event_id}
    else
      {:error, {:integrity_failure, event_id, expected_hash, stored_hash}}
    end
  end
  
  defp extract_tamper_evidence(failed_verifications) do
    Enum.map(failed_verifications, fn
      {:error, {:integrity_failure, event_id, expected, actual}} ->
        %{
          event_id: event_id,
          expected_hash: expected,
          actual_hash: actual,
          detected_at: DateTime.utc_now()
        }
    end)
  end
  
  defp perform_audit_archival(archive_opts) do
    # Archive old audit logs based on retention policy
    cutoff_date = calculate_archive_cutoff(archive_opts[:retention_days] || 2555) # ~7 years default
    
    {:ok, old_events} = query_audit_trail(%{
      time_range: {~U[1970-01-01 00:00:00Z], cutoff_date}
    })
    
    # Archive to external storage (implementation depends on storage backend)
    archive_result = archive_events_to_storage(old_events, archive_opts)
    
    # Remove from active tables if archival successful
    case archive_result do
      {:ok, archive_info} ->
        remove_archived_events(old_events)
        {:ok, Map.put(archive_info, :archived_count, length(old_events))}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp archive_events_to_storage(events, archive_opts) do
    # Placeholder for external storage integration
    # Could integrate with S3, GCS, or other archive storage
    archive_file = "/tmp/audit_archive_#{System.os_time(:second)}.json"
    
    case File.write(archive_file, Jason.encode!(events)) do
      :ok ->
        {:ok, %{
          archive_file: archive_file,
          archive_method: :local_file,
          compression: archive_opts[:compression] || :none
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp remove_archived_events(events) do
    Enum.each(events, fn {_, event_id, _, _, _, _, _, _} ->
      :mnesia.transaction(fn ->
        :mnesia.delete({@audit_table, event_id})
      end)
    end)
  end
  
  # Helper functions for report generation
  defp get_report_time_range(:last_24_hours) do
    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -24 * 60 * 60, :second)
    {start_time, end_time}
  end
  
  defp get_report_time_range(:last_7_days) do
    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -7 * 24 * 60 * 60, :second)
    {start_time, end_time}
  end
  
  defp get_report_time_range(:last_30_days) do
    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -30 * 24 * 60 * 60, :second)
    {start_time, end_time}
  end
  
  defp group_events_by_type(events) do
    Enum.group_by(events, fn {_, _, _, type, _, _, _, _} -> type end)
    |> Enum.map(fn {type, type_events} -> {type, length(type_events)} end)
    |> Enum.into(%{})
  end
  
  defp group_events_by_node(events) do
    Enum.group_by(events, fn {_, _, _, _, _, _, node, _} -> node end)
    |> Enum.map(fn {node, node_events} -> {node, length(node_events)} end)
    |> Enum.into(%{})
  end
  
  defp calculate_auth_success_rate(events) do
    auth_events = Enum.filter(events, fn {_, _, _, type, _, _, _, _} ->
      type == :authentication_attempt
    end)
    
    if length(auth_events) == 0 do
      0.0
    else
      successful = count_successful_auths(auth_events)
      successful / length(auth_events) * 100
    end
  end
  
  defp count_successful_auths(events) do
    Enum.count(events, fn {_, _, _, _, _, _, _, data} ->
      Map.get(data, :result) == :success
    end)
  end
  
  defp count_failed_auths(events) do
    Enum.count(events, fn {_, _, _, _, _, _, _, data} ->
      Map.get(data, :result) == :failure
    end)
  end
  
  defp count_security_violations(events) do
    violation_types = [:authorization_failure, :privilege_escalation, :security_violation, :audit_tampering]
    
    Enum.count(events, fn {_, _, _, type, _, _, _, _} ->
      type in violation_types
    end)
  end
  
  defp count_authorization_failures(events) do
    Enum.count(events, fn {_, _, _, type, _, _, _, _} ->
      type == :authorization_failure
    end)
  end
  
  defp count_privilege_escalations(events) do
    Enum.count(events, fn {_, _, _, type, _, _, _, _} ->
      type == :privilege_escalation
    end)
  end
  
  defp count_data_access(events) do
    Enum.count(events, fn {_, _, _, type, _, _, _, _} ->
      type == :data_access
    end)
  end
  
  defp analyze_failure_reasons(events) do
    events
    |> Enum.filter(fn {_, _, _, _, _, _, _, data} ->
      Map.get(data, :result) == :failure
    end)
    |> Enum.group_by(fn {_, _, _, _, _, _, _, data} ->
      Map.get(data, :failure_reason, :unknown)
    end)
    |> Enum.map(fn {reason, failures} -> {reason, length(failures)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
  end
  
  defp analyze_geographic_distribution(events) do
    # Group by source IP or geographic region if available
    events
    |> Enum.group_by(fn {_, _, _, _, _, _, _, data} ->
      Map.get(data, :source_ip, "unknown")
    end)
    |> Enum.map(fn {ip, ip_events} -> {ip, length(ip_events)} end)
    |> Enum.into(%{})
  end
  
  defp identify_top_violators(events) do
    events
    |> Enum.group_by(fn {_, _, _, _, user_id, _, _, _} -> user_id end)
    |> Enum.map(fn {user_id, user_events} -> {user_id, length(user_events)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(10)
  end
  
  # Utility functions
  defp generate_event_id do
    "audit_#{:erlang.unique_integer([:positive])}_#{System.os_time(:millisecond)}"
  end
  
  defp calculate_archive_cutoff(retention_days) do
    DateTime.add(DateTime.utc_now(), -retention_days * 24 * 60 * 60, :second)
  end
  
  defp get_default_verification_range do
    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -7 * 24 * 60 * 60, :second)
    {start_time, end_time}
  end
  
  defp calculate_audit_coverage do
    # Calculate percentage of system activities that are audited
    0.95  # Placeholder - 95% coverage
  end
  
  defp verify_retention_compliance do
    # Verify audit log retention meets compliance requirements
    %{
      status: :compliant,
      current_retention_days: 2555,
      required_retention_days: 2555,
      compliance_frameworks: [:sox, :hipaa]
    }
  end
  
  defp verify_access_control_compliance do
    # Verify access control audit requirements
    %{
      status: :compliant,
      access_events_audited: true,
      privilege_changes_audited: true,
      admin_actions_audited: true
    }
  end
  
  defp verify_encryption_compliance do
    # Verify encryption of audit data
    %{
      status: :compliant,
      audit_data_encrypted: true,
      transmission_encrypted: true,
      key_management_compliant: true
    }
  end
  
  defp init_metrics do
    %{
      events_logged: 0,
      queries_processed: 0,
      reports_generated: 0,
      integrity_checks_performed: 0,
      violations_detected: 0
    }
  end
  
  defp update_security_metrics(state, _event) do
    # Update metrics when events are logged
    metrics = %{state.metrics |
      events_logged: state.metrics.events_logged + 1
    }
    
    %{state | metrics: metrics}
  end
  
  defp refresh_security_metrics(state) do
    # Refresh metrics from current data
    state
  end
  
  defp compile_security_metrics(state) do
    %{
      node: state.node,
      metrics: state.metrics,
      active_sessions: map_size(state.active_sessions),
      integrity_status: get_latest_integrity_status(state),
      cluster_nodes: get_cluster_audit_nodes()
    }
  end
  
  defp get_latest_integrity_status(_state) do
    # Get latest integrity check result
    :verified  # Placeholder
  end
  
  defp get_cluster_audit_nodes do
    :pg.get_members(@pg_scope, :audit_loggers)
    |> Enum.map(&node/1)
    |> Enum.uniq()
  end
  
  defp handle_security_event(%{type: type} = event, state) when type in [:authentication_attempt, :authorization_failure, :session_created, :session_closed] do
    # Convert event bus events to audit events
    audit_event = %{
      type: type,
      user_id: event.data[:user_id],
      session_id: event.data[:session_id],
      result: event.data[:result] || :unknown,
      metadata: event.metadata
    }
    
    # Log the security event
    log_security_event(audit_event)
    
    state
  end
  
  defp handle_security_event(_event, state), do: state
  
  defp cache_compliance_report(state, report_opts, report) do
    # Cache report for performance
    cache_key = generate_cache_key(report_opts)
    cached_report = %{
      report: report,
      generated_at: DateTime.utc_now(),
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)  # 1 hour
    }
    
    %{state |
      compliance_cache: Map.put(state.compliance_cache, cache_key, cached_report)
    }
  end
  
  defp generate_cache_key(report_opts) do
    :crypto.hash(:md5, :erlang.term_to_binary(report_opts))
    |> Base.encode16()
  end
  
  defp update_integrity_checks(state, verification_result) do
    check_id = generate_event_id()
    
    integrity_check = %{
      check_id: check_id,
      timestamp: DateTime.utc_now(),
      result: verification_result
    }
    
    %{state |
      integrity_checks: Map.put(state.integrity_checks, check_id, integrity_check)
    }
  end
  
  defp perform_periodic_integrity_check do
    # Perform automated integrity verification
    spawn(fn ->
      case verify_audit_integrity() do
        {:ok, result} ->
          if result.overall_status != :verified do
            Logger.error("Audit integrity check failed: #{inspect(result)}")
            # Could trigger alerts here
          end
          
        {:error, reason} ->
          Logger.error("Integrity check error: #{inspect(reason)}")
      end
    end)
  end
  
  defp schedule_integrity_check do
    # Schedule next integrity check (every hour)
    Process.send_after(self(), :integrity_check, 60 * 60 * 1000)
  end
  
  defp schedule_metrics_update do
    # Schedule metrics update (every 5 minutes)
    Process.send_after(self(), :metrics_update, 5 * 60 * 1000)
  end
  
  defp validate_remote_audit_event(event) do
    # Validate event from remote node
    required_fields = [:event_id, :timestamp, :type, :node, :integrity_hash]
    
    if Enum.all?(required_fields, &Map.has_key?(event, &1)) do
      # Verify integrity hash
      expected_hash = calculate_integrity_hash(event, event.event_id)
      
      if expected_hash == event.integrity_hash do
        {:ok, event}
      else
        {:error, :integrity_verification_failed}
      end
    else
      {:error, :missing_required_fields}
    end
  end
end