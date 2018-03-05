defmodule Chaperon.Session.Test do
  use ExUnit.Case
  doctest Chaperon.Session
  alias Chaperon.Session

  setup do
    {:ok, %{session: %Session{}}}
  end

  test "assign", %{session: s} do
    assert Session.assign(s, foo: 1, bar: 2).assigned == %{
             foo: 1,
             bar: 2
           }

    assert Session.assign(s, foo: 1).assigned == %{foo: 1}
  end

  test "config" do
    s = %Session{
      config: %{
        key: "value",
        nested: %{nested_key: "okidoki"}
      }
    }

    assert Session.config(s, :key) == "value"
    assert Session.config(s, :nested) == %{nested_key: "okidoki"}
    assert Session.config(s, [:nested, :nested_key]) == "okidoki"
    assert Session.config(s, "nested.nested_key") == "okidoki"
    assert Session.config(s, "nested.nested_key", "default") == "okidoki"
    assert Session.config(s, "nested.not_defined", "default") == "default"
  end
end
