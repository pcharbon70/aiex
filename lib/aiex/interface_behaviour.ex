defmodule Aiex.InterfaceBehaviour do
  @moduledoc """
  Behavior defining the contract for all Aiex interfaces.

  This behavior ensures consistent interaction patterns across different
  interfaces (CLI, Phoenix LiveView, VS Code LSP) while leveraging the
  distributed OTP architecture.
  """

  @type interface_type :: :cli | :liveview | :lsp | :api | :tui | :web
  @type session_id :: String.t()
  @type user_id :: String.t() | nil
  @type request_id :: String.t()

  @type request :: %{
          id: request_id(),
          type: :completion | :analysis | :generation | :explanation | :refactor | :test_generation,
          content: String.t(),
          context: map(),
          options: keyword(),
          priority: :low | :normal | :high | :urgent
        }

  @type response :: %{
          id: request_id(),
          status: :success | :error | :partial,
          content: String.t() | map(),
          metadata: map()
        }

  @type interface_config :: %{
          type: interface_type(),
          session_id: session_id(),
          user_id: user_id(),
          capabilities: [atom()],
          settings: map()
        }

  @doc """
  Initialize the interface with configuration.
  Called when the interface starts.
  """
  @callback init(interface_config()) :: {:ok, term()} | {:error, term()}

  @doc """
  Handle incoming requests from the interface.
  Should return responses asynchronously when possible.
  """
  @callback handle_request(request(), term()) ::
              {:ok, response(), term()}
              | {:async, request_id(), term()}
              | {:error, term()}

  @doc """
  Handle streaming responses for long-running operations.
  Called when partial results are available.
  """
  @callback handle_stream(request_id(), term(), term()) ::
              {:continue, term()}
              | {:complete, response(), term()}
              | {:error, term()}

  @doc """
  Handle interface-specific events and notifications.
  """
  @callback handle_event(atom(), term(), term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Clean up interface resources.
  Called when the interface shuts down.
  """
  @callback terminate(term(), term()) :: :ok

  @doc """
  Get interface capabilities and current status.
  """
  @callback get_status(term()) :: %{
              capabilities: [atom()],
              active_requests: [request_id()],
              session_info: map(),
              health: :healthy | :degraded | :unhealthy
            }

  @doc """
  Handle interface configuration updates.
  Called when distributed configuration changes.
  """
  @callback handle_config_update(map(), term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Handle inter-interface communication.
  Enables interfaces to coordinate with each other.
  """
  @callback handle_interface_message(atom(), term(), term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Validate request before processing.
  Allows interface-specific validation logic.
  """
  @callback validate_request(request()) :: :ok | {:error, term()}

  @doc """
  Format response for interface-specific presentation.
  """
  @callback format_response(response(), term()) :: term()

  @optional_callbacks [
    handle_stream: 3,
    handle_event: 3,
    handle_config_update: 2,
    handle_interface_message: 3,
    validate_request: 1,
    format_response: 2
  ]
end
