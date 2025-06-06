import Config

# Test configuration
config :aiex,
  llm: [
    default_provider: :openai,
    # Shorter timeout for tests
    timeout: 5_000,
    # No retries in tests
    max_retries: 0
  ],
  context: [
    max_memory_mb: 10,
    persistence_interval_ms: 1_000
  ],
  sandbox: [
    # Only allow /tmp in tests
    allowed_paths: ["/tmp"],
    # Disable audit logging in tests
    audit_log_enabled: false
  ]

# Configure Hammer with shorter intervals for tests
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       # Shorter expiry for tests
       expiry_ms: 1_000,
       cleanup_interval_ms: 500
     ]}
