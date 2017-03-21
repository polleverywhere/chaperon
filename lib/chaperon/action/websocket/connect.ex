defmodule Chaperon.Action.WebSocket.Connect do
  @moduledoc """
  WebSocket connection action that needs to be run in order for a
  `Chaperon.Session` to be successfully connected to a web server via WebSocket.

  Assigns `websocket` and `websocket_url` values to a session when run,
  which are used by the remaining websocket actions found under
  `Chaperon.Action.WebSocket`.
  The stored values are accessible via `session.assigns.websocket` &
  `session.assigns.websocket_url`.
  """

  defstruct [
    path: nil
  ]

  def url(action, session) do
    case Chaperon.Action.HTTP.url(action, session) do
      "https" <> rest -> "wss" <> rest
      "http"  <> rest -> "ws"  <> rest
    end
  end

  def opts(_action, %Chaperon.Session{config: %{base_url: base_url}}) do
    uri = URI.parse(base_url)
    opts = case uri.scheme do
      "http"  -> %{transport: :tcp}
      "https" -> %{transport: :ssl}
    end

    {uri.host, uri.port, opts}
  end
end

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.Connect do
  alias Chaperon.Session
  alias Chaperon.Action.WebSocket.Connect
  alias Chaperon.Action.Error
  require Logger

  def run(action, session) do
    ws_url = Connect.url(action, session)
    Logger.info "WS_CONN #{ws_url}"

    timeout = Session.timeout(session)
    {host, port, opts} = Connect.opts(action, session)
    {:ok, conn}  = :gun.open(host |> String.to_charlist, port, opts)
    {:ok, :http} = :gun.await_up(conn)
    :gun.ws_upgrade(conn, action.path)

    receive do
      {:gun_ws_upgrade, ^conn, :ok, _} ->
        Logger.info "Connected via WS to #{ws_url}"
        session
        |> Session.assign(
          websocket: conn,
          websocket_url: ws_url
        )
        |> Session.ok

    after timeout ->
      {:error, %Error{reason: "WS_CONN timeout: #{timeout}", action: action, session: session}}
    end
  end

  def abort(action, session) do
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.Connect do
  def to_string(%{path: path}),
    do: "WS Connect[#{path}]"
end
