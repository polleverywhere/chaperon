defmodule Chaperon.Action.WebSocket.Client do
  use WebSockex
  require Logger

  defmodule State  do
    defstruct messages: [],
              awaiting: []
  end

  alias __MODULE__.State

  def start_link(url) do
    WebSockex.start_link(url, __MODULE__, %State{})
  end

  @spec send_frame(pid, WebSockex.frame) :: :ok
  def send_frame(pid, {:text, msg} = frame) do
    Logger.debug("WS Client | Sending message: #{msg}")
    WebSockex.send_frame(pid, frame)
  end

  def send_frame(pid, frame) do
    Logger.debug("WS Client | Sending frame")
    WebSockex.send_frame(pid, frame)
  end

  def handle_frame(msg, state) do
    Logger.debug("WS Client | Received Frame")

    case state.awaiting do
      [] ->
        state = update_in state.messages, &[msg | &1]
        {:ok, state}

      clients ->
        for pid <- clients do
          send pid, {:recv_message, msg}
        end
        state = put_in state.awaiting, []
        {:ok, state}
    end
  end

  def handle_disconnect(%{reason: {:local, reason}}, state) do
    Logger.debug("WS Client | Local close with reason: #{inspect reason}")
    {:ok, state}
  end

  def handle_disconnect(disconnect_map, state) do
    super(disconnect_map, state)
  end

  def handle_info({:ssl_closed, _info}, state) do
    {:close, state}
  end

  def handle_info({:next_frame, pid}, state) do
    case Enum.reverse(state.messages) do
      [m1 | rest] ->
        state = put_in state.messages, Enum.reverse(rest)
        send pid, {:next_frame, m1}
        {:ok, state}
      [] ->
        state = update_in state.awaiting, &[pid | &1]
        {:ok, state}
    end
  end

  def recv_message(pid, timeout \\ nil) do
    # ask for next frame frmo WebSockex process and then await response
    send pid, {:next_frame, self}
    case timeout do
      nil ->
        receive do
          {:next_frame, msg} ->
            msg
        end

      timeout when is_integer(timeout) ->
        receive do
          {:next_frame, msg} ->
            msg

          after timeout ->
            {:error, {:timeout, timeout}}
        end
    end
  end
end
