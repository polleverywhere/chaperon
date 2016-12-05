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
      id: "#{scenario_mod} #{UUID.uuid4}",
      scenario: scenario,
      config: config
    }

    {:ok, hist} = :hdr_histogram.open(1000000, 3)

    {:ok, session} = session |> scenario_mod.init
    session = session |> scenario_mod.run

    session =
      session.async_tasks
      |> Enum.reduce(session, fn {k, v}, acc ->
        acc |> Chaperon.Session.await(k, v)
      end)


    :hdr_histogram.close(hist)
    session
  end
end
