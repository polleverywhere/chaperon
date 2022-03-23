defmodule Chaperon.Action.WebSocket.Client do
  @moduledoc """
  Implements Chaperon's WebSocket client (behavior of WebSockex WS library).
  """

  use WebSockex
  require Logger

  defmodule State do
    @moduledoc """
    WebSocket client process state.
    """

    defstruct messages: EQ.new(),
              awaiting_clients: EQ.new(),
              log_prefix: nil
  end

  alias __MODULE__.State

  def start_link(session, url) do
    WebSockex.start_link(url, __MODULE__, %State{log_prefix: "#{session.id} [WS Client] |"})
  end

  @spec send_frame(pid, WebSockex.frame()) :: :ok
  def send_frame(pid, frame = {:text, _}) do
    WebSockex.send_frame(pid, frame)
  end

  def send_frame(pid, frame) do
    WebSockex.send_frame(pid, frame)
  end

  def handle_frame(msg, state) do
    Logger.debug(fn -> "#{state.log_prefix} Received Frame" end)

    if EQ.empty?(state.awaiting_clients) do
      state = update_in(state.messages, &EQ.push(&1, msg))
      {:ok, state}
    else
      state.awaiting_clients
      |> EQ.to_list()
      |> Enum.each(&send(&1, {:next_frame, msg}))

      {:ok, put_in(state.awaiting_clients, EQ.new())}
    end
  end

  def handle_ping(:ping, state) do
    {:reply, {:ping, "pong"}, state}
  end

  def handle_ping({:ping, msg}, state) do
    {:reply, {:ping, msg}, state}
  end

  def handle_pong(:pong, state) do
    {:ok, state}
  end

  def handle_pong({:pong, _}, state) do
    {:ok, state}
  end

  def handle_disconnect(%{reason: {:local, reason}}, state) do
    Logger.debug(fn ->
      "#{state.log_prefix} Local close with reason: #{inspect(reason)}"
    end)

    {:ok, state}
  end

  def handle_disconnect(disconnect_map, state) do
    super(disconnect_map, state)
  end

  def handle_info({:ssl_closed, _info}, state) do
    {:close, state}
  end

  def handle_info({:next_frame, pid}, state) do
    case EQ.pop(state.messages) do
      {{:value, msg}, remaining} ->
        state = put_in(state.messages, remaining)
        send(pid, {:next_frame, msg})
        {:ok, state}

      {:empty, _} ->
        state = update_in(state.awaiting_clients, &EQ.push(&1, pid))
        {:ok, state}
    end
  end

  def handle_info(:close, state) do
    {:close, state}
  end

  def recv_message(pid, timeout \\ nil) do
    # ask for next frame from WebSockex process and then await response
    send(pid, {:next_frame, self()})

    case timeout do
      x when x in [nil, :infinity] ->
        receive do
          {:next_frame, msg} ->
            msg
        end

      timeout when is_integer(timeout) ->
        receive do
          {:next_frame, msg} ->
            msg
        after
          timeout ->
            {:error, {:timeout, timeout}}
        end
    end
  end

  def close(pid) do
    send(pid, :close)
  end
end
