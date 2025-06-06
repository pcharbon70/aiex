defmodule Aiex.MixProject do
  use Mix.Project

  def project do
    [
      app: :aiex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:owl, "~> 0.12.0"},
      {:optimus, "~> 0.3.0"}
    ]
  end

  defp escript do
    [
      main_module: Aiex.CLI
    ]
  end
end
