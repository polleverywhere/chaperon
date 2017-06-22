defmodule Chaperon.Action.WebSocket.SendMessage do
  @moduledoc """
  WebSocket action to send a message in a WebSocket-connected session.
  Includes an optional list of `options` to be sent along to `Socket.Web.send/3`.
  """

  defstruct [
    message: nil,
    options: []
  ]

  def encoded_message(%{message: [json: data]}),
    do: Poison.encode!(data)
  def encoded_message(%{message: msg}),
    do: msg
end

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.SendMessage do
  import Chaperon.Session, only: [log_debug: 2]
  alias Chaperon.Action.WebSocket
  import Chaperon.Action.WebSocket.SendMessage

  def run(action, session) do
    {socket, ws_url} =
      session
      |> WebSocket.for_action(action)

    session
    |> log_debug("WS_SEND #{ws_url} #{inspect action.message}")

    :ok = WebSocket.Client.send_frame(socket, {:binary, action |> encoded_message})
    {:ok, session}
  end

  def abort(action, session) do
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.SendMessage do
  def to_string(send_msg),
    do: "WS-Send[#{inspect send_msg.message}, #{inspect send_msg.options}]"
end
