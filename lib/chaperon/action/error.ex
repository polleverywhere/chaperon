defmodule Chaperon.Action.Error do
  alias Chaperon.Actionable
  alias Chaperon.Session

  defexception reason: nil, action: nil, session: nil

  @type t :: %__MODULE__{
    reason: any,
    action: Actionable,
    session: Session.t
  }

  def message(%__MODULE__{reason: reason, action: action, session: session}) do
    "[Chaperon.Action.Error: #{inspect action} @ #{inspect session}] - #{inspect reason}"
  end
end
