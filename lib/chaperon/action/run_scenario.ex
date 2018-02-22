defmodule Chaperon.Action.RunScenario do
  @moduledoc """
  Action that runs a `Chaperon.Scenario` module from the current session.
  """

  defstruct scenario: nil,
            config: %{},
            scheduler: :local,
            id: nil,
            pid: nil

  @type t :: %__MODULE__{
          scenario: Chaperon.Scenario.t(),
          config: map,
          scheduler: scheduler,
          id: String.t(),
          pid: pid
        }

  alias __MODULE__
  alias Chaperon.Scenario

  @type scenario :: module | Scenario.t()
  @type scheduler :: :local | :cluster

  def new(scenario, config, scheduler) do
    %RunScenario{
      scenario: scenario |> as_scenario,
      config: config,
      scheduler: scheduler
    }
  end

  @spec as_scenario(scenario) :: Scenario.t()
  defp as_scenario(scenario_mod) when is_atom(scenario_mod), do: %Scenario{module: scenario_mod}
  defp as_scenario(s = %Scenario{}), do: s
end

defimpl Chaperon.Actionable, for: Chaperon.Action.RunScenario do
  import Chaperon.Session,
    only: [
      set_config: 2,
      merge: 2,
      reset_action_metadata: 1,
      add_metric: 3
    ]

  alias Chaperon.Worker
  import Chaperon.Timing

  def run(%{scheduler: scheduler, scenario: scenario, config: config}, session) do
    scenario_config =
      config
      |> Map.merge(%{merge_scenario_sessions: true})

    start = timestamp()

    scenario_session =
      case {scheduler, session.config[:execute_nested_scenario]} do
        {:cluster, _} ->
          schedule_cluster_worker(scenario, scenario_config, session)

        {_, :random_node} ->
          # The code below runs the nested scenario on a random worker node
          # in the cluster. This can be alot slower if the amount of nested
          # scenarios being run is high.
          schedule_cluster_worker(scenario, scenario_config, session)

        _ ->
          # In cases with a high amount of nested scenarios being executed per
          # running session, running the nested scenario inside the current
          # session's process is going to be alot faster and have less
          # communication overhead. Also, this won't ensure the nested scenario
          # times out after a configured worker timeout. Instead, the execution
          # time of the nested scenario will be added to this session's
          # execution time.
          schedule_local_worker(scenario, scenario_config, session)
      end

    merge_scenario_sessions = session.config[:merge_scenario_sessions]

    merged_session =
      session
      |> merge_scenario_session(scenario_session)
      |> set_config(merge_scenario_sessions: merge_scenario_sessions)
      |> add_metric({:run_scenario, scenario.module}, timestamp() - start)

    {:ok, merged_session}
  end

  defp schedule_cluster_worker(scenario, scenario_config, session) do
    scenario
    |> Worker.start_nested(
      session |> reset_action_metadata,
      scenario_config
    )
    |> Worker.await(Worker.timeout(scenario_config))
  end

  defp schedule_local_worker(scenario, scenario_config, session) do
    Chaperon.Scenario.execute_nested(
      scenario,
      session |> reset_action_metadata,
      scenario_config
    )
  end

  def abort(action = %{pid: pid}, session) do
    # TODO
    send(pid, :abort)
    {:ok, action, session}
  end

  defp merge_scenario_session(session, scenario_session) do
    %{
      session
      | config: Map.merge(session.config, scenario_session.config),
        assigned: Map.merge(session.assigned, scenario_session.assigned),
        cookies: scenario_session.cookies
    }
    |> merge(scenario_session)
  end
end

defimpl String.Chars, for: Chaperon.Action.RunScenario do
  alias Chaperon.Action.RunScenario

  def to_string(%RunScenario{scenario: scenario}) do
    "RunScenario[#{scenario.module}]"
  end
end
