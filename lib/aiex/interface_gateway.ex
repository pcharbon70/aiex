defmodule Aiex.InterfaceGateway do
  @moduledoc """
  Unified gateway for all Aiex interfaces to interact with the distributed system.
  
  This module provides a single entry point for CLI, LiveView, LSP, and other
  interfaces to access distributed context management, LLM coordination,
  and other Aiex services across the cluster.

  ## Overview

  The InterfaceGateway acts as a central coordination hub that:

  - Manages interface registration and lifecycle
  - Routes requests to appropriate distributed services
  - Handles event subscription and distribution
  - Provides cluster-wide status and monitoring
  - Ensures consistent behavior across all interface types

  ## Interface Registration

  Interfaces must implement the `Aiex.InterfaceBehaviour` and register with the gateway:

      config = %{
        type: :cli,
        session_id: "cli_session_123",
        user_id: nil,
        capabilities: [:text_output, :colored_output],
        settings: %{color: true, interactive: true}
      }

      {:ok, interface_id} = InterfaceGateway.register_interface(MyInterface, config)

  ## Request Processing

  The gateway supports different request types that are routed to appropriate services:

  - `:completion` - Routed to LLM ModelCoordinator
  - `:analysis` - Routed to Context DistributedEngine  
  - `:generation` - Routed to LLM ModelCoordinator
  - `:explanation` - Routed to LLM ModelCoordinator

  Example request:

      request = %{
        id: "req_123",
        type: :completion,
        content: "Explain this Elixir function",
        context: %{file_path: "lib/example.ex"},
        options: [model: "gpt-4", temperature: 0.3]
      }

      {:ok, request_id} = InterfaceGateway.submit_request(interface_id, request)

  ## Event System

  Interfaces can subscribe to events for real-time updates:

      InterfaceGateway.subscribe_events(interface_id, [
        :request_completed,
        :request_failed,
        :progress_update
      ])

  Events are automatically forwarded to subscribed interfaces via the
  `handle_event/3` callback in their behaviour implementation.

  ## Distributed Architecture

  The gateway leverages Aiex's distributed architecture:

  - Uses `Aiex.Events.EventBus` for cluster-wide event distribution
  - Coordinates with `Aiex.LLM.ModelCoordinator` for LLM requests
  - Integrates with `Aiex.Context.DistributedEngine` for code analysis
  - Provides cluster status aggregation across all nodes

  ## Examples

      # Get cluster-wide status
      status = InterfaceGateway.get_cluster_status()
      # => %{
      #   node: :node@host,
      #   interfaces: 3,
      #   active_requests: 5,
      #   llm_providers: %{...},
      #   cluster_nodes: [:node1@host, :node2@host]
      # }

      # Check request status
      {:ok, status} = InterfaceGateway.get_request_status(request_id)
      # => %{
      #   id: "req_123",
      #   status: :processing,
      #   interface_id: "cli_123",
      #   progress: 45
      # }
  """

  use GenServer
  require Logger
  
  alias Aiex.Context.DistributedEngine
  alias Aiex.LLM.ModelCoordinator
  alias Aiex.Events.EventBus

  @type interface_id :: String.t()
  @type session_id :: String.t()
  @type request_id :: String.t()

  defstruct [
    :node,
    :interfaces,
    :active_sessions,
    :request_registry,
    :event_subscriptions
  ]

  ## Client API

  @doc """
  Starts the interface gateway.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new interface with the gateway.
  """
  @doc type: :client
  @spec register_interface(module(), Aiex.InterfaceBehaviour.interface_config()) :: 
    {:ok, interface_id()} | {:error, term()}
  def register_interface(interface_module, config) do
    GenServer.call(__MODULE__, {:register_interface, interface_module, config})
  end

  @doc """
  Unregister an interface from the gateway.
  """
  @spec unregister_interface(interface_id()) :: :ok
  def unregister_interface(interface_id) do
    GenServer.call(__MODULE__, {:unregister_interface, interface_id})
  end

  @doc """
  Submit a request through the gateway to the distributed system.
  """
  @doc type: :client
  @spec submit_request(interface_id(), Aiex.InterfaceBehaviour.request()) :: 
    {:ok, request_id()} | {:error, term()}
  def submit_request(interface_id, request) do
    GenServer.call(__MODULE__, {:submit_request, interface_id, request})
  end

  @doc """
  Get the status of a request.
  """
  @spec get_request_status(request_id()) :: 
    {:ok, map()} | {:error, :not_found}
  def get_request_status(request_id) do
    GenServer.call(__MODULE__, {:get_request_status, request_id})
  end

  @doc """
  Subscribe to events for a specific interface.
  """
  @spec subscribe_events(interface_id(), [atom()]) :: :ok
  def subscribe_events(interface_id, event_types) do
    GenServer.call(__MODULE__, {:subscribe_events, interface_id, event_types})
  end

  @doc """
  Get cluster-wide status information.
  """
  @spec get_cluster_status() :: map()
  def get_cluster_status do
    GenServer.call(__MODULE__, :get_cluster_status)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    # Subscribe to relevant events
    EventBus.subscribe(:request_completed)
    EventBus.subscribe(:request_failed)
    EventBus.subscribe(:interface_event)
    
    state = %__MODULE__{
      node: node(),
      interfaces: %{},
      active_sessions: %{},
      request_registry: %{},
      event_subscriptions: %{}
    }
    
    Logger.info("Interface Gateway started on node #{node()}")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_interface, interface_module, config}, _from, state) do
    interface_id = generate_interface_id(config.type)
    
    interface_info = %{
      id: interface_id,
      module: interface_module,
      config: config,
      pid: self(),
      registered_at: DateTime.utc_now(),
      status: :active
    }
    
    new_interfaces = Map.put(state.interfaces, interface_id, interface_info)
    new_state = %{state | interfaces: new_interfaces}
    
    # Publish interface registration event
    EventBus.publish(:interface_registered, %{
      interface_id: interface_id,
      type: config.type,
      node: node()
    })
    
    Logger.info("Registered #{config.type} interface: #{interface_id}")
    {:reply, {:ok, interface_id}, new_state}
  end

  @impl true
  def handle_call({:unregister_interface, interface_id}, _from, state) do
    case Map.get(state.interfaces, interface_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      _interface_info ->
        new_interfaces = Map.delete(state.interfaces, interface_id)
        new_state = %{state | interfaces: new_interfaces}
        
        # Clean up associated sessions and subscriptions
        new_state = cleanup_interface_resources(interface_id, new_state)
        
        EventBus.publish(:interface_unregistered, %{
          interface_id: interface_id,
          node: node()
        })
        
        Logger.info("Unregistered interface: #{interface_id}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:submit_request, interface_id, request}, _from, state) do
    case Map.get(state.interfaces, interface_id) do
      nil ->
        {:reply, {:error, :interface_not_found}, state}
        
      interface_info ->
        request_id = generate_request_id()
        
        case process_request(request_id, request, interface_info, state) do
          {:ok, new_state} ->
            {:reply, {:ok, request_id}, new_state}
            
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_request_status, request_id}, _from, state) do
    case Map.get(state.request_registry, request_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      request_info ->
        status = %{
          id: request_id,
          status: request_info.status,
          created_at: request_info.created_at,
          updated_at: request_info.updated_at,
          interface_id: request_info.interface_id,
          progress: request_info.progress
        }
        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call({:subscribe_events, interface_id, event_types}, _from, state) do
    case Map.get(state.interfaces, interface_id) do
      nil ->
        {:reply, {:error, :interface_not_found}, state}
        
      _interface_info ->
        # Subscribe to each event type
        Enum.each(event_types, &EventBus.subscribe/1)
        
        subscriptions = Map.get(state.event_subscriptions, interface_id, [])
        new_subscriptions = Enum.uniq(subscriptions ++ event_types)
        
        new_event_subscriptions = Map.put(
          state.event_subscriptions, 
          interface_id, 
          new_subscriptions
        )
        
        new_state = %{state | event_subscriptions: new_event_subscriptions}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:get_cluster_status, _from, state) do
    cluster_status = %{
      node: node(),
      interfaces: map_size(state.interfaces),
      active_requests: map_size(state.request_registry),
      llm_providers: get_llm_provider_status(),
      context_engine: get_context_engine_status(),
      cluster_nodes: [node() | Node.list()]
    }
    
    {:reply, cluster_status, state}
  end

  @impl true
  def handle_info({:event, event_type, event_data}, state) do
    # Forward events to subscribed interfaces
    forward_event_to_interfaces(event_type, event_data, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp generate_interface_id(type) do
    timestamp = System.system_time(:microsecond)
    node_hash = :erlang.phash2(node(), 1000)
    "#{type}_#{node_hash}_#{timestamp}"
  end

  defp generate_request_id do
    timestamp = System.system_time(:microsecond)
    random = :rand.uniform(10000)
    "req_#{timestamp}_#{random}"
  end

  defp process_request(request_id, request, interface_info, state) do
    request_info = %{
      id: request_id,
      request: request,
      interface_id: interface_info.id,
      interface_type: interface_info.config.type,
      status: :processing,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      progress: 0
    }
    
    # Route request to appropriate service based on type
    case route_request(request, request_info) do
      {:ok, :async} ->
        new_registry = Map.put(state.request_registry, request_id, request_info)
        new_state = %{state | request_registry: new_registry}
        {:ok, new_state}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp route_request(request, request_info) do
    case request.type do
      :completion ->
        route_to_llm_coordinator(request, request_info)
        
      :analysis ->
        route_to_context_engine(request, request_info)
        
      :generation ->
        route_to_llm_coordinator(request, request_info)
        
      :explanation ->
        route_to_llm_coordinator(request, request_info)
        
      _ ->
        {:error, :unsupported_request_type}
    end
  end

  defp route_to_llm_coordinator(request, request_info) do
    # Submit to ModelCoordinator asynchronously
    Task.start(fn ->
      llm_request = %{
        messages: [%{role: :user, content: request.content}],
        model: request.options[:model],
        temperature: request.options[:temperature]
      }
      
      case ModelCoordinator.select_provider(llm_request, request.options) do
        {:ok, {provider, adapter}} ->
          # Simulate processing (in real implementation, would call LLM)
          :timer.sleep(100)
          
          response = %{
            id: request_info.id,
            status: :success,
            content: "Mock response from #{provider}",
            metadata: %{provider: provider, adapter: adapter}
          }
          
          EventBus.publish(:request_completed, %{
            request_id: request_info.id,
            response: response
          })
          
        {:error, reason} ->
          EventBus.publish(:request_failed, %{
            request_id: request_info.id,
            reason: reason
          })
      end
    end)
    
    {:ok, :async}
  end

  defp route_to_context_engine(request, request_info) do
    # Submit to DistributedEngine asynchronously
    Task.start(fn ->
      case DistributedEngine.analyze_code(request.content, request.context) do
        {:ok, analysis} ->
          response = %{
            id: request_info.id,
            status: :success,
            content: analysis,
            metadata: %{analysis_type: :code_structure}
          }
          
          EventBus.publish(:request_completed, %{
            request_id: request_info.id,
            response: response
          })
          
        {:error, reason} ->
          EventBus.publish(:request_failed, %{
            request_id: request_info.id,
            reason: reason
          })
      end
    end)
    
    {:ok, :async}
  end

  defp cleanup_interface_resources(interface_id, state) do
    # Remove associated sessions
    new_active_sessions = Map.reject(state.active_sessions, fn {_session_id, session_info} ->
      session_info.interface_id == interface_id
    end)
    
    # Remove event subscriptions
    new_event_subscriptions = Map.delete(state.event_subscriptions, interface_id)
    
    # Remove pending requests
    new_request_registry = Map.reject(state.request_registry, fn {_request_id, request_info} ->
      request_info.interface_id == interface_id
    end)
    
    %{state |
      active_sessions: new_active_sessions,
      event_subscriptions: new_event_subscriptions,
      request_registry: new_request_registry
    }
  end

  defp forward_event_to_interfaces(event_type, event_data, state) do
    # Find interfaces subscribed to this event type
    Enum.each(state.event_subscriptions, fn {interface_id, subscribed_events} ->
      if event_type in subscribed_events do
        case Map.get(state.interfaces, interface_id) do
          %{module: module, pid: pid} ->
            # Forward event to interface module
            send(pid, {:interface_event, event_type, event_data})
            
          nil ->
            Logger.warn("Interface #{interface_id} not found for event forwarding")
        end
      end
    end)
  end

  defp get_llm_provider_status do
    case Process.whereis(ModelCoordinator) do
      nil -> %{status: :not_available}
      _pid -> 
        try do
          ModelCoordinator.get_cluster_status()
        catch
          _, _ -> %{status: :error}
        end
    end
  end

  defp get_context_engine_status do
    case Process.whereis(DistributedEngine) do
      nil -> %{status: :not_available}
      _pid -> %{status: :available, node: node()}
    end
  end
end