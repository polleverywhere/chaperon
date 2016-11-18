defmodule Canary.Action.Error do
  alias Canary.Actionable
  alias Canary.Session

  defexception reason: nil, action: nil, session: nil

  @type t :: %__MODULE__{
    reason: any,
    action: Actionable,
    session: Session.t
  }

  def message(%__MODULE__{reason: reason, action: action, session: session}) do
    "[Canary.Action.Error: #{inspect action} @ #{inspect session}] - #{inspect reason}"
  end
end
