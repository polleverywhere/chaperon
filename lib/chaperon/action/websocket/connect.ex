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

  defstruct path: nil,
            options: []

  def url(action, session) do
    case Chaperon.Action.HTTP.url(action, session) do
      "https" <> rest ->
        "wss" <> rest

      "http" <> rest ->
        "ws" <> rest

      "ws" <> _ = ws_url ->
        ws_url
    end
  end
end

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.Connect do
  alias Chaperon.Session
  alias Chaperon.Action.WebSocket
  alias Chaperon.Action.WebSocket.Connect
  import Chaperon.Timing, only: [seconds: 1]
  use Chaperon.Session.Logging

  def run(action, session) do
    ws_url = Connect.url(action, session)

    session
    |> log_info("WS_CONN #{ws_url}")

    timeout = Session.timeout(session)
    async_connect(session, ws_url)

    receive do
      {:ws_connected, ws_client, ^ws_url} ->
        session
        |> WebSocket.assign_for_action(action, ws_client, ws_url)
        |> Session.ok()

      {:ws_closed, ^ws_url} ->
        session
        |> log_error("Failed to connect via WS to #{ws_url} - Connection closed remotely")

      {:ws_failed, ^ws_url, error = %WebSockex.RequestError{code: code, message: message}} ->
        session
        |> log_error(
          "Failed to connect via WS to #{ws_url} - Failed connection request response: #{code} : #{
            message
          }"
        )
        |> Session.error({:ws_failed, ws_url, error})
    after
      timeout ->
        session
        |> log_info("Timeout while connecting via WS to #{ws_url}")
        |> Session.error({:timeout, :ws_conn, ws_url, timeout})
    end
  end

  def abort(action, session) do
    {:ok, action, session}
  end

  def async_connect(session, ws_url) do
    parent = self()

    spawn_link(fn ->
      session
      |> connection_attempt_loop(ws_url, parent)
    end)
  end

  defp connection_attempt_loop(session, ws_url, parent) do
    case WebSocket.Client.start_link(session, ws_url) do
      {:ok, ws_client} ->
        send(parent, {:ws_connected, ws_client, ws_url})

      {:error, %WebSockex.ConnError{original: :closed}} ->
        send(parent, {:ws_closed, ws_url})

      {:error, %WebSockex.ConnError{original: :timeout}} ->
        session
        |> log_warn("Failed to connect via WS to #{ws_url} - TIMEOUT")
        |> Session.random_delay(
          session
          |> Session.config("ws.connect_timeout", 3 |> seconds)
        )
        |> connection_attempt_loop(ws_url, parent)

      {:error, req_err = %WebSockex.RequestError{}} ->
        send(parent, {:ws_failed, ws_url, req_err})
    end
  end
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.Connect do
  def to_string(%{path: path}), do: "WS Connect[#{path}]"
end
