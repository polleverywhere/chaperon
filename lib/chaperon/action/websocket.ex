defmodule Chaperon.Action.WebSocket do
  alias Chaperon.Session

  defmodule Connect do
    defstruct path: nil

    def url(action, session) do
      case Chaperon.Action.HTTP.url(action, session) do
        "https" <> rest -> "wss" <> rest
        "http"  <> rest -> "ws" <> rest
      end
    end
  end

  defmodule SendMessage do
    defstruct message: nil,
              options: []


    def encoded_message(%{message: [json: data]}) do
      {:text, Poison.encode!(data)}
    end

    def encoded_message(%{message: msg}),
      do: msg
  end

  defmodule ReceiveMessage do
    defstruct options: []

    def decode_message(action, message) do
      case action.options[:decode] do
        nil   -> message
        :json -> Poison.decode!(message)
      end
    end
  end

  alias __MODULE__

  def connect(path) do
    %WebSocket.Connect{path: path}
  end

  def send(msg, options \\ []) do
    %WebSocket.SendMessage{
      message: msg,
      options: options
    }
  end

  def recv(options \\ []) do
    %WebSocket.ReceiveMessage{options: options}
  end

  def ws_opts(%{path: path}, %Session{config: %{base_url: base_url}}) do
    uri = URI.parse(base_url)
    opts = case uri.scheme do
      "http"  -> [path: path]
      "https" -> [path: path, secure: true]
    end

    {{uri.host, uri.port}, opts}
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

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.SendMessage do
  alias Chaperon.Action.Error
  require Logger
  import Chaperon.Action.WebSocket.SendMessage

  def run(action, session = %{assigns: %{websocket: socket}}) do
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

defimpl Chaperon.Actionable, for: Chaperon.Action.WebSocket.ReceiveMessage do
  import Chaperon.Timing
  import Chaperon.Action.WebSocket.ReceiveMessage
  alias Chaperon.Action.HTTP
  alias Chaperon.Session
  alias Chaperon.Action.Error
  require Logger

  def run(action, session = %{assigns: %{websocket: socket}}) do
    start = timestamp

    case Socket.Web.recv(socket, action.options) do
      {:ok, {:text, message}} ->
        result = action |> decode_message(message)

        session
        |> Session.add_ws_result(action, result)
        |> Session.add_metric([:duration, :ws_recv, session.assigns.websocket_url], timestamp - start)
        |> Session.ok

      {:error, reason} ->
        Logger.error "#{action} failed: #{inspect reason}"
        {:error, %Error{reason: reason, action: action, session: session}}
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

defimpl String.Chars, for: Chaperon.Action.WebSocket.SendMessage do
  def to_string(send_msg),
    do: "WS Send[#{inspect send_msg.message}, #{inspect send_msg.options}]"
end

defimpl String.Chars, for: Chaperon.Action.WebSocket.ReceiveMessage do
  def to_string(%{options: []}),
    do: "WS-Recv"
  def to_string(%{options: opts}),
    do: "WS-Recv#{inspect opts}"
end
