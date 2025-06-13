defmodule Aiex.DevTools.OperationalDocs do
  @moduledoc """
  Dynamic operational documentation generator for Aiex distributed systems.
  
  Generates comprehensive runbooks, troubleshooting guides, and operational
  procedures based on current cluster configuration and discovered issues.
  """
  
  require Logger
  
  alias Aiex.DevTools.ClusterInspector
  alias Aiex.Telemetry.DistributedAggregator
  alias Aiex.Performance.DistributedAnalyzer
  
  @doc "Generate comprehensive operational runbook"
  def generate_runbook(format \\ :markdown) do
    %{
      title: "Aiex Operational Runbook",
      generated_at: DateTime.utc_now(),
      cluster_info: get_cluster_info(),
      sections: [
        cluster_overview_section(),
        deployment_procedures_section(),
        monitoring_section(),
        troubleshooting_section(),
        maintenance_section(),
        emergency_procedures_section(),
        configuration_reference_section()
      ]
    }
    |> format_documentation(format)
  end
  
  @doc "Generate troubleshooting guide based on current issues"
  def generate_troubleshooting_guide(format \\ :markdown) do
    current_issues = identify_current_issues()
    
    %{
      title: "Aiex Troubleshooting Guide",
      generated_at: DateTime.utc_now(),
      current_issues: current_issues,
      sections: [
        common_issues_section(),
        performance_troubleshooting_section(),
        network_troubleshooting_section(),
        storage_troubleshooting_section(),
        application_troubleshooting_section(),
        diagnostic_commands_section()
      ]
    }
    |> format_documentation(format)
  end
  
  @doc "Generate configuration reference"
  def generate_config_reference(format \\ :markdown) do
    %{
      title: "Aiex Configuration Reference",
      generated_at: DateTime.utc_now(),
      sections: [
        environment_variables_section(),
        application_config_section(),
        kubernetes_config_section(),
        release_config_section(),
        telemetry_config_section()
      ]
    }
    |> format_documentation(format)
  end
  
  @doc "Generate deployment checklist"
  def generate_deployment_checklist(deployment_type \\ :rolling_update) do
    %{
      title: "Aiex Deployment Checklist - #{String.upcase(to_string(deployment_type))}",
      deployment_type: deployment_type,
      generated_at: DateTime.utc_now(),
      pre_deployment: pre_deployment_checklist(),
      deployment_steps: deployment_steps_checklist(deployment_type),
      post_deployment: post_deployment_checklist(),
      rollback_procedures: rollback_checklist()
    }
  end
  
  @doc "Generate monitoring dashboard documentation"
  def generate_monitoring_docs(format \\ :markdown) do
    %{
      title: "Aiex Monitoring and Observability Guide",
      generated_at: DateTime.utc_now(),
      sections: [
        metrics_overview_section(),
        dashboards_section(),
        alerts_section(),
        tracing_section(),
        logging_section(),
        health_checks_section()
      ]
    }
    |> format_documentation(format)
  end
  
  # Private functions - Section generators
  
  defp cluster_overview_section do
    cluster_info = get_cluster_info()
    
    %{
      title: "Cluster Overview",
      content: """
      ## Current Cluster State
      
      - **Cluster Name**: #{cluster_info.cluster_name}
      - **Total Nodes**: #{cluster_info.node_count}
      - **Aiex Version**: #{cluster_info.version}
      - **Environment**: #{cluster_info.environment}
      - **Cluster Health**: #{cluster_info.health}
      
      ### Connected Nodes
      #{format_node_list(cluster_info.nodes)}
      
      ### Architecture Overview
      Aiex operates as a distributed system built on Erlang/OTP with the following key components:
      
      - **Context Management**: Distributed context with Mnesia persistence
      - **LLM Integration**: Multi-provider coordination with circuit breakers
      - **Event Sourcing**: Distributed event bus using pg process groups
      - **Telemetry**: Cluster-wide metrics aggregation and monitoring
      - **Release Management**: Automated deployment and health checking
      """
    }
  end
  
  defp deployment_procedures_section do
    %{
      title: "Deployment Procedures",
      content: """
      ## Standard Deployment Process
      
      ### Pre-deployment Validation
      ```bash
      # Check cluster health
      ./scripts/release-management.sh health
      
      # Validate deployment readiness
      ./scripts/release-management.sh status
      ```
      
      ### Rolling Update Deployment
      ```bash
      # Build new release
      ./scripts/release-management.sh build -v <version>
      
      # Build container image
      ./scripts/release-management.sh container -v <version>
      
      # Deploy with rolling update strategy
      ./scripts/release-management.sh deploy -s rolling_update -v <version>
      ```
      
      ### Blue-Green Deployment
      ```bash
      # Deploy with blue-green strategy
      ./scripts/release-management.sh deploy -s blue_green -v <version>
      ```
      
      ### Rollback Procedures
      ```bash
      # Automatic rollback
      ./scripts/release-management.sh rollback
      
      # Manual rollback to specific version
      kubectl rollout undo deployment/aiex --to-revision=<revision>
      ```
      
      ### Post-deployment Verification
      - Check pod status: `kubectl get pods -n aiex`
      - Verify health endpoints: `curl http://<service-ip>:8090/health`
      - Monitor metrics: Access Prometheus dashboard
      - Check application logs: `kubectl logs -f deployment/aiex -n aiex`
      """
    }
  end
  
  defp monitoring_section do
    %{
      title: "Monitoring and Observability",
      content: """
      ## Monitoring Endpoints
      
      ### Health Checks
      - **Readiness**: `http://<node>:8090/health/ready`
      - **Liveness**: `http://<node>:8090/health/live`
      - **Detailed Health**: `http://<node>:8090/health/detailed`
      
      ### Metrics
      - **Prometheus**: `http://<node>:9090/metrics`
      - **Health Metrics**: `http://<node>:8090/metrics/health`
      - **Cluster Dashboard**: `http://<node>:8080`
      
      ### Key Metrics to Monitor
      - `aiex_connected_nodes_total`: Number of connected cluster nodes
      - `aiex_memory_usage_bytes`: Memory usage by category
      - `aiex_process_count`: Total process count
      - `aiex_health_ready`: Node readiness status
      - `aiex_uptime_seconds`: Node uptime
      
      ### Alerts Configuration
      Configure alerts for:
      - High memory usage (>90%)
      - Process count exceeding limits (>10k)
      - Node disconnections
      - Health check failures
      - Deployment failures
      """
    }
  end
  
  defp troubleshooting_section do
    current_issues = identify_current_issues()
    
    %{
      title: "Troubleshooting Guide",
      content: """
      ## Current Issues Detected
      #{format_current_issues(current_issues)}
      
      ## Common Issues and Solutions
      
      ### Node Connectivity Issues
      **Symptoms**: Nodes showing as disconnected, cluster coordination failures
      
      **Diagnosis**:
      ```bash
      # Check node connectivity
      kubectl get nodes
      kubectl get pods -n aiex -o wide
      
      # Test network connectivity
      kubectl exec -it <pod> -n aiex -- ping <other-pod-ip>
      ```
      
      **Solutions**:
      - Check network policies and firewall rules
      - Verify Kubernetes DNS resolution
      - Restart affected pods: `kubectl rollout restart deployment/aiex -n aiex`
      
      ### High Memory Usage
      **Symptoms**: Memory alerts, pods being OOMKilled
      
      **Diagnosis**:
      ```bash
      # Check memory usage
      kubectl top pods -n aiex
      kubectl describe pod <pod-name> -n aiex
      ```
      
      **Solutions**:
      - Increase memory limits in deployment
      - Force garbage collection: Use debugging console
      - Check for memory leaks in application logs
      
      ### Performance Issues
      **Symptoms**: High latency, slow response times
      
      **Diagnosis**:
      ```bash
      # Use performance analysis tools
      ./scripts/release-management.sh status
      # Access cluster dashboard for detailed metrics
      ```
      
      **Solutions**:
      - Scale horizontally: `kubectl scale deployment/aiex --replicas=<count> -n aiex`
      - Check hot processes and message queues
      - Review LLM provider response times
      
      ### Database/Mnesia Issues
      **Symptoms**: Data inconsistency, schema errors
      
      **Diagnosis**:
      - Check Mnesia status in debugging console
      - Review cluster formation logs
      
      **Solutions**:
      - Restart Mnesia: Restart all nodes in sequence
      - Check disk space and permissions
      - Verify persistent volume claims
      """
    }
  end
  
  defp maintenance_section do
    %{
      title: "Maintenance Procedures",
      content: """
      ## Regular Maintenance Tasks
      
      ### Daily Checks
      - [ ] Verify cluster health status
      - [ ] Check resource usage (CPU, memory, disk)
      - [ ] Review application logs for errors
      - [ ] Validate backup procedures
      
      ### Weekly Maintenance
      - [ ] Clean up old container images
      - [ ] Review and rotate logs
      - [ ] Update monitoring dashboards
      - [ ] Test backup and restore procedures
      
      ### Monthly Maintenance
      - [ ] Security updates and patches
      - [ ] Performance optimization review
      - [ ] Capacity planning assessment
      - [ ] Documentation updates
      
      ### Maintenance Commands
      ```bash
      # Clean up old releases
      ./scripts/release-management.sh cleanup
      
      # Rotate logs
      kubectl logs --tail=1000 deployment/aiex -n aiex > aiex-$(date +%Y%m%d).log
      
      # Update configurations
      kubectl apply -f k8s/manifests/
      ```
      
      ### Backup Procedures
      1. **Mnesia Backup**:
         ```bash
         kubectl exec -it <pod> -n aiex -- mkdir -p /app/backups
         kubectl exec -it <pod> -n aiex -- cp -r /app/data/mnesia /app/backups/mnesia-$(date +%Y%m%d)
         ```
      
      2. **Configuration Backup**:
         ```bash
         kubectl get configmap -n aiex -o yaml > aiex-config-backup.yaml
         kubectl get secret -n aiex -o yaml > aiex-secrets-backup.yaml
         ```
      """
    }
  end
  
  defp emergency_procedures_section do
    %{
      title: "Emergency Procedures",
      content: """
      ## Emergency Response Procedures
      
      ### Complete Cluster Failure
      1. **Immediate Response**:
         ```bash
         # Check cluster status
         kubectl get nodes
         kubectl get pods --all-namespaces
         ```
      
      2. **Recovery Steps**:
         ```bash
         # Restart all Aiex pods
         kubectl rollout restart deployment/aiex -n aiex
         
         # If cluster is unresponsive, restart nodes
         kubectl drain <node> --ignore-daemonsets
         kubectl uncordon <node>
         ```
      
      3. **Data Recovery**:
         - Restore from Mnesia backups
         - Verify data integrity
         - Test application functionality
      
      ### Security Incident Response
      1. **Immediate Isolation**:
         ```bash
         # Scale down to stop traffic
         kubectl scale deployment/aiex --replicas=0 -n aiex
         
         # Block network access if needed
         kubectl apply -f emergency-network-policy.yaml
         ```
      
      2. **Investigation**:
         - Collect logs and system state
         - Analyze security alerts
         - Document incident timeline
      
      3. **Recovery**:
         - Apply security patches
         - Rotate secrets and certificates
         - Gradually restore service
      
      ### Data Corruption
      1. **Stop Write Operations**:
         ```bash
         # Set pods to read-only mode
         kubectl set env deployment/aiex EMERGENCY_READ_ONLY=true -n aiex
         ```
      
      2. **Assess Damage**:
         - Check Mnesia table integrity
         - Verify backup availability
         - Estimate recovery time
      
      3. **Restore from Backup**:
         - Stop all services
         - Restore Mnesia data
         - Restart cluster in maintenance mode
         - Verify data integrity before resuming operations
      
      ### Contact Information
      - **On-call Engineer**: [Contact details]
      - **Platform Team**: [Contact details]
      - **Escalation**: [Management contact]
      """
    }
  end
  
  defp configuration_reference_section do
    %{
      title: "Configuration Reference",
      content: """
      ## Environment Variables
      
      ### Core Configuration
      - `CLUSTER_ENABLED`: Enable/disable clustering (true/false)
      - `LLM_DEFAULT_PROVIDER`: Default LLM provider (ollama/openai/anthropic)
      - `LOG_LEVEL`: Logging level (debug/info/warning/error)
      - `SECRET_KEY_BASE`: Phoenix secret key for sessions
      
      ### Kubernetes Configuration
      - `KUBERNETES_SERVICE_HOST`: Auto-detected in K8s environments
      - `POD_IP`: Pod IP address for cluster formation
      - `POD_NAMESPACE`: Kubernetes namespace
      - `SERVICE_NAME`: Service name for cluster discovery
      
      ### Monitoring Configuration
      - `PROMETHEUS_ENABLED`: Enable Prometheus metrics export
      - `PROMETHEUS_PORT`: Prometheus metrics port (default: 9090)
      - `HEALTH_PORT`: Health check port (default: 8090)
      - `DASHBOARD_PORT`: Cluster dashboard port (default: 8080)
      
      ### Performance Configuration
      - `MEMORY_LIMIT_MB`: Container memory limit
      - `SCHEDULERS_ONLINE`: Number of Erlang schedulers
      - `ERL_MAX_PORTS`: Maximum number of ports
      
      ## Application Configuration (config/prod.exs)
      
      ```elixir
      config :aiex,
        llm: [
          default_provider: :ollama,
          timeout: 30_000,
          max_retries: 3
        ],
        context: [
          max_memory_mb: 200,
          persistence_interval_ms: 1_000
        ],
        performance: [
          monitoring_enabled: true,
          dashboard_update_interval: 5_000
        ],
        telemetry: [
          prometheus_enabled: true,
          tracing_enabled: true,
          dashboard_enabled: true
        ],
        release: [
          health_endpoint_enabled: true,
          deployment_automation_enabled: false
        ]
      ```
      """
    }
  end
  
  # Utility functions
  
  defp get_cluster_info do
    try do
      case Process.whereis(ClusterInspector) do
        nil ->
          get_default_cluster_info()
        _pid ->
          overview = ClusterInspector.cluster_overview()
          
          %{
            cluster_name: "aiex-cluster",
            node_count: overview.total_nodes,
            version: overview.system_overview.aiex_version || "unknown",
            environment: get_environment(),
            health: overview.cluster_health,
            nodes: overview.node_summary
          }
      end
    rescue
      _ ->
        get_default_cluster_info()
    end
  end
  
  defp get_default_cluster_info do
    %{
      cluster_name: "aiex-cluster",
      node_count: 1,
      version: "unknown",
      environment: get_environment(),
      health: :unknown,
      nodes: []
    }
  end
  
  defp identify_current_issues do
    try do
      case Process.whereis(ClusterInspector) do
        nil ->
          []
        _pid ->
          health_report = ClusterInspector.health_report()
          health_report.issues || []
      end
    rescue
      _ -> []
    end
  end
  
  defp get_environment do
    cond do
      System.get_env("KUBERNETES_SERVICE_HOST") -> "kubernetes"
      System.get_env("DOCKER_HOST") -> "docker"
      true -> "standalone"
    end
  end
  
  defp format_node_list(nodes) do
    nodes
    |> Enum.map(fn node ->
      "- **#{node.node}**: #{node.processes} processes, #{node.memory_mb}MB memory (#{node.status})"
    end)
    |> Enum.join("\n")
  end
  
  defp format_current_issues([]), do: "*No issues detected at generation time.*"
  defp format_current_issues(issues) do
    issues
    |> Enum.with_index(1)
    |> Enum.map(fn {issue, index} -> "#{index}. #{issue}" end)
    |> Enum.join("\n")
  end
  
  defp pre_deployment_checklist do
    [
      "Verify cluster health status",
      "Check resource availability (CPU, memory, storage)",
      "Backup current configuration and data",
      "Validate new release artifacts",
      "Notify stakeholders of deployment window",
      "Ensure rollback plan is ready",
      "Verify monitoring and alerting systems",
      "Check for any ongoing incidents or maintenance"
    ]
  end
  
  defp deployment_steps_checklist(:rolling_update) do
    [
      "Scale up new replica set",
      "Wait for new pods to be ready",
      "Gradually shift traffic to new pods",
      "Monitor application metrics and logs",
      "Verify all health checks pass",
      "Scale down old replica set",
      "Confirm deployment success"
    ]
  end
  
  defp deployment_steps_checklist(:blue_green) do
    [
      "Deploy to green environment",
      "Run smoke tests on green environment",
      "Switch load balancer to green environment",
      "Monitor traffic and metrics",
      "Verify all functionality works",
      "Keep blue environment as fallback",
      "Clean up blue environment after confirmation"
    ]
  end
  
  defp deployment_steps_checklist(:canary) do
    [
      "Deploy canary version to subset of nodes",
      "Route small percentage of traffic to canary",
      "Monitor canary metrics and error rates",
      "Gradually increase traffic percentage",
      "Monitor for any issues or regressions",
      "Complete rollout if metrics are healthy",
      "Clean up old version"
    ]
  end
  
  defp post_deployment_checklist do
    [
      "Verify all pods are running and healthy",
      "Check application logs for errors",
      "Validate all API endpoints",
      "Confirm monitoring and metrics collection",
      "Test key application functionality",
      "Verify database connectivity and integrity",
      "Update deployment documentation",
      "Notify stakeholders of completion"
    ]
  end
  
  defp rollback_checklist do
    [
      "Identify the issue requiring rollback",
      "Determine target rollback version",
      "Execute rollback procedure",
      "Monitor rollback progress",
      "Verify system stability after rollback",
      "Investigate root cause of deployment issue",
      "Document lessons learned",
      "Plan remediation for next deployment"
    ]
  end
  
  defp metrics_overview_section do
    %{
      title: "Metrics Overview",
      content: """
      ## Core Metrics
      
      ### System Metrics
      - **aiex_connected_nodes_total**: Number of connected cluster nodes
      - **aiex_memory_usage_bytes**: Memory usage by type (total, processes, system, etc.)
      - **aiex_process_count**: Total number of processes
      - **aiex_uptime_seconds**: Node uptime in seconds
      
      ### Application Metrics
      - **aiex_llm_requests_total**: Total LLM requests by provider
      - **aiex_llm_response_time_seconds**: LLM response time distribution
      - **aiex_context_operations_total**: Context management operations
      - **aiex_events_published_total**: Published events by topic
      
      ### Performance Metrics
      - **aiex_gc_time_seconds**: Garbage collection time
      - **aiex_reductions_total**: Process reductions (work done)
      - **aiex_message_queue_length**: Process message queue lengths
      """
    }
  end
  
  defp dashboards_section do
    %{
      title: "Dashboards",
      content: """
      ## Available Dashboards
      
      ### Cluster Dashboard (Port 8080)
      - Real-time cluster overview
      - Node health and status
      - Resource utilization
      - Active alerts
      
      ### Prometheus Metrics (Port 9090)
      - Raw metrics data
      - Custom queries
      - Historical data
      
      ### Grafana (External)
      Recommended Grafana dashboards:
      - Erlang/OTP system metrics
      - Application performance
      - Business metrics
      """
    }
  end
  
  defp alerts_section do
    %{
      title: "Alerting",
      content: """
      ## Default Alert Rules
      
      ### Critical Alerts
      - Node disconnection
      - High memory usage (>90%)
      - Health check failures
      - Database connection issues
      
      ### Warning Alerts
      - High process count (>10k)
      - Elevated response times
      - Memory usage >80%
      - Disk space low
      
      ## Alert Configuration
      Configure alerts in your monitoring system to:
      1. Send notifications to appropriate channels
      2. Include context and runbook links
      3. Set appropriate escalation procedures
      """
    }
  end
  
  defp tracing_section do
    %{
      title: "Distributed Tracing",
      content: """
      ## Tracing Configuration
      
      Aiex includes built-in distributed tracing:
      - OpenTelemetry-compatible format
      - Automatic context propagation
      - Configurable sampling rates
      
      ## Viewing Traces
      Use the debugging console to start traces:
      ```
      trace <operation_name>
      ```
      
      Or configure external tracing systems like Jaeger or Zipkin.
      """
    }
  end
  
  defp logging_section do
    %{
      title: "Logging",
      content: """
      ## Log Configuration
      
      ### Log Levels
      - **debug**: Detailed debugging information
      - **info**: General information
      - **warning**: Warning messages
      - **error**: Error conditions
      
      ### Structured Logging
      Logs include:
      - Correlation IDs for request tracking
      - Node information
      - Timestamp and severity
      - Contextual metadata
      
      ### Log Aggregation
      Configure log forwarding to:
      - ELK Stack (Elasticsearch, Logstash, Kibana)
      - Splunk
      - CloudWatch Logs
      - Fluentd/Fluent Bit
      """
    }
  end
  
  defp health_checks_section do
    %{
      title: "Health Checks",
      content: """
      ## Health Check Endpoints
      
      ### Kubernetes Probes
      - **Readiness**: `/health/ready` - Traffic routing decision
      - **Liveness**: `/health/live` - Restart decision
      
      ### Detailed Health
      - **Comprehensive**: `/health/detailed` - Full system status
      - **Metrics**: `/metrics/health` - Prometheus format
      
      ## Custom Health Checks
      Register custom health checks in the application:
      ```elixir
      DistributedRelease.register_health_check(:custom_check, fn ->
        # Your health check logic
        :ok
      end)
      ```
      """
    }
  end
  
  defp environment_variables_section do
    %{
      title: "Environment Variables",
      content: """
      ## Complete Environment Variable Reference
      
      ### Core Settings
      | Variable | Default | Description |
      |----------|---------|-------------|
      | `CLUSTER_ENABLED` | `false` | Enable distributed clustering |
      | `LLM_DEFAULT_PROVIDER` | `ollama` | Default LLM provider |
      | `LOG_LEVEL` | `info` | Application log level |
      | `SECRET_KEY_BASE` | auto-generated | Phoenix secret key |
      
      ### Networking
      | Variable | Default | Description |
      |----------|---------|-------------|
      | `PORT` | `4000` | HTTP port for Phoenix |
      | `HOST` | `0.0.0.0` | Bind address |
      | `HEALTH_PORT` | `8090` | Health check port |
      | `PROMETHEUS_PORT` | `9090` | Metrics port |
      | `DASHBOARD_PORT` | `8080` | Dashboard port |
      
      ### Performance
      | Variable | Default | Description |
      |----------|---------|-------------|
      | `MEMORY_LIMIT_MB` | auto | Container memory limit |
      | `SCHEDULERS_ONLINE` | auto | Erlang schedulers |
      | `ERL_MAX_PORTS` | `32768` | Maximum ports |
      """
    }
  end
  
  defp application_config_section do
    %{
      title: "Application Configuration",
      content: """
      ## Configuration Files
      
      - `config/config.exs`: Base configuration
      - `config/dev.exs`: Development settings
      - `config/prod.exs`: Production settings
      - `config/test.exs`: Test settings
      
      ## Key Configuration Sections
      
      ### LLM Configuration
      ```elixir
      config :aiex, llm: [
        default_provider: :ollama,
        timeout: 30_000,
        max_retries: 3,
        distributed_coordination: true
      ]
      ```
      
      ### Context Management
      ```elixir
      config :aiex, context: [
        max_memory_mb: 200,
        persistence_interval_ms: 1_000
      ]
      ```
      
      ### Telemetry
      ```elixir
      config :aiex, telemetry: [
        prometheus_enabled: true,
        tracing_enabled: true,
        dashboard_enabled: true
      ]
      ```
      """
    }
  end
  
  defp kubernetes_config_section do
    %{
      title: "Kubernetes Configuration",
      content: """
      ## Manifest Files
      
      - `k8s/manifests/namespace.yaml`: Namespace definition
      - `k8s/manifests/configmap.yaml`: Configuration data
      - `k8s/manifests/secret.yaml`: Sensitive data
      - `k8s/manifests/deployment.yaml`: Application deployment
      - `k8s/manifests/service.yaml`: Service definitions
      - `k8s/manifests/hpa.yaml`: Horizontal Pod Autoscaler
      
      ## Helm Configuration
      
      Values file: `k8s/helm/aiex/values.yaml`
      
      Key settings:
      - Replica count
      - Resource limits
      - Autoscaling configuration
      - Network policies
      """
    }
  end
  
  defp release_config_section do
    %{
      title: "Release Configuration",
      content: """
      ## Mix Release Settings
      
      File: `mix.exs`
      
      ```elixir
      def releases do
        [
          aiex: [
            include_executables_for: [:unix],
            applications: [runtime_tools: :permanent],
            steps: [:assemble, &copy_tui_binary/1],
            strip_beams: Mix.env() == :prod,
            include_erts: true
          ]
        ]
      end
      ```
      
      ## Environment Configuration
      
      File: `rel/env.sh.eex`
      
      - Automatic environment detection
      - Dynamic cluster configuration
      - Performance tuning
      """
    }
  end
  
  defp telemetry_config_section do
    %{
      title: "Telemetry Configuration",
      content: """
      ## Telemetry Settings
      
      ```elixir
      config :aiex, telemetry: [
        prometheus_enabled: true,
        prometheus_port: 9090,
        tracing_enabled: true,
        tracing_sampling_rate: 1.0,
        dashboard_enabled: true,
        dashboard_port: 8080
      ]
      ```
      
      ## Metrics Collection
      
      - Automatic system metrics
      - Application-specific metrics
      - Custom metric registration
      - Cross-cluster aggregation
      
      ## Retention Policies
      
      - Metrics: 5 minutes (in-memory)
      - Traces: Until span completion
      - Logs: 24 hours (dashboard history)
      """
    }
  end
  
  defp format_documentation(doc, :markdown) do
    sections_content = doc.sections
    |> Enum.map(fn section ->
      "# #{section.title}\n\n#{section.content}\n"
    end)
    |> Enum.join("\n")
    
    """
    # #{doc.title}
    
    *Generated on #{DateTime.to_iso8601(doc.generated_at)}*
    
    #{sections_content}
    """
  end
  
  defp format_documentation(doc, :html) do
    # HTML formatting implementation
    sections_html = doc.sections
    |> Enum.map(fn section ->
      "<section><h2>#{section.title}</h2><div>#{format_markdown_to_html(section.content)}</div></section>"
    end)
    |> Enum.join("\n")
    
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>#{doc.title}</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            h1, h2, h3 { color: #333; }
            code { background: #f4f4f4; padding: 2px 4px; }
            pre { background: #f4f4f4; padding: 10px; overflow-x: auto; }
        </style>
    </head>
    <body>
        <h1>#{doc.title}</h1>
        <p><em>Generated on #{DateTime.to_iso8601(doc.generated_at)}</em></p>
        #{sections_html}
    </body>
    </html>
    """
  end
  
  defp format_documentation(doc, :json) do
    Jason.encode!(doc, pretty: true)
  end
  
  defp common_issues_section do
    %{
      title: "Common Issues",
      content: """
      ## Frequently Encountered Issues
      
      ### Node Connection Problems
      **Symptoms**: Nodes not joining cluster, connection timeouts
      **Resolution**: Check network connectivity, DNS resolution, firewall rules
      
      ### Memory Pressure
      **Symptoms**: High memory usage, OOM kills
      **Resolution**: Increase memory limits, optimize process memory usage
      
      ### Performance Degradation
      **Symptoms**: Slow response times, high latency
      **Resolution**: Profile CPU usage, check for hot processes, scale horizontally
      """
    }
  end
  
  defp performance_troubleshooting_section do
    %{
      title: "Performance Troubleshooting",
      content: """
      ## Performance Analysis
      
      ### CPU Profiling
      ```bash
      # Use observer to analyze CPU usage
      kubectl exec -it <pod> -- erl -eval "observer:start()."
      ```
      
      ### Memory Analysis
      ```bash
      # Check memory distribution
      kubectl top pods -n aiex
      kubectl exec -it <pod> -- recon:memory(processes, 10).
      ```
      
      ### Process Analysis
      ```bash
      # Find hot processes
      kubectl exec -it <pod> -- recon:proc_count(reductions, 10).
      ```
      """
    }
  end
  
  defp network_troubleshooting_section do
    %{
      title: "Network Troubleshooting",
      content: """
      ## Network Connectivity Issues
      
      ### DNS Resolution
      ```bash
      # Test DNS resolution within cluster
      kubectl exec -it <pod> -- nslookup aiex-headless
      ```
      
      ### Network Policies
      ```bash
      # Check network policies
      kubectl get networkpolicies -n aiex
      kubectl describe networkpolicy aiex-network-policy -n aiex
      ```
      
      ### Service Discovery
      ```bash
      # Test service connectivity
      kubectl exec -it <pod> -- curl http://aiex-service:4000/health
      ```
      """
    }
  end
  
  defp storage_troubleshooting_section do
    %{
      title: "Storage Troubleshooting",
      content: """
      ## Persistent Storage Issues
      
      ### Volume Claims
      ```bash
      # Check PVC status
      kubectl get pvc -n aiex
      kubectl describe pvc aiex-data -n aiex
      ```
      
      ### Mnesia Database
      ```bash
      # Check Mnesia status
      kubectl exec -it <pod> -- mnesia:system_info(running_db_nodes).
      ```
      
      ### Disk Space
      ```bash
      # Check disk usage
      kubectl exec -it <pod> -- df -h
      ```
      """
    }
  end
  
  defp application_troubleshooting_section do
    %{
      title: "Application Troubleshooting",
      content: """
      ## Application-Specific Issues
      
      ### LLM Provider Connectivity
      ```bash
      # Test LLM provider endpoints
      kubectl exec -it <pod> -- curl -I https://api.openai.com/v1/models
      ```
      
      ### Context Management
      ```bash
      # Check context engine status
      kubectl logs -f <pod> | grep "Context.Manager"
      ```
      
      ### AI Engine Status
      ```bash
      # Verify AI engines are running
      kubectl exec -it <pod> -- process:whereis('Elixir.Aiex.AI.Engines.CodeAnalyzer').
      ```
      """
    }
  end
  
  defp diagnostic_commands_section do
    %{
      title: "Diagnostic Commands",
      content: """
      ## Essential Diagnostic Commands
      
      ### Cluster Status
      ```bash
      # Overall cluster health
      kubectl get nodes
      kubectl get pods -n aiex -o wide
      kubectl top nodes
      kubectl top pods -n aiex
      ```
      
      ### Application Logs
      ```bash
      # Application logs
      kubectl logs -f deployment/aiex -n aiex
      kubectl logs --previous deployment/aiex -n aiex
      ```
      
      ### Events
      ```bash
      # Kubernetes events
      kubectl get events -n aiex --sort-by='.lastTimestamp'
      ```
      
      ### Process Information
      ```bash
      # Erlang/OTP diagnostics
      kubectl exec -it <pod> -- recon:info().
      kubectl exec -it <pod> -- observer:start().
      ```
      """
    }
  end

  defp format_markdown_to_html(markdown) do
    # Simple markdown to HTML conversion
    markdown
    |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
    |> String.replace(~r/\*\*(.+?)\*\*/m, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/m, "<em>\\1</em>")
    |> String.replace(~r/`(.+?)`/m, "<code>\\1</code>")
    |> String.replace("\n\n", "</p><p>")
    |> then(&"<p>#{&1}</p>")
  end
end