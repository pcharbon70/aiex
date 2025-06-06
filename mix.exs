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
      extra_applications: [:logger],
      mod: {Aiex, []},
      env: [
        hammer_backend: Hammer.Backend.ETS,
        hammer_backend_config: [
          expiry_ms: 60_000,
          cleanup_interval_ms: 60_000
        ]
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:owl, "~> 0.12.0"},
      {:optimus, "~> 0.3.0"},
      {:finch, "~> 0.18.0"},
      {:hammer, "~> 6.1"},
      {:jason, "~> 1.4"}
    ]
  end

  defp escript do
    [
      main_module: Aiex.CLI
    ]
  end
end
