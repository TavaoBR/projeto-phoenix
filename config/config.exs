# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Configure Mix tasks and generators
config :ledger,
  ecto_repos: [Ledger.Repo]

config :ledger_events,
  amqp_url: "amqp://guest:guest@localhost:5672",
  relay_interval_ms: 1_000

config :ledger_web,
  ecto_repos: [Ledger.Repo],
  generators: [context_app: :ledger]

# Configures the endpoint
config :ledger_web, LedgerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: LedgerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ledger.PubSub,
  live_view: [signing_salt: "GMtWkn2a"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :remote_ip]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
