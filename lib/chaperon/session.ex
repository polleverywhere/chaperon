defmodule Chaperon.Session do
  defstruct [
    id: nil,
    actions: [],
    results: %{},
    async_tasks: %{},
    config: %{},
    assigns: %{},
    scenario: nil
  ]

  @type t :: %Chaperon.Session{
    id: String.t,
    actions: [Chaperon.Actionable],
    results: map,
    async_tasks: map,
    config: map,
    assigns: map,
    scenario: Chaperon.Scenario.t
  }

  def loop(session, action_name, duration) do
    session
    |> add_action(%Chaperon.Action.Loop{
      action: %Chaperon.Action.Function{func: action_name},
      duration: duration
    })
  end

  def await(session, action) when is_atom(action) do
    # TODO
    session
  end

  def await(session, actions) when is_list(actions) do
    actions
    |> Enum.reduce(session, &await(&2, &1))
  end

  def await_all(session, action_name) do
    session
    |> await(session |> async_tasks(action_name))
  end

  def async_tasks(session, action_name) do
    session.async_tasks
    |> Map.get(action_name, [])
  end

  def get(session, path, params) do
    session
    |> add_action(Chaperon.Action.HTTP.get(path, params))
  end

  def post(session, path, data) do
    session
    |> add_action(Chaperon.Action.HTTP.post(path, data))
  end

  def put(session, path, data) do
    session
    |> add_action(Chaperon.Action.HTTP.put(path, data))
  end

  def patch(session, path, data) do
    session
    |> add_action(Chaperon.Action.HTTP.patch(path, data))
  end

  def delete(session, path) do
    session
    |> add_action(Chaperon.Action.HTTP.delete(path))
  end

  def call(session, func) do
    session
    |> add_action(%Chaperon.Action.Function{func: func})
  end

  def add_action(session, action) do
    update_in session.actions, &[action | &1] # prepend and reverse on execution
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

  def update_action(session, action, new_action) do
    idx = session.actions
          |> Enum.find_index(&(&1 == action))

    update_in session.actions,
              &List.replace_at(&1, idx, new_action)
  end

  alias Chaperon.Session.Error

  def ok(session),      do: {:ok, session}
  def error(s, reason), do: {:error, %Error{reason: reason, session: s}}
end
