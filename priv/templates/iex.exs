# Enhanced IEx configuration for Aiex AI-powered development
# Copy this file to ~/.iex.exs to enable AI helpers in all IEx sessions

# Application configuration
Application.put_env(:elixir, :ansi_enabled, true)

# Import standard helpers
import_if_available(IEx.Helpers)

# Load Aiex AI helpers if available
if Code.ensure_loaded?(Aiex.IEx.Integration) do
  Aiex.IEx.Integration.load_helpers()
  
  # Set up convenient aliases
  alias Aiex.IEx.{Helpers, EnhancedHelpers}
  alias Aiex.CLI.InteractiveShell
  
  # Define shortcuts
  defmodule H do
    @moduledoc """
    Convenient AI helper shortcuts for IEx.
    """
    
    def ai(query), do: EnhancedHelpers.ai(query)
    def shell(opts \\ []), do: EnhancedHelpers.ai_shell(opts)
    def complete(code, opts \\ []), do: EnhancedHelpers.ai_complete(code, opts)
    def eval(code, opts \\ []), do: EnhancedHelpers.ai_eval(code, opts)
    def doc(target, opts \\ []), do: EnhancedHelpers.ai_doc(target, opts)
    def debug(target, opts \\ []), do: EnhancedHelpers.ai_debug(target, opts)
    def project(opts \\ []), do: EnhancedHelpers.ai_project(opts)
    def test(module, opts \\ []), do: EnhancedHelpers.ai_test_suggest(module, opts)
    def status(), do: Aiex.IEx.Integration.check_ai_status()
    def help(), do: Aiex.IEx.Integration.show_ai_help()
  end
  
  # Make shortcuts available globally
  import H
  
else
  IO.puts("""
  ⚠️  Aiex AI helpers not available in this session.
  
  To enable AI assistance:
  1. Make sure Aiex is compiled: mix compile
  2. Start IEx with the project: iex -S mix
  3. Or add Aiex to your Mix dependencies
  """)
end

# Custom IEx configuration
IEx.configure(
  colors: [
    syntax_colors: [
      number: :light_yellow,
      atom: :light_cyan,
      string: :light_black,
      boolean: :red,
      nil: [:magenta, :bright],
    ],
    ls_directory: :cyan,
    ls_device: :yellow,
    doc_code: :green,
    doc_inline_code: :magenta,
    doc_headings: [:cyan, :underline],
    doc_title: [:cyan, :bright, :underline],
  ],
  default_prompt: 
    "#{IO.ANSI.light_cyan}🤖 aiex#{IO.ANSI.reset}" <>
    "#{IO.ANSI.light_black}(#{IO.ANSI.reset}%counter#{IO.ANSI.light_black})>#{IO.ANSI.reset} ",
  alive_prompt: 
    "#{IO.ANSI.light_cyan}🤖 aiex#{IO.ANSI.reset}" <>
    "#{IO.ANSI.light_black}(#{IO.ANSI.reset}%node#{IO.ANSI.light_black})#{IO.ANSI.reset}" <>
    "#{IO.ANSI.light_black}(#{IO.ANSI.reset}%counter#{IO.ANSI.light_black})>#{IO.ANSI.reset} ",
  history_size: 1000,
  inspect: [
    pretty: true,
    limit: :infinity,
    width: 80
  ]
)

# Helpful startup message
defmodule IExStartup do
  def show_welcome do
    if Code.ensure_loaded?(Aiex) do
      IO.puts("""
      
      🤖 Welcome to Aiex AI-Enhanced IEx!
      #{String.duplicate("=", 50)}
      
      Quick AI Commands:
      • ai("your query")       - Ask AI anything
      • shell()                - Start AI shell
      • complete("code")       - Get completions
      • help()                 - Show all AI commands
      • status()               - Check AI systems
      
      Enhanced IEx Commands:
      • h(Module, :ai)         - AI-enhanced help
      • c("file.ex", :analyze) - Smart compilation
      
      Happy coding! 🚀
      #{String.duplicate("=", 50)}
      """)
    end
  end
end

# Show welcome message
IExStartup.show_welcome()

# Helper to quickly check what's loaded
if Code.ensure_loaded?(Aiex) do
  defmodule Quick do
    def modules, do: :application.get_key(:aiex, :modules)
    def apps, do: Application.loaded_applications() |> Enum.map(&elem(&1, 0))
    def nodes, do: [node() | Node.list()]
    def processes(name), do: Process.whereis(name) |> Process.info()
  end
end

# Auto-complete helpers
if Code.ensure_loaded?(IEx.Autocomplete) do
  # This would enhance autocomplete with AI suggestions in a real implementation
  # For now, just document the intention
  """
  Future enhancement: AI-powered autocomplete integration
  """
end