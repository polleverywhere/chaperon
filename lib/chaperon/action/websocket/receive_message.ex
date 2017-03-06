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

  def decode_message(action, message) do
    case action.options[:decode] do
      nil   -> message
      :json -> Poison.decode!(message)
    end
  end
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

    case Socket.Web.recv(socket, action.options) do
      {:ok, {:text, message}} ->
        result = action |> decode_message(message)

        session
        |> Session.add_ws_result(action, result)
        |> Session.add_metric([:duration, :ws_recv, ws_url], timestamp - start)
        |> run_callback(action, result)
        |> Session.ok

      {:error, reason} ->
        Logger.error "#{action} failed: #{inspect reason}"
        {:error, %Error{reason: reason, action: action, session: session}}
    end
  end

  def run_callback(session, %{callback: nil}, _),
    do: session

  def run_callback(session, %{callback: cb}, result) when is_function(cb),
    do: cb.(session, result)

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
