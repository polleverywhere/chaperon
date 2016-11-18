defmodule Canary.Session.Error do
  alias Canary.Session

  defexception reason: nil, session: nil

  @type t :: %Session.Error{
    reason: any,
    session: Session.t
  }

  def message(%Session.Error{reason: reason, session: session}) do
    "[Canary.Session.Error: #{session.id}] - #{inspect reason}"
  end
end
