defmodule Chaperon.Action.WebSocket.Connect do
  defstruct [
    path: nil
  ]

  def url(action, session) do
    case Chaperon.Action.HTTP.url(action, session) do
      "https" <> rest -> "wss" <> rest
      "http"  <> rest -> "ws"  <> rest
    end
  end
end

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.Connect do
  alias Chaperon.Session
  alias Chaperon.Action.WebSocket.Connect

  def run(action, session) do
    {addr, opts} = Chaperon.Action.WebSocket.ws_opts(action, session)
    ws = Socket.Web.connect! addr, opts

    session =
      session
      |> Session.assign(
        websocket: ws,
        websocket_url: Connect.url(action, session)
      )

    {:ok, session}
  end

  def abort(action, session) do
    {:ok, action, session}
  end
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.Connect do
  def to_string(%{path: path}),
    do: "WS Connect[#{path}]"
end
