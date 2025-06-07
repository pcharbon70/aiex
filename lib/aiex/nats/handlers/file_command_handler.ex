defmodule Aiex.NATS.Handlers.FileCommandHandler do
  @moduledoc """
  Handles file-related commands from the Rust TUI via NATS.
  
  This handler processes commands like file open, save, list, and integrates
  with the sandbox system for secure file operations.
  """
  
  require Logger
  alias Aiex.Sandbox
  
  @behaviour Aiex.NATS.MessageHandler
  
  @impl true
  def handle_message(data, context) do
    case data do
      %{"action" => action, "path" => path} = command ->
        handle_file_command(action, path, command, context)
        
      _ ->
        send_error_response(context, "Invalid file command format")
    end
  end
  
  defp handle_file_command("open", path, _command, context) do
    case Sandbox.read_file(path) do
      {:ok, content} ->
        response = %{
          status: "success",
          action: "file_opened",
          path: path,
          content: content,
          size: byte_size(content)
        }
        send_response(context, response)
        
      {:error, reason} ->
        send_error_response(context, "Failed to open file: #{inspect(reason)}")
    end
  end
  
  defp handle_file_command("save", path, %{"content" => content}, context) do
    case Sandbox.write_file(path, content) do
      :ok ->
        response = %{
          status: "success",
          action: "file_saved",
          path: path,
          size: byte_size(content)
        }
        send_response(context, response)
        
      {:error, reason} ->
        send_error_response(context, "Failed to save file: #{inspect(reason)}")
    end
  end
  
  defp handle_file_command("list", path, _command, context) do
    case Sandbox.list_directory(path) do
      {:ok, entries} ->
        response = %{
          status: "success",
          action: "directory_listed",
          path: path,
          entries: entries
        }
        send_response(context, response)
        
      {:error, reason} ->
        send_error_response(context, "Failed to list directory: #{inspect(reason)}")
    end
  end
  
  defp handle_file_command("create", path, command, context) do
    file_type = Map.get(command, "type", "file")
    
    case file_type do
      "file" ->
        case Sandbox.write_file(path, "") do
          :ok ->
            response = %{
              status: "success",
              action: "file_created",
              path: path,
              type: "file"
            }
            send_response(context, response)
            
          {:error, reason} ->
            send_error_response(context, "Failed to create file: #{inspect(reason)}")
        end
        
      "directory" ->
        case Sandbox.create_directory(path) do
          :ok ->
            response = %{
              status: "success",
              action: "directory_created",
              path: path,
              type: "directory"
            }
            send_response(context, response)
            
          {:error, reason} ->
            send_error_response(context, "Failed to create directory: #{inspect(reason)}")
        end
        
      _ ->
        send_error_response(context, "Unknown file type: #{file_type}")
    end
  end
  
  defp handle_file_command(action, _path, _command, context) do
    send_error_response(context, "Unknown file action: #{action}")
  end
  
  defp send_response(%{reply_to: nil}, _response) do
    # No reply requested
    :ok
  end
  
  defp send_response(%{reply_to: reply_to, gnat_conn: gnat_conn}, response) do
    enriched_response = Map.put(response, :timestamp, System.system_time(:microsecond))
    encoded_response = Msgpax.pack!(enriched_response)
    
    case Gnat.pub(gnat_conn, reply_to, encoded_response) do
      :ok ->
        Logger.debug("Sent file command response to #{reply_to}")
        
      {:error, reason} ->
        Logger.warning("Failed to send response: #{inspect(reason)}")
    end
  end
  
  defp send_error_response(context, error_message) do
    error_response = %{
      status: "error",
      message: error_message,
      timestamp: System.system_time(:microsecond)
    }
    
    send_response(context, error_response)
  end
end