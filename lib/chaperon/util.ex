defmodule Chaperon.Util do
  @moduledoc """
  Helper functions used throughout `Chaperon`'s codebase.
  """

  @spec preserve_vals_merge(map, map) :: map
  def preserve_vals_merge(map1, map2) do
    new_map = for {k, v2} <- map2 do
      case map1[k] do
        nil ->
          {k, v2}
        v1 when is_list(v1) and is_list(v2) ->
          {k, v2 ++ v1}
        v1 when is_list(v1) ->
          {k, [v2 | v1]}
        v1 ->
          {k, [v2, v1]}
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

  @doc """
  Inserts a given key-value pair (`{k2, v2}` under any values within `map` that
  are also maps).

  ## Example

      iex> m = %{a: 1, b: %{baz: 3}, c: %{foo: 1, bar: 2}}
      iex> Chaperon.Util.map_nested_put(m, :baz, 10)
      %{a: 1, b: %{baz: 10}, c: %{foo: 1, bar: 2, baz: 10}}
      iex> Chaperon.Util.map_nested_put(m, :foo, "ok")
      %{a: 1, b: %{baz: 3, foo: "ok"}, c: %{foo: "ok", bar: 2}}
  """
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

  @doc """
  Returns last `amount` elements in a given `Enum` as a `List`.

  ## Example

      iex> alias Chaperon.Util
      iex> [] |> Util.last(1)
      []
      iex> [1] |> Util.last(1)
      [1]
      iex> [1,2,3,4] |> Util.last(1)
      [4]
      iex> [1,2,3,4] |> Util.last(2)
      [3,4]
      iex> [1,2,3,4] |> Util.last(3)
      [2,3,4]
      iex> [1,2,3,4] |> Util.last(4)
      [1,2,3,4]
      iex> [1,2,3,4] |> Util.last(5)
      [1,2,3,4]
  """
  def last(enum, amount) when is_list(enum) do
    case Enum.count(enum) - amount do
      n when n > 0 ->
        enum
        |> Enum.drop(n)
      _ ->
        enum
    end
  end

  def shortened_module_name(mod) do
    mod
    |> Module.split
    |> last(2)
    |> Enum.join(".")
  end

  @spec module_name(module) :: String.t
  def module_name(mod) when is_atom(mod) do
    mod
    |> Module.split
    |> Enum.join(".")
  end

  @spec local_pid?(pid) :: boolean
  def local_pid?(pid) do
    case inspect(pid) do
      "#PID<0." <> _ ->
        true
      _ ->
        false
    end
  end

  def percentile_name(percentile) do
    p =
      percentile
      |> to_string
      |> String.replace(".", "_")

    :"percentile_#{p}"
  end
end
