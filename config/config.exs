# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :muddle, :scopes,
  user: [
    default: true,
    module: Muddle.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Muddle.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :muddle,
  ecto_repos: [Muddle.Repo],
  generators: [timestamp_type: :utc_datetime]

config :muddle, :features,
  guest_join: true,
  accessory_uploads: true

# When false, /users/register only accepts visitors who arrived via a
# valid invite token (`/users/register?invite=...`). Existing users can
# generate invite tokens at /users/invites. Flip to true to let anyone
# self-register.
config :muddle, :registration_open, false

# Where uploaded accessory images live on disk. Override in runtime.exs
# for production (e.g. a persistent volume or S3-backed mount).
config :muddle, :accessory_storage,
  root: Path.expand("../priv/static/uploads/accessories", __DIR__),
  url_prefix: "/uploads/accessories"

# Configure the endpoint
config :muddle, MuddleWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MuddleWeb.ErrorHTML, json: MuddleWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Muddle.PubSub,
  live_view: [signing_salt: "iUt9U0l9"]

# Configure the mailer
config :muddle, Muddle.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  muddle: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  muddle: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Sentry error reporting. The DSN is set in runtime.exs from the
# SENTRY_DSN environment variable. When the DSN is empty, Sentry quietly
# no-ops.
config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  environment_name: Mix.env()

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
