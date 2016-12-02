defmodule Chaperon.Session do
  defstruct [
    id: nil,
    results: %{},
    async_tasks: %{},
    config: %{},
    assigns: %{},
    scenario: nil
  ]

  @type t :: %Chaperon.Session{
    id: String.t,
    results: map,
    async_tasks: map,
    config: map,
    assigns: map,
    scenario: Chaperon.Scenario.t
  }

  require Logger
  import Chaperon.Timing

  @default_timeout seconds(10)

  def loop(session, action_name, duration) do
    session
    |> run_action(%Chaperon.Action.Loop{
      action: %Chaperon.Action.Function{func: action_name},
      duration: duration
    })
  end

  def await(session, async_task) when is_atom(async_task) do
    result =
      async_task
      |> Task.await(session.config.timeout || @default_timeout)

    put_in session.results[async_task], result
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
    result = Chaperon.Actionable.run(action, session)
    put_in session.results[action], result
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
    case Task.start(session.scenario.module, func_name, session) do
      {:ok, task} ->
        put_in session.async_tasks[func_name], task
      error = {:error, reason} ->
        Logger.error "Session.async failed for #{session.scenario.module} #{inspect func_name}: #{inspect reason}"
        error
    end
  end

  alias Chaperon.Session.Error

  def ok(session),      do: {:ok, session}
  def error(s, reason), do: {:error, %Error{reason: reason, session: s}}
end
