defmodule Chaperon.LoadTest do
  @moduledoc """
  Implementation & helper module for defining load tests.
  A load test defines a list of scenarios and their config to run them with.

  ## Example

      defmodule LoadTest.Staging do
        use Chaperon.LoadTest

        # You can define a default config that is used by default.
        # Any additional config passed at runtime will be merged into this.
        # If default_config/0 is not defined, it defaults to %{}.
        def default_config, do: %{
          scenario_timeout: 15_000,
          base_url: "http://staging.mydomain.com"
        }

        def scenarios, do: [
          # session name is "my_session_name"
          {MyScenarioModule, "my_session_name", %{
            delay: 2 |> seconds,
            my_config_key: "my_config_val"
          }},

          # will get an assigned session name based on module name and UUID
          {MyScenarioModule, %{
            delay: 10 |> seconds,
            my_config_key: "my_config_val"
          }},

          # same as above but spawned 10 times (across the cluster):
          {{10, MyScenarioModule}, "my_session_name", %{
            random_delay: 5 |> seconds,
            my_config_key: "my_config_val"
          }},

          # run Scenario A, followed by Scenario B as a new scenario
          {[A, B], %{
            # ...
          }},

          # same as above, but spawned 10 times
          {{10, [A, B]}, %{
            # ...
          }}
        ]
      end
  """

  defstruct name: nil,
            scenarios: [],
            config: %{}

  @type t :: %Chaperon.LoadTest{
          name: atom,
          scenarios: [Chaperon.Scenario.t()],
          config: map
        }

  @type lt_conf :: module | %{name: String.t()}

  defmodule Results do
    @moduledoc """
    LoadTest results struct.
    """

    defstruct load_test: nil,
              start_ms: nil,
              end_ms: nil,
              duration_ms: nil,
              sessions: [],
              max_timeout: nil,
              timed_out: nil

    @type t :: %Chaperon.LoadTest.Results{
            load_test: module,
            start_ms: integer,
            end_ms: integer,
            duration_ms: integer,
            sessions: [Chaperon.Session.t()],
            timed_out: integer
          }
  end

  defmacro __using__(_opts) do
    quote do
      require Chaperon.LoadTest
      import Chaperon.LoadTest
      import Chaperon.Timing
    end
  end

  alias Chaperon.{Session, Scenario, Worker}
  alias Chaperon.LoadTest.Results
  require Logger

  @spec run(lt_conf(), map) :: Chaperon.LoadTest.Results.t()
  def run(lt_mod, extra_config \\ %{}) do
    start_time = Chaperon.Timing.timestamp()

    {timeout, sessions, timed_out} =
      lt_mod
      |> start_workers_with_config(extra_config)
      |> await_workers

    end_time = Chaperon.Timing.timestamp()

    %Results{
      load_test: lt_mod,
      start_ms: start_time,
      end_ms: end_time,
      duration_ms: end_time - start_time,
      sessions: sessions,
      max_timeout: timeout,
      timed_out: timed_out
    }
  end

  @spec default_config(lt_conf()) :: any()
  def default_config(lt_conf) when is_map(lt_conf) do
    lt_conf[:default_config] || %{}
  end

  def default_config(lt_mod) do
    if lt_mod.module_info(:exports)[:default_config] do
      lt_mod.default_config
    else
      %{}
    end
  end

  defp scenarios(%{scenarios: scenarios}), do: scenarios
  defp scenarios(lt_mod) when is_atom(lt_mod), do: lt_mod.scenarios()

  @spec name(lt_conf()) :: String.t()
  def name(lt_mod), do: Chaperon.Util.module_name(lt_mod)

  defp start_workers_with_config(lt_mod, extra_config) do
    lt_mod
    |> scenarios
    |> Enum.map(fn
      {scenario, name, scenario_config} ->
        config =
          lt_mod
          |> default_config
          |> DeepMerge.deep_merge(scenario_config)
          |> DeepMerge.deep_merge(extra_config)

        start_worker(scenario, Map.put(config, :session_name, name))

      {scenario, scenario_config} ->
        config =
          lt_mod
          |> default_config
          |> DeepMerge.deep_merge(scenario_config)
          |> DeepMerge.deep_merge(extra_config)

        start_worker(scenario, config)
    end)
    |> List.flatten()
  end

  def start_worker({concurrency, scenarios}, config)
      when is_list(scenarios) do
    config = Scenario.Sequence.config_for(scenarios, config)

    concurrency
    |> Worker.start(Scenario.Sequence, config)
    |> Enum.map(&{&1, config})
  end

  def start_worker(scenarios, config)
      when is_list(scenarios) do
    config = Scenario.Sequence.config_for(scenarios, config)
    w = Worker.start(Scenario.Sequence, config)
    {w, config}
  end

  def start_worker({concurrency, scenario}, config) do
    concurrency
    |> Worker.start(scenario, config)
    |> Enum.map(&{&1, config})
  end

  def start_worker(scenario, config) do
    w = Worker.start(scenario, config)
    {w, config}
  end

  def await_workers(tasks_with_config) do
    case max_timeout(tasks_with_config) do
      :infinity ->
        sessions =
          tasks_with_config
          |> Enum.map(fn {task, config} ->
            Task.await(task, Chaperon.Worker.timeout(config))
          end)

        {:infinity, sessions, 0}

      timeout when is_integer(timeout) ->
        results =
          tasks_with_config
          |> worker_tasks
          |> Task.yield_many(timeout)
          |> Enum.map(fn {task, res} ->
            res || Task.shutdown(task, :brutal_kill)
          end)

        sessions = for {:ok, session} <- results, do: session
        sessions = sessions |> Enum.reject(&is_nil/1)
        timed_out_count = Enum.count(tasks_with_config) - Enum.count(sessions)
        {timeout, sessions, timed_out_count}
    end
  end

  defp worker_tasks(tasks_with_config) do
    for {task, _config} <- tasks_with_config, do: task
  end

  defp max_timeout(tasks_with_config) do
    timeout =
      tasks_with_config
      |> Enum.reduce(nil, fn {_, config}, last_timeout ->
        case {last_timeout, Chaperon.Worker.timeout(config)} do
          {:infinity, _} ->
            :infinity

          {_, :infinity} ->
            :infinity

          {nil, t} when is_integer(t) ->
            t

          {last, t} when is_integer(last) and is_integer(t) and t > last ->
            t

          _ ->
            last_timeout
        end
      end)

    timeout || :infinity
  end

  def timeout(lt_mod) do
    default_config(lt_mod)[:load_test_timeout] || :infinity
  end

  @doc """
  Merges metrics & results of all `Chaperon.Session`s in a list.
  """
  @spec merge_sessions(Results.t()) :: Session.t()
  def merge_sessions(results = %Results{sessions: [], max_timeout: timeout}) do
    Logger.warn(
      "No scenario task finished in time (timeout = #{timeout}) for load_test: #{
        results.load_test
      }"
    )

    %Session{}
  end

  def merge_sessions(%Results{sessions: [s | sessions]}) do
    sessions
    |> Enum.reduce(s |> prepare_merge, &Session.merge(&2, &1))
  end

  @doc """
  Prepares `session` to be merged.

  This wraps all metrics and results with the session's name to be able to
  differentiate later on for which session they were recorded.
  """
  @spec prepare_merge(Session.t()) :: Session.t()
  def prepare_merge(session) do
    %{
      session
      | metrics: session |> Session.session_metrics(),
        results: session |> Session.session_results()
    }
  end
end
