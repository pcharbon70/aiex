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

# Libcluster configuration for distributed deployment
# This will be overridden in dev.exs and test.exs
config :libcluster,
  topologies: [
    aiex_cluster: [
      # Kubernetes DNS-based discovery for production
      strategy: Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: "aiex-headless",
        application_name: "aiex",
        polling_interval: 10_000
      ]
    ]
  ]

# Application-specific configuration
config :aiex,
  # Clustering configuration
  # Set cluster_enabled: true in production for distributed deployment
  # Default: false (single-node mode for development)
  cluster_enabled: true,

  # Distributed cluster configuration (only used when cluster_enabled: true)
  cluster: [
    node_name: :aiex,
    discovery_strategy: :kubernetes_dns,
    heartbeat_interval: 5_000,
    node_recovery_timeout: 30_000
  ],
  # LLM configuration
  llm: [
    default_provider: :ollama,
    timeout: 30_000,
    max_retries: 3,
    distributed_coordination: true,
    provider_affinity: :local_preferred
  ],
  # Context engine configuration
  context: [
    max_memory_mb: 100,
    persistence_interval_ms: 5_000,
    distributed_sync: true,
    replication_factor: 2
  ],
  # Sandbox configuration
  sandbox: [
    allowed_paths: [],
    audit_log_enabled: true,
    distributed_audit: true
  ],
  # Interface gateway configuration
  interface_gateway: [
    max_concurrent_requests: 100,
    request_timeout: 60_000,
    event_buffer_size: 1000
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
