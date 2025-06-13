defmodule Aiex.DevTools.Supervisor do
  @moduledoc """
  Supervisor for Aiex distributed developer tools.
  
  Manages cluster inspection, debugging console, and operational documentation
  generation tools for distributed system debugging and operations.
  """
  
  use Supervisor
  require Logger
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Check if development tools should be enabled
    dev_tools_enabled = Application.get_env(:aiex, :dev_tools, [])[:enabled] || false
    console_enabled = Application.get_env(:aiex, :dev_tools, [])[:console_enabled] || false
    
    children = []
    
    # Always start ClusterInspector as it's used by other components
    children = [
      {Aiex.DevTools.ClusterInspector, []} | children
    ]
    
    # Conditionally start DebuggingConsole in development/test environments
    children = if console_enabled or Application.get_env(:aiex, :environment) in [:dev, :test] do
      [{Aiex.DevTools.DebuggingConsole, []} | children]
    else
      children
    end
    
    # Log configuration
    if dev_tools_enabled do
      Logger.info("Developer tools enabled")
      
      if console_enabled do
        Logger.info("Debugging console enabled - use Aiex.DevTools.DebuggingConsole.start_interactive/0")
      end
    else
      Logger.debug("Developer tools disabled")
    end
    
    # Note: OperationalDocs is a utility module with no state, so no GenServer needed
    
    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.init(children, opts)
  end
  
  @doc """
  Get status of all developer tools components.
  """
  def status do
    children = Supervisor.which_children(__MODULE__)
    
    %{
      supervisor: __MODULE__,
      children_count: length(children),
      components: Enum.map(children, fn {id, pid, type, modules} ->
        %{
          id: id,
          pid: pid,
          type: type,
          modules: modules,
          status: if(is_pid(pid) and Process.alive?(pid), do: :running, else: :not_running)
        }
      end),
      cluster_inspector: get_component_status(Aiex.DevTools.ClusterInspector),
      debugging_console: get_component_status(Aiex.DevTools.DebuggingConsole),
      operational_docs: :available  # Always available as utility functions
    }
  end
  
  @doc """
  Start interactive debugging console session.
  """
  def start_console do
    case Process.whereis(Aiex.DevTools.DebuggingConsole) do
      pid when is_pid(pid) ->
        Aiex.DevTools.DebuggingConsole.start_interactive()
      nil ->
        {:error, :console_not_running}
    end
  end
  
  @doc """
  Generate quick cluster health report.
  """
  def quick_health_report do
    case Process.whereis(Aiex.DevTools.ClusterInspector) do
      pid when is_pid(pid) ->
        Aiex.DevTools.ClusterInspector.health_report()
      nil ->
        {:error, :cluster_inspector_not_running}
    end
  end
  
  @doc """
  Generate operational runbook for current cluster state.
  """
  def generate_runbook(format \\ :markdown) do
    Aiex.DevTools.OperationalDocs.generate_runbook(format)
  end
  
  @doc """
  Generate troubleshooting guide with current cluster issues.
  """
  def generate_troubleshooting_guide(format \\ :markdown) do
    Aiex.DevTools.OperationalDocs.generate_troubleshooting_guide(format)
  end
  
  @doc """
  Get cluster overview from inspector.
  """
  def cluster_overview do
    case Process.whereis(Aiex.DevTools.ClusterInspector) do
      pid when is_pid(pid) ->
        Aiex.DevTools.ClusterInspector.cluster_overview()
      nil ->
        {:error, :cluster_inspector_not_running}
    end
  end
  
  @doc """
  Execute debugging console command programmatically.
  """
  def execute_command(command) do
    case Process.whereis(Aiex.DevTools.DebuggingConsole) do
      pid when is_pid(pid) ->
        Aiex.DevTools.DebuggingConsole.execute_command(command)
      nil ->
        {:error, :console_not_running}
    end
  end
  
  # Private helper functions
  
  defp get_component_status(module) do
    case Process.whereis(module) do
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          :running
        else
          :dead
        end
      nil ->
        :not_running
    end
  end
end