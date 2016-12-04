defmodule Chaperon.Util do
  def as_list(nil), do: []
  def as_list([h|t]), do: [h|t]
  def as_list(val), do: [val]

  def preserve_vals_merge(map1, map2) do
    new_map = for {k,v} <- map2 do
      case map1[k] do
        nil ->
          {k, v}
        vals when is_list(vals) ->
          {k, [v|vals]}
        val ->
          {k, [v, val]}
      end
    end
    |> Enum.into(%{})

    map1
    |> Map.merge(new_map)
  end
end
