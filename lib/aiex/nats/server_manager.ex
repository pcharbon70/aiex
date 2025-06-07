defmodule Aiex.NATS.ServerManager do
  @moduledoc """
  Manages an embedded NATS server process lifecycle.
  
  This GenServer downloads (if needed) and manages a NATS server binary,
  allowing the OTP application to run with an embedded NATS instance
  instead of requiring an external server.
  """
  
  use GenServer
  require Logger
  
  @nats_version "2.10.7"
  @nats_download_base "https://github.com/nats-io/nats-server/releases/download"
  
  defstruct [
    :port,
    :data_dir,
    :server_port,
    :server_pid,
    :binary_path,
    :config_path,
    status: :stopped
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets the current server status.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end
  
  @doc """
  Gets the server configuration (host, port, etc).
  """
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end
  
  @doc """
  Stops the embedded NATS server.
  """
  def stop_server do
    GenServer.call(__MODULE__, :stop_server)
  end
  
  @doc """
  Restarts the embedded NATS server.
  """
  def restart_server do
    GenServer.call(__MODULE__, :restart_server)
  end
  
  ## Callbacks
  
  @impl true
  def init(opts) do
    # Get configuration
    config = build_config(opts)
    
    state = %__MODULE__{
      data_dir: config.data_dir,
      server_port: config.port,
      binary_path: config.binary_path,
      config_path: config.config_path
    }
    
    # Ensure directories exist
    ensure_directories(state)
    
    # Start the server
    send(self(), :start_server)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end
  
  def handle_call(:get_config, _from, state) do
    config = %{
      host: ~c"127.0.0.1",
      port: state.server_port,
      embedded: true
    }
    {:reply, config, state}
  end
  
  def handle_call(:stop_server, _from, state) do
    new_state = stop_nats_server(state)
    {:reply, :ok, new_state}
  end
  
  def handle_call(:restart_server, _from, state) do
    new_state = state
      |> stop_nats_server()
      |> start_nats_server()
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_info(:start_server, state) do
    case ensure_binary_exists(state) do
      {:ok, binary_path} ->
        new_state = %{state | binary_path: binary_path}
        |> write_config_file()
        |> start_nats_server()
        
        {:noreply, new_state}
        
      {:error, reason} ->
        Logger.error("Failed to ensure NATS binary exists: #{inspect(reason)}")
        {:noreply, %{state | status: :error}}
    end
  end
  
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    Logger.debug("NATS Server: #{String.trim(data)}")
    {:noreply, state}
  end
  
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("NATS server exited with status: #{status}")
    
    # Attempt to restart after a delay
    Process.send_after(self(), :start_server, 5_000)
    
    {:noreply, %{state | port: nil, status: :stopped}}
  end
  
  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.warning("NATS server port exited: #{inspect(reason)}")
    {:noreply, %{state | port: nil, status: :stopped}}
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    stop_nats_server(state)
    :ok
  end
  
  ## Private Functions
  
  defp build_config(opts) do
    app_config = Application.get_env(:aiex, :nats_server, [])
    config = Keyword.merge(app_config, opts)
    
    priv_dir = :code.priv_dir(:aiex) |> to_string()
    
    %{
      data_dir: Keyword.get(config, :data_dir, Path.join(priv_dir, "nats")),
      port: Keyword.get(config, :port, 4222),
      binary_path: Keyword.get(config, :binary_path, Path.join([priv_dir, "nats", "bin", "nats-server"])),
      config_path: Keyword.get(config, :config_path, Path.join([priv_dir, "nats", "config", "server.conf"])),
      cluster_name: Keyword.get(config, :cluster_name, "aiex-cluster"),
      store_dir: Keyword.get(config, :store_dir, Path.join([priv_dir, "nats", "data"]))
    }
  end
  
  defp ensure_directories(state) do
    # Create necessary directories
    dirs = [
      state.data_dir,
      Path.dirname(state.binary_path),
      Path.dirname(state.config_path),
      Path.join(state.data_dir, "data"),
      Path.join(state.data_dir, "logs")
    ]
    
    Enum.each(dirs, &File.mkdir_p!/1)
  end
  
  defp ensure_binary_exists(state) do
    if File.exists?(state.binary_path) do
      # Make sure it's executable
      File.chmod!(state.binary_path, 0o755)
      {:ok, state.binary_path}
    else
      download_nats_binary(state)
    end
  end
  
  defp download_nats_binary(state) do
    Logger.info("Downloading NATS server binary...")
    
    # Determine platform
    {os, arch} = detect_platform()
    
    # Build download URL
    filename = "nats-server-v#{@nats_version}-#{os}-#{arch}.tar.gz"
    url = "#{@nats_download_base}/v#{@nats_version}/#{filename}"
    
    # Download to temp file
    temp_file = Path.join(System.tmp_dir!(), filename)
    
    case download_file(url, temp_file) do
      :ok ->
        # Extract the binary
        extract_nats_binary(temp_file, state.binary_path)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp detect_platform do
    os = case :os.type() do
      {:unix, :darwin} -> "darwin"
      {:unix, :linux} -> "linux"
      {:win32, _} -> "windows"
      _ -> "linux"  # Default to linux
    end
    
    arch = case :erlang.system_info(:system_architecture) do
      arch when is_list(arch) ->
        arch_str = to_string(arch)
        cond do
          String.contains?(arch_str, "x86_64") or String.contains?(arch_str, "amd64") -> "amd64"
          String.contains?(arch_str, "aarch64") or String.contains?(arch_str, "arm64") -> "arm64"
          String.contains?(arch_str, "armv7") -> "arm7"
          String.contains?(arch_str, "386") -> "386"
          true -> "amd64"  # Default
        end
      _ -> "amd64"
    end
    
    {os, arch}
  end
  
  defp download_file(url, dest_path) do
    Logger.info("Downloading from #{url}...")
    
    # Ensure inets is started
    :inets.start()
    :ssl.start()
    
    case :httpc.request(:get, {String.to_charlist(url), []}, 
                       [{:timeout, 60_000}, {:connect_timeout, 10_000}], 
                       [{:body_format, :binary}, {:stream, dest_path}]) do
      {:ok, :saved_to_file} ->
        :ok
        
      {:ok, {{_, status, _}, _, _}} ->
        {:error, "HTTP #{status}"}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp extract_nats_binary(tar_path, dest_path) do
    Logger.info("Extracting NATS server binary...")
    
    # Ensure destination directory exists
    File.mkdir_p!(Path.dirname(dest_path))
    
    # Extract using tar command
    extract_dir = Path.dirname(dest_path)
    
    result = case System.cmd("tar", ["-xzf", tar_path, "-C", extract_dir, "--strip-components=1"]) do
      {_, 0} ->
        # Find the nats-server binary
        binary_name = Path.basename(dest_path)
        extracted_binary = Path.join(extract_dir, binary_name)
        
        if File.exists?(extracted_binary) do
          File.chmod!(extracted_binary, 0o755)
          {:ok, extracted_binary}
        else
          {:error, "Binary not found after extraction"}
        end
        
      {error, code} ->
        {:error, "Extraction failed (#{code}): #{error}"}
    end
    
    # Clean up temp file
    File.rm(tar_path)
    
    result
  end
  
  defp write_config_file(state) do
    config_content = """
    # NATS Server Configuration for Aiex
    # Auto-generated - do not edit manually
    
    port: #{state.server_port}
    
    http_port: #{state.server_port + 1000}
    
    # Logging
    log_file: "#{Path.join(state.data_dir, "logs/nats-server.log")}"
    log_size_limit: 10MB
    max_traced_msg_len: 10000
    
    # Performance
    max_payload: 8MB
    max_pending: 64MB
    max_connections: 64K
    
    # JetStream
    jetstream {
      store_dir: "#{Path.join(state.data_dir, "data")}"
      max_mem: 1GB
      max_file: 10GB
    }
    """
    
    File.write!(state.config_path, config_content)
    state
  end
  
  defp start_nats_server(state) do
    Logger.info("Starting embedded NATS server on port #{state.server_port}...")
    
    args = [
      "-c", state.config_path,
      "-DV"  # Debug and verbose for development
    ]
    
    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      args: args
    ]
    
    port = Port.open({:spawn_executable, state.binary_path}, port_opts)
    
    # Give NATS time to start
    Process.sleep(1000)
    
    Logger.info("NATS server started")
    
    %{state | port: port, status: :running}
  end
  
  defp stop_nats_server(%{port: nil} = state), do: state
  defp stop_nats_server(%{port: port} = state) do
    Logger.info("Stopping embedded NATS server...")
    
    # Try graceful shutdown first
    Port.command(port, <<3>>)  # Ctrl+C
    Process.sleep(500)
    
    # Force close if still running
    if Port.info(port) do
      Port.close(port)
    end
    
    %{state | port: nil, status: :stopped}
  end
end