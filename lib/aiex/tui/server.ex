defmodule Aiex.TUI.Server do
  @moduledoc """
  TCP server for TUI communication using MessagePack protocol.

  Provides a lightweight pub/sub system for the Rust TUI to connect to,
  replacing the need for an external NATS server.
  """

  use GenServer
  require Logger

  @default_port 9487
  @protocol_version 1

  defstruct [
    :listen_socket,
    :port,
    :acceptor_ref,
    clients: %{},
    subscriptions: %{},
    next_client_id: 1
  ]

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the server configuration (port, etc).
  """
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  @doc """
  Publishes a message to all subscribers of a topic.
  """
  def publish(topic, message) do
    GenServer.cast(__MODULE__, {:publish, topic, message})
  end

  @doc """
  Gets the list of connected clients.
  """
  def list_clients do
    GenServer.call(__MODULE__, :list_clients)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, @default_port)

    case :gen_tcp.listen(port, [
           :binary,
           active: false,
           reuseaddr: true,
           # 4-byte length prefix
           packet: 4
         ]) do
      {:ok, listen_socket} ->
        Logger.info("TUI Server listening on port #{port}")

        # Start accepting connections in a separate task
        pid = self()
        Task.start_link(fn -> acceptor_loop(listen_socket, pid) end)

        state = %__MODULE__{
          listen_socket: listen_socket,
          port: port,
          acceptor_ref: nil
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start TUI server: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    config = %{
      port: state.port,
      protocol_version: @protocol_version,
      connected_clients: map_size(state.clients)
    }

    {:reply, config, state}
  end

  def handle_call(:list_clients, _from, state) do
    clients =
      Enum.map(state.clients, fn {id, client} ->
        %{
          id: id,
          connected_at: client.connected_at,
          subscriptions: MapSet.to_list(client.subscriptions)
        }
      end)

    {:reply, clients, state}
  end

  @impl true
  def handle_cast({:publish, topic, message}, state) do
    # Find all clients subscribed to this topic
    subscribers = Map.get(state.subscriptions, topic, MapSet.new())

    # Prepare the message
    msg = %{
      type: "message",
      topic: topic,
      payload: message,
      timestamp: System.system_time(:microsecond)
    }

    encoded = Msgpax.pack!(msg)

    # Send to all subscribers
    Enum.each(subscribers, fn client_id ->
      case Map.get(state.clients, client_id) do
        %{socket: socket} ->
          case :gen_tcp.send(socket, encoded) do
            :ok ->
              :ok

            {:error, _reason} ->
              # Client disconnected, will be cleaned up by handle_info
              :ok
          end

        nil ->
          :ok
      end
    end)

    {:noreply, state}
  end

  def handle_cast({:client_message, client_id, message}, state) do
    state = handle_client_message(client_id, message, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:new_client, client_socket}, state) do
    # Set socket options
    :inet.setopts(client_socket, [{:active, true}, {:packet, 4}])

    # Add client to state
    client_id = state.next_client_id

    client = %{
      id: client_id,
      socket: client_socket,
      connected_at: DateTime.utc_now(),
      subscriptions: MapSet.new()
    }

    new_clients = Map.put(state.clients, client_id, client)

    Logger.info("TUI client #{client_id} connected")

    # Send welcome message
    welcome = %{
      type: "welcome",
      client_id: client_id,
      protocol_version: @protocol_version
    }

    :gen_tcp.send(client_socket, Msgpax.pack!(welcome))

    {:noreply, %{state | clients: new_clients, next_client_id: client_id + 1}}
  end

  def handle_info({:tcp, socket, data}, state) do
    # Find client by socket
    client_id =
      Enum.find_value(state.clients, fn {id, %{socket: s}} ->
        if s == socket, do: id
      end)

    if client_id do
      # Decode message
      case Msgpax.unpack(data) do
        {:ok, message} ->
          state = handle_client_message(client_id, message, state)
          {:noreply, state}

        {:error, reason} ->
          Logger.warning("Invalid message from client #{client_id}: #{inspect(reason)}")
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:tcp_closed, socket}, state) do
    # Find and remove client
    {client_id, state} = remove_client_by_socket(socket, state)

    if client_id do
      Logger.info("TUI client #{client_id} disconnected")
    end

    {:noreply, state}
  end

  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.warning("TCP error: #{inspect(reason)}")

    # Remove client
    {_client_id, state} = remove_client_by_socket(socket, state)

    {:noreply, state}
  end

  ## Private Functions

  defp handle_client_message(client_id, %{"type" => "subscribe", "topic" => topic}, state) do
    # Add subscription
    client = Map.get(state.clients, client_id)

    if client do
      # Update client subscriptions
      new_subscriptions = MapSet.put(client.subscriptions, topic)
      updated_client = %{client | subscriptions: new_subscriptions}
      new_clients = Map.put(state.clients, client_id, updated_client)

      # Update topic -> subscribers map
      topic_subs = Map.get(state.subscriptions, topic, MapSet.new())
      new_topic_subs = MapSet.put(topic_subs, client_id)
      new_subscriptions_map = Map.put(state.subscriptions, topic, new_topic_subs)

      # Send confirmation
      response = %{
        type: "subscribed",
        topic: topic
      }

      :gen_tcp.send(client.socket, Msgpax.pack!(response))

      Logger.debug("Client #{client_id} subscribed to #{topic}")

      %{state | clients: new_clients, subscriptions: new_subscriptions_map}
    else
      state
    end
  end

  defp handle_client_message(client_id, %{"type" => "unsubscribe", "topic" => topic}, state) do
    # Remove subscription
    client = Map.get(state.clients, client_id)

    if client do
      # Update client subscriptions
      new_subscriptions = MapSet.delete(client.subscriptions, topic)
      updated_client = %{client | subscriptions: new_subscriptions}
      new_clients = Map.put(state.clients, client_id, updated_client)

      # Update topic -> subscribers map
      topic_subs = Map.get(state.subscriptions, topic, MapSet.new())
      new_topic_subs = MapSet.delete(topic_subs, client_id)

      new_subscriptions_map =
        if MapSet.size(new_topic_subs) == 0 do
          Map.delete(state.subscriptions, topic)
        else
          Map.put(state.subscriptions, topic, new_topic_subs)
        end

      # Send confirmation
      response = %{
        type: "unsubscribed",
        topic: topic
      }

      :gen_tcp.send(client.socket, Msgpax.pack!(response))

      Logger.debug("Client #{client_id} unsubscribed from #{topic}")

      %{state | clients: new_clients, subscriptions: new_subscriptions_map}
    else
      state
    end
  end

  defp handle_client_message(client_id, %{"type" => "ping"}, state) do
    client = Map.get(state.clients, client_id)

    if client do
      response = %{
        type: "pong",
        timestamp: System.system_time(:microsecond)
      }

      :gen_tcp.send(client.socket, Msgpax.pack!(response))
    end

    state
  end

  defp handle_client_message(
         client_id,
         %{"type" => "request", "id" => request_id} = message,
         state
       ) do
    # Forward request to appropriate handler
    Task.start(fn ->
      handle_tui_request(client_id, request_id, message)
    end)

    state
  end

  defp handle_client_message(_client_id, message, state) do
    Logger.debug("Unhandled message type: #{inspect(message)}")
    state
  end

  defp handle_tui_request(client_id, request_id, %{"command" => command, "params" => params}) do
    # Route commands to appropriate modules
    response =
      case command do
        "file.list" ->
          # Example: List files in a directory
          %{status: "ok", files: ["file1.ex", "file2.ex"]}

        "project.info" ->
          # Example: Get project information
          %{status: "ok", name: "aiex", version: "0.1.0"}

        _ ->
          %{status: "error", error: "Unknown command: #{command}"}
      end

    # Send response
    msg = %{
      type: "response",
      id: request_id,
      result: response
    }

    GenServer.cast(__MODULE__, {:send_to_client, client_id, msg})
  end

  defp remove_client_by_socket(socket, state) do
    case Enum.find(state.clients, fn {_id, %{socket: s}} -> s == socket end) do
      {client_id, client} ->
        # Close socket
        :gen_tcp.close(socket)

        # Remove from clients map
        new_clients = Map.delete(state.clients, client_id)

        # Remove from all subscriptions
        new_subscriptions =
          Enum.reduce(client.subscriptions, state.subscriptions, fn topic, subs_map ->
            topic_subs = Map.get(subs_map, topic, MapSet.new())
            new_topic_subs = MapSet.delete(topic_subs, client_id)

            if MapSet.size(new_topic_subs) == 0 do
              Map.delete(subs_map, topic)
            else
              Map.put(subs_map, topic, new_topic_subs)
            end
          end)

        {client_id, %{state | clients: new_clients, subscriptions: new_subscriptions}}

      nil ->
        {nil, state}
    end
  end

  @impl true
  def handle_cast({:send_to_client, client_id, message}, state) do
    case Map.get(state.clients, client_id) do
      %{socket: socket} ->
        :gen_tcp.send(socket, Msgpax.pack!(message))

      nil ->
        :ok
    end

    {:noreply, state}
  end

  ## Private Functions - Acceptor Loop

  defp acceptor_loop(listen_socket, server_pid) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        # Notify the server about the new client
        send(server_pid, {:new_client, client_socket})

        # Continue accepting connections
        acceptor_loop(listen_socket, server_pid)

      {:error, reason} ->
        Logger.error("Accept failed: #{inspect(reason)}")
        # Retry after a delay
        Process.sleep(1000)
        acceptor_loop(listen_socket, server_pid)
    end
  end
end
