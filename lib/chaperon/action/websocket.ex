defmodule Chaperon.Action.WebSocket do
  @moduledoc """
  Helper functions for creating WebSocket actions.
  """

  alias __MODULE__

  @doc """
  Returns a `Chaperon.WebSocket.Connect` action for a given `path`.
  """
  def connect(path) do
    %WebSocket.Connect{path: path}
  end

  @doc """
  Returns a `Chaperon.WebSocket.SendMessage` action with a given `message` and
  `options`.
  """
  def send(message, options \\ []) do
    %WebSocket.SendMessage{
      message: message,
      options: options
    }
  end

  @doc """
  Returns a `Chaperon.WebSocket.ReceiveMessages` action with `options`.
  """
  def recv(options \\ []) do
    %WebSocket.ReceiveMessage{options: options}
  end
end
