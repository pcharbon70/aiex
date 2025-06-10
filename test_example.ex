defmodule TestExample do
  @moduledoc """
  A simple test module to demonstrate AI analysis capabilities.
  """

  def calculate_sum(a, b) do
    a + b
  end

  def complex_function(list) do
    list
    |> Enum.filter(fn x -> x > 0 end)
    |> Enum.map(fn x -> x * 2 end)
    |> Enum.reduce(0, fn x, acc -> x + acc end)
  end

  def factorial(0), do: 1
  def factorial(n) when n > 0 do
    n * factorial(n - 1)
  end
end