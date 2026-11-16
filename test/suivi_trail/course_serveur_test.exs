defmodule SuiviTrail.CourseServeurTest do
  use ExUnit.Case, async: false

  import SuiviTrail.Fixtures
  alias SuiviTrail.CourseServeur

  @moduletag :tmp_dir

  defp demarrer(dossier, id) do
    start_supervised!(
      {CourseServeur, parcours: parcours(id), coureurs: coureurs(), journal_dir: dossier}
    )
  end

  test "les spectateurs reçoivent le classement mis à jour, regroupé", %{tmp_dir: dossier} do
    demarrer(dossier, "diffusion")
    Phoenix.PubSub.subscribe(SuiviTrail.PubSub, CourseServeur.sujet("diffusion"))

    for d <- 1..4, do: :ok = CourseServeur.passage("diffusion", d, "DEP", a(0))

    # Quatre passages, une seule diffusion.
    assert_receive {:course, course}, 2_000
    assert map_size(course.passages) == 4
    refute_receive {:course, _}, 1_200
  end

  test "après un plantage, la course redémarre et relit son journal", %{tmp_dir: dossier} do
    pid = demarrer(dossier, "plantage")
    :ok = CourseServeur.passage("plantage", 1, "DEP", a(0))
    :ok = CourseServeur.passage("plantage", 1, "A", a(55))
    :ok = CourseServeur.abandon("plantage", 2, "DEP")
    :ok = CourseServeur.traiter_alerte("plantage", 3, "DEP")

    Process.exit(pid, :kill)

    # Le superviseur relance le processus ; il retrouve l'état exact depuis le journal.
    assert eventually(fn ->
             is_pid(GenServer.whereis(CourseServeur.via("plantage"))) and
               GenServer.whereis(CourseServeur.via("plantage")) != pid
           end)

    course = CourseServeur.etat("plantage")
    assert course.passages[1] == %{"DEP" => a(0), "A" => a(55)}
    assert course.abandons == %{2 => "DEP"}
    assert MapSet.member?(course.alertes_traitees, {3, "DEP"})
  end

  test "les erreurs ne sont pas écrites au journal", %{tmp_dir: dossier} do
    demarrer(dossier, "erreurs")
    assert {:error, :dossard_inconnu} = CourseServeur.passage("erreurs", 99, "A", a(10))

    assert {:ignore, :deja_enregistre} =
             with(
               :ok <- CourseServeur.passage("erreurs", 1, "DEP", a(0)),
               do: CourseServeur.passage("erreurs", 1, "DEP", a(0))
             )

    assert File.read!(Path.join(dossier, "erreurs.jsonl"))
           |> String.split("\n", trim: true)
           |> length() == 1
  end

  defp eventually(condition, essais \\ 50) do
    cond do
      condition.() -> true
      essais == 0 -> false
      true -> Process.sleep(20) && eventually(condition, essais - 1)
    end
  end
end
