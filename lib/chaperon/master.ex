defmodule Chaperon.Master do
  defstruct [
    id: nil,
    sessions: %{},
    tasks: %{}
  ]

  @type t :: %Chaperon.Master{
    id: atom,
    sessions: %{atom => Chaperon.Session.t},
    tasks: %{atom => pid}
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

  def handle_call({:run_environment, env_mod, options}, client, state) do
    Logger.info "Running Environment #{env_mod} @ Master #{state.id}"

    {:ok, _} = Task.start_link fn ->
      session = Chaperon.run_environment(env_mod, options)
      GenServer.cast @name, {:environment_finished, env_mod, session}
    end
    state = update_in state.tasks, &Map.put(&1, env_mod, client)
    {:noreply, state}
  end

  def handle_cast({:environment_finished, env_mod, session}, state) do
    Logger.info "Environment finished: #{env_mod}"
    client = state.tasks[env_mod]
    GenServer.reply(client, session)
    state = update_in state.tasks, &Map.delete(&1, env_mod)
    {:noreply, state}
  end
end
