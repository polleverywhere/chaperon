defmodule Chaperon.Action.WebSocket.Close do
  @moduledoc """
  WebSocket connection action that can be run to close the WebSocket connection
  with the given `options`.

  Closes & removes the `websocket` and `websocket_url` assigned values in
  a session when run.
  """

  defstruct [
    options: []
  ]
end

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.Close do
  alias Chaperon.Session
  alias Chaperon.Action.WebSocket
  import Chaperon.Session, only: [log_info: 2]

  def run(action, session) do
    {ws_conn, ws_url} = WebSocket.for_action(session, action)


    WebSocket.Client.close(ws_conn)

    session
    |> log_info("WS_CLOSE #{ws_url}")
    |> WebSocket.delete_for_action(action)
    |> Session.ok
  end

  def abort(action, session) do
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.Close do
  def to_string(%{options: options}) do
    "WS Close#{inspect options}"
  end
end
