defmodule Chaperon.Session.Test do
  use ExUnit.Case
  doctest Chaperon.Session
  alias Chaperon.Session

  setup do
    {:ok, %{session: %Session{}}}
  end

  test "assign", %{session: s} do
    assert Session.assign(s, foo: 1, bar: 2).assigned == %{
             foo: 1,
             bar: 2
           }

    assert Session.assign(s, foo: 1).assigned == %{foo: 1}
  end

  test "config" do
    s = %Session{
      config: %{
        key: "value",
        nested: %{nested_key: "okidoki"}
      }
    }

    assert Session.config(s, :key) == "value"
    assert Session.config(s, :nested) == %{nested_key: "okidoki"}
    assert Session.config(s, [:nested, :nested_key]) == "okidoki"
    assert Session.config(s, "nested.nested_key") == "okidoki"
    assert Session.config(s, "nested.nested_key", "default") == "okidoki"
    assert Session.config(s, "nested.not_defined", "default") == "default"
  end

  test "abort" do
    defmodule MaybeRunScenario do
      use Chaperon.Scenario

      def init(session) do
        session
        |> assign(names: [])
      end

      def run(session) do
        session
        |> assign(ran_scenario: true)
        |> update_assign(names: &[session |> config(:name) | &1])
      end
    end

    s = %Session{
      config: %{
        key1: "value1",
        key2: "value2"
      }
    }

    s2 = s |> Session.abort("failure")
    assert s2.cancellation == "failure"

    s3 =
      s2
      |> Session.get(
        "https://polleverywhere.com",
        with_result: fn
          session, {:ok, resp} ->
            session |> Session.assign(response: resp)

          session, {:error, _reason} ->
            session
            |> Session.abort("another failure")
        end
      )

    assert s3.cancellation == "failure"

    s4 =
      %Session{}
      |> Session.assign(ran_scenario: false)
      |> Session.run_scenario(MaybeRunScenario, %{name: "success_run"})

    s5 =
      s4
      |> Session.assign(ran_scenario: false)
      |> Session.abort("run_failed")
      |> Session.run_scenario(MaybeRunScenario, %{name: "aborted_run"})

    assert s4.assigned.ran_scenario == true
    assert s4.cancellation == nil
    assert s4.assigned.names == ["success_run"]

    assert s5.cancellation == "run_failed"
    assert s5.assigned.ran_scenario == false
    assert s5.assigned.names == ["success_run"]
  end

  test "store_response_cookies" do
    response = %HTTPoison.Response{
      headers: [
        {"Set-Cookie", "cookie1=value1; Expires=Wed, 21 Oct 2015 07:28:00 GMT; HttpOnly"},
        {"set-cookie", "cookie2=value2"},
        {"ETag", "ignored"}
      ]
    }
    session = Chaperon.Session.store_response_cookies(%Chaperon.Session{}, response)

    assert session.cookies == "cookie1=value1; cookie2=value2"
  end
end
