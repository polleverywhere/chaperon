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
      id: Chaperon.Session.new_id(),
      name: "test-session",
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

    assert_raise(Chaperon.Session.RequiredConfigMissing, fn ->
      Session.config(s, :not_found)
    end)

    assert_raise(Chaperon.Session.RequiredConfigMissing, fn ->
      Session.config(s, [:invalid, :config, :key, :path])
    end)

    assert_raise(Chaperon.Session.RequiredConfigMissing, fn ->
      Session.config(s, "invalid.config.key.path")
    end)
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

    assert session.cookies == ["cookie1=value1; cookie2=value2"]
  end

  describe "await_signal/2" do
    setup %{session: session} do
      session =
        session
        |> Session.update_config(timeout: fn _ -> 1 end)

      {:ok, session: session}
    end

    test "without callback, timeout", %{session: session} do
      assert {:error, %{reason: {:timeout, :await_signal, 1}}} =
               session |> Session.await_signal(:no_signal_coming)
    end

    test "without callback, success", %{session: session} do
      send(self(), {:chaperon_signal, :test_signal})

      assert %Session{} = session |> Session.await_signal(:test_signal)
    end

    test "with callback, timeout", %{session: session} do
      assert {:error, %{reason: {:timeout, :await_signal, 1}}} =
               session |> Session.await_signal(&test_callback/2)

      refute_receive {:callback_called, :no_signal_coming}
    end

    test "with callback, success", %{session: session} do
      send(self(), {:chaperon_signal, :test_signal})

      assert :callback_called ==
               session |> Session.await_signal(&test_callback/2)

      assert_receive {:callback_called, :test_signal}
    end
  end

  describe "await_signal/3" do
    test "timeout", %{session: session} do
      assert {:error, %{reason: {:timeout, :await_signal, 1}}} =
               session |> Session.await_signal(:no_signal_coming, 1)
    end

    test "success", %{session: session} do
      send(self(), {:chaperon_signal, :test_signal})

      assert %Session{} = session |> Session.await_signal(:test_signal, 1)
    end

    test "infinite timeout", %{session: session} do
      send(self(), {:chaperon_signal, :test_signal})

      assert %Session{} = session |> Session.await_signal(:test_signal, :infinity)
    end
  end

  describe "await_signal_or_timeout/3" do
    test "timeout", %{session: session} do
      assert {:error, %{reason: {:timeout, :await_signal, 1}}} =
               session |> Session.await_signal_or_timeout(1, &test_callback/2)

      refute_receive {:callback_called, :no_signal_coming}
    end

    test "success", %{session: session} do
      send(self(), {:chaperon_signal, :test_signal})

      assert :callback_called ==
               session |> Session.await_signal_or_timeout(1, &test_callback/2)

      assert_receive {:callback_called, :test_signal}
    end
  end

  describe "await_signal with interval" do
    setup %{session: session} do
      self = self()

      session =
        session
        |> Session.assign(interval_count: 0)
        |> Session.update_config(
          interval: fn _ -> {50, fn session -> interval_fun(session, self) end} end
        )
        |> Session.update_config(timeout: fn _ -> 200 end)

      {:ok, session: session}
    end

    test "simple interval, timeout", %{session: session} do
      assert {:error, %{reason: {:timeout, :await_signal, 200}}} =
               session |> Session.await_signal(:no_signal_coming)

      assert_receive {:interval_called, 0}
      assert_receive {:interval_called, 1}
      assert_receive {:interval_called, 2}
      refute_receive {:interval_called, 3}
    end

    test "simple interval, success", %{session: session} do
      Process.send_after(self(), {:chaperon_signal, :test_signal}, 125)

      assert %Session{assigned: %{interval_count: 2}} =
               session |> Session.await_signal(:test_signal)

      assert_receive {:interval_called, 0}
      assert_receive {:interval_called, 1}
      refute_receive {:interval_called, 2}
    end

    test "explicit timeout, timeout", %{session: session} do
      assert {:error, %{reason: {:timeout, :await_signal, 75}}} =
               session |> Session.await_signal(:no_signal_coming, 75)

      assert_receive {:interval_called, 0}
      refute_receive {:interval_called, 1}
    end

    test "explicit timeout, success", %{session: session} do
      Process.send_after(self(), {:chaperon_signal, :test_signal}, 70)

      assert %Session{assigned: %{interval_count: 1}} =
               session |> Session.await_signal(:test_signal, 90)

      assert_receive {:interval_called, 0}
      refute_receive {:interval_called, 1}
    end
  end

  describe "await task" do
    setup %{session: session} do
      session =
        session
        |> Session.update_config(timeout: fn _ -> 100 end)

      {:ok, session: session}
    end

    test "await by name, success", %{session: session} do
      assert %Session{} =
               session
               |> Session.async({__MODULE__, :async_fun}, [0], :async_name)
               |> Session.await(:async_name)
    end

    test "await by name, timeout", %{session: session} do
      catch_exit(
        session
        |> Session.async({__MODULE__, :async_fun}, [500], :async_name)
        |> Session.await(:async_name)
      )
    end

    test "await multiple tasks, success", %{session: session} do
      assert %Session{} =
               session
               |> Session.async({__MODULE__, :async_fun}, [0], :async_name)
               |> Session.async({__MODULE__, :async_fun}, [0], :async_name)
               |> Session.async({__MODULE__, :async_fun}, [0], :async_name)
               |> Session.await(:async_name)
    end

    test "await multiple tasks, timeout", %{session: session} do
      catch_exit(
        session
        |> Session.async({__MODULE__, :async_fun}, [0], :async_name)
        |> Session.async({__MODULE__, :async_fun}, [500], :async_name)
        |> Session.async({__MODULE__, :async_fun}, [0], :async_name)
        |> Session.await(:async_name)
      )
    end

    test "await multipe names, success", %{session: session} do
      assert %Session{} =
               session
               |> Session.async({__MODULE__, :async_fun}, [0], :a)
               |> Session.async({__MODULE__, :async_fun}, [0], :b)
               |> Session.async({__MODULE__, :async_fun}, [0], :c)
               |> Session.await([:a, :b, :c])
    end

    test "await multiple names, timeout", %{session: session} do
      catch_exit(
        session
        |> Session.async({__MODULE__, :async_fun}, [0], :a)
        |> Session.async({__MODULE__, :async_fun}, [500], :b)
        |> Session.async({__MODULE__, :async_fun}, [0], :c)
        |> Session.await([:a, :b, :c])
      )
    end
  end

  describe "await task with interval" do
    setup %{session: session} do
      self = self()

      session =
        session
        |> Session.update_config(
          interval: fn _ -> {50, fn session -> interval_fun(session, self) end} end
        )
        |> Session.update_config(timeout: fn _ -> 200 end)

      {:ok, session: session}
    end

    test "await by name, success", %{session: session} do
      assert %Session{} =
               session
               |> Session.async({__MODULE__, :async_fun}, [80], :async_name)
               |> Session.await(:async_name)

      assert_receive {:interval_called, 0}
      refute_receive {:interval_called, 1}
    end
  end

  defp test_callback(_session, signal) do
    send(self(), {:callback_called, signal})
    :callback_called
  end

  defp interval_fun(session, target) do
    {count, session} =
      case session.assigned[:interval_count] do
        nil -> {0, session |> Session.assign(interval_count: 0)}
        n -> {n, session |> Session.assign(interval_count: n + 1)}
      end

    send(target, {:interval_called, count})

    session
  end

  def async_fun(session, duration) do
    Process.sleep(duration)
    session
  end
end
