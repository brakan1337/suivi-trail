# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :suivi_trail,
  generators: [timestamp_type: :utc_datetime],
  # Le journal des passages : relu au redémarrage, rien n'est perdu si le serveur tombe.
  journal_dir: "priv/journal",
  course_demo: true,
  simulation: false,
  # Valeurs de développement. En production, elles viennent de l'environnement (runtime.exs).
  jeton_chronometreur: "jeton-de-developpement-chronometreur",
  mot_de_passe_securite: "securite-dev"

# Configure the endpoint
config :suivi_trail, SuiviTrailWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SuiviTrailWeb.ErrorHTML, json: SuiviTrailWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SuiviTrail.PubSub,
  live_view: [signing_salt: "o1nqzBsv"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  suivi_trail: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  suivi_trail: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
