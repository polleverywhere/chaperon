defmodule Chaperon.Action.WebSocket do
  @moduledoc """
  Helper functions for creating WebSocket actions.
  """

  alias __MODULE__
  alias Chaperon.Session

  @doc """
  Returns a `Chaperon.WebSocket.Connect` action for a given `path`.
  """
  def connect(path, options \\ []) do
    %WebSocket.Connect{path: path, options: options}
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
    decode = Keyword.get(options, :decode, nil)
    callback = Keyword.get(options, :with_result, nil)
    options = Keyword.delete(options, :with_result)

    %WebSocket.ReceiveMessage{
      options: options,
      decode: decode,
      callback: callback
    }
  end


  @doc """
  Returns a `Chaperon.WebSocket.Close` action with `options`.
  """
  def close(options \\ []) do
    %WebSocket.Close{
      options: options
    }
  end

  def for_action(session, action) do
    case action.options[:name] do
      nil ->
        {session.assigned.websocket.connection, session.assigned.websocket.url}

      name ->
        Map.get(session.assigned.websocket.named_connections, name)
    end
  end

  def assign_for_action(session, action, ws_conn, ws_url) do
    case action.options[:name] do
      nil ->
        session
        |> Session.assign(:websocket,
          connection: ws_conn,
          url: ws_url
        )

      name ->
        session
        |> Session.update_assign(websocket: &(&1 || %{}))
        |> Session.update_assign(:websocket,
          named_connections: fn
            nil ->
              %{name => {ws_conn, ws_url}}
            sockets ->
              Map.put(sockets, name, {ws_conn, ws_url})
          end
        )
    end
  end

  def delete_for_action(session, action) do
    case action.options[:name] do
      nil ->
        session
        |> Session.delete_assign(:websocket, :connection)
        |> Session.delete_assign(:websocket, :url)

      name ->
        session
        |> Session.update_assign(:websocket,
          named_connections: &Map.delete(&1, name)
        )
    end
  end
end
