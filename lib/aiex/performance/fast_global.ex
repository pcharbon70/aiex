defmodule Aiex.Performance.FastGlobal do
  @moduledoc """
  FastGlobal pattern implementation for frequently accessed hot data.
  
  Based on the Discord FastGlobal library pattern, this module provides
  ultra-fast access to globally shared data by using code generation
  to create module attributes that are loaded into the constant pool.
  
  This is ideal for configuration data, feature flags, and other
  frequently accessed but rarely changed data.
  """

  defmodule Storage do
    @moduledoc false
    use Agent

    def start_link(_opts) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def put(key, value) do
      Agent.update(__MODULE__, &Map.put(&1, key, value))
    end

    def get(key) do
      Agent.get(__MODULE__, &Map.get(&1, key))
    end

    def delete(key) do
      Agent.update(__MODULE__, &Map.delete(&1, key))
    end

    def all do
      Agent.get(__MODULE__, & &1)
    end
  end

  @doc """
  Stores a value in FastGlobal storage.
  
  The value is compiled into a module for zero-cost runtime access.
  
  ## Example
  
      FastGlobal.put(:feature_flags, %{new_ui: true, beta_features: false})
      FastGlobal.get(:feature_flags)
      #=> %{new_ui: true, beta_features: false}
  """
  def put(key, value) when is_atom(key) do
    # Store in agent for persistence
    Storage.put(key, value)
    
    # Generate and compile module
    compile_fast_global(key, value)
    
    # Broadcast update to cluster
    broadcast_update(key, value)
    
    :ok
  end

  @doc """
  Gets a value from FastGlobal storage.
  
  This is a zero-cost operation at runtime as it reads from
  the module's constant pool.
  """
  def get(key) when is_atom(key) do
    module = module_name(key)
    
    if Code.ensure_loaded?(module) do
      apply(module, :get, [])
    else
      # Fallback to storage if module not compiled yet
      Storage.get(key)
    end
  end

  @doc """
  Deletes a value from FastGlobal storage.
  """
  def delete(key) when is_atom(key) do
    Storage.delete(key)
    
    # Purge compiled module
    module = module_name(key)
    if Code.ensure_loaded?(module) do
      :code.purge(module)
      :code.delete(module)
    end
    
    # Broadcast deletion
    broadcast_delete(key)
    
    :ok
  end

  @doc """
  Lists all FastGlobal keys.
  """
  def keys do
    Storage.all() |> Map.keys()
  end

  @doc """
  Puts multiple values at once.
  
  ## Example
  
      FastGlobal.put_many(%{
        config: %{timeout: 5000},
        features: %{admin_panel: true}
      })
  """
  def put_many(map) when is_map(map) do
    Enum.each(map, fn {key, value} ->
      put(key, value)
    end)
  end

  @doc """
  Initializes FastGlobal with startup data.
  
  This should be called during application startup to preload
  frequently accessed data.
  """
  def initialize(data) when is_map(data) do
    put_many(data)
  end

  @doc """
  Benchmarks access time for a FastGlobal key vs other storage methods.
  """
  def benchmark(key) do
    unless get(key) do
      raise ArgumentError, "Key #{inspect(key)} not found in FastGlobal"
    end
    
    ets_table = :ets.new(:benchmark, [:set, :public])
    :ets.insert(ets_table, {key, get(key)})
    
    persistent_term_key = {__MODULE__, key}
    :persistent_term.put(persistent_term_key, get(key))
    
    scenarios = %{
      "FastGlobal.get" => fn -> get(key) end,
      "ETS lookup" => fn -> :ets.lookup(ets_table, key) end,
      "Process dictionary" => fn -> Process.get(key) end,
      "Persistent term" => fn -> :persistent_term.get(persistent_term_key) end,
      "Agent.get" => fn -> Storage.get(key) end
    }
    
    Benchee.run(scenarios, 
      time: 2,
      warmup: 1,
      memory_time: 1,
      formatters: [{Benchee.Formatters.Console, comparison: true}]
    )
    
    # Cleanup
    :ets.delete(ets_table)
    :persistent_term.erase(persistent_term_key)
  end

  # Private functions

  defp module_name(key) do
    :"#{__MODULE__}.FastGlobal_#{key}"
  end

  defp compile_fast_global(key, value) do
    module = module_name(key)
    
    # Generate module code
    quoted = quote do
      defmodule unquote(module) do
        @compile {:inline, get: 0}
        
        @value unquote(Macro.escape(value))
        
        def get, do: @value
      end
    end
    
    # Compile module
    Code.compiler_options(ignore_module_conflict: true)
    
    try do
      # Purge old version if exists
      if Code.ensure_loaded?(module) do
        :code.purge(module)
        :code.delete(module)
      end
      
      # Compile new version
      [{^module, _binary}] = Code.compile_quoted(quoted)
      
      :ok
    rescue
      error ->
        require Logger
        Logger.error("Failed to compile FastGlobal module: #{inspect(error)}")
        {:error, error}
    after
      Code.compiler_options(ignore_module_conflict: false)
    end
  end

  defp broadcast_update(key, value) do
    message = {:fast_global_update, node(), key, value}
    
    for node <- Node.list() do
      spawn(fn ->
        :rpc.call(node, __MODULE__, :handle_remote_update, [key, value], 5000)
      end)
    end
  end

  defp broadcast_delete(key) do
    message = {:fast_global_delete, node(), key}
    
    for node <- Node.list() do
      spawn(fn ->
        :rpc.call(node, __MODULE__, :handle_remote_delete, [key], 5000)
      end)
    end
  end

  @doc false
  def handle_remote_update(key, value) do
    # Store in local storage
    Storage.put(key, value)
    
    # Compile locally
    compile_fast_global(key, value)
    
    :ok
  end

  @doc false  
  def handle_remote_delete(key) do
    delete(key)
  end
end

defmodule Aiex.Performance.FastGlobal.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      Aiex.Performance.FastGlobal.Storage
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end