defmodule Chaperon.Environment do
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

      def run do
        scenarios()
        |> Enum.map(fn {scenario, config} ->
          t = Task.async Chaperon.Scenario, :execute, [scenario, config]
          {t, config}
        end)
        |> Enum.map(fn {t, config} ->
          Task.await(t, config[:scenario_timeout] || :infinity)
        end)
      end
    end
  end

  alias Chaperon.Session

  @spec merge_sessions([Session.t]) :: Session.t
  def merge_sessions([s | sessions]) when is_list(sessions) do
    sessions
    |> Enum.reduce(s |> prepare_merge, &Session.merge(&2, &1))
  end

  @spec prepare_merge(Session.t) :: Session.t
  defp prepare_merge(session) do
    %{session |
      metrics: session |> Session.session_metrics,
      results: session |> Session.session_results
    }
  end

  defmacro scenarios(do: {:__block__, _, run_exprs}) do
    [default_config] = for {:default_config, _, [config]} <- run_exprs do
      config
    end

    scenarios = for {:run, _, [scenario, config]} <- run_exprs do
      quote do
        {unquote(scenario), Map.merge(unquote(default_config), unquote(config))}
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
    end
  end
end
