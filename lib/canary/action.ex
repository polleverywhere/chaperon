defprotocol Canary.Actionable do
  alias Canary.Session
  alias Canary.Action.Error

  @type result :: {:ok, Session.t} | {:error, Error.t}

  @spec run(Canary.Action, Session.t) :: result
  def run(action, session)

  @spec abort(Canary.Action, Session.t) :: result
  def abort(action, session)

  @spec retry(Canary.Action, Session.t) :: result
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
