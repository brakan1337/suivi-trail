defmodule SuiviTrailWeb.SecuriteLive do
  @moduledoc """
  Le PC sécurité : les coureurs dont il faut s'occuper maintenant, les plus urgents d'abord.
  Une barrière horaire dépassée passe avant un retard ; parmi les retards, le plus long silence en premier.
  """
  use SuiviTrailWeb, :live_view

  alias SuiviTrail.{Course, CourseServeur, Parcours}
  alias SuiviTrailWeb.Format

  @course Parcours.grand_trail().id

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(SuiviTrail.PubSub, CourseServeur.sujet(@course))

    course = CourseServeur.etat(@course)

    {:ok,
     assign(socket,
       page_title: "PC sécurité",
       alertes: CourseServeur.alertes(@course),
       statistiques: Course.statistiques(course)
     )}
  end

  @impl true
  def handle_info({:alertes, alertes}, socket), do: {:noreply, assign(socket, alertes: alertes)}

  def handle_info({:course, course}, socket),
    do: {:noreply, assign(socket, statistiques: Course.statistiques(course))}

  @impl true
  def handle_event("prise_en_charge", %{"dossard" => d, "point" => p}, socket) do
    :ok = CourseServeur.traiter_alerte(@course, String.to_integer(d), p)

    {:noreply,
     socket
     |> assign(alertes: CourseServeur.alertes(@course))
     |> put_flash(:info, "Dossard #{d} : alerte prise en charge.")}
  end

  def handle_event("abandon", %{"dossard" => d, "point" => p}, socket) do
    :ok = CourseServeur.abandon(@course, String.to_integer(d), p)

    {:noreply,
     socket
     |> assign(alertes: CourseServeur.alertes(@course))
     |> put_flash(:info, "Dossard #{d} : abandon enregistré.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-wrap items-end justify-between gap-2">
        <h1 class="text-2xl font-bold">PC sécurité</h1>
        <p id="compteur" class="opacity-70">{length(@alertes)} coureur(s) à surveiller</p>
      </div>

      <section id="sur-le-parcours" class="grid grid-cols-3 gap-2 sm:grid-cols-6">
        <div :for={s <- tl(@statistiques)} class="rounded-box border border-base-300 bg-base-100 p-3">
          <div class="text-sm font-semibold leading-tight">{s.point.nom}</div>
          <div class="mt-1 text-2xl font-bold">{s.avant}</div>
          <div class="text-xs opacity-70">encore attendus</div>
        </div>
      </section>

      <p :if={@alertes == []} class="rounded-box border border-base-300 bg-base-100 p-6">
        Aucun coureur à surveiller pour l'instant.
      </p>

      <div id="alertes" class="space-y-3">
        <article
          :for={a <- @alertes}
          id={"alerte-#{a.coureur.dossard}"}
          class={"rounded-box border-l-4 bg-base-100 p-4 shadow-sm #{if a.type == :hors_delai, do: "border-error", else: "border-warning"}"}
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <span class={"badge #{if a.type == :hors_delai, do: "badge-error", else: "badge-warning"}"}>
                {if a.type == :hors_delai, do: "HORS DÉLAI", else: "SANS NOUVELLES"}
              </span>
              <h2 class="mt-1 text-lg font-bold">
                <span class="font-mono">{a.coureur.dossard}</span>
                · {a.coureur.prenom} {String.upcase(a.coureur.nom)}
              </h2>
              <p>
                Vu <strong>{Parcours.au(a.dernier)}</strong>
                à {Format.heure(a.heure)}, attendu {Parcours.au(a.suivant)}.
                Sans nouvelles depuis
                <strong>{Format.minutes(a.depuis)}</strong><span :if={a.attendu}> (tronçon prévu en {Format.minutes(a.attendu)} à son allure)</span>.
              </p>
              <p :if={a.type == :hors_delai} class="text-error">
                La barrière horaire {Parcours.du(a.suivant)} est passée.
              </p>
            </div>
            <div class="flex gap-2">
              <button
                phx-click="prise_en_charge"
                phx-value-dossard={a.coureur.dossard}
                phx-value-point={a.dernier.code}
                class="btn btn-sm"
              >Pris en charge</button>
              <button
                phx-click="abandon"
                phx-value-dossard={a.coureur.dossard}
                phx-value-point={a.dernier.code}
                class="btn btn-sm btn-error"
                data-confirm={"Déclarer l'abandon du dossard #{a.coureur.dossard} ?"}
              >Abandon</button>
            </div>
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end
end
