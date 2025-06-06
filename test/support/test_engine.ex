defmodule TestEngine do
  @moduledoc """
  Test helper for Context Engine operations.
  """

  def put(engine_pid, key, value, metadata \\ %{}) do
    GenServer.call(engine_pid, {:put, key, value, metadata})
  end

  def get(engine_pid, key) do
    GenServer.call(engine_pid, {:get, key})
  end

  def delete(engine_pid, key) do
    GenServer.call(engine_pid, {:delete, key})
  end

  def list_keys(engine_pid) do
    GenServer.call(engine_pid, :list_keys)
  end

  def stats(engine_pid) do
    GenServer.call(engine_pid, :stats)
  end

  def clear(engine_pid) do
    GenServer.call(engine_pid, :clear)
  end
end
