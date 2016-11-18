defmodule Canary.Session do
  defstruct [
    id: nil,
    actions: [],
    results: %{},
    async_tasks: %{},
    config: %{},
    assigns: %{},
    scenario: nil
  ]

  @type t :: %Canary.Session{
    id: String.t,
    actions: [Canary.Actionable],
    results: map,
    async_tasks: map,
    config: map,
    assigns: map,
    scenario: Canary.Scenario.t
  }

  def loop(session, action_name, duration) do
    # TODO
    session
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
    |> await(session |> Session.async_actions(action_name))
  end

  def async_actions(session, action_name) do
    session.async_tasks
    |> Map.get(action_name, [])
  end

  def post(session, path, data) do
    # TODO
    session
  end

  def call(session, func) do
    session
    |> add_action(%Canary.Action.Function{func: func})
  end

  def add_action(session, action) do
    IO.inspect session
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

  alias Canary.Session.Error

  def ok(session), do: {:ok, session}
  def error(s, reason), do: {:error, %Error{reason: reason, session: s}}
end
