defmodule Chaperon.Action.WebSocket.ReceiveMessage do
  @moduledoc """
  WebSocket action to receive message in a WebSocket-connected session.
  """

  defstruct [
    options: [],
    decode: nil,
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
  alias Chaperon.Action.WebSocket
  alias Chaperon.Session
  alias Chaperon.Action.Error
  require Logger

  def run(action, session) do
    {socket, ws_url} =
      session
      |> WebSocket.for_action(action)

    Logger.debug "WS_RECV #{ws_url}"
    start = timestamp

    case WebSocket.Client.recv_message(socket, action.options[:timeout]) do
      {:binary, message} ->
        Logger.debug "WS_RECV binary (#{byte_size message} bytes)"
        session
        |> handle_message(action, message, start)

      {:text, message} ->
        Logger.debug "WS_RECV: #{message}"
        session
        |> handle_message(action, message, start)

      {:error, {:timeout, timeout}} ->
        Logger.error "WS_RECV timeout: #{timeout}"
        session
        |> Session.error({:timeout, timeout})

      other ->
        Logger.warn "WS_RECV unexpected message: #{inspect other}"
        session
        |> Session.ok
    end
  end

  def handle_message(
    session,
    action,
    message,
    start_time
  ) do
    {_, ws_url} =
      session
      |> WebSocket.for_action(action)

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
