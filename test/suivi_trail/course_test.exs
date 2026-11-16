defmodule SuiviTrail.CourseTest do
  use ExUnit.Case, async: true

  import SuiviTrail.Fixtures
  alias SuiviTrail.{Course, Parcours}

  defp course, do: Course.nouvelle(parcours(), coureurs())

  defp avec(course, passages) do
    Enum.reduce(passages, course, fn {dossard, code, minutes}, c ->
      {:ok, c} = Course.enregistrer(c, dossard, code, a(minutes))
      c
    end)
  end

  describe "enregistrer un passage" do
    test "refuse un dossard ou un point inconnu, et un passage avant le départ" do
      assert Course.enregistrer(course(), 99, "A", a(60)) == {:error, :dossard_inconnu}
      assert Course.enregistrer(course(), 1, "Z", a(60)) == {:error, :point_inconnu}
      assert Course.enregistrer(course(), 1, "A", a(-5)) == {:error, :avant_le_depart}
    end

    test "une puce lue deux fois par le tapis ne compte qu'une fois" do
      c = avec(course(), [{1, "A", 60}])
      assert Course.enregistrer(c, 1, "A", a(61)) == {:ignore, :deja_enregistre}
    end

    test "un passage qui arrive en retard est rangé à sa place" do
      # Le point A, en zone blanche, transmet après l'arrivée.
      c = avec(course(), [{1, "DEP", 0}, {1, "ARR", 150}, {1, "A", 55}])
      assert Course.dernier_passage(c, 1) == {"ARR", a(150)}
      assert Course.arrive?(c, 1)
    end
  end

  describe "classement" do
    setup do
      c =
        avec(course(), [
          {1, "DEP", 0},
          {2, "DEP", 0},
          {3, "DEP", 0},
          {4, "DEP", 0},
          {1, "A", 50},
          {2, "A", 48},
          {3, "A", 61},
          {2, "ARR", 130}
        ])

      %{c: c}
    end

    test "le point le plus avancé d'abord, puis l'heure", %{c: c} do
      assert Enum.map(Course.classement(c), & &1.coureur.dossard) == [2, 1, 3, 4]
      assert hd(Course.classement(c)).temps == 130 * 60
    end

    test "un filtre donne un rang propre à la sélection", %{c: c} do
      assert [%{rang: 1, coureur: %{dossard: 1}}, %{rang: 2, coureur: %{dossard: 3}}] =
               Course.classement(c, %{sexe: "F"})

      assert [%{rang: 1, coureur: %{dossard: 2}}, %{rang: 2, coureur: %{dossard: 3}}] =
               Course.classement(c, %{categorie: "M1"})

      assert [%{coureur: %{dossard: 3}}] = Course.classement(c, %{recherche: "hourc"})
      assert [%{coureur: %{dossard: 4}}] = Course.classement(c, %{recherche: "4", sexe: ""})
    end

    test "un abandon sort du classement", %{c: c} do
      {:ok, c} = Course.abandon(c, 2, "ARR")
      refute 2 in Enum.map(Course.classement(c), & &1.coureur.dossard)
    end
  end

  describe "fiche d'un coureur" do
    test "le rang à chaque point et l'heure d'arrivée estimée" do
      c = avec(course(), [{1, "DEP", 0}, {2, "DEP", 0}, {2, "A", 48}, {1, "A", 60}])
      fiche = Course.fiche(c, 1)

      assert [%{rang: 1}, %{rang: 2, temps: 3600}, %{rang: nil}] = fiche.etapes

      # 60 min pour 10 km-effort, soit 6 min par km-effort ; l'arrivée vaut 20 + 500/100 = 25 km-effort : 150 min.
      assert fiche.arrivee_estimee == a(150)
    end

    test "un dossard inconnu n'a pas de fiche" do
      assert Course.fiche(course(), 99) == nil
    end
  end

  describe "alertes de sécurité" do
    test "le km-effort compte le dénivelé" do
      assert Parcours.km_effort(%Parcours.Point{code: "X", nom: "X", km: 20.0, d_plus: 500}) ==
               25.0
    end

    test "un coureur sans nouvelles bien au-delà du temps prévu pour son tronçon" do
      # Allure 6 min/km-effort ; le tronçon A → arrivée vaut 15 km-effort : 90 min prévues.
      # Alerte au-delà de 90 × 1,5 + 15 = 150 min sans nouvelles, soit après 60 + 150 = 210 min de course.
      c = avec(course(), [{1, "DEP", 0}, {1, "A", 60}])

      assert Course.alertes(c, a(209)) == []

      assert [%{type: :retard, attendu: 5400, coureur: %{dossard: 1}, dernier: %{code: "A"}}] =
               Course.alertes(c, a(211))
    end

    test "un coureur lent n'est pas en alerte tant qu'il reste dans son propre rythme" do
      # 2 h pour les 10 premiers km : 12 min/km-effort, 180 min prévues pour la fin. Pas d'alerte à 4 h 30.
      c = avec(course(), [{1, "DEP", 0}, {1, "A", 120}])
      assert Course.alertes(c, a(270)) == []
    end

    test "une barrière horaire dépassée passe avant tout" do
      c = avec(course(), [{1, "DEP", 0}, {2, "DEP", 0}, {2, "A", 60}])

      assert [%{type: :hors_delai, coureur: %{dossard: 1}, suivant: %{code: "A"}}] =
               Course.alertes(c, a(181))
    end

    test "une alerte prise en charge, un abandon ou une arrivée ne remontent plus" do
      c =
        avec(course(), [
          {1, "DEP", 0},
          {2, "DEP", 0},
          {3, "DEP", 0},
          {3, "A", 50},
          {3, "ARR", 140}
        ])

      c = Course.traiter_alerte(c, 1, "DEP")
      {:ok, c} = Course.abandon(c, 2, "DEP")
      assert Course.alertes(c, a(200)) == []
    end
  end

  test "statistiques par point" do
    c =
      avec(course(), [
        {1, "DEP", 0},
        {2, "DEP", 0},
        {3, "DEP", 0},
        {1, "A", 50},
        {2, "A", 52},
        {1, "ARR", 130}
      ])

    assert [%{passes: 3, avant: 0}, %{passes: 2, avant: 1}, %{passes: 1, avant: 2}] =
             Course.statistiques(c)
  end

  test "les prépositions des points" do
    [dep, _, _, crete, _, arrivee] = Parcours.grand_trail().points
    assert Parcours.au(dep) == "au Départ"
    assert Parcours.au(crete) == "à la Crête de Sarrat"
    assert Parcours.du(crete) == "de la Crête de Sarrat"
    assert Parcours.au(arrivee) == "à l'Arrivée"
    assert Parcours.du(arrivee) == "de l'Arrivée"
  end
end
