defmodule Aiex.NATS.Consumer do
  @moduledoc """
  Generic NATS message consumer that subscribes to subjects and routes messages
  to handler modules.

  Each consumer process subscribes to a specific NATS subject pattern and
  forwards received messages to a configured handler module for processing.
  """

  use GenServer
  require Logger

  defstruct [
    :subject,
    :handler,
    :subscription,
    :gnat_conn,
    message_count: 0
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Gets consumer statistics.
  """
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  @impl true
  def init(opts) do
    subject = Keyword.fetch!(opts, :subject)
    handler = Keyword.fetch!(opts, :handler)
    consumer_opts = Keyword.get(opts, :consumer_opts, [])

    state = %__MODULE__{
      subject: subject,
      handler: handler
    }

    # Wait for NATS connection and then subscribe
    send(self(), :subscribe)

    Logger.info("NATS Consumer initialized for subject: #{subject}")

    {:ok, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      subject: state.subject,
      handler: state.handler,
      message_count: state.message_count,
      connected: not is_nil(state.gnat_conn)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    case get_nats_connection() do
      {:ok, gnat_conn} ->
        case Gnat.sub(gnat_conn, self(), state.subject) do
          {:ok, subscription} ->
            Logger.info("Subscribed to NATS subject: #{state.subject}")

            {:noreply, %{state | gnat_conn: gnat_conn, subscription: subscription}}

          {:error, reason} ->
            Logger.error("Failed to subscribe to #{state.subject}: #{inspect(reason)}")
            schedule_retry()
            {:noreply, state}
        end

      {:error, :not_connected} ->
        Logger.debug("NATS not connected, retrying subscription for #{state.subject}")
        schedule_retry()
        {:noreply, state}
    end
  end

  def handle_info({:msg, %{topic: topic, body: body, reply_to: reply_to}}, state) do
    # Increment message counter
    new_state = %{state | message_count: state.message_count + 1}

    # Decode message
    case decode_message(body) do
      {:ok, decoded_data} ->
        # Create message context
        message_context = %{
          topic: topic,
          reply_to: reply_to,
          gnat_conn: state.gnat_conn,
          timestamp: System.system_time(:microsecond)
        }

        # Forward to handler
        handle_message(state.handler, decoded_data, message_context)

      {:error, reason} ->
        Logger.warning("Failed to decode message from #{topic}: #{inspect(reason)}")
        send_error_reply(reply_to, state.gnat_conn, "Invalid message format")
    end

    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("Consumer received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp get_nats_connection do
    case :global.whereis_name(:nats_conn) do
      :undefined -> {:error, :not_connected}
      pid when is_pid(pid) -> {:ok, pid}
    end
  end

  defp schedule_retry do
    Process.send_after(self(), :subscribe, 2_000)
  end

  defp decode_message(body) do
    try do
      decoded = Msgpax.unpack!(body)
      {:ok, decoded}
    rescue
      e -> {:error, e}
    end
  end

  defp handle_message(handler_module, data, context) do
    try do
      handler_module.handle_message(data, context)
    rescue
      e ->
        Logger.error("Handler #{handler_module} failed: #{inspect(e)}")
        send_error_reply(context.reply_to, context.gnat_conn, "Handler error: #{inspect(e)}")
    end
  end

  defp send_error_reply(nil, _gnat_conn, _error), do: :ok

  defp send_error_reply(reply_to, gnat_conn, error) do
    error_response = %{
      status: "error",
      message: error,
      timestamp: System.system_time(:microsecond)
    }

    encoded_response = Msgpax.pack!(error_response)
    Gnat.pub(gnat_conn, reply_to, encoded_response)
  end
end
