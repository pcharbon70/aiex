defmodule Aiex.CLI.Commands.Shell do
  @moduledoc """
  Shell command handler for starting the interactive AI shell.
  
  Provides command-line interface to launch the enhanced AI shell with
  various configuration options and modes.
  """

  @behaviour Aiex.CLI.Commands.CommandBehaviour

  alias Aiex.CLI.InteractiveShell

  @impl true
  def execute({[:shell], %Optimus.ParseResult{options: options, flags: flags}}) do
    # Extract options
    project_dir = Map.get(options, :project_dir, System.cwd!())
    mode = String.to_atom(Map.get(options, :mode, "interactive"))
    save_session = Map.get(options, :save_session)
    
    # Extract flags
    no_auto_save = Map.get(flags, :no_auto_save, false)
    verbose = Map.get(flags, :verbose, false)
    
    # Validate project directory
    if !File.dir?(project_dir) do
      {:error, "Project directory does not exist: #{project_dir}"}
    else
    
    # Prepare shell settings
    settings = %{
      mode: mode,
      auto_save: not no_auto_save,
      verbose: verbose,
      save_session_file: save_session
    }
    
    shell_opts = [
      project_dir: project_dir,
      settings: settings
    ]
    
    if verbose do
      IO.puts("🚀 Starting AI shell with settings:")
      IO.puts("   Project Dir: #{project_dir}")
      IO.puts("   Mode: #{mode}")
      IO.puts("   Auto Save: #{not no_auto_save}")
      if save_session do
        IO.puts("   Session File: #{save_session}")
      end
      IO.puts("")
    end
    
    # Start the interactive shell
    case InteractiveShell.start(shell_opts) do
      :ok -> 
        {:ok, {:shell_completed, "AI shell session completed"}}
        
      {:error, :already_running} -> 
        {:error, "AI shell is already running. Use 'quit' to exit the current session first."}
        
      {:error, reason} -> 
        {:error, "Failed to start AI shell: #{reason}"}
    end
    end
  end

  @impl true
  def execute({[:shell], %Optimus.ParseResult{args: args}}) when map_size(args) > 0 do
    {:error, "Unknown shell subcommand. Use 'aiex help shell' for usage information."}
  end

  @impl true 
  def execute(_) do
    {:error, "Invalid shell command usage. Use 'aiex help shell' for usage information."}
  end
end