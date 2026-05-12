import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :whistle, Whistle.Repo,
  username: "ref",
  password: "sql",
  port: 5438,
  hostname: "localhost",
  database: "ref_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :whistle, WhistleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "lCgxUK51FA2wEbEjC6n14lTMjxpg/2DoUUsVs784lJJcLJXuLgLx13FByS3Vay6d",
  server: false

# In test we don't send emails
config :whistle, Whistle.Mailer, adapter: Swoosh.Adapters.Test

config :whistle, Whistle.Oban, testing: :inline

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Speed up password hashing in tests.
config :bcrypt_elixir, log_rounds: 4

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
