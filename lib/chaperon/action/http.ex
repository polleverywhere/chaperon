defmodule Chaperon.Action.HTTP do
  defstruct [
    method: :get,
    path: nil,
    args: %{}
  ]

  @type method :: :get | :post | :put | :patch | :delete

  @type t :: %Chaperon.Action.HTTP{
    method: method,
    path: String.t,
    args: map
  }
end

defimpl Chaperon.Actionable, for: Chaperon.Action.HTTP do
  def run(action, session) do
    # TODO
    {:ok, session}
  end

  def abort(action, session) do
    # TODO
    {:ok, session}
  end

  def retry(action, session) do
    Chaperon.Action.Any.retry(action, session)
  end
end
