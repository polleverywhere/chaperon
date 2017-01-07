defprotocol Chaperon.Actionable do
  alias Chaperon.Session
  alias Chaperon.Action.Error

  @type result :: {:ok, Session.t} | {:error, Error.t}
  @type abort_result :: {:ok, Chaperon.Actionable.t, Session.t} | {:error, Error.t}

  @spec run(Chaperon.Actionable.t, Session.t) :: result
  def run(action, session)

  @spec abort(Chaperon.Actionable.t, Session.t) :: abort_result
  def abort(action, session)
end
