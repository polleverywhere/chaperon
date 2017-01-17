defmodule Chaperon.Action.Function do
  @moduledoc """
  Performs & measures a function call (with args) within a session's
  `Chaperon.Scenario` module.
  """

  defstruct [
    func: nil,
    called: false,
    args: []
  ]

  @type callback :: atom
                    | (Chaperon.Session.t -> Chaperon.Session.t)

  @type t :: %Chaperon.Action.Function{
    func: callback,
    called: boolean,
    args: [any]
  }
end

defimpl Chaperon.Actionable, for: Chaperon.Action.Function do
  import Chaperon.Timing
  alias Chaperon.Session

  def run(%{func: f, args: args}, session) when is_atom(f) do
    start = timestamp
    session = apply(session.scenario.module, f, [session | args])
    session
    |> Session.add_metric([:duration, :call, f], timestamp - start)
    |> Session.ok
  end
  def run(%{func: f}, session), do: f.(session)
  def abort(func, session),     do: {:ok, func, session}
end

defimpl String.Chars, for: Chaperon.Action.Function do
  def to_string(%{func: func}) when is_atom(func) do
    "#{func}"
  end

  def to_string(%{func: func}) when is_function(func) do
    "Function[#{inspect func}]"
  end
end
