defmodule Aiex.Telemetry.PrometheusExporterTest do
  use ExUnit.Case, async: false
  
  alias Aiex.Telemetry.{PrometheusExporter, DistributedAggregator}
  
  @test_port 9091
  
  setup do
    # Start dependencies
    {:ok, _aggregator} = DistributedAggregator.start_link()
    {:ok, _exporter} = PrometheusExporter.start_link(port: @test_port)
    
    on_exit(fn ->
      if Process.whereis(PrometheusExporter) do
        GenServer.stop(PrometheusExporter)
      end
      if Process.whereis(DistributedAggregator) do
        GenServer.stop(DistributedAggregator)
      end
    end)
    
    :ok
  end
  
  describe "HTTP endpoints" do
    test "metrics endpoint returns Prometheus format" do
      # Record some test metrics
      DistributedAggregator.record_metric("test.counter", 42)
      DistributedAggregator.sync_cluster_metrics()
      Process.sleep(200)
      
      # Make HTTP request to metrics endpoint
      {:ok, {status, _headers, body}} = :httpc.request("http://localhost:#{@test_port}/metrics")
      
      assert status == {200, 'OK'}
      assert String.contains?(to_string(body), "aiex_node_info")
      assert String.contains?(to_string(body), "# HELP")
      assert String.contains?(to_string(body), "# TYPE")
    end
    
    test "health endpoint returns JSON status" do
      {:ok, {status, _headers, body}} = :httpc.request("http://localhost:#{@test_port}/health")
      
      assert status == {200, 'OK'}
      
      {:ok, json} = Jason.decode(to_string(body))
      assert json["status"] == "healthy"
    end
    
    test "unknown endpoints return 404" do
      {:ok, {status, _headers, _body}} = :httpc.request("http://localhost:#{@test_port}/unknown")
      
      assert status == {404, 'Not Found'}
    end
  end
  
  describe "metrics collection" do
    test "system collector provides basic metrics" do
      metrics = PrometheusExporter.SystemCollector.collect()
      
      assert is_list(metrics)
      assert length(metrics) > 0
      
      # Check for required system metrics
      metric_names = Enum.map(metrics, & &1.name)
      assert "aiex_node_info" in metric_names
      assert "aiex_connected_nodes_total" in metric_names
      assert "aiex_memory_usage_bytes" in metric_names
      assert "aiex_process_count" in metric_names
    end
    
    test "custom collector can be registered" do
      defmodule TestCollector do
        def collect do
          [%{
            name: "test_custom_metric",
            help: "A test metric",
            type: :gauge,
            value: 123,
            labels: %{test: "true"}
          }]
        end
      end
      
      PrometheusExporter.register_collector(TestCollector)
      
      metrics_text = PrometheusExporter.get_metrics_text()
      
      assert String.contains?(metrics_text, "test_custom_metric")
      assert String.contains?(metrics_text, "123")
      assert String.contains?(metrics_text, "test=\"true\"")
    end
  end
  
  describe "metrics formatting" do
    test "formats labels correctly" do
      exporter = PrometheusExporter
      
      # Test empty labels
      assert exporter.format_labels(%{}) == ""
      
      # Test single label
      formatted = exporter.format_labels(%{key: "value"})
      assert formatted == "{key=\"value\"}"
      
      # Test multiple labels
      formatted = exporter.format_labels(%{key1: "value1", key2: "value2"})
      assert String.contains?(formatted, "key1=\"value1\"")
      assert String.contains?(formatted, "key2=\"value2\"")
      assert String.starts_with?(formatted, "{")
      assert String.ends_with?(formatted, "}")
    end
    
    test "escapes label values" do
      exporter = PrometheusExporter
      
      formatted = exporter.format_labels(%{key: "value with \"quotes\" and \\backslashes"})
      assert String.contains?(formatted, "\\\"")
      assert String.contains?(formatted, "\\\\")
    end
  end
end