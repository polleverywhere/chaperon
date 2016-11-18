defmodule Canary.Scenario do
  defstruct [
    name: nil,
    sessions: [],
  ]

  @type t :: %Canary.Scenario{
    name: atom,
    sessions: [Canary.Session.t]
  }

  defmacro __using__(_opts) do
    quote do
      require Canary.Scenario
      import  Canary.Scenario
      import  Canary.Timing
      import  Canary.Session
    end
  end


  alias Canary.Session
  alias Canary.Action.SpreadAsync

  @doc """
  Concurrently spreads a given action with a given rate over a
  """
  @spec cc_spread(Session.t, atom, SpreadAsync.rate, SpreadAsync.spread) :: Session.t
  def cc_spread(session, action_name, rate, interval) do
    action = %SpreadAsync{
      callback: {session.scenario.name, action_name},
      rate: rate,
      interval: interval
    }
    update_in session.actions, &[action | &1] # prepend and reverse on execution
  end
end
