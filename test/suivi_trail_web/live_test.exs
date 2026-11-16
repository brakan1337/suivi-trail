defmodule SuiviTrailWeb.LiveTest do
  use SuiviTrailWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias SuiviTrail.{CourseServeur, Engages, Horloge, Parcours}

  @moduletag :tmp_dir
  @depart Parcours.grand_trail().depart

  setup %{tmp_dir: dossier} do
    start_supervised!(
      {CourseServeur,
       parcours: Parcours.grand_trail(), coureurs: Engages.demo(20), journal_dir: dossier}
    )

    on_exit(&Horloge.reelle/0)
    :ok
  end

  defp passage(dossard, code, minutes),
    do:
      :ok =
        CourseServeur.passage(
          "grand-trail",
          dossard,
          code,
          NaiveDateTime.add(@depart, minutes * 60)
        )

  test "le classement se met à jour sans recharger la page", %{conn: conn} do
    passage(5, "DEP", 0)
    {:ok, vue, html} = live(conn, ~p"/")
    assert html =~ "Grand trail des crêtes"
    assert has_element?(vue, "#coureur-5")
    refute has_element?(vue, "#coureur-7")

    passage(7, "DEP", 0)
    passage(7, "BRU", 70)
    send(vue.pid, {:course, CourseServeur.etat("grand-trail")})

    assert vue |> element("#classement tbody tr:first-child") |> render() =~ "Col des Bruyères"
    assert has_element?(vue, "#coureur-7")
  end

  test "les filtres s'appliquent", %{conn: conn} do
    for d <- 1..20, do: passage(d, "DEP", 0)
    {:ok, vue, _} = live(conn, ~p"/")
    femmes = Engages.demo(20) |> Enum.filter(&(&1.sexe == "F")) |> Enum.map(& &1.dossard)

    vue |> form("#filtres", %{sexe: "F"}) |> render_change()

    for d <- 1..20, do: assert(has_element?(vue, "#coureur-#{d}") == d in femmes)
  end

  test "la fiche d'un coureur", %{conn: conn} do
    passage(5, "DEP", 0)
    passage(5, "BRU", 72)
    {:ok, vue, _} = live(conn, ~p"/coureurs/5")

    assert vue |> element("#statut") |> render() =~ "En course"
    assert vue |> element("#passages") |> render() =~ "1:12:00"
    assert has_element?(vue, "#estimation")
  end

  test "un dossard inconnu renvoie au classement", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/coureurs/999")
  end

  describe "PC sécurité" do
    setup %{conn: conn} do
      mot_de_passe = Application.fetch_env!(:suivi_trail, :mot_de_passe_securite)

      %{
        securite:
          put_req_header(
            conn,
            "authorization",
            Plug.BasicAuth.encode_basic_auth("securite", mot_de_passe)
          )
      }
    end

    test "réservé au PC sécurité", %{conn: conn} do
      assert conn |> get(~p"/securite") |> response(401)
    end

    test "on ne rejoint pas le PC sécurité en naviguant depuis une page publique", %{conn: conn} do
      {:ok, vue, _} = live(conn, ~p"/")

      # Changer de live_session force une requête HTTP complète, qui repasse par le mot de passe.
      assert {:error, {:redirect, %{to: adresse}}} = live_redirect(vue, to: ~p"/securite")
      assert String.ends_with?(adresse, "/securite")
    end

    test "un coureur sans nouvelles remonte, puis disparaît une fois pris en charge", %{
      securite: conn
    } do
      passage(5, "DEP", 0)
      passage(5, "BRU", 70)
      # Bien plus tard, il n'est toujours pas au lac : l'heure de course avance jusque-là.
      Horloge.accelerer(NaiveDateTime.add(@depart, 225 * 60), 1)
      send(GenServer.whereis(CourseServeur.via("grand-trail")), :verifier)

      {:ok, vue, _} = live(conn, ~p"/securite")
      assert vue |> element("#alerte-5") |> render() =~ "SANS NOUVELLES"

      vue |> element("#alerte-5 button", "Pris en charge") |> render_click()
      refute has_element?(vue, "#alerte-5")
    end

    test "déclarer un abandon", %{securite: conn} do
      # Vu au col après 2 h, il n'a pas atteint le lac avant sa barrière de 4 h.
      passage(6, "DEP", 0)
      passage(6, "BRU", 120)
      Horloge.accelerer(NaiveDateTime.add(@depart, 245 * 60), 1)
      send(GenServer.whereis(CourseServeur.via("grand-trail")), :verifier)

      {:ok, vue, _} = live(conn, ~p"/securite")
      assert vue |> element("#alerte-6") |> render() =~ "HORS DÉLAI"
      vue |> element("#alerte-6 button", "Abandon") |> render_click()

      assert CourseServeur.etat("grand-trail").abandons == %{6 => "BRU"}
      refute has_element?(vue, "#alerte-6")
    end
  end
end
