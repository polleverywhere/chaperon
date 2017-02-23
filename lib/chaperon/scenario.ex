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
    session = scenario |> new_session(config)

    {:ok, session} = scenario_mod |> init(session)

    scenario
    |> run(session)
  end

  def run(scenario, {:ok, session}) do
    scenario
    |> run(session)
  end

  def run(scenario, {:error, reason}) do
    Logger.error "Error running #{scenario}: #{inspect reason}"
    {:error, reason}
  end

  def run(scenario, session) do
    Logger.info "Running #{session.id}"

    session =
      session
      |> with_scenario(scenario, fn session ->
        session
        |> initial_delay
        |> scenario.module.run
      end)

    session.async_tasks
    |> Enum.reduce(session, fn {k, v}, acc ->
      acc |> Session.await(k, v)
    end)
    |> Chaperon.Scenario.Metrics.add_histogram_metrics
  end

  defp with_scenario(session, scenario, func) do
    s2 = func.(%{session | scenario: scenario})
    %{s2 | scenario: session.scenario}
  end

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
    if function_exported?(scenario_mod, :init, 1) do
      session |> scenario_mod.init
    else
      {:ok, session}
    end
  end

  @spec new_session(Chaperon.Scenario.t, map) :: Session.t
  def new_session(scenario, config) do
    %Session{
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
  @spec name(Chaperon.Scenario.t) :: String.t
  def name(%Chaperon.Scenario{module: mod}) do
    mod
    |> Module.split
    |> Enum.join(".")
  end

  @spec session_id(Chaperon.Scenario.t, map) :: String.t
  def session_id(_scenario, %{id: id}),
    do: id

  def session_id(scenario, %{merge_scenario_sessions: true}),
    do: scenario |> name

  def session_id(scenario, _config),
    do: "#{scenario |> name} #{UUID.uuid4}"
end
