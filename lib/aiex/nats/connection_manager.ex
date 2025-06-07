defmodule Aiex.NATS.ConnectionManager do
  @moduledoc """
  Manages NATS server connection with robust reconnection logic and health monitoring.
  
  This GenServer maintains a persistent connection to the NATS server and provides
  connection pooling and automatic reconnection capabilities for the TUI integration.
  """
  
  use GenServer
  require Logger
  
  @reconnect_delay 1_000
  @max_reconnect_delay 30_000
  @connection_timeout 5_000
  
  defstruct [
    :connection_pid,
    :gnat_config,
    reconnect_attempts: 0,
    status: :disconnected
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets the current NATS connection PID.
  """
  def get_connection do
    GenServer.call(__MODULE__, :get_connection)
  end
  
  @doc """
  Gets the connection status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end
  
  @doc """
  Forces a reconnection attempt.
  """
  def reconnect do
    GenServer.cast(__MODULE__, :reconnect)
  end
  
  @impl true
  def init(opts) do
    config = build_config(opts)
    state = %__MODULE__{gnat_config: config}
    
    # Start connection attempt
    send(self(), :connect)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_connection, _from, %{connection_pid: pid, status: :connected} = state) do
    {:reply, {:ok, pid}, state}
  end
  
  def handle_call(:get_connection, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end
  
  def handle_call(:status, _from, %{status: status} = state) do
    {:reply, status, state}
  end
  
  @impl true
  def handle_cast(:reconnect, state) do
    send(self(), :connect)
    {:noreply, %{state | status: :connecting}}
  end
  
  @impl true
  def handle_info(:connect, state) do
    case connect_to_nats(state.gnat_config) do
      {:ok, pid} ->
        Logger.info("Connected to NATS server")
        Process.monitor(pid)
        
        # Register connection for other processes
        :global.register_name(:nats_conn, pid)
        
        {:noreply, %{state | 
          connection_pid: pid, 
          status: :connected,
          reconnect_attempts: 0
        }}
        
      {:error, reason} ->
        Logger.warning("Failed to connect to NATS: #{inspect(reason)}")
        schedule_reconnect(state.reconnect_attempts)
        
        {:noreply, %{state |
          status: :disconnected,
          reconnect_attempts: state.reconnect_attempts + 1
        }}
    end
  end
  
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{connection_pid: pid} = state) do
    Logger.warning("NATS connection lost: #{inspect(reason)}")
    
    # Unregister connection
    :global.unregister_name(:nats_conn)
    
    # Schedule reconnection
    send(self(), :connect)
    
    {:noreply, %{state |
      connection_pid: nil,
      status: :disconnected
    }}
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  defp connect_to_nats(config) do
    case Gnat.start_link(config) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp build_config(opts) do
    defaults = [
      host: '127.0.0.1',
      port: 4222,
      tcp_opts: [:binary, packet: :raw, active: false],
      connection_timeout: @connection_timeout
    ]
    
    Keyword.merge(defaults, opts)
  end
  
  defp schedule_reconnect(attempts) do
    delay = min(@reconnect_delay * :math.pow(2, attempts), @max_reconnect_delay)
    Process.send_after(self(), :connect, round(delay))
  end
end