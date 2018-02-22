defprotocol Chaperon.Actionable do
  @moduledoc """
  Protocol implemented by all valid measurable actions that can be performed
  in a `Chaperon.Session`. All Actions implementing this protocol are found
  within the `Chaperon.Action` module.
  """

  alias Chaperon.Session
  alias Chaperon.Action.Error

  @type error ::
          {:error, Error.t()}
          | {:error, Chaperon.Session.Error.t()}
          | {:error, any}
  @type result :: {:ok, Session.t()} | error
  @type abort_result :: {:ok, Chaperon.Actionable.t(), Session.t()} | error

  @doc """
  Attempts to run a `Chaperon.Actionable` within a `Chaperon.Session` and
  returns the resulting session or a `Chaperon.Action.Error`.
  """
  @spec run(Chaperon.Actionable.t(), Session.t()) :: result
  def run(action, session)

  @doc """
  Attempts to abort a `Chaperon.Actionable` within a `Chaperon.Session` and
  returns the resulting `Chaperon.Actionable` and `Chaperon.Session` or a
  `Chaperon.Action.Error`.
  """
  @spec abort(Chaperon.Actionable.t(), Session.t()) :: abort_result
  def abort(action, session)
end
