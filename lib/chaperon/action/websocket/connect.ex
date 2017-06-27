defmodule Chaperon.Action.WebSocket.Connect do
  @moduledoc """
  WebSocket connection action that needs to be run in order for a
  `Chaperon.Session` to be successfully connected to a web server via WebSocket.

  Assigns `websocket` and `websocket_url` values to a session when run,
  which are used by the remaining websocket actions found under
  `Chaperon.Action.WebSocket`.
  The stored values are accessible via `session.assigned.websocket` &
  `session.assigned.websocket_url`.
  """

  defstruct [
    path: nil,
    options: []
  ]

  def url(action, session) do
    case Chaperon.Action.HTTP.url(action, session) do
      "https" <> rest ->
        "wss" <> rest

      "http"  <> rest ->
        "ws"  <> rest

      ("ws" <> _) = ws_url ->
        ws_url
    end
  end
end

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.Connect do
  alias Chaperon.Session
  alias Chaperon.Action.WebSocket
  alias Chaperon.Action.WebSocket.Connect
  use Chaperon.Session.Logging

  def run(action, session) do
    ws_url = Connect.url(action, session)

    session
    |> log_info("WS_CONN #{ws_url}")

    timeout = Session.timeout(session)
    {:ok, ws_conn} = WebSocket.Client.start_link(session, ws_url)

    session
    |> log_info("Connected via WS to #{ws_url}")

    session
    |> WebSocket.assign_for_action(action, ws_conn, ws_url)
    |> Session.ok
  end

  def abort(action, session) do
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.Connect do
  def to_string(%{path: path}),
    do: "WS Connect[#{path}]"
end
