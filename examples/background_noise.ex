defmodule Example.Scenario.BackgroundNoise do
  use Chaperon.Scenario

  def init(session) do
    session
    # rate: incoming requests per interval
    # interval: spread request rate over this amount of time (in ms)
    |> assign(rate: 25, interval: seconds(1))
    |> ok
  end

  def run(session) do
    session
    |> loop(:spread_post_data, 10 |> minutes)
  end

  def spread_post_data(session) do
    session
    |> cc_spread(:post_data, round(session.assigns.rate), session.assigns.interval)
    |> await_all(:post_data)
    ~> increase_noise
  end

  def post_data(session) do
    session
    |> post("/data", %{data: "hello, world!"})
  end

  def increase_noise(session) do
    session
    |> update_assign(rate: &(&1 * 1.025)) # increase by 2.5%
  end
end

alias Example.Scenario.BackgroundNoise

scenario = %Chaperon.Scenario{name: "test-scenario"}
session = %Chaperon.Session{id: "test-session", scenario: scenario}
{:ok, bg_session} = session |> BackgroundNoise.init
bg_session
|> BackgroundNoise.run
|> IO.inspect
