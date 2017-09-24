defmodule Chaperon.Master do
  @moduledoc """
  Master process for running load tests. Initiates running a load test and awaits
  results from a run. Needs to be started before used.
  The Chaperon.Master process is started only once per cluster and registered
  globally as `Chaperon.Master`.
  """

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

  def run_load_test(lt_mod, options \\ []) do
    timeout = Chaperon.LoadTest.timeout(lt_mod)

    result = GenServer.call(@name,
      {:run_load_test, lt_mod, run_options(options)},
      timeout
    )

    case result do
      {:remote, session, data} ->
        Chaperon.write_output(lt_mod, data, options[:output])
        session

      session ->
        session
    end
  end

  defp run_options(options) do
    case {:global.whereis_name(Chaperon.Master), options[:output]} do
      {_, nil} ->
        options

      {pid, _} when is_pid(pid) ->
        if local_pid?(pid) do
          options
        else
          options
          |> Keyword.merge(output: :remote)
        end
    end
  end

  def local_pid?(pid) do
    case inspect(pid) do
      "#PID<0." <> _ ->
        true
      _ ->
        false
    end
  end

  def handle_call({:run_load_test, lt_mod, options}, client, state) do
    Logger.info "Starting LoadTest #{lt_mod} @ Master #{state.id}"
    task_id = UUID.uuid4
    {:ok, _} = Task.start_link fn ->
      session = Chaperon.run_load_test(lt_mod, options)
      GenServer.cast @name, {:load_test_finished, lt_mod, task_id, session}
    end
    state = update_in state.tasks, &Map.put(&1, {lt_mod, task_id}, client)
    {:noreply, state}
  end

  def handle_cast({:load_test_finished, lt_mod, task_id, session}, state) do
    Logger.info "LoadTest finished: #{lt_mod}"
    case state.tasks[{lt_mod, task_id}] do
      nil ->
        Logger.error "No client found for finished load test: #{lt_mod} @ #{task_id}"
      client ->
        GenServer.reply(client, session)
    end
    state = update_in state.tasks, &Map.delete(&1, {lt_mod, task_id})
    {:noreply, state}
  end
end
