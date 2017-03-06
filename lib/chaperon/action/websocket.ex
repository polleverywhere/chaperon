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
  Returns a `Chaperon.WebSocket.ReceiveMessage` action with `options`.

  `options` can include a result handler callback to be called once the message
  arrived.

  Example:

      Chaperon.Action.WebSocket.recv(with_result: fn (session, result) ->
        session
        |> Chaperon.Session.assign(ws_message: result)
      end)
  """
  def recv(options \\ []) do
    callback = Keyword.get(options, :with_result, nil)
    options = Keyword.delete(options, :with_result)

    %WebSocket.ReceiveMessage{
      options: options,
      callback: callback
    }
  end
end
