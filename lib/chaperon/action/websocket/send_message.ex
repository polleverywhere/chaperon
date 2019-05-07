defmodule Chaperon.Action.WebSocket.SendMessage do
  @moduledoc """
  WebSocket action to send a message in a WebSocket-connected session.
  Includes an optional list of `options` to be sent along to `Socket.Web.send/3`.
  """

  defstruct message: nil,
            type: :text,
            options: []

  def encoded_message(%{message: [json: data]}), do: Poison.encode!(data)
  def encoded_message(%{message: msg}), do: msg

  def message_type(%{message: [json: _]}), do: :text
  def message_type(%{type: nil}), do: :text
  def message_type(%{type: type}), do: type
end

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.SendMessage do
  use Chaperon.Session.Logging
  alias Chaperon.Action.WebSocket
  import Chaperon.Action.WebSocket.SendMessage

  def run(action, session) do
    {socket, ws_url} =
      session
      |> WebSocket.for_action(action)

    session
    |> log_debug("WS_SEND #{ws_url} #{inspect(action.message)}")

    :ok =
      WebSocket.Client.send_frame(
        socket,
        {action |> message_type, action |> encoded_message}
      )

    {:ok, session}
  end

  def abort(action, session) do
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.SendMessage do
  def to_string(%{type: type, message: msg, options: options}),
    do: "WS-Send[#{inspect(type)} | #{inspect(msg)} | #{inspect(options)}]"
end
