defmodule SuiviTrail.Fixtures do
  @moduledoc "Une petite course de test, assez simple pour vérifier chaque calcul à la main."

  alias SuiviTrail.Course.Coureur
  alias SuiviTrail.Parcours
  alias SuiviTrail.Parcours.Point

  @depart ~N[2027-05-15 07:30:00]

  def depart, do: @depart

  @doc "Départ, puis 10 km sans dénivelé (barrière à 3 h), puis 10 km avec 500 m D+ jusqu'à l'arrivée."
  def parcours(id \\ "test") do
    %Parcours{
      id: id,
      nom: "Trail de test",
      depart: @depart,
      points: [
        %Point{code: "DEP", nom: "Départ", km: 0.0, d_plus: 0},
        %Point{code: "A", nom: "Point A", km: 10.0, d_plus: 0, barriere: 180},
        %Point{code: "ARR", nom: "Arrivée", km: 20.0, d_plus: 500, barriere: 360}
      ]
    }
  end

  def coureurs do
    [
      %Coureur{dossard: 1, nom: "Lacoste", prenom: "Maïa", sexe: "F", categorie: "SE"},
      %Coureur{dossard: 2, nom: "Darrigade", prenom: "Iban", sexe: "H", categorie: "M1"},
      %Coureur{dossard: 3, nom: "Hourcade", prenom: "Léa", sexe: "F", categorie: "M1"},
      %Coureur{dossard: 4, nom: "Peyrot", prenom: "Jon", sexe: "H", categorie: "SE"}
    ]
  end

  @doc "Une heure de course, en minutes après le départ."
  def a(minutes), do: NaiveDateTime.add(@depart, minutes * 60)
end
