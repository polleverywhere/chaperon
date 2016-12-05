defmodule Chaperon.Action.Loop do
  defstruct action: nil,
            duration: nil,
            started: nil

  @type duration :: non_neg_integer
  @type t :: %Chaperon.Action.Loop{
    action: Chaperon.Actionable,
    duration: duration,
    started: DateTime.t
  }
end

defimpl Chaperon.Actionable, for: Chaperon.Action.Loop do
  def run(loop = %{started: nil}, session) do
    %{loop | started: DateTime.utc_now}
    |> run(session)
  end

  def run(loop = %{action: a, duration: d}, session) do
    now = DateTime.utc_now |> DateTime.to_unix(:milliseconds)
    s = loop.started |> DateTime.to_unix(:milliseconds)
    if now - s > d do
      loop
      |> abort(session)
    else
      session = Chaperon.Actionable.run(a, session)
      run(loop, session)
    end
  end

  def abort(_loop, session) do
    {:ok, session}
  end

  def retry(action, session) do
    %{action | started: DateTime.utc_now}
    |> run(session)
  end
end

defimpl String.Chars, for: Chaperon.Action.Loop do
  def to_string(%{action: action, duration: duration}) do
    "Loop[#{action}, #{duration}]"
  end
end
