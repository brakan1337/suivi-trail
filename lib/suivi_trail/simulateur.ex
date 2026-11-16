defmodule SuiviTrail.Simulateur do
  @moduledoc """
  Rejoue une course en accéléré pour la démonstration, sans matériel : chaque coureur
  reçoit une allure, certains faiblissent, quelques-uns s'arrêtent sans prévenir.
  Les passages entrent par la même porte que ceux des vrais tapis.
  """
  use GenServer

  alias SuiviTrail.{CourseServeur, Horloge, Parcours}

  @pas 500

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    parcours = Keyword.fetch!(opts, :parcours)
    vitesse = Keyword.get(opts, :vitesse, 60)
    :rand.seed(:exsss, {7, 7, 7})
    Horloge.accelerer(NaiveDateTime.add(parcours.depart, -120), vitesse)

    plans =
      for coureur <- Keyword.fetch!(opts, :coureurs), into: %{} do
        # Allure en secondes par km-effort : 6 min 40 en médiane (environ 7 h de course),
        # les meilleurs vers 4 h, les plus lents au ras des barrières horaires.
        # Le petit tirage en plus évite que les plus rapides finissent tous à la même seconde.
        allure = min(max(400 + :rand.normal() * 70, 230 + :rand.uniform() * 20), 640)
        defaillance = if :rand.uniform() < 0.12, do: Enum.random(1..4), else: nil
        arret = if :rand.uniform() < 0.02, do: Enum.random(1..4), else: nil

        {coureur.dossard,
         %{allure: allure, defaillance: defaillance, arret: arret, envoyes: MapSet.new()}}
      end

    Process.send_after(self(), :avancer, @pas)
    {:ok, %{parcours: parcours, plans: plans}}
  end

  @impl true
  def handle_info(:avancer, s) do
    maintenant = Horloge.maintenant()

    plans =
      Map.new(s.plans, fn {dossard, plan} ->
        prevus = horaires(s.parcours, plan)

        nouveaux =
          for {code, heure} <- prevus,
              not MapSet.member?(plan.envoyes, code),
              NaiveDateTime.compare(heure, maintenant) != :gt,
              do: {code, heure}

        Enum.each(nouveaux, fn {code, heure} ->
          CourseServeur.passage(s.parcours.id, dossard, code, heure)
        end)

        {dossard,
         %{plan | envoyes: Enum.reduce(nouveaux, plan.envoyes, &MapSet.put(&2, elem(&1, 0)))}}
      end)

    Process.send_after(self(), :avancer, @pas)
    {:noreply, %{s | plans: plans}}
  end

  # Les heures de passage prévues d'un coureur, point par point.
  defp horaires(parcours, plan) do
    parcours.points
    |> Enum.with_index()
    |> Enum.reduce_while({[], parcours.depart, nil}, fn {point, i}, {acc, _heure, precedent} ->
      cond do
        plan.arret && i > plan.arret ->
          {:halt, {acc, nil, nil}}

        precedent == nil ->
          {:cont, {[{point.code, parcours.depart} | acc], parcours.depart, point}}

        true ->
          # Un coureur qui défaille met deux fois plus de temps à partir de ce tronçon.
          lenteur = if plan.defaillance && i > plan.defaillance, do: 2.1, else: 1.0

          duree =
            round(
              plan.allure * lenteur * (Parcours.km_effort(point) - Parcours.km_effort(precedent))
            )

          {_, heure_prec} = hd(acc)
          heure = NaiveDateTime.add(heure_prec, duree)
          {:cont, {[{point.code, heure} | acc], heure, point}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
