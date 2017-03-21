defmodule Chaperon.Action.WebSocket.ReceiveMessage do
  @moduledoc """
  WebSocket action to receive message in a WebSocket-connected session.
  """

  defstruct [
    options: [],
    callback: nil
  ]

  @type t :: %__MODULE__{
    options: [any],
    callback: Chaperon.Session.result_callback
  }
end

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.ReceiveMessage do
  import Chaperon.Timing
  import Chaperon.Action.WebSocket.ReceiveMessage
  alias Chaperon.Session
  alias Chaperon.Action.Error
  require Logger

  def run(
    action,
    session = %{assigns: %{websocket: socket, websocket_url: ws_url}}
  ) do
    Logger.debug "WS_RECV #{ws_url}"
    start = timestamp

    receive do
      {:gun_down, ^socket, _, _, _, _} ->
        Logger.error "WS: received down event"
        {:error, %Error{reason: "WS socket down", action: action, session: session}}

      {:gun_ws, ^socket, {:binary, message}} ->
        Logger.debug "WS_RECV binary (#{byte_size message} bytes)"
        session
        |> handle_message(action, message, start)

      {:gun_ws, ^socket, {:text, message}} ->
        Logger.debug "WS_RECV: #{message}"
        session
        |> handle_message(action, message, start)

      other ->
        Logger.warn "WS_RECV unexpected message: #{inspect other}"
        session
        |> Session.ok
    end
  end

  def handle_message(
    session = %{assigns: %{websocket_url: ws_url}},
    action,
    message,
    start_time
  ) do
    session
    |> Session.add_ws_result(action, message)
    |> Session.add_metric([:duration, :ws_recv, ws_url], timestamp - start_time)
    |> Session.run_callback(action, action.callback, message)
    |> Session.ok
  end

  def abort(action, session) do
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.ReceiveMessage do
  def to_string(%{options: []}),
    do: "WS-Recv"
  def to_string(%{options: opts}),
    do: "WS-Recv#{inspect opts}"
end
