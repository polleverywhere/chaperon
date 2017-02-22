defmodule Chaperon.Action.RunScenario do
  @moduledoc """
  Action that runs a `Chaperon.Scenario` module from the current session.
  """

  defstruct [
    scenario: nil,
    config: %{},
    id: nil,
    pid: nil
  ]

  @type t :: %__MODULE__{
    scenario: Chaperon.Scenario.t,
    config: map,
    id: String.t,
    pid: pid
  }

  alias __MODULE__
  alias Chaperon.Scenario

  @type scenario :: atom | Scenario.t

  @spec new(scenario, map) :: Session.t
  def new(scenario, config) do
    %RunScenario{
      scenario: scenario |> as_scenario,
      config: config
    }
  end

  @spec as_scenario(scenario) :: Scenario.t
  defp as_scenario(scenario_mod) when is_atom(scenario_mod),
    do: %Scenario{module: scenario_mod}
  defp as_scenario(s = %Scenario{}),
    do: s
end

defimpl Chaperon.Actionable, for: Chaperon.Action.RunScenario do
  require Logger

  def run(%{scenario: scenario}, session) do
    scenario_session = Chaperon.Scenario.run(scenario, session)
    {:ok, session |> merge_scenario_session(scenario_session)}
  end

  def abort(action = %{pid: pid}, session) do
    # TODO
    send pid, :abort
    {:ok, action, session}
  end

  defp merge_scenario_session(session, scenario_session) do
    %{session |
      config: Map.merge(session.config, scenario_session.config),
      assigns: Map.merge(session.assigns, scenario_session.assigns)
    }
  end
end



defimpl String.Chars, for: Chaperon.Action.RunScenario do
  alias Chaperon.Action.RunScenario

  def to_string(%RunScenario{scenario: scenario}) do
    "RunScenario[#{scenario.module}]"
  end
end
