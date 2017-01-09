defmodule Chaperon.Action.RunScenario do
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
