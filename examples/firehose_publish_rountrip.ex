defmodule Firehose.Scenario.PublishRountrip do
  use Chaperon.Scenario

  def init(session) do
    session
    |> ok
  end

  def run(session) do
    session
    |> subscribe
    |> publish_receive_loop(session.config.iterations)
  end

  def publish_receive_loop(session, 0), do: session

  def publish_receive_loop(session, iterations) do
    session
    |> call(:publish_roundtrip)
    |> publish_receive_loop(iterations - 1)
  end

  def publish_roundtrip(session) do
    session
    |> publish
    |> ws_recv
  end

  def subscribe(session) do
    session
    |> ws_connect(session.config.channel)
    |> ws_send(json: %{last_message_sequence: 0})
  end

  def publish(session) do
    session
    |> put(session.config.channel, json: json_message)
  end

  def json_message do
    %{"hello" => "world", "time" => Chaperon.Timing.timestamp}
  end
end

defmodule Environment.Staging do
  alias Firehose.Scenario.PublishRountrip

  use Chaperon.Environment

  scenarios do
    default_config %{
      scenario_timeout: 15_000,
      base_url: "http://localhost:7474",
      channel: "/testchannel"
    }

    run PublishRountrip, %{
      iterations: 500
    }
  end
end

Chaperon.run_environment(Environment.Staging)
