defmodule SuiviTrail.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SuiviTrailWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:suivi_trail, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: SuiviTrail.PubSub},
        {Registry, keys: :unique, name: SuiviTrail.Courses},
        SuiviTrail.Horloge
      ] ++ course_demo() ++ [SuiviTrailWeb.Endpoint]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SuiviTrail.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # La course de démonstration, et en développement son simulateur.
  defp course_demo do
    if Application.get_env(:suivi_trail, :course_demo) do
      parcours = SuiviTrail.Parcours.grand_trail()
      coureurs = SuiviTrail.Engages.demo()
      simulation = Application.get_env(:suivi_trail, :simulation, false)

      [
        {SuiviTrail.CourseServeur,
         parcours: parcours,
         coureurs: coureurs,
         journal_dir: Application.fetch_env!(:suivi_trail, :journal_dir),
         repartir_de_zero: simulation}
      ] ++
        if(simulation,
          do: [{SuiviTrail.Simulateur, parcours: parcours, coureurs: coureurs, vitesse: 60}],
          else: []
        )
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SuiviTrailWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
