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

# Configure Phoenix
config :aiex, AiexWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: AiexWeb.ErrorHTML, json: AiexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Aiex.PubSub,
  live_view: [signing_salt: "jL3h9kM2"]

# Configure Phoenix generators
config :phoenix, :json_library, Jason

# Configure PubSub
config :aiex, Aiex.PubSub, name: Aiex.PubSub

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  aiex: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  aiex: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

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
  ],
  
  # Developer tools configuration
  dev_tools: [
    enabled: true,
    console_enabled: false  # Enable in dev/test environments
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
