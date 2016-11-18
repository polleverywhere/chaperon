defmodule Canary.Session do
  defstruct [
    id: nil,
    actions: [],
    results: %{},
    config: %{},
    scenario: nil
  ]

  @type t :: %Canary.Session{
    id: String.t,
    actions: [Canary.Action.t],
    results: map,
    config: map,
    scenario: Canary.Scenario.t
  }
end
