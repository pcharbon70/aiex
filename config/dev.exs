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
  ]
