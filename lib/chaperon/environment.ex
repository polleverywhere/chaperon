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
        for {scenario, config} <- scenarios do
          Chaperon.Scenario.execute(scenario, config)
        end
      end
    end
  end

  defmacro scenarios(do: {:__block__, _, run_exprs}) do
    scenarios = for {:run, _, [scenario, config]} <- run_exprs do
      {scenario, config}
    end
    quote do
      def scenarios do
        unquote(scenarios)
      end
    end
  end
end
