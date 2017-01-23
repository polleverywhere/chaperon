defmodule Chaperon.Master do
  defstruct [
    id: nil,
    sessions: %{}
  ]

  @type t :: %Chaperon.Master{
    id: String.t,
    sessions: %{atom => Chaperon.Session.t}
  }

  use GenServer
  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    id = Node.self
    Logger.info "Starting Chaperon.Master #{id}"
    {:ok, %Chaperon.Master{id: id}}
  end

  def run_environment(env_mod, options \\ []) do
    # TODO: store result
    GenServer.call(__MODULE__, {:run_environment, env_mod, options}, :infinity)
  end

  def handle_call({:run_environment, env_mod, options}, _from, state) do
    session = Chaperon.run_environment(env_mod, options)
    state = update_in state.sessions, &Map.put(&1, env_mod, session)
    {:reply, session, state}
  end
end
