defmodule Chaperon.Action.CallFunction do
  @moduledoc """
  Performs & measures a function call (with args) within a session's
  `Chaperon.Scenario` module.
  """

  defstruct func: nil,
            args: []

  @type callback ::
          atom
          | {module, atom}
          | (Chaperon.Session.t() -> Chaperon.Session.t())

  @type t :: %Chaperon.Action.CallFunction{
          func: callback,
          args: [any]
        }
end

defimpl Chaperon.Actionable, for: Chaperon.Action.CallFunction do
  alias Chaperon.Session

  def run(%{func: f, args: args}, session) when is_atom(f) do
    metric = {:call, {session.scenario.module, f}}

    session
    |> Session.time(metric, fn session ->
      apply(session.scenario.module, f, [session | args])
    end)
    |> Session.ok()
  end

  def run(%{func: {mod, f}, args: args}, session) do
    metric = {:call, {mod, f}}

    session
    |> Session.time(metric, fn session ->
      apply(mod, f, [session | args])
    end)
    |> Session.ok()
  end

  def run(%{func: f, args: args}, session) do
    metric = {:call, inspect(f)}

    session
    |> Session.time(metric, fn session ->
      f
      |> apply([session | args])
    end)
    |> Session.ok()
  end

  def abort(action, session) do
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.CallFunction do
  def to_string(%{func: func}) when is_atom(func) do
    "#{func}"
  end

  def to_string(%{func: func}) when is_function(func) do
    "Function[#{inspect(func)}]"
  end
end
