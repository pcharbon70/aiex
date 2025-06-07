defmodule Aiex.Interfaces.LiveViewInterface do
  @moduledoc """
  Phoenix LiveView interface for real-time AI assistance.

  This module provides a web-based interface using Phoenix LiveView for real-time
  collaborative AI assistance with multi-user sessions and shared context.
  """

  @behaviour Aiex.InterfaceBehaviour

  use GenServer
  require Logger

  alias Aiex.InterfaceGateway
  alias Aiex.Events.EventBus

  defstruct [
    :interface_id,
    :config,
    :active_sessions,
    :shared_context,
    :collaboration_state
  ]

  ## Client API

  @doc """
  Start the LiveView interface.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new collaborative session.
  """
  def create_session(session_config) do
    GenServer.call(__MODULE__, {:create_session, session_config})
  end

  @doc """
  Join an existing session.
  """
  def join_session(session_id, user_info) do
    GenServer.call(__MODULE__, {:join_session, session_id, user_info})
  end

  @doc """
  Leave a session.
  """
  def leave_session(session_id, user_id) do
    GenServer.call(__MODULE__, {:leave_session, session_id, user_id})
  end

  @doc """
  Submit a request in a session context.
  """
  def submit_session_request(session_id, user_id, request) do
    GenServer.call(__MODULE__, {:submit_session_request, session_id, user_id, request})
  end

  ## InterfaceBehaviour Callbacks

  @impl true
  def init(config) do
    # Register with InterfaceGateway
    interface_config = %{
      type: :liveview,
      session_id: "liveview_main",
      user_id: nil,
      capabilities: [
        :real_time_collaboration,
        :multi_user_sessions,
        :shared_context,
        :streaming_responses,
        :file_uploads,
        :code_visualization
      ],
      settings: Map.get(config, :settings, %{})
    }

    case InterfaceGateway.register_interface(__MODULE__, interface_config) do
      {:ok, interface_id} ->
        state = %__MODULE__{
          interface_id: interface_id,
          config: interface_config,
          active_sessions: %{},
          shared_context: %{},
          collaboration_state: %{
            active_users: %{},
            cursor_positions: %{},
            selection_ranges: %{}
          }
        }

        # Subscribe to relevant events
        EventBus.subscribe(:context_updated)
        EventBus.subscribe(:request_completed)
        EventBus.subscribe(:request_failed)

        Logger.info("LiveView interface started with ID: #{interface_id}")
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_request(request, state) do
    # Process request with session context
    case validate_session_request(request, state) do
      :ok ->
        # Enhance request with collaborative context
        enhanced_request = enhance_request_with_session_context(request, state)
        
        case InterfaceGateway.submit_request(state.interface_id, enhanced_request) do
          {:ok, request_id} ->
            response = %{
              id: request.id,
              status: :async,
              request_id: request_id,
              metadata: %{
                session_id: request.context[:session_id],
                collaboration_enabled: true
              }
            }
            {:async, request_id, state}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_stream(request_id, partial_response, state) do
    # Broadcast streaming response to all session participants
    case find_session_for_request(request_id, state) do
      {:ok, session_id} ->
        broadcast_to_session(session_id, :stream_update, %{
          request_id: request_id,
          partial_response: partial_response
        }, state)

        case partial_response.status do
          :complete ->
            {:complete, partial_response, state}
          _ ->
            {:continue, state}
        end

      {:error, :not_found} ->
        {:continue, state}
    end
  end

  @impl true
  def handle_event(:context_updated, event_data, state) do
    # Update shared context and notify all sessions
    updated_context = Map.merge(state.shared_context, event_data.context)
    new_state = %{state | shared_context: updated_context}

    # Broadcast context update to all active sessions
    Enum.each(state.active_sessions, fn {session_id, _session_info} ->
      broadcast_to_session(session_id, :context_updated, event_data, new_state)
    end)

    {:ok, new_state}
  end

  def handle_event(:request_completed, event_data, state) do
    # Notify relevant session participants
    case find_session_for_request(event_data.request_id, state) do
      {:ok, session_id} ->
        broadcast_to_session(session_id, :request_completed, event_data, state)
      {:error, :not_found} ->
        :ok
    end
    {:ok, state}
  end

  def handle_event(event_type, event_data, state) do
    Logger.debug("LiveView interface received event: #{event_type}")
    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cleanup sessions and unregister interface
    Enum.each(state.active_sessions, fn {session_id, _session_info} ->
      cleanup_session(session_id, state)
    end)

    InterfaceGateway.unregister_interface(state.interface_id)
    :ok
  end

  @impl true
  def get_status(state) do
    %{
      capabilities: state.config.capabilities,
      active_requests: get_active_request_count(state),
      session_info: %{
        active_sessions: map_size(state.active_sessions),
        total_users: count_total_users(state),
        shared_context_size: map_size(state.shared_context)
      },
      health: determine_health(state)
    }
  end

  @impl true
  def handle_config_update(config_updates, state) do
    updated_config = Map.merge(state.config, config_updates)
    new_state = %{state | config: updated_config}

    # Notify all sessions of config changes
    Enum.each(state.active_sessions, fn {session_id, _session_info} ->
      broadcast_to_session(session_id, :config_updated, config_updates, new_state)
    end)

    {:ok, new_state}
  end

  @impl true
  def handle_interface_message(from_interface, message, state) do
    Logger.info("LiveView interface received message from #{from_interface}: #{inspect(message)}")
    
    case message do
      {:context_sync, context_data} ->
        # Sync context from other interfaces
        sync_context_from_interface(context_data, state)

      {:session_invite, session_info} ->
        # Handle session invitation from other interfaces
        handle_session_invitation(session_info, state)

      _ ->
        {:ok, state}
    end
  end

  @impl true
  def validate_request(request) do
    required_fields = [:id, :type, :content]
    
    case Enum.all?(required_fields, &Map.has_key?(request, &1)) do
      true -> :ok
      false -> {:error, :missing_required_fields}
    end
  end

  @impl true
  def format_response(response, state) do
    # Format response for LiveView consumption
    %{
      response | 
      metadata: Map.merge(response.metadata || %{}, %{
        interface: :liveview,
        collaborative: true,
        session_count: map_size(state.active_sessions)
      })
    }
  end

  ## GenServer Callbacks

  @impl true
  def handle_call({:create_session, session_config}, _from, state) do
    session_id = generate_session_id()
    
    session_info = %{
      id: session_id,
      created_at: DateTime.utc_now(),
      created_by: session_config[:user_id],
      participants: %{},
      shared_context: %{},
      settings: session_config[:settings] || %{}
    }

    new_sessions = Map.put(state.active_sessions, session_id, session_info)
    new_state = %{state | active_sessions: new_sessions}

    Logger.info("Created LiveView session: #{session_id}")
    {:reply, {:ok, session_id}, new_state}
  end

  def handle_call({:join_session, session_id, user_info}, _from, state) do
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session_info ->
        user_id = user_info[:id] || generate_user_id()
        
        updated_participants = Map.put(session_info.participants, user_id, %{
          id: user_id,
          name: user_info[:name],
          joined_at: DateTime.utc_now(),
          status: :active
        })

        updated_session = %{session_info | participants: updated_participants}
        updated_sessions = Map.put(state.active_sessions, session_id, updated_session)
        new_state = %{state | active_sessions: updated_sessions}

        # Broadcast user joined event
        broadcast_to_session(session_id, :user_joined, %{user: user_info}, new_state)

        Logger.info("User #{user_id} joined session #{session_id}")
        {:reply, {:ok, user_id}, new_state}
    end
  end

  def handle_call({:leave_session, session_id, user_id}, _from, state) do
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session_info ->
        updated_participants = Map.delete(session_info.participants, user_id)
        
        if map_size(updated_participants) == 0 do
          # Remove empty session
          updated_sessions = Map.delete(state.active_sessions, session_id)
          new_state = %{state | active_sessions: updated_sessions}
          Logger.info("Removed empty session #{session_id}")
          {:reply, :ok, new_state}
        else
          updated_session = %{session_info | participants: updated_participants}
          updated_sessions = Map.put(state.active_sessions, session_id, updated_session)
          new_state = %{state | active_sessions: updated_sessions}

          # Broadcast user left event
          broadcast_to_session(session_id, :user_left, %{user_id: user_id}, new_state)

          Logger.info("User #{user_id} left session #{session_id}")
          {:reply, :ok, new_state}
        end
    end
  end

  def handle_call({:submit_session_request, session_id, user_id, request}, _from, state) do
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session_info ->
        if Map.has_key?(session_info.participants, user_id) do
          # Add session context to request
          enhanced_request = %{
            request |
            context: Map.merge(request.context || %{}, %{
              session_id: session_id,
              user_id: user_id,
              shared_context: session_info.shared_context,
              collaboration_mode: true
            })
          }

          case handle_request(enhanced_request, state) do
            {:async, request_id, new_state} ->
              {:reply, {:ok, request_id}, new_state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          {:reply, {:error, :user_not_in_session}, state}
        end
    end
  end

  ## Private Functions

  defp validate_session_request(request, _state) do
    # Validate request has required session context
    case request.context[:session_id] do
      nil -> {:error, :missing_session_context}
      _session_id -> :ok
    end
  end

  defp enhance_request_with_session_context(request, state) do
    session_id = request.context[:session_id]
    session_info = Map.get(state.active_sessions, session_id)

    enhanced_context = Map.merge(request.context || %{}, %{
      shared_context: state.shared_context,
      session_participants: session_info.participants,
      collaboration_state: state.collaboration_state
    })

    %{request | context: enhanced_context}
  end

  defp find_session_for_request(_request_id, _state) do
    # In a real implementation, this would track request-to-session mapping
    {:error, :not_found}
  end

  defp broadcast_to_session(session_id, event_type, data, state) do
    case Map.get(state.active_sessions, session_id) do
      nil -> :ok
      session_info ->
        # In a real implementation, this would use Phoenix.PubSub
        # For now, we log the broadcast
        Logger.debug("Broadcasting #{event_type} to session #{session_id} (#{map_size(session_info.participants)} participants)")
        :ok
    end
  end

  defp cleanup_session(_session_id, _state) do
    # Cleanup session resources
    :ok
  end

  defp get_active_request_count(_state) do
    # In a real implementation, track active requests
    0
  end

  defp count_total_users(state) do
    state.active_sessions
    |> Enum.reduce(0, fn {_session_id, session_info}, acc ->
      acc + map_size(session_info.participants)
    end)
  end

  defp determine_health(state) do
    cond do
      map_size(state.active_sessions) > 100 -> :degraded
      true -> :healthy
    end
  end

  defp sync_context_from_interface(context_data, state) do
    updated_context = Map.merge(state.shared_context, context_data)
    new_state = %{state | shared_context: updated_context}
    {:ok, new_state}
  end

  defp handle_session_invitation(session_info, state) do
    Logger.info("Received session invitation: #{inspect(session_info)}")
    {:ok, state}
  end

  defp generate_session_id do
    "lv_session_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generate_user_id do
    "user_" <> (:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower))
  end
end