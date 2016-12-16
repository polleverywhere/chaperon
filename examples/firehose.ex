defmodule Firehose.Scenario.SubscribeChannel do
  use Chaperon.Scenario

  def init(session) do
    session
    |> ok
  end

  def run(session = %{config: %{delay: delay}}) do
    :timer.sleep(delay)

    session
    |> multi_subscribe_loop(session.config.subscriptions_per_loop)
  end

  def run(session) do
    session
    |> multi_subscribe_loop(session.config.subscriptions_per_loop)
  end

  def multi_subscribe_loop(session, 0) do
    session
    <~ subscribe_loop
  end

  def multi_subscribe_loop(session, count) when count > 0 do
    session
    ~> subscribe_loop(session.config.duration)
    |> multi_subscribe_loop(count - 1)
  end

  def subscribe_loop(session, duration) do
    session
    |> loop(:subscribe, duration)
    <~ subscribe
  end

  def subscribe(session) do
    :timer.sleep(:rand.uniform(session.config.base_interval))
    session
    ~> subscribe(session.config.channel)
  end

  def subscribe(session, channel) do
    session
    |> get(channel)
  end
end

defmodule Environment.Staging do
  alias Firehose.Scenario.SubscribeChannel
  use Chaperon.Environment

  scenarios do
    default_config %{
      # scenario_timeout: 12_000,
      base_url: "https://staging-firehose.ops.pe",
      http: %{
        # http (hackney request) parameters
      },
      timeout: :infinity
    }

    run SubscribeChannel, "s1", %{
      delay: 5 |> seconds,
      duration: 1 |> seconds,
      channel: "/users/6004534/polls/current.json",
      base_interval: 50,
      subscriptions_per_loop: 5
    }

    run SubscribeChannel, "s2", %{
      duration: 15 |> seconds,
      channel: "/users/6004534/polls/current.json",
      base_interval: 500,
      subscriptions_per_loop: 5
    }

    run SubscribeChannel, "s3", %{
      delay: 7.5 |> seconds,
      duration: 3 |> seconds,
      channel: "/users/6004534/polls/current.json",
      base_interval: 75,
      subscriptions_per_loop: 20
    }

    run SubscribeChannel, "s4", %{
      delay: 2 |> seconds,
      duration: 3 |> seconds,
      channel: "/users/6004534/polls/current.json",
      base_interval: 150,
      subscriptions_per_loop: 1
    }
  end
end

require Logger

session = Environment.Staging.run
          |> Chaperon.Environment.merge_sessions

Logger.info("Metrics:")
for {k, v} <- session.metrics do
  k = inspect k
  delimiter = for _ <- 1..byte_size(k), do: "="
  IO.puts("#{delimiter}\n#{k}\n#{delimiter}")
  IO.inspect(v)
  IO.puts("")
end

IO.puts Chaperon.Export.CSV.encode(session)
