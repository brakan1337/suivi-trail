defmodule SuiviTrailWeb.DirectLive do
  @moduledoc """
  Le classement en direct, la page que suivent les spectateurs.

  Chaque page ouverte est un processus Elixir léger. Elle s'abonne à la course et reçoit
  le classement à jour au plus une fois par seconde, sans rien redemander au serveur.
  """
  use SuiviTrailWeb, :live_view

  alias SuiviTrail.{Course, CourseServeur, Horloge, Parcours}
  alias SuiviTrailWeb.Format

  @course Parcours.grand_trail().id
  @affiches 40

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SuiviTrail.PubSub, CourseServeur.sujet(@course))
      :timer.send_interval(1_000, :tic)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Classement en direct",
       filtres: %{sexe: "", categorie: "", recherche: ""},
       maintenant: Horloge.maintenant()
     )
     |> assign_course(CourseServeur.etat(@course))}
  end

  @impl true
  def handle_info({:course, course}, socket), do: {:noreply, assign_course(socket, course)}
  def handle_info({:alertes, _}, socket), do: {:noreply, socket}
  def handle_info(:tic, socket), do: {:noreply, assign(socket, maintenant: Horloge.maintenant())}

  @impl true
  def handle_event("filtrer", params, socket) do
    filtres = %{
      sexe: params["sexe"] || "",
      categorie: params["categorie"] || "",
      recherche: params["recherche"] || ""
    }

    {:noreply, socket |> assign(filtres: filtres) |> assign_course(socket.assigns.course)}
  end

  defp assign_course(socket, course) do
    classement = Course.classement(course, socket.assigns.filtres)

    assign(socket,
      course: course,
      classement: Enum.take(classement, @affiches),
      total: length(classement),
      statistiques: Course.statistiques(course),
      categories:
        course.coureurs |> Map.values() |> Enum.map(& &1.categorie) |> Enum.uniq() |> Enum.sort()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold">{@course.parcours.nom}</h1>
          <p class="opacity-70">
            42,5 km · 2 150 m D+ · départ {Format.heure(@course.parcours.depart)}
          </p>
        </div>
        <div class="text-right">
          <div class="text-xs uppercase opacity-70">Heure de course</div>
          <div id="horloge" class="font-mono text-3xl font-bold">{Format.heure(@maintenant)}</div>
          <div :if={Horloge.vitesse() > 1} class="badge badge-warning badge-sm">
            Simulation × {Horloge.vitesse()}
          </div>
        </div>
      </div>

      <section id="points" class="grid grid-cols-3 gap-2 sm:grid-cols-6">
        <div :for={s <- @statistiques} class="rounded-box border border-base-300 bg-base-100 p-3">
          <div class="text-xs opacity-70">km {Format.km(s.point.km)}</div>
          <div class="text-sm font-semibold leading-tight">{s.point.nom}</div>
          <div class="mt-1 text-2xl font-bold">{s.passes}</div>
          <div class="text-xs opacity-70">passés</div>
        </div>
      </section>

      <form id="filtres" phx-change="filtrer" class="flex flex-wrap gap-2">
        <input
          type="search"
          name="recherche"
          value={@filtres.recherche}
          placeholder="Nom ou dossard"
          phx-debounce="300"
          class="input input-sm w-48"
        />
        <select name="sexe" class="select select-sm w-36">
          <option value="">Tous</option>
          <option value="F" selected={@filtres.sexe == "F"}>Femmes</option>
          <option value="H" selected={@filtres.sexe == "H"}>Hommes</option>
        </select>
        <select name="categorie" class="select select-sm w-40">
          <option value="">Toutes catégories</option>
          <option :for={c <- @categories} value={c} selected={@filtres.categorie == c}>{c}</option>
        </select>
      </form>

      <section class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table id="classement" class="table table-sm">
          <thead>
            <tr>
              <th>Rang</th><th>Dossard</th><th>Coureur</th><th>Cat.</th><th>Dernier point</th><th class="text-right">
                Temps
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={l <- @classement} id={"coureur-#{l.coureur.dossard}"}>
              <td class="font-bold">{l.rang}</td>
              <td class="font-mono">{l.coureur.dossard}</td>
              <td>
                <.link navigate={~p"/coureurs/#{l.coureur.dossard}"} class="link link-hover">{l.coureur.prenom} {String.upcase(
                  l.coureur.nom
                )}</.link>
              </td>
              <td>{l.coureur.categorie}</td>
              <td>{l.point.nom} <span class="opacity-60">· km {Format.km(l.point.km)}</span></td>
              <td class="text-right font-mono">{Format.duree(l.temps)}</td>
            </tr>
            <tr :if={@classement == []}>
              <td colspan="6" class="opacity-70">Personne n'est encore passé au départ.</td>
            </tr>
          </tbody>
        </table>
      </section>
      <p :if={@total > length(@classement)} class="text-sm opacity-70">
        {@total} coureurs classés · les {length(@classement)} premiers sont affichés.
      </p>
    </Layouts.app>
    """
  end
end
