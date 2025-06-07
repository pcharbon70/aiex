defmodule Mix.Tasks.Ai do
  @shortdoc "AI-powered development tools for Elixir"

  @moduledoc """
  AI-powered development tools for Elixir using the Aiex framework.

  Available tasks:

      mix ai.gen.module    Generate Elixir modules with AI assistance
      mix ai.explain       Explain Elixir code using AI analysis

  ## Getting Started

  1. Ensure you have at least one LLM provider configured:
     - Ollama (local): Install and run Ollama with a model
     - OpenAI: Set OPENAI_API_KEY environment variable
     - Anthropic: Set ANTHROPIC_API_KEY environment variable
     - LM Studio: Run LM Studio server locally

  2. Test your setup:
     
      mix ai.explain lib/aiex.ex

  ## Examples

      # Generate a new module
      mix ai.gen.module UserManager "manage user accounts with CRUD operations"

      # Explain existing code
      mix ai.explain lib/my_module.ex
      mix ai.explain lib/my_module.ex my_function

  ## Configuration

  You can configure default LLM settings in config/config.exs:

      config :aiex, :llm,
        default_adapter: :ollama,
        adapters: %{
          ollama: %{base_url: "http://localhost:11434"},
          openai: %{api_key: System.get_env("OPENAI_API_KEY")},
          anthropic: %{api_key: System.get_env("ANTHROPIC_API_KEY")}
        }

  Run `mix help TASK` for more information on specific tasks.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case args do
      [] ->
        show_overview()

      ["--help"] ->
        Mix.shell().info(@moduledoc)

      [task | _rest] ->
        Mix.shell().info("Unknown AI task: #{task}")
        Mix.shell().info("Run `mix ai` to see available tasks.")
        System.halt(1)
    end
  end

  defp show_overview do
    Mix.shell().info("""
    🤖 Aiex AI-Powered Development Tools

    Available tasks:
      mix ai.gen.module    Generate Elixir modules with AI assistance
      mix ai.explain       Explain Elixir code using AI analysis

    Quick start:
      mix ai.gen.module Calculator "basic arithmetic operations"
      mix ai.explain lib/aiex.ex

    For detailed help:
      mix help ai.gen.module
      mix help ai.explain

    Check provider status:
      iex -S mix
      iex> Aiex.LLM.ModelCoordinator.get_cluster_status()
    """)
  end
end
