defmodule Chaperon.Action.WebSocket do
  alias Chaperon.Session
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
