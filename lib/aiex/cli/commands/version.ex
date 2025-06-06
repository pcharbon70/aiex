defmodule Aiex.CLI.Commands.Version do
  @moduledoc """
  Version command handler showing application version and build information.
  """

  @behaviour Aiex.CLI.Commands.CommandBehaviour

  @impl true
  def execute({[:version], %Optimus.ParseResult{}}) do
    version = Application.spec(:aiex, :vsn) |> to_string()
    elixir_version = System.version()
    otp_version = System.otp_release()
    
    {:ok, {:info, "Aiex Version Information", %{
      "Aiex" => version,
      "Elixir" => elixir_version,
      "OTP" => otp_version,
      "Build" => build_info()
    }}}
  end

  defp build_info do
    case System.get_env("AIEX_BUILD_INFO") do
      nil -> "development"
      info -> info
    end
  end
end