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

defmodule Firehose.Scenario.PublishChannel do
  use Chaperon.Scenario

  def init(session) do
    session
    |> ok
  end

  def run(session = %{config: %{delay: delay}}) do
    :timer.sleep(delay)

    session
    |> publish_loop
  end

  def publish_loop(session) do
    session
    |> publish_loop(session.config.publications_per_loop)
  end

  def publish_loop(session, 0) do
    session
    <~ publish
  end

  def publish_loop(session, publications) do
    session
    |> loop(:publish, session.config.duration)
    |> publish_loop(publications - 1)
  end

  def publish(session) do
    :timer.sleep(:rand.uniform(session.config.base_interval))

    session
    ~> publish(session.config.channel)
  end

  def publish(session, channel) do
    session
    |> put(channel,
           json: %{"hello" => "world"},
           headers: %{"X-Firehose-Persist" => true})
  end
end

defmodule Environment.Staging do
  alias Firehose.Scenario.SubscribeChannel
  alias Firehose.Scenario.PublishChannel
  use Chaperon.Environment

  scenarios do
    default_config %{
      # scenario_timeout: 12_000,
      base_url: "http://localhost:7474",
      http: %{
        # http (hackney request) parameters
      },
      timeout: :infinity
    }

    run PublishChannel, %{
      delay: 1 |> seconds,
      duration: 1 |> seconds,
      channel: "/testchannel",
      base_interval: 50,
      publications_per_loop: 5
    }

    run PublishChannel, %{
      delay: 4 |> seconds,
      duration: 10 |> seconds,
      channel: "/testchannel",
      base_interval: 180,
      publications_per_loop: 3
    }

    run PublishChannel, %{
      delay: 10 |> seconds,
      duration: 5 |> seconds,
      channel: "/testchannel",
      base_interval: 50,
      publications_per_loop: 10
    }

    run SubscribeChannel, "s1", %{
      delay: 5 |> seconds,
      duration: 1 |> seconds,
      channel: "/testchannel",
      base_interval: 50,
      subscriptions_per_loop: 5
    }

    run SubscribeChannel, "s2", %{
      duration: 15 |> seconds,
      channel: "/testchannel",
      base_interval: 500,
      subscriptions_per_loop: 5
    }

    run SubscribeChannel, "s3", %{
      delay: 7.5 |> seconds,
      duration: 3 |> seconds,
      channel: "/testchannel",
      base_interval: 75,
      subscriptions_per_loop: 20
    }

    run SubscribeChannel, "s4", %{
      delay: 2 |> seconds,
      duration: 3 |> seconds,
      channel: "/testchannel",
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
