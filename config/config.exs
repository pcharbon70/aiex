import Config

# Configure Hammer rate limiting backend
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       expiry_ms: 60_000,
       cleanup_interval_ms: 60_000
     ]}

# Configure Finch HTTP client
config :aiex, AiexFinch,
  pools: %{
    default: [size: 25, timeout: 30_000]
  }

# Application-specific configuration
config :aiex,
  # LLM configuration
  llm: [
    default_provider: :openai,
    timeout: 30_000,
    max_retries: 3
  ],
  # Context engine configuration
  context: [
    max_memory_mb: 100,
    persistence_interval_ms: 5_000
  ],
  # Sandbox configuration
  sandbox: [
    allowed_paths: [],
    audit_log_enabled: true
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
