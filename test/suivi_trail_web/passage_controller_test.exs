defmodule SuiviTrailWeb.PassageControllerTest do
  use SuiviTrailWeb.ConnCase, async: false

  alias SuiviTrail.{CourseServeur, Engages, Parcours}

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: dossier} do
    start_supervised!(
      {CourseServeur,
       parcours: Parcours.grand_trail(), coureurs: Engages.demo(20), journal_dir: dossier}
    )

    jeton = Application.fetch_env!(:suivi_trail, :jeton_chronometreur)

    %{
      conn:
        conn
        |> put_req_header("authorization", "Bearer " <> jeton)
        |> put_req_header("content-type", "application/json")
    }
  end

  test "un paquet de passages : chaque ligne a sa réponse", %{conn: conn} do
    passages = [
      %{dossard: 3, point: "DEP", heure: "2027-05-15T07:30:00"},
      %{dossard: 3, point: "BRU", heure: "2027-05-15T08:41:12"},
      %{dossard: 3, point: "BRU", heure: "2027-05-15T08:41:13"},
      %{dossard: 999, point: "BRU", heure: "2027-05-15T08:42:00"},
      %{dossard: 4, point: "BRU", heure: "pas une heure"},
      %{point: "BRU"}
    ]

    reponse = conn |> post(~p"/api/passages", %{passages: passages}) |> json_response(200)

    assert reponse == %{
             "acceptes" => 2,
             "ignores" => 1,
             "refuses" => [
               %{"ligne" => 3, "raison" => "dossard_inconnu"},
               %{"ligne" => 4, "raison" => "heure_illisible"},
               %{"ligne" => 5, "raison" => "ligne_incomplete"}
             ]
           }

    assert CourseServeur.etat("grand-trail").passages[3]["BRU"] == ~N[2027-05-15 08:41:12]
  end

  test "sans le jeton du chronométreur, rien n'entre", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer faux")
      |> post(~p"/api/passages", %{passages: []})

    assert json_response(conn, 401)["erreur"] =~ "Jeton"
  end

  test "un envoi mal formé est refusé", %{conn: conn} do
    assert conn |> post(~p"/api/passages", %{rien: true}) |> json_response(422)
  end
end
