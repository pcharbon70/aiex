import Config

# Development configuration
config :aiex,
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
