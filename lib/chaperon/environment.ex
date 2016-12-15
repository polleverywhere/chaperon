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
        scenarios
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
  def merge_sessions(sessions) when is_list(sessions) do
    sessions
    |> Enum.reduce(&Session.merge(&2, &1))
  end

  defmacro scenarios(do: {:__block__, _, run_exprs}) do
    #default_config = find_expr_val(run_exprs, :default_config, %{})
    [default_config] = for {:default_config, _, [config]} <- run_exprs do
      config
    end

    scenarios = for {:run, _, [scenario, config]} <- run_exprs do
      quote do
        {unquote(scenario), Map.merge(unquote(default_config), unquote(config))}
      end
    end

    quote do
      def scenarios do
        unquote(scenarios)
      end
    end
  end

  defp find_expr_val(exprs, key, default) do
    exprs
    |> Enum.find(default, fn
      {key, _, val} -> val
      _             -> nil
    end)
  end
end
