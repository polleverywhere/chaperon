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

  def run(action = %{scenario: scenario, config: config}, session) do
    case scenario.start_link(config) do
      {:ok, pid} ->
        id = UUID.uuid4
        put_in session.async_tasks[id], %{action | id: id, pid: pid}

      {:error, reason} = error ->
        Logger.error "Couldn't start Scenario #{inspect scenario}: #{inspect reason}"
        error
    end
  end

  def abort(action = %{pid: pid}, session) do
    # TODO
    send pid, :abort
    {:ok, action, session}
  end
end
