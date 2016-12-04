defmodule Chaperon.Util.Test do
  use ExUnit.Case
  doctest Chaperon
  import Chaperon.Util

  test "as_list" do
    assert [] = as_list(nil)
    assert [] = as_list([])
    assert [1] = as_list(1)
    assert [1] = as_list([1])
    assert [1,2] = as_list([1,2])
    assert [1,2,3] = as_list([1,2,3])
  end

  test "preserve_vals_merge" do
    map1 = %{foo: 1, bar: 2, baz: 3}
    map2 = %{foo: 10, bar: 20}

    assert preserve_vals_merge(map1, map2) == %{
      foo: [10, 1],
      bar: [20, 2],
      baz: 3
    }

    assert %{} = preserve_vals_merge(%{}, %{})
    assert preserve_vals_merge(%{foo: 1}, %{bar: 2}) == %{foo: 1, bar: 2}
    assert preserve_vals_merge(%{bar: 2}, %{foo: 1}) == %{foo: 1, bar: 2}
    assert preserve_vals_merge(%{foo: 1, bar: 2}, %{}) == %{foo: 1, bar: 2}
    assert preserve_vals_merge(%{}, %{foo: 1, bar: 2}) == %{foo: 1, bar: 2}
    assert preserve_vals_merge(%{foo: 1, bar: 2}, %{foo: 1, baz: 3}) == %{
      foo: [1,1],
      bar: 2,
      baz: 3
    }
    assert preserve_vals_merge(%{foo: 1, baz: 3}, %{foo: 1, bar: 2}) == %{
      foo: [1,1],
      bar: 2,
      baz: 3
    }
  end
end
