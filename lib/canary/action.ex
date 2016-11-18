defprotocol Canary.Actionable do
  alias Canary.Session
  alias Canary.Action.Error

  @type result :: Session.t | {:ok, Session.t} | {:error, Error.t}

  @spec run(Canary.Actionable.t, Session.t) :: result
  def run(action, session)

  @spec abort(Canary.Actionable.t, Session.t) :: result
  def abort(action, session)

  @spec retry(Canary.Actionable.t, Session.t) :: result
  def retry(action, session)
end

defmodule Canary.Action do
  def retry(action, session) do
    with {:ok, session} <- Canary.Actionable.abort(action, session) do
      Canary.Actionable.run(action, session)
    end
  end

  def error(action, session, reason) do
    %Canary.Action.Error{
      reason: reason,
      action: action,
      session: session
    }
  end
end

defmodule Canary.Action.Function do
  defstruct func: nil

  @type callback :: (Canary.Actionable -> Canary.Session.t)
  @type t :: %Canary.Action.Function{func: callback}
end

defimpl Canary.Actionable, for: Canary.Action.Function do
  def run(%{func: f}, session), do: f.(session)
  def abort(_, session),        do: session
  def retry(action, session),   do: run(action, session)
end
