defmodule SuiviTrail.Engages do
  @moduledoc """
  La liste des coureurs engagés. En vrai, elle vient de l'export des inscriptions ;
  ici, une liste fictive et déterministe pour la démonstration.
  """

  alias SuiviTrail.Course.Coureur

  @prenoms_f ~w(Léa Manon Chloé Inès Camille Sarah Jade Louise Emma Lucie Ambre Maïa Anaïs Clara Pauline Elsa Marion Julie Laure Nina)
  @prenoms_h ~w(Hugo Lucas Louis Arthur Jules Léo Gabriel Paul Ethan Nathan Tom Mathis Romain Julien Thomas Pierre Antoine Bastien Iban Peio)
  @noms ~w(Lacoste Darrigade Hourcade Larrieu Peyrot Bénesse Laborde Dufau Lafitte Etcheverry Castaing Duprat Lalanne Mirande
           Barrère Cazenave Labat Sallaberry Pujol Garat Lafargue Tauzin Dubos Lassalle Bordes Camblong Harriague Lamarque
           Saint-Martin Domecq Ithurralde Larrouy Haramboure Destenave Lagardère)
  @categories [
    {"SE", 30},
    {"M0", 18},
    {"M1", 16},
    {"M2", 13},
    {"M3", 10},
    {"M4", 7},
    {"M5", 4},
    {"ES", 2}
  ]

  @doc "`nombre` coureurs, dossards 1 à `nombre`, toujours les mêmes pour une même graine."
  def demo(nombre \\ 396, graine \\ 2027) do
    :rand.seed(:exsss, {graine, graine, graine})

    for dossard <- 1..nombre do
      sexe = if :rand.uniform() < 0.3, do: "F", else: "H"

      %Coureur{
        dossard: dossard,
        sexe: sexe,
        prenom: Enum.random(if sexe == "F", do: @prenoms_f, else: @prenoms_h),
        nom: Enum.random(@noms),
        categorie: tirer(@categories),
        club:
          if(:rand.uniform() < 0.3,
            do: "AC " <> Enum.random(~w(Dax Pau Mont-de-Marsan Bayonne Orthez Tarbes)),
            else: nil
          )
      }
    end
  end

  defp tirer(ponderes) do
    total = ponderes |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    cible = :rand.uniform(total)

    Enum.reduce_while(ponderes, 0, fn {valeur, poids}, cumul ->
      if cumul + poids >= cible, do: {:halt, valeur}, else: {:cont, cumul + poids}
    end)
  end
end
