defmodule Chaperon.Action.WebSocket.SendMessage do
  defstruct [
    message: nil,
    options: []
  ]

  def encoded_message(%{message: [json: data]}) do
    {:text, Poison.encode!(data)}
  end

  def encoded_message(%{message: msg}),
    do: msg
end

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.SendMessage do
  alias Chaperon.Action.Error
  require Logger
  import Chaperon.Action.WebSocket.SendMessage

  def run(action, session = %{assigns: %{websocket: socket}}) do
    Logger.debug "WS_SEND #{session.assigns.websocket_url} #{inspect action.message}"

    case Socket.Web.send(socket, action |> encoded_message, action.options) do
      :ok ->
        {:ok, session}

      {:error, reason} ->
        Logger.error "WS Send failed: #{inspect reason}"
        {:error, %Error{reason: reason, action: action, session: session}}
    end
  end

  def abort(action, session) do
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.SendMessage do
  def to_string(send_msg),
    do: "WS Send[#{inspect send_msg.message}, #{inspect send_msg.options}]"
end
