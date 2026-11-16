defmodule SuiviTrail.Course do
  @moduledoc """
  L'état d'une épreuve le jour J, en fonctions pures : enregistrer un passage, classer,
  repérer les coureurs en retard. Aucune horloge ni processus ici : l'heure est toujours
  passée en paramètre, ce qui rend chaque règle testable à la seconde près.
  """

  alias SuiviTrail.Parcours

  defmodule Coureur do
    @moduledoc false
    @enforce_keys [:dossard, :nom, :prenom, :sexe, :categorie]
    defstruct [:dossard, :nom, :prenom, :sexe, :categorie, :club]
  end

  @enforce_keys [:parcours, :coureurs]
  defstruct [:parcours, :coureurs, passages: %{}, abandons: %{}, alertes_traitees: MapSet.new()]

  @typedoc "Passages d'un coureur : code du point => heure de passage."
  @type passages :: %{String.t() => NaiveDateTime.t()}

  # Un coureur dont le temps sans nouvelles dépasse 1,5 fois le temps prévu du tronçon,
  # plus cette marge, déclenche une alerte de sécurité.
  @facteur_retard 1.5
  @marge_retard_s 15 * 60
  # Allure de référence quand on ne sait encore rien d'un coureur (en secondes par km-effort).
  @allure_par_defaut 9 * 60

  def nouvelle(%Parcours{} = parcours, coureurs) do
    %__MODULE__{parcours: parcours, coureurs: Map.new(coureurs, &{&1.dossard, &1})}
  end

  @doc """
  Enregistre un passage lu par un tapis de chronométrage ou saisi à la main.

  Un tapis lit souvent la même puce plusieurs fois : un deuxième passage au même point
  est ignoré. Les passages peuvent arriver dans le désordre (un point en zone blanche
  transmet en retard) : on les range par point, pas par ordre d'arrivée.
  """
  def enregistrer(%__MODULE__{} = c, dossard, code, %NaiveDateTime{} = heure) do
    cond do
      not Map.has_key?(c.coureurs, dossard) ->
        {:error, :dossard_inconnu}

      Parcours.point(c.parcours, code) == nil ->
        {:error, :point_inconnu}

      NaiveDateTime.compare(heure, c.parcours.depart) == :lt ->
        {:error, :avant_le_depart}

      Map.has_key?(Map.get(c.passages, dossard, %{}), code) ->
        {:ignore, :deja_enregistre}

      true ->
        {:ok,
         %{
           c
           | passages:
               Map.update(c.passages, dossard, %{code => heure}, &Map.put(&1, code, heure))
         }}
    end
  end

  @doc "Le PC sécurité déclare un abandon au point donné : le coureur sort du classement et des alertes."
  def abandon(%__MODULE__{} = c, dossard, code) do
    if Map.has_key?(c.coureurs, dossard),
      do: {:ok, %{c | abandons: Map.put(c.abandons, dossard, code)}},
      else: {:error, :dossard_inconnu}
  end

  def traiter_alerte(%__MODULE__{} = c, dossard, code) do
    %{c | alertes_traitees: MapSet.put(c.alertes_traitees, {dossard, code})}
  end

  @doc "Le dernier point atteint par un coureur, avec l'heure, ou nil s'il n'est pas passé au départ."
  def dernier_passage(%__MODULE__{} = c, dossard) do
    case Map.get(c.passages, dossard) do
      nil -> nil
      points -> Enum.max_by(points, fn {code, _} -> Parcours.index(c.parcours, code) end)
    end
  end

  def arrive?(%__MODULE__{} = c, dossard),
    do: Map.has_key?(Map.get(c.passages, dossard, %{}), Parcours.arrivee(c.parcours).code)

  @doc """
  Le classement à l'instant : d'abord le point le plus avancé, puis l'heure d'arrivée à ce point.
  Les abandons et les coureurs jamais partis n'y figurent pas. Les filtres (sexe, catégorie)
  donnent un rang propre à la sélection, comme sur un classement officiel.
  """
  def classement(%__MODULE__{} = c, filtres \\ %{}) do
    c.passages
    |> Enum.reject(fn {dossard, _} -> Map.has_key?(c.abandons, dossard) end)
    |> Enum.map(fn {dossard, _} ->
      {code, heure} = dernier_passage(c, dossard)
      {Map.fetch!(c.coureurs, dossard), Parcours.point(c.parcours, code), heure}
    end)
    |> Enum.filter(fn {coureur, _, _} -> garde?(coureur, filtres) end)
    |> Enum.sort_by(fn {_, point, heure} ->
      {-Parcours.index(c.parcours, point.code), NaiveDateTime.to_gregorian_seconds(heure)}
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {{coureur, point, heure}, rang} ->
      %{
        rang: rang,
        coureur: coureur,
        point: point,
        heure: heure,
        temps: NaiveDateTime.diff(heure, c.parcours.depart)
      }
    end)
  end

  defp garde?(coureur, filtres) do
    Enum.all?(filtres, fn
      {_, v} when v in [nil, ""] -> true
      {:sexe, v} -> coureur.sexe == v
      {:categorie, v} -> coureur.categorie == v
      {:recherche, v} -> correspond?(coureur, v)
    end)
  end

  defp correspond?(coureur, texte) do
    t = String.downcase(String.trim(texte))

    Integer.to_string(coureur.dossard) == t or
      String.contains?(String.downcase("#{coureur.prenom} #{coureur.nom}"), t)
  end

  @doc """
  La fiche d'un coureur : chaque point passé, son temps, son rang à ce point,
  et une estimation de l'heure d'arrivée tirée de son allure.
  """
  def fiche(%__MODULE__{} = c, dossard) do
    with %Coureur{} = coureur <- Map.get(c.coureurs, dossard) do
      passages = Map.get(c.passages, dossard, %{})

      etapes =
        for point <- c.parcours.points do
          case Map.get(passages, point.code) do
            nil ->
              %{point: point, heure: nil, temps: nil, rang: nil}

            heure ->
              %{
                point: point,
                heure: heure,
                temps: NaiveDateTime.diff(heure, c.parcours.depart),
                rang: rang_au_point(c, point.code, heure)
              }
          end
        end

      %{
        coureur: coureur,
        etapes: etapes,
        abandon: Map.get(c.abandons, dossard),
        arrivee_estimee: arrivee_estimee(c, dossard)
      }
    end
  end

  defp rang_au_point(c, code, heure) do
    1 +
      Enum.count(c.passages, fn {_, points} ->
        case Map.get(points, code) do
          nil -> false
          h -> NaiveDateTime.compare(h, heure) == :lt
        end
      end)
  end

  @doc "Allure d'un coureur depuis le départ, en secondes par km-effort, ou nil s'il n'a pas dépassé le départ."
  def allure(%__MODULE__{} = c, dossard) do
    case dernier_passage(c, dossard) do
      {code, heure} when code != "DEP" ->
        Parcours.point(c.parcours, code)
        |> then(&(NaiveDateTime.diff(heure, c.parcours.depart) / Parcours.km_effort(&1)))

      _ ->
        nil
    end
  end

  defp arrivee_estimee(c, dossard) do
    with false <- arrive?(c, dossard),
         false <- Map.has_key?(c.abandons, dossard),
         allure when is_number(allure) <- allure(c, dossard) do
      secondes = round(allure * Parcours.km_effort(Parcours.arrivee(c.parcours)))
      NaiveDateTime.add(c.parcours.depart, secondes)
    else
      _ -> nil
    end
  end

  @doc """
  Les coureurs dont le PC sécurité doit s'occuper maintenant.

  * `:hors_delai` : la barrière horaire du point suivant est passée sans qu'il y soit arrivé.
  * `:retard` : il n'a plus donné de nouvelles depuis bien plus longtemps que le temps prévu
    pour le tronçon, calculé avec sa propre allure et le dénivelé du tronçon.

  Une alerte déjà prise en charge n'est plus remontée.
  """
  def alertes(%__MODULE__{} = c, %NaiveDateTime{} = maintenant) do
    allure_mediane = allure_mediane(c)

    c.passages
    |> Enum.reject(fn {dossard, _} ->
      Map.has_key?(c.abandons, dossard) or arrive?(c, dossard)
    end)
    |> Enum.flat_map(fn {dossard, _} ->
      {code, heure} = dernier_passage(c, dossard)
      point = Parcours.point(c.parcours, code)
      suivant = Parcours.suivant(c.parcours, code)
      depuis = NaiveDateTime.diff(maintenant, heure)

      alerte =
        cond do
          suivant.barriere &&
              NaiveDateTime.diff(maintenant, c.parcours.depart) > suivant.barriere * 60 ->
            %{type: :hors_delai, attendu: nil}

          true ->
            allure = allure(c, dossard) || allure_mediane
            attendu = round(allure * (Parcours.km_effort(suivant) - Parcours.km_effort(point)))

            if depuis > attendu * @facteur_retard + @marge_retard_s,
              do: %{type: :retard, attendu: attendu}
        end

      if alerte && not MapSet.member?(c.alertes_traitees, {dossard, code}) do
        [
          Map.merge(alerte, %{
            coureur: Map.fetch!(c.coureurs, dossard),
            dernier: point,
            suivant: suivant,
            heure: heure,
            depuis: depuis
          })
        ]
      else
        []
      end
    end)
    |> Enum.sort_by(fn a -> {if(a.type == :hors_delai, do: 0, else: 1), -a.depuis} end)
  end

  defp allure_mediane(c) do
    allures =
      c.passages
      |> Map.keys()
      |> Enum.map(&allure(c, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    case allures do
      [] -> @allure_par_defaut
      liste -> Enum.at(liste, div(length(liste), 2))
    end
  end

  @doc "Par point : combien de coureurs y sont passés, et combien sont encore en course avant lui."
  def statistiques(%__MODULE__{} = c) do
    en_course =
      c.passages
      |> Enum.reject(fn {dossard, _} -> Map.has_key?(c.abandons, dossard) end)
      |> Enum.map(fn {dossard, _} ->
        dernier_passage(c, dossard) |> elem(0) |> then(&Parcours.index(c.parcours, &1))
      end)

    for {point, i} <- Enum.with_index(c.parcours.points) do
      %{
        point: point,
        passes: Enum.count(c.passages, fn {_, p} -> Map.has_key?(p, point.code) end),
        avant: Enum.count(en_course, &(&1 < i))
      }
    end
  end
end
