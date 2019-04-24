defmodule Firehose.Scenario.SubscribeChannel do
  use Chaperon.Scenario

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

defmodule Firehose.Scenario.WSSubscribeChannel do
  use Chaperon.Scenario

  def init(session) do
    session
    |> ok
  end

  def run(session) do
    session
    |> subscribe(session.config.channel, session |> expected_messages)
  end

  def subscribe(session, channel, amount) do
    Logger.info("WS subscribe #{channel} (Awaiting #{amount} messages)")

    session
    |> ws_connect(channel)
    |> ws_send(json: %{last_message_sequence: 0})
    |> receive_messages(amount)
  end

  def receive_messages(session, 0) do
    amount = session |> expected_messages
    Logger.info("WS received #{amount}/#{amount} messages")
    session
  end

  def receive_messages(session, amount) do
    session
    |> ws_recv
    # |> ws_recv(decode: :json) # same as above but decode message as json
    |> receive_messages(amount - 1)
  end

  defp expected_messages(session),
    do: session.config.await_messages
end

defmodule Firehose.Scenario.PublishChannel do
  use Chaperon.Scenario

  def init(session) do
    session
    |> ok
  end

  def run(session) do
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
    session
    |> delay(:rand.uniform(session.config.base_interval))
    ~> publish(session.config.channel)
  end

  def publish(session, channel) do
    session
    |> put(
      channel,
      json: %{"hello" => "world", "time" => Chaperon.Timing.timestamp()},
      headers: %{"X-Firehose-Persist" => true}
    )
  end
end

defmodule Firehose.LoadTest.Local do
  alias Firehose.Scenario.SubscribeChannel
  alias Firehose.Scenario.PublishChannel
  alias Firehose.Scenario.WSSubscribeChannel

  use Chaperon.LoadTest

  def default_config,
    do: %{
      # scenario_timeout: 12_000,
      merge_scenario_sessions: true,
      base_url: "http://localhost:7474",
      timeout: :infinity,
      channel: "/testchannel"
    }

  def scenarios,
    do: [
      {PublishChannel, "p1",
       %{
         delay: 1 |> seconds,
         duration: 1 |> seconds,
         base_interval: 50,
         publications_per_loop: 5
       }},
      {PublishChannel, "p2",
       %{
         delay: 4 |> seconds,
         duration: 10 |> seconds,
         base_interval: 250,
         publications_per_loop: 1
       }},
      {SubscribeChannel, "s1",
       %{
         delay: 5 |> seconds,
         duration: 1 |> seconds,
         base_interval: 50,
         subscriptions_per_loop: 5
       }},
      {SubscribeChannel, "s2",
       %{
         duration: 15 |> seconds,
         base_interval: 500,
         subscriptions_per_loop: 5
       }},
      {SubscribeChannel, "s3",
       %{
         delay: 7.5 |> seconds,
         duration: 3 |> seconds,
         base_interval: 75,
         subscriptions_per_loop: 20
       }},
      {SubscribeChannel, "s4",
       %{
         delay: 2 |> seconds,
         duration: 3 |> seconds,
         base_interval: 150,
         subscriptions_per_loop: 1
       }},
      {WSSubscribeChannel, "ws1",
       %{
         await_messages: 10
       }},
      {WSSubscribeChannel, "ws2",
       %{
         await_messages: 50
       }},
      {WSSubscribeChannel, "ws3",
       %{
         await_messages: 100
       }},
      {WSSubscribeChannel, "ws4",
       %{
         await_messages: 200
       }}
    ]
end

Chaperon.run_load_test(Firehose.LoadTest.Local)
