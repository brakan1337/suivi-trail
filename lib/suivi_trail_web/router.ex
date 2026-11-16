defmodule SuiviTrailWeb.Router do
  use SuiviTrailWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SuiviTrailWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :securite do
    plug :identifier_pc_securite
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Ce que voient les spectateurs : public
  scope "/", SuiviTrailWeb do
    pipe_through :browser

    live_session :public do
      live "/", DirectLive
      live "/coureurs/:dossard", CoureurLive
    end
  end

  # Le PC sécurité : identifiant et mot de passe.
  # Sa propre live_session : passer d'une page publique à celle-ci impose une vraie requête HTTP,
  # donc le contrôle du mot de passe. Dans la même session, LiveView naviguerait par le WebSocket
  # sans repasser par ce contrôle.
  scope "/securite", SuiviTrailWeb do
    pipe_through [:browser, :securite]

    live_session :securite do
      live "/", SecuriteLive
    end
  end

  # Les tapis de chronométrage envoient leurs passages ici, avec le jeton du chronométreur
  scope "/api", SuiviTrailWeb do
    pipe_through :api

    post "/passages", PassageController, :create
  end

  defp identifier_pc_securite(conn, _opts) do
    Plug.BasicAuth.basic_auth(conn,
      username: "securite",
      password: Application.fetch_env!(:suivi_trail, :mot_de_passe_securite)
    )
  end

  if Application.compile_env(:suivi_trail, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SuiviTrailWeb.Telemetry
    end
  end
end
