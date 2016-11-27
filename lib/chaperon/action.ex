defmodule Chaperon.Action do
  def retry(action, session) do
    with {:ok, session} <- Chaperon.Actionable.abort(action, session) do
      Chaperon.Actionable.run(action, session)
    end
  end

  def error(action, session, reason) do
    %Chaperon.Action.Error{
      reason: reason,
      action: action,
      session: session
    }
  end
end
