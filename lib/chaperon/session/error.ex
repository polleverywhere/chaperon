defmodule Chaperon.Session.Error do
  alias Chaperon.Session

  defexception reason: nil, session: nil

  @type t :: %Session.Error{
    reason: any,
    session: Session.t
  }

  def message(%Session.Error{reason: reason, session: session}) do
    "[Chaperon.Session.Error: #{session.id}] - #{inspect reason}"
  end
end
