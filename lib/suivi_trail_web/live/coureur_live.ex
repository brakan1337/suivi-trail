defmodule SuiviTrailWeb.CoureurLive do
  @moduledoc "Le suivi d'un coureur : ses passages, son rang à chaque point, son heure d'arrivée estimée."
  use SuiviTrailWeb, :live_view

  alias SuiviTrail.{Course, CourseServeur, Parcours}
  alias SuiviTrailWeb.Format

  @course Parcours.grand_trail().id

  @impl true
  def mount(%{"dossard" => dossard}, _session, socket) do
    with {numero, ""} <- Integer.parse(dossard),
         %{} = fiche <- Course.fiche(CourseServeur.etat(@course), numero) do
      if connected?(socket),
        do: Phoenix.PubSub.subscribe(SuiviTrail.PubSub, CourseServeur.sujet(@course))

      {:ok, assign(socket, dossard: numero, fiche: fiche, page_title: "Dossard #{numero}")}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Aucun coureur ne porte le dossard #{dossard}.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:course, course}, socket),
    do: {:noreply, assign(socket, fiche: Course.fiche(course, socket.assigns.dossard))}

  def handle_info({:alertes, _}, socket), do: {:noreply, socket}

  defp statut(fiche) do
    arrivee = List.last(fiche.etapes)

    cond do
      fiche.abandon -> {"Abandon", "badge-error"}
      arrivee.heure -> {"Arrivé", "badge-success"}
      Enum.any?(fiche.etapes, & &1.heure) -> {"En course", "badge-info"}
      true -> {"Pas encore parti", "badge-ghost"}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :statut, statut(assigns.fiche))

    ~H"""
    <Layouts.app flash={@flash}>
      <.link navigate={~p"/"} class="link text-sm">← Classement</.link>
      <div class="flex flex-wrap items-center gap-4">
        <div class="rounded-box bg-neutral px-4 py-2 font-mono text-3xl font-bold text-neutral-content">
          {@fiche.coureur.dossard}
        </div>
        <div>
          <h1 class="text-2xl font-bold">
            {@fiche.coureur.prenom} {String.upcase(@fiche.coureur.nom)}
          </h1>
          <p class="opacity-70">{@fiche.coureur.categorie} · {@fiche.coureur.club || "sans club"}</p>
        </div>
        <span id="statut" class={"badge #{elem(@statut, 1)}"}>{elem(@statut, 0)}</span>
      </div>

      <p :if={@fiche.arrivee_estimee} id="estimation" class="text-lg">
        Arrivée estimée vers <strong>{Format.heure(@fiche.arrivee_estimee)}</strong>, à son allure actuelle.
      </p>

      <section class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table id="passages" class="table">
          <thead>
            <tr>
              <th>Point</th><th>km</th><th>Heure</th><th class="text-right">Temps</th><th class="text-right">
                Rang au point
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={e <- @fiche.etapes} class={if(e.heure, do: "", else: "opacity-50")}>
              <td class="font-semibold">{e.point.nom}</td>
              <td>{Format.km(e.point.km)}</td>
              <td class="font-mono">{Format.heure(e.heure)}</td>
              <td class="text-right font-mono">{Format.duree(e.temps)}</td>
              <td class="text-right">{e.rang || "—"}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end
end
