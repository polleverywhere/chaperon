defmodule Chaperon.Action.SpreadAsync do
  @moduledoc """
  Action that calls a function with a given `rate` over a given `interval` of
  time (ms).
  """

  defstruct [
    func: nil,
    rate: nil,
    interval: nil
  ]

  @type rate :: non_neg_integer
  @type time :: non_neg_integer

  @type t :: %__MODULE__{
    func: Chaperon.Function.callback,
    rate: rate,
    interval: time
  }
end

defimpl Chaperon.Actionable, for: Chaperon.Action.SpreadAsync do
  alias Chaperon.Session
  import Chaperon.Timing
  require Logger

  def run(action, session) do
    delay = round(action.interval / action.rate)
    Logger.info "SpreadAsync[#{action.rate} / #{action.interval} @ #{delay}]"

    1..action.rate
    |> Enum.map(fn _ ->
      action
      |> execute_task(session, delay)
    end)
    |> Enum.reduce(session, fn (task, session) ->
      session
      |> Session.add_async_task(action.func, task)
    end)
    |> Session.ok
  end

  defp execute_task(action, session, delay) do
    session
    |> Session.delay(delay)

    Task.async fn ->
      start = timestamp
      session = apply(session.scenario.module, action.func, [session])
      duration = timestamp - start

      session
      |> Session.add_metric([:duration, action.func], duration)
    end
  end

  def abort(action, session) do
    # TODO
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.SpreadAsync do
  def to_string(%{func: func, rate: r, interval: i}) when is_atom(func) do
    "SpreadAsync[#{func}, #{r}, #{i}]"
  end

  def to_string(%{func: func, rate: r, interval: i}) when is_function(func) do
    "SpreadAsync[#{inspect func}, #{r}, #{i}]"
  end
end
