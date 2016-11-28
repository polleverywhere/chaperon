defmodule Chaperon.Action.Function do
  defstruct func: nil,
            called: false

  @type callback :: (Chaperon.Actionable -> Chaperon.Session.t)
  @type t :: %Chaperon.Action.Function{func: callback, called: boolean}
end

defimpl Chaperon.Actionable, for: Chaperon.Action.Function do
  def run(%{func: f}, session),       do: f.(session)
  def abort(_, session),              do: session
  def retry(function, session),       do: run(function, session)
  def done?(%{called: is_called}, _), do: is_called
end
