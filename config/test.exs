import Config

# Disable libcluster for tests
config :libcluster,
  topologies: []

# Test configuration
config :aiex,
  # Disable clustering for tests - single node mode
  cluster_enabled: false,
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

# Configure Phoenix endpoint for testing
config :aiex, AiexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_characters_long_for_testing_purposes_only",
  server: false
