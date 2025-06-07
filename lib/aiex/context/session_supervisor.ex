defmodule Aiex.Context.SessionSupervisor do
  @moduledoc """
  Distributed supervisor for context session processes using Horde.

  Provides automatic distribution of session processes across cluster nodes
  with fault tolerance and automatic migration on node failures.
  """

  use Horde.DynamicSupervisor
  require Logger

  @doc """
  Starts the distributed session supervisor.
  """
  def start_link(opts \\ []) do
    Horde.DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a new session process on the optimal node.
  """
  def start_session(session_id, user_id \\ nil) do
    child_spec = %{
      id: {:session, session_id},
      start: {Aiex.Context.Session, :start_link, [session_id, user_id]},
      restart: :transient,
      type: :worker
    }

    case Horde.DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started session #{session_id} on node #{node()}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Session #{session_id} already exists")
        {:ok, pid}

      error ->
        Logger.error("Failed to start session #{session_id}: #{inspect(error)}")
        error
    end
  end

  @doc """
  Stops a session process.
  """
  def stop_session(session_id) do
    case find_session_child(session_id) do
      {:ok, pid} ->
        Horde.DynamicSupervisor.terminate_child(__MODULE__, pid)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active sessions across the cluster.
  """
  def list_sessions do
    Horde.DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {id, pid, _type, _modules} ->
      case id do
        {:session, session_id} -> %{session_id: session_id, pid: pid, node: node(pid)}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Gets statistics about session distribution.
  """
  def stats do
    children = Horde.DynamicSupervisor.which_children(__MODULE__)

    %{
      total_sessions: length(children),
      local_sessions: count_local_sessions(children),
      node_distribution: get_node_distribution(children),
      cluster_nodes: [node() | Node.list()]
    }
  end

  ## Horde.DynamicSupervisor Callbacks

  @impl true
  def init(opts) do
    # Configure Horde for distributed supervision
    horde_options = [
      strategy: :one_for_one,
      distribution_strategy: Horde.UniformQuorumDistribution,
      members: get_cluster_members()
    ]

    merged_options = Keyword.merge(horde_options, opts)

    Logger.info(
      "Starting distributed session supervisor with options: #{inspect(merged_options)}"
    )

    Horde.DynamicSupervisor.init(merged_options)
  end

  ## Private Functions

  defp find_session_child(session_id) do
    Horde.DynamicSupervisor.which_children(__MODULE__)
    |> Enum.find_value(fn
      {{:session, ^session_id}, pid, _type, _modules} -> {:ok, pid}
      _ -> nil
    end)
    |> case do
      nil -> {:error, :not_found}
      result -> result
    end
  end

  defp count_local_sessions(children) do
    Enum.count(children, fn {_id, pid, _type, _modules} ->
      node(pid) == node()
    end)
  end

  defp get_node_distribution(children) do
    children
    |> Enum.group_by(fn {_id, pid, _type, _modules} -> node(pid) end)
    |> Enum.map(fn {node, sessions} -> {node, length(sessions)} end)
    |> Enum.into(%{})
  end

  defp get_cluster_members do
    cluster_nodes = [node() | Node.list()]

    Enum.map(cluster_nodes, fn node ->
      {Aiex.Context.SessionSupervisor, node}
    end)
  end
end
