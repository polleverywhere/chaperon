defmodule Chaperon.Util do
  @moduledoc """
  Helper functions used throughout `Chaperon`'s codebase.
  """

  @doc """
  Converts a given value to a list.
  If given a list, simply returns the list.
  Otherwise wraps the given value in a list.

  ## Examples

      iex> Chaperon.Util.as_list([1,2,3])
      [1,2,3]
      iex> Chaperon.Util.as_list(nil)
      []
      iex> Chaperon.Util.as_list(1)
      [1]
      iex> Chaperon.Util.as_list("foo")
      ["foo"]
  """
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

  @doc """
  Converts a map's values to be prefixed (put in a tuple as the first element).

  ## Examples

      iex> Chaperon.Util.map_prefix_value(%{foo: 1, bar: 2}, :wat)
      %{foo: {:wat, 1}, bar: {:wat, 2}}
  """
  @spec map_prefix_value(map, any) :: map
  def map_prefix_value(map, prefix) do
    for {k, v} <- map do
      {k, {prefix, v}}
    end
    |> Enum.into(%{})
  end

  @spec map_nested_put(map, any, any) :: map
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
