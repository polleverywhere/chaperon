defmodule Chaperon.Scenario do
  defstruct [
    name: nil,
    sessions: [],
  ]

  @type t :: %Chaperon.Scenario{
    name: atom,
    sessions: [Chaperon.Session.t]
  }

  defmacro __using__(_opts) do
    quote do
      require Chaperon.Scenario
      import  Chaperon.Scenario
      import  Chaperon.Timing
      import  Chaperon.Session
    end
  end


  alias Chaperon.Session
  alias Chaperon.Action.SpreadAsync
  import  Chaperon.Session

  @doc """
  Concurrently spreads a given action with a given rate over a
  """
  @spec cc_spread(Session.t, atom, SpreadAsync.rate, SpreadAsync.time) :: Session.t
  def cc_spread(session, action_name, rate, interval) do
    action = %SpreadAsync{
      callback: {session.scenario.name, action_name},
      rate: rate,
      interval: interval
    }
    session
    |> Session.add_action(action)
  end

  defmacro session ~> func_call do
    quote do
      unquote(session)
      |> call(fn s ->
        s
        |> unquote(func_call)
      end)
    end
  end
end
