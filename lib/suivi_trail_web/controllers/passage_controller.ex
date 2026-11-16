defmodule SuiviTrailWeb.PassageController do
  @moduledoc """
  La porte d'entrée des tapis de chronométrage. Un tapis envoie ses lectures par paquets,
  parfois en double, parfois en retard quand le point de contrôle est en zone blanche.
  Chaque passage reçoit sa propre réponse : un paquet n'est jamais rejeté en bloc pour une ligne fausse.
  """
  use SuiviTrailWeb, :controller

  alias SuiviTrail.{CourseServeur, Parcours}

  @max_par_paquet 500

  plug :verifier_jeton

  def create(conn, %{"passages" => passages} = params)
      when is_list(passages) and length(passages) <= @max_par_paquet do
    course = Map.get(params, "course", Parcours.grand_trail().id)

    resultats =
      passages
      |> Enum.with_index()
      |> Enum.map(fn {p, i} -> {i, enregistrer(course, p)} end)

    json(conn, %{
      acceptes: Enum.count(resultats, &match?({_, :ok}, &1)),
      ignores: Enum.count(resultats, &match?({_, {:ignore, _}}, &1)),
      refuses: for({i, {:error, raison}} <- resultats, do: %{ligne: i, raison: raison})
    })
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      erreur:
        "Envoyez {\"passages\": [{\"dossard\", \"point\", \"heure\"}, ...]}, #{@max_par_paquet} au plus par envoi."
    })
  end

  defp enregistrer(course, %{"dossard" => dossard, "point" => point, "heure" => heure})
       when is_integer(dossard) and is_binary(point) do
    with {:ok, heure} <- NaiveDateTime.from_iso8601(to_string(heure)) do
      CourseServeur.passage(course, dossard, point, NaiveDateTime.truncate(heure, :second))
    else
      _ -> {:error, :heure_illisible}
    end
  catch
    :exit, _ -> {:error, :course_inconnue}
  end

  defp enregistrer(_course, _ligne), do: {:error, :ligne_incomplete}

  defp verifier_jeton(conn, _opts) do
    attendu = "Bearer " <> Application.fetch_env!(:suivi_trail, :jeton_chronometreur)

    case get_req_header(conn, "authorization") do
      [recu] -> if Plug.Crypto.secure_compare(recu, attendu), do: conn, else: refuser(conn)
      _ -> refuser(conn)
    end
  end

  defp refuser(conn),
    do:
      conn
      |> put_status(:unauthorized)
      |> json(%{erreur: "Jeton du chronométreur absent ou invalide."})
      |> halt()
end
