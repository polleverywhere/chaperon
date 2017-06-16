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
  require Logger
  import Chaperon.Action.WebSocket.SendMessage
  alias Chaperon.Action.WebSocket

  def run(action, session = %{assigns: %{websocket: socket}}) do
    Logger.debug "WS_SEND #{session.assigns.websocket_url} #{inspect action.message}"
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
