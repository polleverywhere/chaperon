defmodule Firehose.Scenario.PublishRountrip do
  use Chaperon.Scenario

  def run(session) do
    session
    |> set_config(channel: "#{session.config.channel}-#{:rand.uniform(1_000_000)}")
    |> subscribe
    |> publish_receive_loop(publications(session) / batch_size(session))
  end

  defp publications(session) do
    session |> config(:publications, 500)
  end

  defp batch_size(session) do
    session |> config(:batch, 1)
  end

  def publish_receive_loop(session, iterations) when iterations <= 0 do
    session
  end

  def publish_receive_loop(session, iterations) do
    session
    |> call_traced(:publish_roundtrip)
    |> publish_receive_loop(iterations - 1)
  end

  def publish_roundtrip(session) do
    case session |> batch_size do
      1 ->
        session
        |> publish

      n ->
        session
        |> batch_publish(n)
    end
    |> ws_recv
  end

  def subscribe(session) do
    session
    |> ws_connect(session.config.channel)
    |> ws_send(json: %{last_message_sequence: 0})
  end

  def publish(session) do
    session
    |> put(session.config.channel, json: json_message(session.config.channel, "test"))
  end

  def batch_publish(session, n) do
    session
    |> put("/channels@firehose", json: json_messages(session, n))
  end

  def json_messages(session, n) do
    for i <- 0..n, do: json_message(session.config.channel, i)
  end

  def json_message(channel, msg) do
    %{
      channel: channel,
      payload: %{"hello world" => msg, "time" => Chaperon.Timing.timestamp()},
      ttl: 1000,
      buffer_size: 10
    }
  end
end

defmodule Firehose.LoadTest.PublishRountrip.Local do
  alias Firehose.Scenario.PublishRountrip

  use Chaperon.LoadTest

  def default_config,
    do: %{
      scenario_timeout: 25_000,
      base_url: "http://localhost:7474",
      channel: "/testchannel"
    }

  def scenarios,
    do: [
      {PublishRountrip,
       %{
         publications: 500,
         batch: 10
       }}
    ]
end

Chaperon.run_load_test(Firehose.LoadTest.PublishRountrip.Local)
