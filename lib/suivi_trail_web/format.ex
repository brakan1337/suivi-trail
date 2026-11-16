defmodule SuiviTrailWeb.Format do
  @moduledoc "Mise en forme française des durées, heures et distances."

  @doc "3725 → « 1:02:05 »"
  def duree(nil), do: "—"

  def duree(secondes) when is_integer(secondes) do
    h = div(secondes, 3600)
    m = secondes |> rem(3600) |> div(60)
    s = rem(secondes, 60)
    "#{h}:#{pad(m)}:#{pad(s)}"
  end

  @doc "Durée courte pour les alertes : « 47 min », « 1 h 12 »."
  def minutes(secondes) do
    m = div(secondes, 60)
    if m < 60, do: "#{m} min", else: "#{div(m, 60)} h #{pad(rem(m, 60))}"
  end

  def heure(nil), do: "—"
  def heure(%NaiveDateTime{} = t), do: "#{pad(t.hour)}:#{pad(t.minute)}:#{pad(t.second)}"

  def km(km), do: km |> :erlang.float_to_binary(decimals: 1) |> String.replace(".", ",")

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")
end
