defmodule AiexWeb.WebCase do
  @moduledoc """
  This module defines the test case to be used by tests that require
  setting up a connection and testing web functionality.

  Such tests rely on `Phoenix.ConnTest` and `Phoenix.LiveViewTest` and 
  import other functionality to make it easier to build common data 
  structures and query the data layer.

  Finally, if the test case interacts with the database, we enable the 
  SQL sandbox, so changes done to the database during the test are 
  rolled back at the end of the test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections and LiveViews
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import AiexWeb.WebCase

      # The default endpoint for testing
      @endpoint AiexWeb.Endpoint

      # Setup helper functions
      import AiexWeb.WebTestHelpers
    end
  end

  setup tags do
    # Start clean slate for each test
    start_supervised({Aiex.InterfaceGateway, []})
    start_supervised({Aiex.AI.Coordinators.ConversationManager, []})
    
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end