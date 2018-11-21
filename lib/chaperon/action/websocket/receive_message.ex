defmodule Chaperon.Action.WebSocket.ReceiveMessage do
  @moduledoc """
  WebSocket action to receive message in a WebSocket-connected session.
  """

  defstruct options: [],
            decode: nil,
            callback: nil

  @type t :: %__MODULE__{
          options: [any],
          callback: Chaperon.Session.result_callback()
        }
end

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.ReceiveMessage do
  import Chaperon.Timing
  import Chaperon.Action.WebSocket.ReceiveMessage
  import Chaperon.Session
  use Chaperon.Session.Logging
  alias Chaperon.Action.WebSocket

  def run(action, session) do
    {socket, ws_url} =
      session
      |> WebSocket.for_action(action)

    session
    |> log_debug("WS_RECV #{ws_url}")

    start = timestamp()

    case WebSocket.Client.recv_message(socket, action.options[:timeout]) do
      {:binary, message} ->
        session
        |> log_debug("WS_RECV binary (#{byte_size(message)} bytes)")
        |> handle_message(action, message, start)

      {:text, message} ->
        session
        |> log_debug("WS_RECV: #{message}")
        |> handle_message(action, message, start)

      {:error, {:timeout, timeout}} ->
        session
        |> log_error("WS_RECV timeout: #{timeout}")
        |> run_error_callback(action, {:timeout, timeout})
        |> error({:timeout, timeout}, action)

      other ->
        session
        |> log_warn("WS_RECV unexpected message: #{inspect(other)}")
        |> ok
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
    |> add_ws_result(action, message)
    |> add_metric({:ws_recv, ws_url}, timestamp() - start_time)
    |> run_callback(action, message)
    |> ok
  end

  def abort(action, session) do
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.ReceiveMessage do
  def to_string(%{options: []}), do: "WS-Recv"
  def to_string(%{options: opts}), do: "WS-Recv#{inspect(opts)}"
end
