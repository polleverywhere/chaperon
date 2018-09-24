defmodule Chaperon.Util.Test do
  use ExUnit.Case
  doctest Chaperon.Util
  import Chaperon.Util

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
             foo: [1, 1],
             bar: 2,
             baz: 3
           }

    assert preserve_vals_merge(%{foo: 1, baz: 3}, %{foo: 1, bar: 2}) == %{
             foo: [1, 1],
             bar: 2,
             baz: 3
           }

    m1 = %{foo: [1, 2], bar: [10, 20, 30]}
    m2 = %{foo: 0, bar: [0, 100, 200]}

    assert preserve_vals_merge(m1, m2) == %{
             foo: [0, 1, 2],
             bar: [0, 100, 200, 10, 20, 30]
           }
  end

  test "shortened_module_name" do
    assert shortened_module_name(Chaperon.Util.Test) == "Util.Test"
    assert shortened_module_name(%{name: "Foo.Bar"}) == "Foo.Bar"

    assert shortened_module_name(Chaperon.Util.Test, 1) == "Test"
    assert shortened_module_name(%{name: "Foo.Bar"}, 1) == "Bar"

    assert shortened_module_name(Chaperon.Util.Test, 3) == "Chaperon.Util.Test"
    assert shortened_module_name(%{name: "Foo.Bar"}, 3) == "Foo.Bar"
  end

  test "module_name" do
    assert module_name(Chaperon.Util.Test) == "Chaperon.Util.Test"
    assert module_name(%{name: "Foo.Bar"}) == "Foo.Bar"
  end
end
