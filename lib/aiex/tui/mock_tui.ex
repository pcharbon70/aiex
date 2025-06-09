defmodule Aiex.TUI.MockTUI do
  @moduledoc """
  Mock TUI implementation for development when Ratatouille is not available.
  
  Provides the same API as the real TUI but outputs to console instead.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.TUI.Communication.OTPBridge
  alias Aiex.InterfaceGateway
  
  defstruct [
    :interface_id,
    :session_id,
    :messages,
    :context
  ]
  
  ## Public API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Simulates sending a message to the TUI.
  """
  def send_message(message) do
    GenServer.cast(__MODULE__, {:message, message})
  end
  
  @doc """
  Simulates updating TUI context.
  """
  def update_context(context) do
    GenServer.cast(__MODULE__, {:context_update, context})
  end
  
  @doc """
  Simulates AI response.
  """
  def ai_response(response) do
    GenServer.cast(__MODULE__, {:ai_response, response})
  end
  
  ## GenServer implementation
  
  @impl true
  def init(opts) do
    session_id = "mock_tui_#{System.unique_integer([:positive])}"
    
    # Register with InterfaceGateway
    interface_config = %{
      type: :mock_tui,
      session_id: session_id,
      user_id: nil,
      capabilities: [:text_input, :text_output, :console_output],
      settings: %{
        mock: true,
        console_output: true
      }
    }
    
    state = %__MODULE__{
      interface_id: nil,
      session_id: session_id,
      messages: [],
      context: %{}
    }
    
    case InterfaceGateway.register_interface(__MODULE__, interface_config) do
      {:ok, interface_id} ->
        Logger.info("Mock TUI registered with InterfaceGateway: #{interface_id}")
        
        # Register with OTP Bridge
        OTPBridge.register_tui(self())
        
        print_welcome()
        
        {:ok, %{state | interface_id: interface_id}}
        
      {:error, reason} ->
        Logger.error("Failed to register Mock TUI interface: #{reason}")
        {:ok, state}
    end
  end
  
  @impl true
  def handle_cast({:message, message}, state) do
    print_message("TUI MESSAGE", message)
    {:noreply, state}
  end
  
  def handle_cast({:context_update, context}, state) do
    print_message("CONTEXT UPDATE", context)
    new_state = %{state | context: Map.merge(state.context, context)}
    {:noreply, new_state}
  end
  
  def handle_cast({:ai_response, response}, state) do
    print_ai_response(response)
    
    message = %{
      role: :assistant,
      content: response.content,
      timestamp: DateTime.utc_now(),
      metadata: response
    }
    
    new_messages = state.messages ++ [message]
    {:noreply, %{state | messages: new_messages}}
  end
  
  @impl true
  def handle_info({:tui_message, message}, state) do
    print_message("OTP MESSAGE", message)
    {:noreply, state}
  end
  
  def handle_info({:context_update, context}, state) do
    print_message("CONTEXT UPDATE", context)
    {:noreply, state}
  end
  
  def handle_info({:ai_response, response}, state) do
    handle_cast({:ai_response, response}, state)
  end
  
  def handle_info(msg, state) do
    print_message("UNKNOWN MESSAGE", msg)
    {:noreply, state}
  end
  
  @impl true
  def terminate(reason, state) do
    if state.interface_id do
      InterfaceGateway.unregister_interface(state.interface_id)
    end
    
    OTPBridge.unregister_tui(self())
    print_message("TUI SHUTDOWN", reason)
    :ok
  end
  
  ## Private functions
  
  defp print_welcome do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("🤖 AIEX MOCK TUI - DEVELOPMENT MODE")
    IO.puts("📄 This is a console simulation of the TUI interface")
    IO.puts("🔧 Ratatouille TUI disabled due to build environment")
    IO.puts(String.duplicate("=", 60) <> "\n")
  end
  
  defp print_message(type, message) do
    timestamp = DateTime.utc_now() |> DateTime.to_string() |> String.slice(11, 8)
    
    IO.puts("┌─ [#{timestamp}] #{type}")
    
    formatted_message = case message do
      map when is_map(map) -> inspect(map, pretty: true, limit: :infinity)
      list when is_list(list) -> inspect(list, pretty: true, limit: :infinity)
      binary when is_binary(binary) -> binary
      other -> inspect(other)
    end
    
    # Add proper indentation
    indented = formatted_message
    |> String.split("\n")
    |> Enum.map(&("│ " <> &1))
    |> Enum.join("\n")
    
    IO.puts(indented)
    IO.puts("└─")
    IO.puts("")
  end
  
  defp print_ai_response(response) do
    IO.puts("\n" <> String.duplicate("─", 50))
    IO.puts("🤖 AI RESPONSE")
    IO.puts(String.duplicate("─", 50))
    
    IO.puts(response.content)
    
    if tokens = Map.get(response, :tokens_used) do
      IO.puts("\n💡 Tokens used: #{tokens}")
    end
    
    if time = Map.get(response, :response_time) do
      IO.puts("⚡ Response time: #{time}ms")
    end
    
    if provider = Map.get(response, :provider) do
      IO.puts("🔧 Provider: #{provider}")
    end
    
    IO.puts(String.duplicate("─", 50) <> "\n")
  end
end