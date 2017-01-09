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
end
