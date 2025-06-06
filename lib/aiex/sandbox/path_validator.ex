defmodule Aiex.Sandbox.PathValidator do
  @moduledoc """
  Provides secure path validation and canonicalization to prevent directory traversal attacks.
  
  This module ensures all file operations are constrained within designated sandbox boundaries
  and validates paths against security vulnerabilities.
  """
  
  @type validation_result :: {:ok, String.t()} | {:error, atom() | String.t()}
  
  @doc """
  Validates and canonicalizes a path, ensuring it's safe to access.
  
  Returns {:ok, canonical_path} if the path is valid, or {:error, reason} otherwise.
  """
  @spec validate_path(String.t(), keyword()) :: validation_result()
  def validate_path(path, opts \\ []) do
    with {:ok, expanded} <- expand_path(path),
         {:ok, canonical} <- canonicalize_path(expanded),
         :ok <- check_traversal_attempts(path, canonical),
         :ok <- check_symbolic_links(canonical, opts),
         :ok <- check_special_characters(canonical),
         :ok <- verify_within_sandbox(canonical, opts) do
      {:ok, canonical}
    end
  end
  
  @doc """
  Checks if a path is within the allowed sandbox boundaries.
  """
  @spec within_sandbox?(String.t(), String.t() | [String.t()]) :: boolean()
  def within_sandbox?(path, sandbox_root) when is_binary(sandbox_root) do
    within_sandbox?(path, [sandbox_root])
  end
  
  def within_sandbox?(path, sandbox_roots) when is_list(sandbox_roots) do
    canonical_path = Path.expand(path)
    
    Enum.any?(sandbox_roots, fn root ->
      canonical_root = Path.expand(root)
      String.starts_with?(canonical_path, canonical_root <> "/") or
        canonical_path == canonical_root
    end)
  end
  
  @doc """
  Validates a path is not attempting directory traversal.
  """
  @spec contains_traversal?(String.t()) :: boolean()
  def contains_traversal?(path) do
    # Check for various traversal patterns
    patterns = [
      ~r/\.\./,           # Basic parent directory
      ~r/\.\.\//,         # Parent directory with separator
      ~r/\\\\\.\./,       # Windows-style traversal (escaped backslashes)
      ~r/%2e%2e/i,        # URL-encoded traversal
      ~r/%252e%252e/i,    # Double URL-encoded
      ~r/\x00/,           # Null bytes
      ~r/[\x01-\x1f]/     # Control characters
    ]
    
    Enum.any?(patterns, &Regex.match?(&1, path))
  end
  
  @doc """
  Checks if a path contains potentially dangerous special characters.
  """
  @spec has_dangerous_characters?(String.t()) :: boolean()
  def has_dangerous_characters?(path) do
    # Check for characters that could be problematic
    dangerous_chars = [
      "\x00",  # Null byte
      "|",     # Pipe (command injection)
      ";",     # Semicolon (command separator)
      "&",     # Ampersand (command separator)
      "$",     # Dollar (variable expansion)
      "`",     # Backtick (command substitution)
      "\n",    # Newline
      "\r"     # Carriage return
    ]
    
    Enum.any?(dangerous_chars, &String.contains?(path, &1))
  end
  
  @doc """
  Normalizes a path by resolving . and .. components.
  """
  @spec normalize_path(String.t()) :: String.t()
  def normalize_path(path) do
    path
    |> Path.split()
    |> normalize_components([])
    |> Path.join()
  end
  
  # Private functions
  
  defp expand_path(path) do
    try do
      expanded = Path.expand(path)
      {:ok, expanded}
    rescue
      _ -> {:error, :invalid_path}
    end
  end
  
  defp canonicalize_path(path) do
    # Remove duplicate slashes and resolve relative components
    canonical = path
    |> String.replace(~r/\/+/, "/")
    |> normalize_path()
    
    {:ok, canonical}
  end
  
  defp check_traversal_attempts(original_path, canonical_path) do
    cond do
      contains_traversal?(original_path) ->
        {:error, :traversal_attempt}
      
      # Check if canonicalization changed the path significantly
      path_depth_changed?(original_path, canonical_path) ->
        {:error, :traversal_attempt}
        
      true ->
        :ok
    end
  end
  
  defp check_symbolic_links(path, opts) do
    follow_symlinks = Keyword.get(opts, :follow_symlinks, false)
    
    if follow_symlinks do
      :ok
    else
      case File.lstat(path) do
        {:ok, %File.Stat{type: :symlink}} ->
          {:error, :symlink_not_allowed}
        _ ->
          :ok
      end
    end
  end
  
  defp check_special_characters(path) do
    if has_dangerous_characters?(path) do
      {:error, :dangerous_characters}
    else
      :ok
    end
  end
  
  defp verify_within_sandbox(path, opts) do
    sandbox_roots = Keyword.get(opts, :sandbox_roots, [])
    
    if sandbox_roots == [] do
      # No sandbox configured, allow all paths (use with caution!)
      :ok
    else
      if within_sandbox?(path, sandbox_roots) do
        :ok
      else
        {:error, :outside_sandbox}
      end
    end
  end
  
  defp normalize_components([], []), do: ["/"]  # Return root if empty
  defp normalize_components([], acc), do: Enum.reverse(acc)
  
  defp normalize_components([".." | rest], [_ | acc]) do
    # Go up one directory
    normalize_components(rest, acc)
  end
  
  defp normalize_components([".." | rest], []) do
    # Can't go above root
    normalize_components(rest, [])
  end
  
  defp normalize_components(["." | rest], acc) do
    # Skip current directory references
    normalize_components(rest, acc)
  end
  
  defp normalize_components([component | rest], acc) do
    normalize_components(rest, [component | acc])
  end
  
  defp path_depth_changed?(original, canonical) do
    original_depth = original |> Path.split() |> Enum.count(&(&1 == ".."))
    canonical_parts = Path.split(canonical)
    
    # If we had .. in original but they're gone in canonical, traversal occurred
    original_depth > 0 and not Enum.any?(canonical_parts, &(&1 == ".."))
  end
end