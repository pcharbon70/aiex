defmodule Aiex.Interfaces.CLIInterface do
  @moduledoc """
  CLI interface implementation using the InterfaceBehaviour.

  This module provides the CLI interface with the distributed Aiex system,
  handling command routing and response formatting for terminal display.
  """

  @behaviour Aiex.InterfaceBehaviour

  use GenServer
  require Logger

  alias Aiex.InterfaceGateway
  alias Aiex.CLI.Presenter

  defstruct [
    :interface_id,
    :config,
    :active_requests,
    :presenter_opts
  ]

  ## Client API

  @doc """
  Start the CLI interface with the gateway.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Execute a CLI command through the interface.
  """
  def execute_command(command, args, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_command, command, args, opts})
  end

  ## InterfaceBehaviour Callbacks

  @impl Aiex.InterfaceBehaviour
  def init(config) do
    # Register with the interface gateway
    case InterfaceGateway.register_interface(__MODULE__, config) do
      {:ok, interface_id} ->
        # Subscribe to relevant events
        InterfaceGateway.subscribe_events(interface_id, [
          :request_completed,
          :request_failed,
          :progress_update
        ])

        initial_state = %__MODULE__{
          interface_id: interface_id,
          config: config,
          active_requests: %{},
          presenter_opts: [
            color: true,
            progress: true,
            interactive: System.get_env("TERM") != nil
          ]
        }

        Logger.info("CLI interface initialized: #{interface_id}")
        {:ok, initial_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Aiex.InterfaceBehaviour
  def handle_request(request, state) do
    case InterfaceGateway.submit_request(state.interface_id, request) do
      {:ok, request_id} ->
        new_active_requests = Map.put(state.active_requests, request_id, request)
        new_state = %{state | active_requests: new_active_requests}

        {:async, request_id, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Aiex.InterfaceBehaviour
  def handle_stream(request_id, partial_response, state) do
    # Display streaming progress for CLI
    case Map.get(state.active_requests, request_id) do
      nil ->
        {:error, :request_not_found}

      request ->
        display_progress(request, partial_response, state.presenter_opts)
        {:continue, state}
    end
  end

  @impl Aiex.InterfaceBehaviour
  def handle_event(event_type, event_data, state) do
    case event_type do
      :request_completed ->
        handle_request_completion(event_data, state)

      :request_failed ->
        handle_request_failure(event_data, state)

      :progress_update ->
        handle_progress_update(event_data, state)

      _ ->
        {:ok, state}
    end
  end

  @impl Aiex.InterfaceBehaviour
  def terminate(reason, state) do
    if state.interface_id do
      InterfaceGateway.unregister_interface(state.interface_id)
    end

    Logger.info("CLI interface terminated: #{inspect(reason)}")
    :ok
  end

  @impl Aiex.InterfaceBehaviour
  def get_status(state) do
    %{
      capabilities: [:text_output, :colored_output, :progress_display],
      active_requests: Map.keys(state.active_requests),
      session_info: %{
        interface_id: state.interface_id,
        type: :cli,
        interactive: state.presenter_opts[:interactive]
      }
    }
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    config = %{
      type: :cli,
      session_id: generate_session_id(),
      # CLI doesn't track users
      user_id: nil,
      capabilities: [:text_output, :colored_output, :progress_display],
      settings: %{
        color: Keyword.get(opts, :color, true),
        progress: Keyword.get(opts, :progress, true),
        interactive: Keyword.get(opts, :interactive, true)
      }
    }

    init(config)
  end

  @impl true
  def handle_call({:execute_command, command, args, opts}, _from, state) do
    request = build_request_from_command(command, args, opts)

    case handle_request(request, state) do
      {:async, request_id, new_state} ->
        {:reply, {:ok, request_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:interface_event, event_type, event_data}, state) do
    case handle_event(event_type, event_data, state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp generate_session_id do
    timestamp = System.system_time(:microsecond)
    node_hash = :erlang.phash2(node(), 1000)
    "cli_#{node_hash}_#{timestamp}"
  end

  defp build_request_from_command(command, args, opts) do
    request_id = generate_request_id()

    {request_type, content} =
      case command do
        :analyze ->
          file_path = List.first(args)
          {:analysis, file_path || ""}

        :create ->
          module_name = List.first(args)
          description = Enum.at(args, 1, "")
          {:generation, "#{module_name}: #{description}"}

        :explain ->
          file_path = List.first(args)
          {:explanation, file_path || ""}

        _ ->
          {:completion, Enum.join(args, " ")}
      end

    %{
      id: request_id,
      type: request_type,
      content: content,
      context: %{
        command: command,
        args: args,
        cwd: File.cwd!()
      },
      options: opts
    }
  end

  defp handle_request_completion(event_data, state) do
    %{request_id: request_id, response: response} = event_data

    case Map.get(state.active_requests, request_id) do
      nil ->
        {:ok, state}

      request ->
        display_completion(request, response, state.presenter_opts)

        new_active_requests = Map.delete(state.active_requests, request_id)
        new_state = %{state | active_requests: new_active_requests}

        {:ok, new_state}
    end
  end

  defp handle_request_failure(event_data, state) do
    %{request_id: request_id, reason: reason} = event_data

    case Map.get(state.active_requests, request_id) do
      nil ->
        {:ok, state}

      _request ->
        display_error(reason, state.presenter_opts)

        new_active_requests = Map.delete(state.active_requests, request_id)
        new_state = %{state | active_requests: new_active_requests}

        {:ok, new_state}
    end
  end

  defp handle_progress_update(event_data, state) do
    %{request_id: request_id} = event_data

    case Map.get(state.active_requests, request_id) do
      nil ->
        {:ok, state}

      request ->
        display_progress(request, event_data, state.presenter_opts)
        {:ok, state}
    end
  end

  defp display_completion(request, response, presenter_opts) do
    case response.status do
      :success ->
        Presenter.success("Request completed", presenter_opts)
        Presenter.output(response.content, presenter_opts)

        if response.metadata do
          display_metadata(response.metadata, presenter_opts)
        end

      :error ->
        Presenter.error("Request failed: #{response.content}", presenter_opts)
    end
  end

  defp display_error(reason, presenter_opts) do
    error_message =
      case reason do
        :timeout -> "Request timed out"
        :no_available_providers -> "No LLM providers available"
        reason when is_binary(reason) -> reason
        reason -> "Unknown error: #{inspect(reason)}"
      end

    Presenter.error(error_message, presenter_opts)
  end

  defp display_progress(_request, progress_data, presenter_opts) do
    if presenter_opts[:progress] do
      progress = Map.get(progress_data, :progress, 0)
      message = Map.get(progress_data, :message, "Processing...")

      Presenter.progress(message, progress, presenter_opts)
    end
  end

  defp display_metadata(metadata, presenter_opts) do
    if presenter_opts[:interactive] do
      Presenter.info("Metadata:", presenter_opts)

      Enum.each(metadata, fn {key, value} ->
        Presenter.info("  #{key}: #{inspect(value)}", presenter_opts)
      end)
    end
  end

  defp generate_request_id do
    timestamp = System.system_time(:microsecond)
    random = :rand.uniform(10000)
    "cli_req_#{timestamp}_#{random}"
  end
end
