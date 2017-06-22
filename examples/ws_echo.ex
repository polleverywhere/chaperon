defmodule Scenario.WS.Echo do
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
    msg = "Echo ##{session.assigns.counter}"

    session
    |> ws_send(msg)
    |> ws_await_recv(msg)
    |> update_assign(counter: &(&1 + 1))
  end
end

defmodule LoadTest.Echo do
  use Chaperon.LoadTest

  scenarios do
    default_config %{
      base_url: "wss://echo.websocket.org"
    }

    # run 100 Echo sessions with 10 iterations each
    # accross the cluster
    run {100, Scenario.WS.Echo}, %{
      echo: %{
        iterations: 10
      }
    }
  end
end

Chaperon.run_load_test(LoadTest.Echo)
