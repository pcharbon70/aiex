defmodule Aiex.Sandbox do
  @moduledoc """
  Provides secure file operations within designated sandbox boundaries.

  All file operations are validated, logged, and constrained to prevent
  unauthorized access to the file system.
  """

  alias Aiex.Sandbox.{PathValidator, Config, AuditLogger}

  @type file_result :: {:ok, any()} | {:error, atom() | String.t()}

  # File reading operations

  @doc """
  Reads a file within the sandbox boundaries.
  """
  @spec read(String.t(), keyword()) :: {:ok, binary()} | {:error, any()}
  def read(path, opts \\ []) do
    with {:ok, config} <- get_config(opts),
         {:ok, validated_path} <- validate_and_log(path, :read, config),
         result <- do_read(validated_path, opts) do
      log_result(validated_path, :read, result, config)
      result
    end
  end

  @doc """
  Reads a file and returns lines as a list.
  """
  @spec read_lines(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
  def read_lines(path, opts \\ []) do
    with {:ok, config} <- get_config(opts),
         {:ok, validated_path} <- validate_and_log(path, :read, config),
         {:ok, content} <- do_read(validated_path, opts) do
      lines = String.split(content, ~r/\r?\n/)
      result = {:ok, lines}
      log_result(validated_path, :read_lines, result, config)
      result
    else
      error ->
        log_result(path, :read_lines, error, get_config!(opts))
        error
    end
  end

  # File writing operations

  @doc """
  Writes content to a file within the sandbox boundaries.
  """
  @spec write(String.t(), iodata(), keyword()) :: :ok | {:error, any()}
  def write(path, content, opts \\ []) do
    with {:ok, config} <- get_config(opts),
         {:ok, validated_path} <- validate_and_log(path, :write, config),
         :ok <- ensure_parent_directory(validated_path),
         result <- do_write(validated_path, content, opts) do
      log_result(validated_path, :write, result, config)
      result
    end
  end

  @doc """
  Appends content to a file within the sandbox boundaries.
  """
  @spec append(String.t(), iodata(), keyword()) :: :ok | {:error, any()}
  def append(path, content, opts \\ []) do
    with {:ok, config} <- get_config(opts),
         {:ok, validated_path} <- validate_and_log(path, :append, config),
         :ok <- ensure_parent_directory(validated_path),
         result <- do_append(validated_path, content, opts) do
      log_result(validated_path, :append, result, config)
      result
    end
  end

  # Directory operations

  @doc """
  Lists files in a directory within the sandbox boundaries.
  """
  @spec list_dir(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, any()}
  def list_dir(path, opts \\ []) do
    with {:ok, config} <- get_config(opts),
         {:ok, validated_path} <- validate_and_log(path, :list_dir, config),
         result <- File.ls(validated_path) do
      log_result(validated_path, :list_dir, result, config)
      result
    end
  end

  @doc """
  Creates a directory within the sandbox boundaries.
  """
  @spec mkdir_p(String.t(), keyword()) :: :ok | {:error, any()}
  def mkdir_p(path, opts \\ []) do
    with {:ok, config} <- get_config(opts),
         {:ok, validated_path} <- validate_and_log(path, :mkdir_p, config),
         result <- File.mkdir_p(validated_path) do
      log_result(validated_path, :mkdir_p, result, config)
      result
    end
  end

  # File management operations

  @doc """
  Deletes a file within the sandbox boundaries.
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, any()}
  def delete(path, opts \\ []) do
    with {:ok, config} <- get_config(opts),
         {:ok, validated_path} <- validate_and_log(path, :delete, config),
         result <- File.rm(validated_path) do
      log_result(validated_path, :delete, result, config)
      result
    end
  end

  @doc """
  Copies a file within the sandbox boundaries.
  """
  @spec copy(String.t(), String.t(), keyword()) :: :ok | {:error, any()}
  def copy(source, destination, opts \\ []) do
    with {:ok, config} <- get_config(opts),
         {:ok, validated_source} <- validate_and_log(source, :copy_read, config),
         {:ok, validated_dest} <- validate_and_log(destination, :copy_write, config),
         :ok <- ensure_parent_directory(validated_dest),
         result <- File.cp(validated_source, validated_dest) do
      log_result({validated_source, validated_dest}, :copy, result, config)
      result
    end
  end

  @doc """
  Moves/renames a file within the sandbox boundaries.
  """
  @spec move(String.t(), String.t(), keyword()) :: :ok | {:error, any()}
  def move(source, destination, opts \\ []) do
    with {:ok, config} <- get_config(opts),
         {:ok, validated_source} <- validate_and_log(source, :move_read, config),
         {:ok, validated_dest} <- validate_and_log(destination, :move_write, config),
         :ok <- ensure_parent_directory(validated_dest),
         result <- File.rename(validated_source, validated_dest) do
      log_result({validated_source, validated_dest}, :move, result, config)
      result
    end
  end

  # File information

  @doc """
  Gets file information within the sandbox boundaries.
  """
  @spec stat(String.t(), keyword()) :: {:ok, File.Stat.t()} | {:error, any()}
  def stat(path, opts \\ []) do
    with {:ok, config} <- get_config(opts),
         {:ok, validated_path} <- validate_and_log(path, :stat, config),
         result <- File.stat(validated_path) do
      log_result(validated_path, :stat, result, config)
      result
    end
  end

  @doc """
  Checks if a file exists within the sandbox boundaries.
  """
  @spec exists?(String.t(), keyword()) :: boolean()
  def exists?(path, opts \\ []) do
    case stat(path, opts) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # Configuration management

  @doc """
  Adds a path to the sandbox allowlist.
  """
  @spec add_to_allowlist(String.t()) :: :ok
  def add_to_allowlist(path) do
    Config.add_allowed_path(path)
  end

  @doc """
  Removes a path from the sandbox allowlist.
  """
  @spec remove_from_allowlist(String.t()) :: :ok
  def remove_from_allowlist(path) do
    Config.remove_allowed_path(path)
  end

  @doc """
  Gets the current sandbox configuration.
  """
  @spec get_config(keyword()) :: {:ok, Config.t()} | {:error, any()}
  def get_config(opts \\ []) do
    Config.get(opts)
  end

  # Private functions

  defp get_config!(opts) do
    case get_config(opts) do
      {:ok, config} -> config
      _ -> Config.default()
    end
  end

  defp validate_and_log(path, operation, config) do
    validation_opts = [
      sandbox_roots: config.sandbox_roots ++ config.allowed_paths,
      follow_symlinks: config.follow_symlinks
    ]

    case PathValidator.validate_path(path, validation_opts) do
      {:ok, validated_path} ->
        AuditLogger.log_access_attempt(validated_path, operation, :allowed, config)
        {:ok, validated_path}

      {:error, reason} = error ->
        AuditLogger.log_access_attempt(path, operation, {:denied, reason}, config)
        error
    end
  end

  defp ensure_parent_directory(path) do
    parent = Path.dirname(path)
    File.mkdir_p(parent)
  end

  defp do_read(path, opts) do
    encoding = Keyword.get(opts, :encoding, :utf8)

    case File.read(path) do
      {:ok, content} when encoding == :utf8 ->
        # Ensure valid UTF-8
        case :unicode.characters_to_binary(content) do
          {:error, _, _} -> {:error, :invalid_encoding}
          {:incomplete, _, _} -> {:error, :invalid_encoding}
          binary -> {:ok, binary}
        end

      other ->
        other
    end
  end

  defp do_write(path, content, _opts) do
    File.write(path, content)
  end

  defp do_append(path, content, _opts) do
    File.write(path, content, [:append])
  end

  defp log_result(path, operation, result, config) do
    status =
      case result do
        :ok -> :success
        {:ok, _} -> :success
        {:error, reason} -> {:failed, reason}
      end

    AuditLogger.log_operation_result(path, operation, status, config)
  end
end
