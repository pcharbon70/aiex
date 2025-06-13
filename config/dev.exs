import Config

# Override libcluster for development - disable clustering to avoid errors
config :libcluster,
  topologies: []

# Development configuration
config :aiex,
  # Disable clustering for development - single node mode
  cluster_enabled: false,
  # TUI server configuration - using Mock TUI in development
  tui: [
    enabled: true,
    port: 9487
  ],
  llm: [
    default_provider: :openai,
    # Longer timeout for development
    timeout: 60_000,
    # Fewer retries for faster development feedback
    max_retries: 1
  ],
  context: [
    max_memory_mb: 50,
    # Less frequent persistence
    persistence_interval_ms: 10_000
  ],
  sandbox: [
    allowed_paths: [
      System.user_home!() <> "/code",
      System.user_home!() <> "/projects"
    ],
    audit_log_enabled: true
  ],
  
  # Enable developer tools in development
  dev_tools: [
    enabled: true,
    console_enabled: true
  ]

# Configure Phoenix for development
config :aiex, AiexWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "aiex_development_secret_key_base_that_should_be_changed_in_production",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:aiex, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:aiex, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading.
config :aiex, AiexWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/aiex_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for development helpers
config :aiex, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Include HEEx debug annotations as HTML comments in rendered markup
config :phoenix_live_view, :debug_heex_annotations, true

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false
