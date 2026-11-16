defmodule SuiviTrail.Horloge do
  @moduledoc """
  L'heure de la course. Le jour J, c'est l'heure locale. Pour la démonstration,
  le simulateur la recale avant le départ et la fait défiler plus vite :
  toute l'application (alertes comprises) vit alors à l'heure simulée.
  """
  use Agent

  def start_link(_), do: Agent.start_link(fn -> :reelle end, name: __MODULE__)

  @doc "Heure de course courante."
  def maintenant do
    case Agent.get(__MODULE__, & &1) do
      :reelle ->
        NaiveDateTime.local_now()

      {ancre_reelle, ancre_course, vitesse} ->
        ecoule_ms = System.monotonic_time(:millisecond) - ancre_reelle
        NaiveDateTime.add(ancre_course, round(ecoule_ms * vitesse), :millisecond)
    end
  end

  @doc "Fait partir l'heure de course de `debut`, à `vitesse` fois le temps réel."
  def accelerer(%NaiveDateTime{} = debut, vitesse) when vitesse > 0 do
    Agent.update(__MODULE__, fn _ -> {System.monotonic_time(:millisecond), debut, vitesse} end)
  end

  @doc "Revient à l'heure réelle."
  def reelle, do: Agent.update(__MODULE__, fn _ -> :reelle end)

  def vitesse do
    case Agent.get(__MODULE__, & &1) do
      :reelle -> 1
      {_, _, v} -> v
    end
  end
end
