import Config

# Production configuration
config :aiex,
  llm: [
    default_provider: :openai,
    timeout: 30_000,
    max_retries: 3
  ],
  context: [
    max_memory_mb: 200,
    # More frequent persistence
    persistence_interval_ms: 1_000
  ],
  sandbox: [
    # Empty by default, must be configured by user
    allowed_paths: [],
    audit_log_enabled: true
  ]

# Configure logger for production
config :logger,
  level: :info,
  backends: [:console]
