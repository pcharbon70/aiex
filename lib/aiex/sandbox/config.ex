defmodule Aiex.Sandbox.Config do
  @moduledoc """
  Configuration management for the sandbox system.
  
  Manages sandbox roots, allowed paths, and security policies.
  """
  
  use GenServer
  
  @type t :: %__MODULE__{
    sandbox_roots: [String.t()],
    allowed_paths: [String.t()],
    follow_symlinks: boolean(),
    audit_enabled: boolean(),
    audit_level: :minimal | :normal | :verbose,
    max_file_size: pos_integer() | nil,
    allowed_extensions: [String.t()] | nil
  }
  
  defstruct [
    sandbox_roots: [],
    allowed_paths: [],
    follow_symlinks: false,
    audit_enabled: true,
    audit_level: :normal,
    max_file_size: nil,
    allowed_extensions: nil
  ]
  
  # Client API
  
  @doc """
  Starts the configuration server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets the current configuration.
  """
  @spec get(keyword()) :: {:ok, t()} | {:error, any()}
  def get(overrides \\ []) do
    try do
      config = GenServer.call(__MODULE__, :get_config)
      merged = merge_config(config, overrides)
      {:ok, merged}
    catch
      :exit, {:noproc, _} ->
        # Server not started, use defaults
        {:ok, merge_config(default(), overrides)}
    end
  end
  
  @doc """
  Updates the configuration.
  """
  @spec update(keyword() | (t() -> t())) :: :ok
  def update(updates) when is_list(updates) do
    GenServer.call(__MODULE__, {:update, updates})
  end
  
  def update(fun) when is_function(fun, 1) do
    GenServer.call(__MODULE__, {:update_with, fun})
  end
  
  @doc """
  Adds a path to the allowed paths list.
  """
  @spec add_allowed_path(String.t()) :: :ok
  def add_allowed_path(path) do
    canonical_path = Path.expand(path)
    update(fn config ->
      %{config | allowed_paths: Enum.uniq([canonical_path | config.allowed_paths])}
    end)
  end
  
  @doc """
  Removes a path from the allowed paths list.
  """
  @spec remove_allowed_path(String.t()) :: :ok
  def remove_allowed_path(path) do
    canonical_path = Path.expand(path)
    update(fn config ->
      %{config | allowed_paths: List.delete(config.allowed_paths, canonical_path)}
    end)
  end
  
  @doc """
  Adds a sandbox root directory.
  """
  @spec add_sandbox_root(String.t()) :: :ok
  def add_sandbox_root(path) do
    canonical_path = Path.expand(path)
    update(fn config ->
      %{config | sandbox_roots: Enum.uniq([canonical_path | config.sandbox_roots])}
    end)
  end
  
  @doc """
  Returns the default configuration.
  """
  @spec default() :: t()
  def default do
    %__MODULE__{
      sandbox_roots: [File.cwd!()],
      allowed_paths: [],
      follow_symlinks: false,
      audit_enabled: true,
      audit_level: :normal
    }
  end
  
  @doc """
  Loads configuration from a file.
  """
  @spec load_from_file(String.t()) :: {:ok, t()} | {:error, any()}
  def load_from_file(path) do
    with {:ok, content} <- File.read(path),
         {:ok, config_map} <- decode_config(content) do
      config = struct(__MODULE__, config_map)
      validate_config(config)
    end
  end
  
  @doc """
  Saves configuration to a file.
  """
  @spec save_to_file(String.t()) :: :ok | {:error, any()}
  def save_to_file(path) do
    with {:ok, config} <- get(),
         encoded <- encode_config(config) do
      File.write(path, encoded)
    end
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    config = case Keyword.get(opts, :config_file) do
      nil ->
        struct(__MODULE__, opts)
        
      file ->
        case load_from_file(file) do
          {:ok, loaded} -> merge_config(loaded, opts)
          _ -> struct(__MODULE__, opts)
        end
    end
    
    {:ok, config}
  end
  
  @impl true
  def handle_call(:get_config, _from, config) do
    {:reply, config, config}
  end
  
  @impl true
  def handle_call({:update, updates}, _from, config) do
    new_config = merge_config(config, updates)
    {:reply, :ok, new_config}
  end
  
  @impl true
  def handle_call({:update_with, fun}, _from, config) do
    new_config = fun.(config)
    {:reply, :ok, new_config}
  end
  
  # Private functions
  
  defp merge_config(%__MODULE__{} = config, overrides) do
    map = Map.from_struct(config)
    
    Enum.reduce(overrides, config, fn {key, value}, acc ->
      if Map.has_key?(map, key) do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end
  
  defp validate_config(%__MODULE__{} = config) do
    cond do
      config.sandbox_roots == [] and config.allowed_paths == [] ->
        {:error, "At least one sandbox root or allowed path must be configured"}
        
      config.audit_level not in [:minimal, :normal, :verbose] ->
        {:error, "Invalid audit level"}
        
      true ->
        {:ok, config}
    end
  end
  
  defp decode_config(content) do
    # Simple key-value format for now
    # Could be upgraded to TOML/JSON later
    config_map = content
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          decoded_value = decode_value(String.trim(key), String.trim(value))
          Map.put(acc, String.to_atom(key), decoded_value)
          
        _ ->
          acc
      end
    end)
    
    {:ok, config_map}
  end
  
  defp decode_value("sandbox_roots", value), do: String.split(value, ":", trim: true)
  defp decode_value("allowed_paths", value), do: String.split(value, ":", trim: true)
  defp decode_value("follow_symlinks", value), do: value == "true"
  defp decode_value("audit_enabled", value), do: value == "true"
  defp decode_value("audit_level", value), do: String.to_atom(value)
  defp decode_value("max_file_size", value), do: String.to_integer(value)
  defp decode_value("allowed_extensions", value), do: String.split(value, ",", trim: true)
  defp decode_value(_, value), do: value
  
  defp encode_config(%__MODULE__{} = config) do
    [
      "sandbox_roots=#{Enum.join(config.sandbox_roots, ":")}",
      "allowed_paths=#{Enum.join(config.allowed_paths, ":")}",
      "follow_symlinks=#{config.follow_symlinks}",
      "audit_enabled=#{config.audit_enabled}",
      "audit_level=#{config.audit_level}",
      if(config.max_file_size, do: "max_file_size=#{config.max_file_size}", else: nil),
      if(config.allowed_extensions, do: "allowed_extensions=#{Enum.join(config.allowed_extensions, ",")}", else: nil)
    ]
    |> Enum.filter(&(&1 != nil))
    |> Enum.join("\n")
  end
end