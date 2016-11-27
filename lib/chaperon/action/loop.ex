defmodule Chaperon.Action.Loop do
  defstruct action: nil,
            duration: nil,
            started: nil,
            running: true

  @type duration :: non_neg_integer
  @type t :: %Chaperon.Action.Loop{
    action: Chaperon.Actionable,
    duration: duration,
    started: DateTime.t,
    running: true | false
  }
end

defimpl Chaperon.Actionable, for: Chaperon.Action.Loop do
  alias Chaperon.Session

  def run(loop = %{started: nil}, session) do
    %{loop | started: DateTime.utc_now, running: true}
    |> run(session)
  end

  def run(%{running: false}, session), do: session

  def run(loop = %{action: a, duration: d, running: true}, session) do
    now = DateTime.utc_now |> DateTime.to_unix(:milliseconds)
    s = loop.started |> DateTime.to_unix(:milliseconds)
    if (s + d) > now do
      loop
      |> abort(session)
    else
      Chaperon.Actionable.run(loop, session)
    end
  end

  def abort(loop, session) do
     session
     |> Session.update_action(loop, %{loop | running: false})
   end

  def retry(action, session) do
    %{action | running: true, started: DateTime.utc_now}
    |> run(session)
  end
end
