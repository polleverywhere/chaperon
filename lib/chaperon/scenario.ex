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

  defmodule Sequence do
    @moduledoc """
    Implements `Chaperon.Scenario` and runs a configured list of scenarios
    in sequence, passing along any session assignments as config values to the
    next scenario in the list. Makes it easy to define a new scenario as a
    pipeline of a list of existing scenarios.

    Example usage:

        alias Chaperon.Scenario
        alias MyScenarios.{A, B, C}

        Chaperon.Worker.start(
          Scenario.Sequence,
          Scenario.Sequence.config_for([A, B, C])
        )
    """

    alias Chaperon.Session

    def config_for(scenarios, config \\ %{}) do
      config
      |> Map.merge(%{compound_scenarios: scenarios})
    end

    def run(initial_session = %{config: %{compound_scenarios: scenarios}}) do
      scenarios
      |> Enum.reduce(initial_session, fn(scenario, session) ->
        session
        |> Session.run_scenario(scenario, session.assigns)
      end)
    end
  end

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

      @spec new_session(map) :: Session.t
      def new_session(config) do
        %Chaperon.Session{
          scenario: %Chaperon.Scenario{module: __MODULE__},
          config: config
        }
      end
    end
  end

  require Logger
  alias Chaperon.Session
  alias Chaperon.Scenario

  @doc """
  Runs a given scenario module with a given config and returns the scenario's
  session annotated with histogram metrics via the `Chaperon.Scenario.Metrics`
  module. The returned `Chaperon.Session` will include histogram data for all
  performed `Chaperon.Actionable`s, including for all run actions run
  asynchronously as part of the scenario.
  """
  @spec execute(atom, map) :: Session.t
  def execute(scenario_mod, config) do
    scenario = %Scenario{module: scenario_mod}
    session =
      scenario
      |> new_session(config)

    scenario
    |> run(scenario_mod |> init(session))
  end

  @spec execute_nested(Scenario.t, Session.t, map) :: Session.t
  def execute_nested(scenario, session, config) do
    session =
      scenario
      |> nested_session(session, config)

    scenario
    |> run(scenario.module |> init(session))
  end

  @spec run(Scenario.t, Session.t | {:ok, Session.t} | {:error, any}) :: Session.t | {:error, any}
  def run(scenario, {:ok, session}) do
    scenario
    |> run(session)
  end

  def run(scenario, {:error, reason}) do
    Logger.error "Error running #{scenario}: #{inspect reason}"
    {:error, reason}
  end

  def run(scenario, session) do
    Logger.info "Running #{session_id(scenario, session.config)}"

    session =
      session
      |> with_scenario(scenario, fn session ->
        session
        |> initial_delay
        |> scenario.module.run
      end)

    session =
      session.async_tasks
      |> Enum.reduce(session, fn {k, v}, acc ->
        acc |> Session.await(k, v)
      end)

    if session.config[:merge_scenario_sessions] do
      session
    else
      session
      |> Scenario.Metrics.add_histogram_metrics
    end
  end

  defp with_scenario(session, scenario, func) do
    s2 = func.(%{session | scenario: scenario})
    %{s2 | scenario: session.scenario}
  end

  @spec initial_delay(Session.t) :: Session.t
  def initial_delay(session = %Session{config: %{delay: delay}}) do
    session
    |> Session.delay(delay)
  end

  def initial_delay(session = %Session{config: %{random_delay: delay}}) do
    session
    |> Session.delay(:rand.uniform(delay))
  end

  def initial_delay(session), do: session

  @doc """
  Initializes a `Chaperon.Scenario` for a given `session`.

  If `scenario_mod` defines an `init/1` callback function, calls it with
  `session` and returns its return value.

  Otherwise defaults to returning `{:ok, session}`.
  """
  @spec init(atom, Session.t) :: {:ok, Session.t}
  def init(scenario_mod, session) do
    # for some reason Kernel.function_exported? only works on first compile
    # but not for successive runs. Must be some bug in the compiler ??
    if scenario_mod.module_info(:exports)[:init] do
      session |> scenario_mod.init
    else
      {:ok, session}
    end
  end

  @spec new_session(Scenario.t, map) :: Session.t
  def new_session(scenario, config) do
    %Session{
      id: session_id(scenario, config),
      scenario: scenario,
      config: config
    }
  end

  @spec nested_session(Scenario.t, Session.t, map) :: Session.t
  def nested_session(scenario, session, config) do
    config = session.config |> Map.merge(config)
    %{session |
      id: session_id(scenario, config),
      scenario: scenario,
      config: config
    }
  end

  @doc """
  Returns the name of a `Chaperon.Scenario` based on the `module` its referring
  to.

  ## Example

      iex> alias Chaperon.Scenario
      iex> Scenario.name %Scenario{module: Scenarios.Bruteforce.Login}
      "Scenarios.Bruteforce.Login"
  """
  @spec name(Scenario.t) :: String.t
  def name(%Scenario{module: mod}) do
    mod
    |> Module.split
    |> Enum.join(".")
  end

  @spec session_id(Scenario.t, map) :: String.t
  def session_id(_scenario, %{id: id}),
    do: id

  def session_id(scenario, %{merge_scenario_sessions: true}),
    do: scenario |> name

  def session_id(scenario, _config),
    do: "#{scenario |> name} #{UUID.uuid4}"
end
