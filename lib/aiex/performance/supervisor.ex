defmodule Aiex.Performance.Supervisor do
  @moduledoc """
  Supervisor for all performance monitoring and optimization components.
  
  Manages the lifecycle of performance analysis, benchmarking, and
  optimization services across the distributed cluster.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # FastGlobal storage for hot data
      Aiex.Performance.FastGlobal.Supervisor,
      
      # Distributed performance analyzer
      {Aiex.Performance.DistributedAnalyzer, []},
      
      # Distributed benchmarking coordinator
      {Aiex.Performance.DistributedBenchmarker, []},
      
      # Performance monitoring dashboard
      {Aiex.Performance.Dashboard, [update_interval: 5_000]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end