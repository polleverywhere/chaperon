defmodule Chaperon.Environment do
  @moduledoc """
  Implementation & helper module for defining environments.
  Environments define a list of scenarios and their config to run them with.

  ## Example

      defmodule Environment.Staging do
        use Chaperon.Environment

        scenarios do
          default_config %{
            scenario_timeout: 15_000,
            base_url: "http://staging.mydomain.com"
          }

          # session name is "my_session_name"
          run MyScenarioModule, "my_session_name" %{
            delay: 2 |> seconds,
            my_config_key: "my_config_val"
          }

          # will get an assigned session name based on module name and UUID
          run MyScenarioModule, %{
            delay: 10 |> seconds,
            my_config_key: "my_config_val"
          }
        end
      end
  """

  defstruct [
    name: nil,
    scenarios: [],
    config: %{}
  ]

  @type t :: %Chaperon.Environment{
    name: atom,
    scenarios: [Chaperon.Scenario.t],
    config: map
  }

  defmacro __using__(_opts) do
    quote do
      require Chaperon.Environment
      import  Chaperon.Environment
      import  Chaperon.Timing
    end
  end

  alias Chaperon.Session
  require Logger

  def run(env_mod) do
    env_mod.scenarios
    |> Enum.map(fn
      {concurrency, scenario, config} ->
        Chaperon.Worker.start(concurrency, scenario, config)
        |> Enum.map(&{&1, config})
      {scenario, config} ->
        w = Chaperon.Worker.start(scenario, config)
        {w, config}
    end)
    |> List.flatten
    |> Enum.map(fn {worker, config} ->
      worker
      |> Task.await(config[:scenario_timeout] || :infinity)
    end)
  end

  def timeout(env_mod) do
    env_mod.default_config[:environment_timeout] || :infinity
  end

  @doc """
  Merges metrics & results of all `Chaperon.Session`s in a list.
  """
  @spec merge_sessions([Session.t]) :: Session.t
  def merge_sessions([s | sessions]) when is_list(sessions) do
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
  as sessions within the calling Environment.

  ## Example

      defmodule MyEnvironment do
        use Chaperon.Environment

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
      quote do
        {
          unquote(scenario),
          unquote(default_config)
          |> Map.merge(%{session_name: unquote(name)})
          |> Map.merge(unquote(config))
        }
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
