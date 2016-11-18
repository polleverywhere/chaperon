defmodule Canary.Action.SpreadAsync do
  defstruct [:callback, :rate, :spread]

  @type rate   :: non_neg_integer
  @type spread :: non_neg_integer

  @type t :: %__MODULE__{rate: rate, spread: spread}
end

defimpl Canary.Actionable, for: Canary.Action.SpreadAsync do
  def run(action, session) do
    # TODO
    {:ok, session}
  end

  def abort(action, session) do
    # TODO
    {:ok, session}
  end

  def retry(action, session) do
    Canary.Action.Any.retry(action, session)
  end
end
