defmodule AiexWeb.Router do
  use AiexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AiexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AiexWeb do
    pipe_through :browser

    # Main AI assistant interface
    live "/", ChatLive.Index, :index
    live "/chat/:id", ChatLive.Show, :show
    
    # Code analysis and generation
    live "/analyze", AnalyzeLive.Index, :index
    live "/generate", GenerateLive.Index, :index
    
    # Session management
    live "/sessions", SessionLive.Index, :index
    live "/sessions/:id", SessionLive.Show, :show
  end

  # API routes for programmatic access
  scope "/api", AiexWeb do
    pipe_through :api
    
    post "/chat", ApiController, :chat
    post "/analyze", ApiController, :analyze
    post "/generate", ApiController, :generate
    post "/explain", ApiController, :explain
    post "/refactor", ApiController, :refactor
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:aiex, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AiexWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end