defmodule Chaperon.Action.CallFunction.Test do
  @moduledoc false
  use ExUnit.Case
  doctest Chaperon.Action.CallFunction

  alias Chaperon.Action.CallFunction
  alias Chaperon.Session

  defp new_session(config \\ %{}) do
    s = %Chaperon.Scenario{module: __MODULE__}
    Chaperon.Scenario.new_session(s, config)
  end

  def foo(session, a, b, c) do
    session
    |> Session.assign(foo: {a, b, c})
  end

  def bar(session) do
    session
    |> Session.assign(bar: "Hello, World!")
  end

  test "call function via function name without args" do
    action = %CallFunction{func: :bar}
    assert {:ok, s} = Chaperon.Actionable.run(action, new_session())
    assert s.assigned.bar == "Hello, World!"
  end

  test "call function via function name" do
    action = %CallFunction{func: :foo, args: [1, 2, 3]}
    assert {:ok, s} = Chaperon.Actionable.run(action, new_session())
    assert s.assigned.foo == {1, 2, 3}
  end

  test "call via anonymous function without args" do
    func = fn session ->
      session
      |> Session.assign(anon_foo: :cool)
    end
    action = %CallFunction{func: func}
    assert {:ok, s} = Chaperon.Actionable.run(action, new_session())
    assert s.assigned.anon_foo == :cool
  end

  test "call via anonymous function" do
    func = fn session, a, b, c ->
      session
      |> Session.assign(anon_foo: {a, b, c})
    end
    action = %CallFunction{func: func, args: [1, 2, 3]}
    assert {:ok, s} = Chaperon.Actionable.run(action, new_session())
    assert s.assigned.anon_foo == {1, 2, 3}
  end
end
