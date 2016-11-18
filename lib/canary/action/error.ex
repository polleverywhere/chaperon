defmodule Canary.Action.Error do
  alias Canary.Action
  alias Canary.Session

  defexception reason: nil, action: nil, session: nil

  @type t :: %Action.Error{
    reason: any,
    action: Action.t,
    session: Session.t
  }

  def message(%Action.Error{reason: reason, action: action, session: session}) do
    "[Canary.Action.Error: #{inspect action} @ #{inspect session}] - #{inspect reason}"
  end
end
