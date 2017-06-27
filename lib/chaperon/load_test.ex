defmodule Chaperon.LoadTest do
  @moduledoc """
  Implementation & helper module for defining load_tests.
  LoadTests define a list of scenarios and their config to run them with.

  ## Example

      defmodule LoadTest.Staging do
        use Chaperon.LoadTest

        scenarios do
          default_config %{
            scenario_timeout: 15_000,
            base_url: "http://staging.mydomain.com"
          }

          # session name is "my_session_name"
          run MyScenarioModule, "my_session_name", %{
            delay: 2 |> seconds,
            my_config_key: "my_config_val"
          }

          # will get an assigned session name based on module name and UUID
          run MyScenarioModule, %{
            delay: 10 |> seconds,
            my_config_key: "my_config_val"
          }

          # same as above but spawned 10 times (across the cluster):
          run {10, MyScenarioModule}, "my_session_name", %{
            random_delay: 5 |> seconds,
            my_config_key: "my_config_val"
          }

          # run Scenario A, followed by Scenario B as a new scenario
          run [A, B], %{
            # ...
          }

          # same as above, but spawned 10 times
          run {10, [A, B]}, %{
            # ...
          }
        end
      end
  """

  defstruct [
    name: nil,
    scenarios: [],
    config: %{}
  ]

  @type t :: %Chaperon.LoadTest{
    name: atom,
    scenarios: [Chaperon.Scenario.t],
    config: map
  }

  defmodule Results do
    @moduledoc """
    LoadTest results struct.
    """

    defstruct [
      load_test: nil,
      start_ms: nil,
      end_ms: nil,
      duration_ms: nil,
      sessions: [],
      max_timeout: nil,
      timed_out: nil
    ]

    @type t :: %Chaperon.LoadTest.Results{
      load_test: atom,
      start_ms: integer,
      end_ms: integer,
      duration_ms: integer,
      sessions: [Chaperon.Session.t],
      timed_out: integer
    }
  end

  defmacro __using__(_opts) do
    quote do
      require Chaperon.LoadTest
      import  Chaperon.LoadTest
      import  Chaperon.Timing
    end
  end

  alias Chaperon.{Session, Scenario, Worker}
  alias Chaperon.LoadTest.Results
  require Logger

  @spec run(atom) :: Chaperon.LoadTest.Results.t
  def run(lt_mod) do
    start_time = Chaperon.Timing.timestamp()

    {timeout, sessions, timed_out} =
      lt_mod
      |> start_workers_with_config
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

  defp start_workers_with_config(lt_mod) do
    lt_mod.scenarios
    |> Enum.map(fn
      {concurrency, scenarios, config} when is_list(scenarios) ->
        config = Scenario.Sequence.config_for(scenarios, config)
        concurrency
        |> Worker.start(Scenario.Sequence, config)
        |> Enum.map(&{&1, config})

      {concurrency, scenario, config} ->
        concurrency
        |> Worker.start(scenario, config)
        |> Enum.map(&{&1, config})

      {scenarios, config} when is_list(scenarios) ->
        config = Scenario.Sequence.config_for(scenarios, config)
        w = Worker.start(Scenario.Sequence, config)
        {w, config}

      {scenario, config} ->
        w = Worker.start(scenario, config)
        {w, config}
    end)
    |> List.flatten
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

          {last, t} when is_integer(last)
                     and is_integer(t)
                     and t > last ->
            t

          _ ->
            last_timeout
        end
      end)

    timeout || :infinity
  end

  def timeout(lt_mod) do
    lt_mod.default_config[:load_test_timeout] || :infinity
  end

  @doc """
  Merges metrics & results of all `Chaperon.Session`s in a list.
  """
  @spec merge_sessions(Results.t) :: Session.t
  def merge_sessions(results = %Results{sessions: [], max_timeout: timeout}) do
    Logger.warn "No scenario task finished in time (timeout = #{timeout}) for load_test: #{results.load_test}"
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
  @spec prepare_merge(Session.t) :: Session.t
  def prepare_merge(session) do
    %{session |
      metrics: session |> Session.session_metrics,
      results: session |> Session.session_results
    }
  end

  @doc """
  Helper macro for defining `Chaperon.Scenario` implementation modules to be run
  as sessions within the calling LoadTest.

  ## Example

      defmodule MyLoadTest do
        use Chaperon.LoadTest

        scenarios do
          default_config %{
            key: "val"
          }

          run MyScenarioModule, "session_name", %{
            key2: "another_val"
          }
        end
      end
  """
  defmacro scenarios(do: {:__block__, _, run_exprs}) do
    [default_config] = for {:default_config, _, [config]} <- run_exprs do
      config
    end

    scenarios = for {:run, _, [scenario, config]} <- run_exprs do
      case scenario do
        {num, scenario} ->
          quote do
            {unquote(num), unquote(scenario), Map.merge(unquote(default_config), unquote(config))}
          end

        scenario ->
          quote do
            {unquote(scenario), Map.merge(unquote(default_config), unquote(config))}
          end
      end
    end

    scenarios_with_name = for {:run, _, [scenario, name, config]} <- run_exprs do
      case scenario do
        {num, scenario} ->
          quote do
            {
              unquote(num),
              unquote(scenario),
              unquote(default_config)
              |> Map.merge(%{session_name: unquote(name)})
              |> Map.merge(unquote(config))
            }
          end

        scenario ->
          quote do
            {
              unquote(scenario),
              unquote(default_config)
              |> Map.merge(%{session_name: unquote(name)})
              |> Map.merge(unquote(config))
            }
          end
      end
    end

    scenarios = scenarios ++ scenarios_with_name

    quote do
      def scenarios do
        unquote(scenarios)
      end

      def default_config do
        unquote(default_config)
      end
    end
  end
end
