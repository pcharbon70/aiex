import Config

# Production configuration
config :aiex,
  llm: [
    default_provider: System.get_env("LLM_DEFAULT_PROVIDER", "ollama") |> String.to_atom(),
    timeout: 30_000,
    max_retries: 3,
    distributed_coordination: System.get_env("LLM_DISTRIBUTED_COORDINATION", "true") == "true",
    provider_affinity: System.get_env("LLM_PROVIDER_AFFINITY", "local_preferred") |> String.to_atom()
  ],
  context: [
    max_memory_mb: 200,
    # More frequent persistence in production
    persistence_interval_ms: 1_000
  ],
  sandbox: [
    # Must be configured by user or environment
    allowed_paths: [],
    audit_log_enabled: System.get_env("AUDIT_LOGGING", "true") == "true"
  ],
  performance: [
    monitoring_enabled: System.get_env("PERFORMANCE_MONITORING_ENABLED", "true") == "true",
    dashboard_update_interval: String.to_integer(System.get_env("PERFORMANCE_DASHBOARD_UPDATE_INTERVAL", "5000")),
    benchmarking_enabled: System.get_env("BENCHMARKING_ENABLED", "true") == "true"
  ]

# Kubernetes-specific configuration
kubernetes_env = not is_nil(System.get_env("KUBERNETES_SERVICE_HOST"))

if kubernetes_env do
  # Configure libcluster for Kubernetes
  config :libcluster,
    topologies: [
      aiex_k8s: [
        strategy: Cluster.Strategy.Kubernetes.DNS,
        config: [
          service: System.get_env("SERVICE_NAME", "aiex-headless"),
          application_name: "aiex",
          polling_interval: 10_000
        ]
      ]
    ]
    
  # Enable clustering in Kubernetes
  config :aiex, cluster_enabled: true
end

# Configure Phoenix endpoint for production
config :aiex, AiexWeb.Endpoint,
  url: [host: System.get_env("HOST", "localhost"), port: 80],
  http: [
    port: String.to_integer(System.get_env("PORT", "4000")),
    transport_options: [socket_opts: [:inet6]]
  ],
  secret_key_base: System.get_env("SECRET_KEY_BASE") || 
    raise("SECRET_KEY_BASE environment variable is missing"),
  server: true

# Configure logger for production
log_level = System.get_env("LOG_LEVEL", "info") |> String.to_atom()

config :logger,
  level: log_level,
  backends: [:console]

# Configure structured logging if enabled
if System.get_env("STRUCTURED_LOGGING", "true") == "true" do
  config :logger, :console,
    format: {Jason, :encode},
    metadata: [:request_id, :user_id, :session_id]
end

# Configure SSL if certificates are provided
if System.get_env("TLS_CERT") && System.get_env("TLS_KEY") do
  config :aiex, AiexWeb.Endpoint,
    https: [
      port: String.to_integer(System.get_env("HTTPS_PORT", "4443")),
      cipher_suite: :strong,
      certfile: System.get_env("TLS_CERT"),
      keyfile: System.get_env("TLS_KEY")
    ]
end

# Configure Mnesia for distributed deployment
config :mnesia,
  dir: System.get_env("MNESIA_DIR", "./data/mnesia")

# Set Erlang/OTP configuration for production
if kubernetes_env do
  # Optimize for Kubernetes deployment
  config :kernel,
    inet_dist_listen_min: 9100,
    inet_dist_listen_max: 9200
    
  # Configure for container resource limits
  config :sasl,
    sasl_error_logger: false
end
