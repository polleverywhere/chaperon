defmodule Canary.Action.HTTP do
  defstruct [
    method: :get,
    path: nil,
    args: %{}
  ]

  @type method :: :get | :post | :put | :patch | :delete

  @type t :: %Canary.Action.HTTP{
    method: method,
    path: String.t,
    args: map
  }
end

defimpl Canary.Actionable, for: Canary.Action.HTTP do
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
