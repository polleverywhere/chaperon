defmodule Chaperon.Action.Loop do
  @moduledoc """
  Action that executes a given `Chaperon.Actionable` repeatedly for a given
  `duration`.
  """

  defstruct action: nil,
            duration: 0,
            started: nil

  @type duration :: non_neg_integer
  @type t :: %Chaperon.Action.Loop{
          action: Chaperon.Actionable,
          duration: duration,
          started: DateTime.t()
        }
end

defimpl Chaperon.Actionable, for: Chaperon.Action.Loop do
  def run(loop = %{started: nil}, session) do
    %{loop | started: DateTime.utc_now()}
    |> run(session)
  end

  def run(loop = %{action: a, duration: d}, session) do
    now = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    s = loop.started |> DateTime.to_unix(:millisecond)

    if now - s > d do
      {:ok, _, session} = loop |> abort(session)
      {:ok, session}
    else
      with {:ok, session} <- Chaperon.Actionable.run(a, session) do
        run(loop, session)
      end
    end
  end

  def abort(loop, session) do
    {:ok, %{loop | started: nil}, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.Loop do
  def to_string(%{action: action, duration: duration}) do
    "Loop[#{action}, #{duration}]"
  end
end
