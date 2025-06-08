defmodule TestUserProjection do
  @moduledoc """
  Test projection for event sourcing tests.
  """
  
  @behaviour Aiex.Events.EventProjection
  
  def project(%{type: :user_created, data: data}) do
    {:ok, %{
      action: :insert,
      table: :user_profiles,
      data: data
    }}
  end
  
  def project(%{type: :user_updated, data: data}) do
    {:ok, %{
      action: :update,
      table: :user_profiles,
      data: data
    }}
  end
  
  def project(%{type: :user_deleted}) do
    {:ok, %{
      action: :delete,
      table: :user_profiles,
      data: %{}
    }}
  end
  
  def project(_event), do: {:ok, :ignore}
end