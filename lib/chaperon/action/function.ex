defmodule Chaperon.Action.Function do
  defstruct func: nil

  @type callback :: (Chaperon.Actionable -> Chaperon.Session.t)
  @type t :: %Chaperon.Action.Function{func: callback}
end

defimpl Chaperon.Actionable, for: Chaperon.Action.Function do
  def run(%{func: f}, session), do: f.(session)
  def abort(_, session),        do: session
  def retry(action, session),   do: run(action, session)
end
