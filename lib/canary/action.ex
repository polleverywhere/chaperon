defprotocol Canary.Action do
  alias Canary.Session
  alias Canary.Action.Error

  @fallback_to_any true

  @type result :: {:ok, Session.t} | {:error, Error.t}

  @spec run(Canary.Action, Session.t) :: result
  def run(action, session)

  @spec abort(Canary.Action, Session.t) :: result
  def abort(action, session)

  @spec retry(Canary.Action, Session.t) :: result
  def retry(action, session)
end

defimpl Canary.Action, for: Any do
  def run(action, session) do
    {:error, error(action, session, "Canary.Action.run not defined")}
  end

  def abort(action, session) do
    {:error, error(action, session, "Canary.Action.abort not defined")}
  end

  def retry(action, session) do
    with {:ok, session} <- Canary.Action.abort(action, session) do
      Canary.Action.run(action, session)
    end
  end

  defp error(action, session, reason)do
    %Canary.Action.Error{
      reason: reason,
      action: action,
      session: session
    }
  end
end
