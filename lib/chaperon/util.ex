defmodule Chaperon.Util do
  @spec as_list(any) :: [any]
  def as_list(nil),
    do: []
  def as_list(l) when is_list(l),
    do: l
  def as_list(val),
    do: [val]

  @spec preserve_vals_merge(map, map) :: map
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
