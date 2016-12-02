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
    |> print_config
    |> async(:post_data)
    |> loop(:spread_post_data, 10 |> minutes)
  end

  def spread_post_data(session) do
    session
    |> cc_spread(:post_data, round(session.assigns.rate), session.assigns.interval)
    |> await_all(:post_data)
    |> increase_noise
  end

  def post_data(session) do
    session
    |> post("/data", json: "hello, world!")
  end

  def increase_noise(session) do
    session
    |> update_assign(rate: &(&1 * 1.025)) # increase by 2.5%
  end

  def print_config(session = %{config: %{something: true}}) do
    IO.puts "something: true"
    session
  end

  def print_config(session = %{config: %{something: false}}) do
    IO.puts "something: FALSE!"
    session
  end
end

defmodule Environment.Production do
  alias Example.Scenario.BackgroundNoise
  use Chaperon.Environment

  scenarios do
    default_config %{
      base_url: "https://github.com",
      http: %{
        # http (hackney request) parameters
      }
    }
    run BackgroundNoise, %{
      something: true,
    }
    run BackgroundNoise, %{
      something: false,
    }
  end
end

IO.inspect Environment.Production.run
