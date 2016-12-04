defmodule Chaperon.Action.Function do
  defstruct func: nil,
            called: false

  @type callback :: (Chaperon.Session.t -> Chaperon.Session.t)
  @type t :: %Chaperon.Action.Function{func: callback, called: boolean}
end

defimpl Chaperon.Actionable, for: Chaperon.Action.Function do
  def run(%{func: f}, session), do: f.(session)
  def abort(_, session),        do: session
  def retry(function, session), do: run(function, session)
end

defimpl String.Chars, for: Chaperon.Action.Function do
  def to_string(%{func: func}) when is_atom(func) do
    "#{func}"
  end

  def to_string(%{func: func}) when is_function(func) do
    "Function[#{inspect func}]"
  end
end
