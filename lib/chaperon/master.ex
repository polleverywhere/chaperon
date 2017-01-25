defmodule Chaperon.Master do
  defstruct [
    id: nil,
    sessions: %{}
  ]

  @type t :: %Chaperon.Master{
    id: atom,
    sessions: %{atom => Chaperon.Session.t}
  }

  use GenServer
  require Logger

  @name {:global, __MODULE__}

  def start do
    Chaperon.Master.Supervisor.start_master
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  def init([]) do
    id = Node.self
    Logger.info "Starting Chaperon.Master #{id}"
    {:ok, %Chaperon.Master{id: id}}
  end

  def run_environment(env_mod, options \\ []) do
    # TODO: store result
    timeout = env_mod.default_config[:env_timeout] || :infinity
    GenServer.call(@name, {:run_environment, env_mod, options}, timeout)
  end

  def get_state do
    GenServer.call(@name, :get_state)
  end

  def handle_call({:run_environment, env_mod, options}, _from, state) do
    Logger.info "Running Environment #{env_mod} @ Master #{state.id}"

    session = Chaperon.run_environment(env_mod, options)
    state = update_in state.sessions, &Map.put(&1, env_mod, session)
    {:reply, session, state}
  end

  def handle_call(:get_state, from, state) do
    {:reply, state, state}
  end
end
