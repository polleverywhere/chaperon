defmodule Chaperon.Scenario.Test do
  defmodule ScenarioWithInit do
    use Chaperon.Scenario

    def init(session) do
      session
      |> assign(ran_init: true)
      |> ok
    end

    def run(session) do
      session
      |> assign(ran: true, val: session.config.val * 2)
    end
  end

  defmodule ScenarioWithoutInit do
    use Chaperon.Scenario

    def run(session) do
      session
      |> assign(ran: true, val: session.config.val * 2)
    end
  end

  defmodule ScenarioWithAbort do
    use Chaperon.Scenario

    def run(session) do
      if session |> config(:abort, false) do
        session
        |> abort("expected failure")
      else
        session
      end
    end
  end

  use ExUnit.Case
  doctest Chaperon.Scenario
  alias Chaperon.Scenario
  alias __MODULE__.{ScenarioWithInit, ScenarioWithoutInit}

  test "calls init/1 in the scenario module, if defined" do
    {:ok, session} = Scenario.init(ScenarioWithInit, %Chaperon.Session{})
    assert session.assigned[:ran_init]

    {:ok, session} = Scenario.init(ScenarioWithoutInit, %Chaperon.Session{})
    assert session.assigned[:ran_init] == nil
  end

  test "runs the scenario by calling its run/1 function" do
    s1 = Scenario.execute(ScenarioWithInit, %{val: 10})
    s2 = Scenario.execute(ScenarioWithoutInit, %{val: 20})

    assert s1.assigned.ran
    assert s1.assigned.val == 20
    assert s2.assigned.ran
    assert s2.assigned.val == 40
  end

  test "logs a warning if attempting to run session that has been manually aborted" do
    s1 = Scenario.execute(ScenarioWithAbort, %{abort: false})
    s2 = Scenario.execute(ScenarioWithAbort, %{abort: true})

    assert s1.cancellation == nil
    assert s2.cancellation == "expected failure"
  end
end
