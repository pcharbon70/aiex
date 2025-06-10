defmodule AiexWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  during the test are rolled back at the end of the test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint AiexWeb.Endpoint

      use AiexWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import AiexWeb.ConnCase
    end
  end

  setup tags do
    # Application components should already be started by the main app
    # Just ensure we have a clean test environment
    
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end