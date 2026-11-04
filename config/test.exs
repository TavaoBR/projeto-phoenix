import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ledger, Ledger.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DB_HOST", "localhost"),
  database: "ledger_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 25

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ledger_web, LedgerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Lno58xcQQ34AYP+RweXI60Ts1yGemiDp9nuwUT7kt8Xad/raGUV211g2t0p5ZoS8",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Porta separada para não colidir com um servidor de dev rodando.
config :ledger_web, metrics_port: 9569

config :sentry, dsn: nil
