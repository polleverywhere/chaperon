defmodule Chaperon.Scenario do
  @moduledoc """
  Helper module to be used by scenario definition modules.

  Imports `Chaperon.Session` and other helper modules for easy scenario
  definitions.

  Example

      defmodule MyScenario do
        use Chaperon.Scenario

        def init(session) do
          # Possibly do something with session before running scenario
          delay = :rand.uniform
          if delay > 0.5 do
            {:ok, session |> with_delay(delay |> seconds)}
          else
            {:ok, session}
          end
        end

        def run(session) do
          session
          |> post("/api/messages", json: %{message: "what's up?"})
          |> get("/api/messages")
        end

        def with_delay(session, delay) do
          put_in session.config[:delay], delay
        end
      end
  """

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
      case session.config[:delay] do
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
