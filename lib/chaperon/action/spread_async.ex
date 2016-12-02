defmodule Chaperon.Action.SpreadAsync do
  defstruct [:callback, :rate, :interval]

  @type rate :: non_neg_integer
  @type time :: non_neg_integer

  @type t :: %__MODULE__{rate: rate, interval: time}
end

defimpl Chaperon.Actionable, for: Chaperon.Action.SpreadAsync do
  def run(action, session) do
    # TODO
    {:ok, session}
  end

  def abort(action, session) do
    # TODO
    {:ok, session}
  end

  def retry(action, session) do
    Chaperon.Action.retry(action, session)
  end
end
