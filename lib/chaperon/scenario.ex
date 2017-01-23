defmodule Chaperon.Scenario do
  @moduledoc """
  Helper module to be used by scenario definition modules.

  Imports `Chaperon.Session` and other helper modules for easy scenario
  definitions.

  ## Example

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

      # def start_link(config) do
      #   with {:ok, session} <- __MODULE__ |> init(config |> new_session) do
      #     Chaperon.Scenario.Task.start_link session
      #   end
      # end

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

  @doc """
  Runs a given scenario module with a given config and returns the scenario's
  session annotated with histogram metrics via the `Chaperon.Scenario.Metrics`
  module. The returned `Chaperon.Session` will include histogram data for all
  performed `Chaperon.Actionable`s, including for all run actions run
  asynchronously as part of the scenario.
  """
  @spec execute(atom, map) :: Session.t
  def execute(scenario_mod, config) do
    scenario = %Chaperon.Scenario{module: scenario_mod}
    session = %Session{
      id: "#{scenario |> name} #{UUID.uuid4}",
      scenario: scenario,
      config: config
    }

    {:ok, session} = scenario_mod |> init(session)

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

  @doc """
  Initializes a `Chaperon.Scenario` for a given `session`.

  If `scenario_mod` defines an `init/1` callback function, calls it with
  `session` and returns its return value.

  Otherwise defaults to returning `{:ok, session}`.
  """
  @spec init(atom, Session.t) :: {:ok, Session.t}
  def init(scenario_mod, session) do
    if function_exported?(scenario_mod, :init, 1) do
      session |> scenario_mod.init
    else
      {:ok, session}
    end
  end

  @doc """
  Returns the name of a `Chaperon.Scenario` based on the `module` its referring
  to.

  ## Example

      iex> alias Chaperon.Scenario
      iex> Scenario.name %Scenario{module: Scenarios.Bruteforce.Login}
      "Scenarios.Bruteforce.Login"
  """
  @spec name(Chaperon.Scenario.t) :: String.t
  def name(%Chaperon.Scenario{module: mod}) do
    mod
    |> Module.split
    |> Enum.join(".")
  end
end
