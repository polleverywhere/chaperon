defmodule Chaperon.Session do
  defstruct [
    id: nil,
    results: %{},
    errors: %{},
    async_tasks: %{},
    config: %{},
    assigns: %{},
    scenario: nil
  ]

  @type t :: %Chaperon.Session{
    id: String.t,
    results: map,
    errors: map,
    async_tasks: map,
    config: map,
    assigns: map,
    scenario: Chaperon.Scenario.t
  }

  require Logger
  alias Chaperon.Session
  alias Chaperon.Action.SpreadAsync
  import Chaperon.Timing

  @default_timeout seconds(10)


  @doc """
  Concurrently spreads a given action with a given rate over a given time interval
  """
  @spec cc_spread(Session.t, atom, SpreadAsync.rate, SpreadAsync.time) :: Session.t
  def cc_spread(session, action_name, rate, interval) do
    action = %SpreadAsync{
      callback: {session.scenario.name, action_name},
      rate: rate,
      interval: interval
    }

    session
    |> Session.run_action(action)
  end

  def loop(session, action_name, duration) do
    session
    |> run_action(%Chaperon.Action.Loop{
      action: %Chaperon.Action.Function{func: action_name},
      duration: duration
    })
  end

  def timeout(session) do
    session.config[:timeout] || @default_timeout
  end

  def await(session, task_name, task = %Task{}) do
    task_results =
        task
        |> Task.await(session |> timeout)
        |> async_results(task_name, task)

    update_in session.results,
              &Map.merge(&1, task_results)
  end

  def await(session, task_name) when is_atom(task_name) do
    session
    |> await(task_name, session |> async_tasks(task_name))
  end

  def await(session, async_tasks) when is_list(async_tasks) do
    async_tasks
    |> Enum.reduce(session, &await(&2, &1))
  end

  def await_all(session, task_name) do
    session
    |> await(session |> async_tasks(task_name))
  end

  def async_tasks(session, action_name) do
    session.async_tasks
    |> Map.get(action_name, [])
  end

  def async_results(task_session, task_name, task = %Task{}) do
    for {k, v} <- task_session.results do
      {k, {:async, task_name, v}}
    end
    |> Enum.into(%{})
  end

  def get(session, path, params) do
    session
    |> run_action(Chaperon.Action.HTTP.get(path, params))
  end

  def post(session, path, data) do
    session
    |> run_action(Chaperon.Action.HTTP.post(path, data))
  end

  def put(session, path, data) do
    session
    |> run_action(Chaperon.Action.HTTP.put(path, data))
  end

  def patch(session, path, data) do
    session
    |> run_action(Chaperon.Action.HTTP.patch(path, data))
  end

  def delete(session, path) do
    session
    |> run_action(Chaperon.Action.HTTP.delete(path))
  end

  def call(session, func) do
    session
    |> run_action(%Chaperon.Action.Function{func: func})
  end

  def run_action(session, action) do
    case Chaperon.Actionable.run(action, session) do
      {:error, reason} ->
        Logger.error "Session.run_action failed: #{inspect reason}"
        put_in session.errors[action], reason
      {:ok, session} ->
        Logger.info "Session.run_action success"
        session
    end
  end

  def assign(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, v}, session ->
      put_in session.assigns[k], v
    end)
  end

  def update_assign(session, assignments) do
    assignments
    |> Enum.reduce(session, fn {k, func}, session ->
      update_in session.assigns[k], func
    end)
  end

  def async(session, func_name) do
    task = Task.async(session.scenario.module, func_name, [session])
    put_in session.async_tasks[func_name], task
  end

  alias Chaperon.Session.Error

  def ok(session),      do: {:ok, session}
  def error(s, reason), do: {:error, %Error{reason: reason, session: s}}
end
