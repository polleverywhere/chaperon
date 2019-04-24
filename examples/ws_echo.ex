defmodule WS.Echo.Scenario do
  use Chaperon.Scenario

  def init(session) do
    session
    |> assign(counter: 0)
    |> ok
  end

  def run(session) do
    iterations = session |> config([:echo, :iterations])

    session
    |> ws_connect("/")
    |> repeat_traced(:echo, iterations)
    |> log_info("Echo finished after #{iterations} iterations")
    |> ws_close
  end

  def echo(session) do
    msg = "Echo ##{session.assigned.counter}"

    session
    |> ws_send(msg)
    |> ws_await_recv(msg)
    |> update_assign(counter: &(&1 + 1))
  end
end

defmodule WS.Echo.LoadTest do
  use Chaperon.LoadTest

  def default_config,
    do: %{
      base_url: "wss://echo.websocket.org",
      merge_scenario_sessions: true
    }

  def scenarios,
    do: [
      {{100, WS.Echo.Scenario},
       %{
         echo: %{
           iterations: 10
         }
       }}
    ]
end

Chaperon.run_load_test(WS.Echo.LoadTest)
