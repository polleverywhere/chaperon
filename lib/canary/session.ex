defmodule Canary.Session do
  defstruct [
    id: nil,
    actions: [],
    results: %{},
    async_tasks: %{},
    config: %{},
    scenario: nil
  ]

  @type t :: %Canary.Session{
    id: String.t,
    actions: [Canary.Action.t],
    results: map,
    async_tasks: map,
    config: map,
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
end
