defmodule Chaperon.Scenario do
  defstruct [
    module: nil
  ]

  @type t :: %Chaperon.Scenario{
    module: atom
  }

  defmacro __using__(_opts) do
    quote do
      require Logger
      require Chaperon.Scenario
      require Chaperon.Session
      import  Chaperon.Scenario
      import  Chaperon.Timing
      import  Chaperon.Session

      def start_link(config) do
        with {:ok, session} <- config |> new_session |> init do
          Scenario.Task.start_link session
        end
      end

      def new_session(config) do
        %Chaperon.Session{
          scenario: __MODULE__,
          config: config
        }
      end
    end
  end

  require Logger
  alias Chaperon.Session

  def execute(scenario_mod, config) do
    scenario = %Chaperon.Scenario{module: scenario_mod}
    session = %Session{
      id: "#{scenario_mod} #{UUID.uuid4}",
      scenario: scenario,
      config: config
    }

    {:ok, session} = session |> scenario_mod.init

    session =
      case config[:delay] do
        nil ->
          session

        duration ->
          session
          |> Session.delay(duration)
      end
      |> scenario_mod.run

    session.async_tasks
    |> Enum.reduce(session, fn {k, v}, acc ->
      acc |> Session.await(k, v)
    end)
    |> Chaperon.Scenario.Metrics.add_histogram_metrics
  end
end
