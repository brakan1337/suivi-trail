defmodule SuiviTrail.CourseServeur do
  @moduledoc """
  Le processus qui porte une épreuve le jour J. Un processus par épreuve, enregistré par
  son identifiant et surveillé : s'il plante, il redémarre et relit son journal.

  * Chaque passage accepté est d'abord écrit dans un journal sur disque, une ligne par passage.
  * Les spectateurs ne reçoivent pas un message par passage : le classement est diffusé
    au plus une fois par seconde. Qu'il y ait 10 ou 3 000 pages ouvertes, le processus
    de la course fait le même travail.
  * Toutes les 15 secondes (heure de course), il recalcule les alertes de sécurité.
  """
  use GenServer, restart: :permanent
  require Logger

  alias SuiviTrail.{Course, Horloge}

  @intervalle_diffusion 1_000
  @intervalle_alertes 15_000

  # --- API ---

  def start_link(opts) do
    parcours = Keyword.fetch!(opts, :parcours)
    GenServer.start_link(__MODULE__, opts, name: via(parcours.id))
  end

  def via(id), do: {:via, Registry, {SuiviTrail.Courses, id}}

  def sujet(id), do: "course:" <> id

  @doc "Enregistre un passage. Renvoie `:ok`, `{:ignore, raison}` ou `{:error, raison}`."
  def passage(id, dossard, code, heure),
    do: GenServer.call(via(id), {:passage, dossard, code, heure})

  def abandon(id, dossard, code), do: GenServer.call(via(id), {:abandon, dossard, code})

  def traiter_alerte(id, dossard, code), do: GenServer.call(via(id), {:traiter, dossard, code})

  @doc "Une copie de l'état, pour l'affichage : les calculs se font ensuite dans le processus de la page."
  def etat(id), do: GenServer.call(via(id), :etat)

  def alertes(id), do: GenServer.call(via(id), :alertes)

  # --- Processus ---

  @impl true
  def init(opts) do
    parcours = Keyword.fetch!(opts, :parcours)
    journal = Path.join(Keyword.fetch!(opts, :journal_dir), parcours.id <> ".jsonl")
    File.mkdir_p!(Path.dirname(journal))
    # Une simulation repart d'une course vierge ; une vraie course reprend toujours son journal.
    if Keyword.get(opts, :repartir_de_zero, false), do: File.rm(journal)

    course = relire(Course.nouvelle(parcours, Keyword.fetch!(opts, :coureurs)), journal)

    if map_size(course.passages) > 0,
      do:
        Logger.info(
          "#{parcours.id} : journal relu, #{map_size(course.passages)} coureurs en course"
        )

    Process.send_after(self(), :verifier, @intervalle_alertes)
    {:ok, %{course: course, journal: journal, diffusion_prevue: false, alertes: []}}
  end

  @impl true
  def handle_call({:passage, dossard, code, heure}, _from, s) do
    case Course.enregistrer(s.course, dossard, code, heure) do
      {:ok, course} ->
        journaliser(s.journal, %{t: "passage", dossard: dossard, point: code, heure: heure})
        {:reply, :ok, prevoir_diffusion(%{s | course: course})}

      autre ->
        {:reply, autre, s}
    end
  end

  def handle_call({:abandon, dossard, code}, _from, s) do
    case Course.abandon(s.course, dossard, code) do
      {:ok, course} ->
        journaliser(s.journal, %{t: "abandon", dossard: dossard, point: code})

        {:reply, :ok,
         s |> Map.put(:course, course) |> recalculer_alertes() |> prevoir_diffusion()}

      erreur ->
        {:reply, erreur, s}
    end
  end

  def handle_call({:traiter, dossard, code}, _from, s) do
    journaliser(s.journal, %{t: "traitee", dossard: dossard, point: code})
    s = %{s | course: Course.traiter_alerte(s.course, dossard, code)} |> recalculer_alertes()
    {:reply, :ok, s}
  end

  def handle_call(:etat, _from, s), do: {:reply, s.course, s}
  def handle_call(:alertes, _from, s), do: {:reply, s.alertes, s}

  @impl true
  def handle_info(:diffuser, s) do
    Phoenix.PubSub.broadcast(SuiviTrail.PubSub, sujet(s.course.parcours.id), {:course, s.course})
    {:noreply, %{s | diffusion_prevue: false}}
  end

  def handle_info(:verifier, s) do
    # En simulation accélérée, l'heure de course avance plus vite : on vérifie d'autant plus souvent.
    Process.send_after(
      self(),
      :verifier,
      max(250, div(@intervalle_alertes, round(Horloge.vitesse())))
    )

    {:noreply, recalculer_alertes(s)}
  end

  defp prevoir_diffusion(%{diffusion_prevue: true} = s), do: s

  defp prevoir_diffusion(s) do
    Process.send_after(self(), :diffuser, @intervalle_diffusion)
    %{s | diffusion_prevue: true}
  end

  defp recalculer_alertes(s) do
    alertes = Course.alertes(s.course, Horloge.maintenant())

    if alertes != s.alertes do
      Phoenix.PubSub.broadcast(
        SuiviTrail.PubSub,
        sujet(s.course.parcours.id),
        {:alertes, alertes}
      )
    end

    %{s | alertes: alertes}
  end

  # --- Journal ---

  defp journaliser(fichier, evenement) do
    File.write!(fichier, Jason.encode!(evenement) <> "\n", [:append])
  end

  defp relire(course, fichier) do
    case File.read(fichier) do
      {:ok, contenu} ->
        contenu
        |> String.split("\n", trim: true)
        |> Enum.reduce(course, fn ligne, c -> rejouer(c, Jason.decode!(ligne)) end)

      {:error, :enoent} ->
        course
    end
  end

  defp rejouer(c, %{"t" => "passage", "dossard" => d, "point" => p, "heure" => h}) do
    case Course.enregistrer(c, d, p, NaiveDateTime.from_iso8601!(h)) do
      {:ok, c} -> c
      _ -> c
    end
  end

  defp rejouer(c, %{"t" => "abandon", "dossard" => d, "point" => p}) do
    {:ok, c} = Course.abandon(c, d, p)
    c
  end

  defp rejouer(c, %{"t" => "traitee", "dossard" => d, "point" => p}),
    do: Course.traiter_alerte(c, d, p)
end
