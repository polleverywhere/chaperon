defmodule Chaperon.Action do
  @moduledoc """
  Helper functions to be used with `Chaperon.Actionable`.
  """

  @doc """
  Retries `action` within `session` by calling `Chaperon.Actionable.abort/2`
  followed by `Chaperon.Actionable.run/2`.
  """
  def retry(action, session) do
    with {:ok, action, session} <- Chaperon.Actionable.abort(action, session) do
      Chaperon.Actionable.run(action, session)
    end
  end

  @doc """
  Returns a `Chaperon.Action.Error` for the given arguments.
  """
  def error(action, session, reason) do
    %Chaperon.Action.Error{
      reason: reason,
      action: action,
      session: session
    }
  end
end
