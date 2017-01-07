defmodule Chaperon.Action.Function do
  defstruct func: nil,
            called: false

  @type callback :: (Chaperon.Session.t -> Chaperon.Session.t) | atom
  @type t :: %Chaperon.Action.Function{func: callback, called: boolean}
end

defimpl Chaperon.Actionable, for: Chaperon.Action.Function do
  def run(%{func: f}, session) when is_atom(f) do
    apply(session.scenario.module, f, [session])
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
