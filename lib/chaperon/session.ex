defmodule Chaperon.Session do
  defstruct [
    id: nil,
    results: %{},
    errors: %{},
    async_tasks: %{},
    config: %{},
    assigns: %{},
    metrics: %{},
    scenario: nil
  ]

  @type t :: %Chaperon.Session{
    id: String.t,
    results: map,
    errors: map,
    async_tasks: map,
    config: map,
    assigns: map,
    metrics: map,
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

  def await(session, task_name, nil), do: session

  def await(session, task_name, task = %Task{}) do
    task_result = task |> Task.await(session |> timeout)
    session
    |> remove_async_task(task_name, task)
    |> merge_async_task_result(task_result, task_name)
  end

  def await(session, task_name, tasks) when is_list(tasks) do
    tasks
    |> Enum.reduce(session, &await(&2, task_name, &1))
  end

  def await(session, task_name) when is_atom(task_name) do
    session
    |> await(task_name, session.async_tasks[task_name])
  end

  def await(session, task_names) when is_list(task_names) do
    task_names
    |> Enum.reduce(session, &await(&2, &1))
  end

  def await_all(session, task_name) do
    session
    |> await(task_name, session.async_tasks[task_name])
  end

  def async_task(session, action_name) do
    session.async_tasks[action_name]
  end

  defp async_results(task_session, task_name) do
    for {k, v} <- task_session.results do
      {task_name, {:async, k, v}}
    end
    |> Enum.into(%{})
  end

  defp async_metrics(task_session, task_name) do
    for {k, v} <- task_session.metrics do
      {task_name, {:async, k, v}}
    end
    |> Enum.into(%{})
  end

  defp merge_async_task_result(session, task_session, task_name) do
    task_results = task_session |> async_results(task_name)
    task_metrics = task_session |> async_metrics(task_name)

    %{session |
      results: Map.merge(session.results, task_results),
      metrics: Map.merge(session.metrics, task_metrics)
    }
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
        Logger.debug "SUCCESS #{action}"
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

  def async(session, func_name, args \\ []) do
    task = Task.async(session.scenario.module, func_name, [session | args])
    session
    |> add_async_task(func_name, task)
  end

  def add_async_task(session, name, task) do
    case session.async_tasks[name] do
      nil ->
        put_in session.async_tasks[name], task
      tasks when is_list(tasks) ->
        update_in session.async_tasks[name], &[task | &1]
      _ ->
        update_in session.async_tasks[name], &[task, &1]
    end
  end

  def remove_async_task(session, task_name, task) do
    case session.async_tasks[task_name] do
      nil ->
        session
      tasks when is_list(tasks) ->
        update_in session.async_tasks[task_name],
                  &List.delete(&1, task)
      _ ->
        update_in session.async_tasks,
                  &Map.delete(&1, task_name)
    end
  end

  def add_result(session, action, result) do
    case session.results[action] do
      nil ->
        put_in session.results[action], result

      results when is_list(results) ->
        update_in session.results[action],
                  &[result | &1]

      _ ->
        update_in session.results[action],
                  &[result, &1]
    end
  end

  def with_response(session, task_name, callback) do
    session = session |> await(task_name)
    for {:async, action, resp} <- session.results[task_name] |> as_list do
      callback.(session, resp)
    end
    session
  end

  defp as_list(nil), do: []
  defp as_list([h|t]), do: [h|t]
  defp as_list(val), do: [val]

  alias Chaperon.Session.Error

  def ok(session),      do: {:ok, session}
  def error(s, reason), do: {:error, %Error{reason: reason, session: s}}

  defmacro session ~> {func, _, nil} do
    quote do
      unquote(session)
      |> Chaperon.Session.async(unquote(func))
    end
  end

  defmacro session ~> {task_name, _, _} do
    quote do
      unquote(session)
      |> Chaperon.Session.async(unquote(task_name))
    end
  end

  defmacro session <~ {task_name, _, _} do
    quote do
      unquote(session)
      |> Chaperon.Session.await(unquote(task_name))
    end
  end

  defmacro session ~>> {task_name, _, args} do
    size = args |> Enum.count
    body = List.last(args)
    args = args |> Enum.take(size - 1)
    body = body[:do]
    callback_fn = {:fn, [], [{:->, [], [args, body]}]}

    quote do
      unquote(session)
      |> with_response(unquote(task_name), unquote(callback_fn))
    end
  end
end
