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

      @using_module unquote(__CALLER__)
    end
  end


  alias Canary.Session
  alias Canary.Action.SpreadAsync

  @spec async_spread(Session.t, atom, SpreadAsync.rate, SpreadAsync.spread) :: Session.t
  def async_spread(session, action_name, r, s) do
    action = %SpreadAsync{callback: {session.scenario.name, action_name}, rate: r, spread: s}
    update_in session.actions, &[action | &1] # prepend and reverse on execution
  end
end
