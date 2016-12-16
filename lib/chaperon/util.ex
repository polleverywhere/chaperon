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

  def map_prefix_value(map, prefix) do
    for {k, v} <- map do
      {k, {prefix, v}}
    end
    |> Enum.into(%{})
  end

  def map_nested_put(map, k2, v2) do
    for {k, v} <- map do
      case v do
        v when is_map(v) ->
          {k, Map.put(v, k2, v2)}
        v ->
          {k, v}
      end
    end
    |> Enum.into(%{})
  end
end
