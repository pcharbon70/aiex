defmodule Aiex.DevTools.OperationalDocsTest do
  use ExUnit.Case, async: true
  
  alias Aiex.DevTools.OperationalDocs
  
  describe "generate_runbook/1" do
    test "generates runbook in markdown format by default" do
      runbook = OperationalDocs.generate_runbook()
      
      assert is_binary(runbook)
      assert String.contains?(runbook, "# Aiex Operational Runbook")
      assert String.contains?(runbook, "Generated on")
      assert String.contains?(runbook, "## Cluster Overview")
      assert String.contains?(runbook, "## Deployment Procedures")
      assert String.contains?(runbook, "## Monitoring and Observability")
    end
    
    test "generates runbook in HTML format" do
      runbook = OperationalDocs.generate_runbook(:html)
      
      assert is_binary(runbook)
      assert String.contains?(runbook, "<!DOCTYPE html>")
      assert String.contains?(runbook, "<title>Aiex Operational Runbook</title>")
      assert String.contains?(runbook, "<h1>Aiex Operational Runbook</h1>")
      assert String.contains?(runbook, "<section>")
    end
    
    test "generates runbook in JSON format" do
      runbook = OperationalDocs.generate_runbook(:json)
      
      assert is_binary(runbook)
      
      # Parse JSON to verify structure
      {:ok, parsed} = Jason.decode(runbook)
      assert Map.has_key?(parsed, "title")
      assert Map.has_key?(parsed, "generated_at")
      assert Map.has_key?(parsed, "sections")
      assert parsed["title"] == "Aiex Operational Runbook"
      assert is_list(parsed["sections"])
    end
    
    test "includes all required sections" do
      runbook = OperationalDocs.generate_runbook()
      
      required_sections = [
        "Cluster Overview",
        "Deployment Procedures", 
        "Monitoring and Observability",
        "Troubleshooting Guide",
        "Maintenance Procedures",
        "Emergency Procedures",
        "Configuration Reference"
      ]
      
      Enum.each(required_sections, fn section ->
        assert String.contains?(runbook, section)
      end)
    end
  end
  
  describe "generate_troubleshooting_guide/1" do
    test "generates troubleshooting guide with current issues" do
      guide = OperationalDocs.generate_troubleshooting_guide()
      
      assert is_binary(guide)
      assert String.contains?(guide, "# Aiex Troubleshooting Guide")
      assert String.contains?(guide, "## Current Issues Detected")
      assert String.contains?(guide, "## Common Issues and Solutions")
      assert String.contains?(guide, "Node Connectivity Issues")
      assert String.contains?(guide, "High Memory Usage")
    end
    
    test "includes diagnostic commands" do
      guide = OperationalDocs.generate_troubleshooting_guide()
      
      # Should include actual kubectl and diagnostic commands
      assert String.contains?(guide, "kubectl")
      assert String.contains?(guide, "kubectl get nodes")
      assert String.contains?(guide, "kubectl get pods")
      assert String.contains?(guide, "kubectl logs")
    end
    
    test "generates in different formats" do
      markdown_guide = OperationalDocs.generate_troubleshooting_guide(:markdown)
      json_guide = OperationalDocs.generate_troubleshooting_guide(:json)
      
      assert is_binary(markdown_guide)
      assert is_binary(json_guide)
      assert String.contains?(markdown_guide, "#")
      
      {:ok, parsed_json} = Jason.decode(json_guide)
      assert Map.has_key?(parsed_json, "title")
      assert parsed_json["title"] == "Aiex Troubleshooting Guide"
    end
  end
  
  describe "generate_config_reference/1" do
    test "generates comprehensive configuration reference" do
      config = OperationalDocs.generate_config_reference()
      
      assert is_binary(config)
      assert String.contains?(config, "# Aiex Configuration Reference")
      assert String.contains?(config, "## Environment Variables")
      assert String.contains?(config, "## Application Configuration")
      assert String.contains?(config, "## Kubernetes Configuration")
      assert String.contains?(config, "## Release Configuration")
    end
    
    test "includes environment variable tables" do
      config = OperationalDocs.generate_config_reference()
      
      # Should include environment variable documentation
      assert String.contains?(config, "CLUSTER_ENABLED")
      assert String.contains?(config, "LLM_DEFAULT_PROVIDER")
      assert String.contains?(config, "LOG_LEVEL")
      assert String.contains?(config, "PROMETHEUS_PORT")
    end
    
    test "includes code examples" do
      config = OperationalDocs.generate_config_reference()
      
      # Should include Elixir configuration examples
      assert String.contains?(config, "config :aiex")
      assert String.contains?(config, "llm:")
      assert String.contains?(config, "telemetry:")
    end
  end
  
  describe "generate_deployment_checklist/1" do
    test "generates rolling update checklist by default" do
      checklist = OperationalDocs.generate_deployment_checklist()
      
      assert is_map(checklist)
      assert checklist.deployment_type == :rolling_update
      assert Map.has_key?(checklist, :pre_deployment)
      assert Map.has_key?(checklist, :deployment_steps)
      assert Map.has_key?(checklist, :post_deployment)
      assert Map.has_key?(checklist, :rollback_procedures)
      
      assert is_list(checklist.pre_deployment)
      assert is_list(checklist.deployment_steps)
      assert is_list(checklist.post_deployment)
      assert is_list(checklist.rollback_procedures)
    end
    
    test "generates blue-green deployment checklist" do
      checklist = OperationalDocs.generate_deployment_checklist(:blue_green)
      
      assert checklist.deployment_type == :blue_green
      assert is_list(checklist.deployment_steps)
      
      # Blue-green specific steps
      steps = checklist.deployment_steps
      step_text = Enum.join(steps, " ")
      assert String.contains?(step_text, "green environment")
      assert String.contains?(step_text, "load balancer")
    end
    
    test "generates canary deployment checklist" do
      checklist = OperationalDocs.generate_deployment_checklist(:canary)
      
      assert checklist.deployment_type == :canary
      
      # Canary specific steps
      steps = checklist.deployment_steps
      step_text = Enum.join(steps, " ")
      assert String.contains?(step_text, "canary")
      assert String.contains?(step_text, "traffic percentage")
    end
    
    test "includes comprehensive checklist items" do
      checklist = OperationalDocs.generate_deployment_checklist()
      
      # Pre-deployment should include health checks
      pre_text = Enum.join(checklist.pre_deployment, " ")
      assert String.contains?(pre_text, "health")
      assert String.contains?(pre_text, "backup")
      
      # Post-deployment should include verification
      post_text = Enum.join(checklist.post_deployment, " ")
      assert String.contains?(post_text, "verify")
      assert String.contains?(post_text, "logs")
    end
  end
  
  describe "generate_monitoring_docs/1" do
    test "generates comprehensive monitoring documentation" do
      docs = OperationalDocs.generate_monitoring_docs()
      
      assert is_binary(docs)
      assert String.contains?(docs, "# Aiex Monitoring and Observability Guide")
      assert String.contains?(docs, "## Metrics Overview")
      assert String.contains?(docs, "## Dashboards")
      assert String.contains?(docs, "## Alerting")
      assert String.contains?(docs, "## Distributed Tracing")
      assert String.contains?(docs, "## Logging")
      assert String.contains?(docs, "## Health Checks")
    end
    
    test "includes specific metric names" do
      docs = OperationalDocs.generate_monitoring_docs()
      
      # Should include actual Aiex metric names
      assert String.contains?(docs, "aiex_connected_nodes_total")
      assert String.contains?(docs, "aiex_memory_usage_bytes")
      assert String.contains?(docs, "aiex_process_count")
      assert String.contains?(docs, "aiex_llm_requests_total")
    end
    
    test "includes endpoint information" do
      docs = OperationalDocs.generate_monitoring_docs()
      
      # Should include actual endpoints
      assert String.contains?(docs, "/health/ready")
      assert String.contains?(docs, "/health/live")
      assert String.contains?(docs, "/metrics")
      assert String.contains?(docs, "9090")
      assert String.contains?(docs, "8080")
    end
  end
  
  describe "format handling" do
    test "handles invalid format gracefully" do
      # Should default to markdown for unknown formats
      result = OperationalDocs.generate_runbook(:invalid_format)
      
      # Should still generate something (likely defaulting to markdown)
      assert is_binary(result)
    end
  end
  
  describe "content validation" do
    test "runbook contains practical commands" do
      runbook = OperationalDocs.generate_runbook()
      
      # Should contain actual executable commands
      assert String.contains?(runbook, "./scripts/release-management.sh")
      assert String.contains?(runbook, "kubectl")
      assert String.contains?(runbook, "curl")
    end
    
    test "troubleshooting guide provides actionable solutions" do
      guide = OperationalDocs.generate_troubleshooting_guide()
      
      # Should provide specific solutions, not just descriptions
      assert String.contains?(guide, "kubectl rollout restart")
      assert String.contains?(guide, "kubectl scale")
      assert String.contains?(guide, "kubectl exec")
    end
    
    test "configuration reference includes real examples" do
      config = OperationalDocs.generate_config_reference()
      
      # Should include actual configuration values
      assert String.contains?(config, ":ollama")
      assert String.contains?(config, "30_000")
      assert String.contains?(config, "prometheus_enabled:")
    end
  end
  
  describe "dynamic content generation" do
    test "includes current timestamp" do
      runbook = OperationalDocs.generate_runbook()
      
      # Should include current date/time
      current_year = Date.utc_today().year |> to_string()
      assert String.contains?(runbook, current_year)
    end
    
    test "adapts to current cluster state" do
      # This is harder to test without a full cluster setup
      # but we can verify the structure is correct
      runbook = OperationalDocs.generate_runbook()
      
      # Should attempt to include cluster information
      assert String.contains?(runbook, "Total Nodes")
      assert String.contains?(runbook, "Cluster Health")
    end
  end
end