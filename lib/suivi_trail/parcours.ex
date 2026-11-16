defmodule SuiviTrail.Parcours do
  @moduledoc """
  Le tracé d'une épreuve : ses points de contrôle, dans l'ordre, avec leur distance,
  leur dénivelé positif cumulé et leur barrière horaire.
  """

  defmodule Point do
    @moduledoc """
    Un point de contrôle. `barriere` : minutes après le départ au-delà desquelles un coureur est arrêté.
    `prep` : la préposition qui va avec son nom, pour écrire « au col », « à la crête », « à l'arrivée ».
    """
    @enforce_keys [:code, :nom, :km, :d_plus]
    defstruct [:code, :nom, :km, :d_plus, barriere: nil, prep: "au"]
  end

  @enforce_keys [:id, :nom, :depart, :points]
  defstruct [:id, :nom, :depart, :points]

  @doc """
  Le « kilomètre-effort », mesure classique du trail : 100 m de montée coûtent à peu près
  autant qu'un kilomètre de plat. Il sert à prévoir le temps d'un tronçon qui grimpe.
  """
  def km_effort(%Point{km: km, d_plus: d_plus}), do: km + d_plus / 100

  @doc "« au Col des Bruyères », « à la Crête de Sarrat », « à l'Arrivée »."
  def au(%{nom: nom} = point) do
    case Map.get(point, :prep, "au") do
      "à l'" -> "à l'" <> nom
      prep -> prep <> " " <> nom
    end
  end

  @doc "« du Col des Bruyères », « de la Crête de Sarrat », « de l'Arrivée »."
  def du(%{nom: nom} = point) do
    case Map.get(point, :prep, "au") do
      "à l'" -> "de l'" <> nom
      "à la" -> "de la " <> nom
      _ -> "du " <> nom
    end
  end

  def point(%__MODULE__{points: points}, code), do: Enum.find(points, &(&1.code == code))

  def index(%__MODULE__{points: points}, code), do: Enum.find_index(points, &(&1.code == code))

  def suivant(%__MODULE__{points: points} = parcours, code) do
    case index(parcours, code) do
      nil -> nil
      i -> Enum.at(points, i + 1)
    end
  end

  def arrivee(%__MODULE__{points: points}), do: List.last(points)

  @doc "Le grand trail de démonstration : 42,5 km et 2 150 m de dénivelé positif."
  def grand_trail do
    %__MODULE__{
      id: "grand-trail",
      nom: "Grand trail des crêtes",
      depart: ~N[2027-05-15 07:30:00],
      points: [
        %Point{code: "DEP", nom: "Départ", km: 0.0, d_plus: 0},
        %Point{code: "BRU", nom: "Col des Bruyères", km: 9.2, d_plus: 620},
        %Point{code: "LAC", nom: "Lac d'Ourrec", km: 18.5, d_plus: 980, barriere: 240},
        %Point{
          code: "CRE",
          nom: "Crête de Sarrat",
          km: 27.0,
          d_plus: 1620,
          barriere: 390,
          prep: "à la"
        },
        %Point{code: "REF", nom: "Refuge de Peyrelade", km: 34.4, d_plus: 1980, barriere: 510},
        %Point{code: "ARR", nom: "Arrivée", km: 42.5, d_plus: 2150, barriere: 600, prep: "à l'"}
      ]
    }
  end
end
