defmodule Chaperon.Scenario do
  defstruct [
    module: nil,
    sessions: [],
  ]

  @type t :: %Chaperon.Scenario{
    module: atom,
    sessions: [Chaperon.Session.t]
  }

  defmacro __using__(_opts) do
    quote do
      require Logger
      require Chaperon.Scenario
      require Chaperon.Session
      import  Chaperon.Scenario
      import  Chaperon.Timing
      import  Chaperon.Session

      def start_link(opts) do
        with {:ok, session} <- %Chaperon.Session{scenario: __MODULE__} |> init do
          Scenario.Task.start_link session
        end
      end
    end
  end

  def execute(scenario_mod, config) do
    scenario = %Chaperon.Scenario{module: scenario_mod}
    session = %Chaperon.Session{
      id: "test-session",
      scenario: scenario,
      config: config
    }

    {:ok, session} = session |> scenario_mod.init
    session = session
              |> scenario_mod.run
  end
end
