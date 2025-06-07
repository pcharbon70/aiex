defmodule Aiex.NATS.ConsumerSupervisor do
  @moduledoc """
  Supervisor for NATS message consumers that handle TUI commands and queries.
  
  This supervisor manages individual consumer processes that subscribe to
  different NATS subjects and route messages to appropriate handlers in
  the OTP application.
  """
  
  use DynamicSupervisor
  require Logger
  
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Starts a new consumer for a specific NATS subject pattern.
  """
  def start_consumer(subject_pattern, handler_module, opts \\ []) do
    consumer_spec = {
      Aiex.NATS.Consumer,
      [
        subject: subject_pattern,
        handler: handler_module,
        consumer_opts: opts
      ]
    }
    
    DynamicSupervisor.start_child(__MODULE__, consumer_spec)
  end
  
  @doc """
  Stops a consumer process.
  """
  def stop_consumer(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
  
  @doc """
  Lists all active consumers.
  """
  def list_consumers do
    DynamicSupervisor.which_children(__MODULE__)
  end
  
  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  
  @doc """
  Sets up default consumers for common TUI command patterns.
  """
  def setup_default_consumers do
    # TUI command consumers
    consumers = [
      {"tui.command.file.>", Aiex.NATS.Handlers.FileCommandHandler},
      {"tui.command.project.>", Aiex.NATS.Handlers.ProjectCommandHandler},
      {"tui.command.llm.>", Aiex.NATS.Handlers.LLMCommandHandler},
      {"tui.query.>", Aiex.NATS.Handlers.QueryHandler}
    ]
    
    Enum.each(consumers, fn {subject, handler} ->
      case start_consumer(subject, handler) do
        {:ok, pid} ->
          Logger.info("Started NATS consumer for #{subject}: #{inspect(pid)}")
          
        {:error, reason} ->
          Logger.error("Failed to start consumer for #{subject}: #{inspect(reason)}")
      end
    end)
  end
end