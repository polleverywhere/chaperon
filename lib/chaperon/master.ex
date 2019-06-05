defmodule Chaperon.Master do
  @moduledoc """
  Master process for running load tests. Initiates running a load test and awaits
  results from a run. Needs to be started before used.
  The Chaperon.Master process is started only once per cluster and registered
  globally as `Chaperon.Master`.
  """

  defstruct id: nil,
            sessions: %{},
            tasks: %{},
            non_worker_nodes: [],
            scheduled_load_tests: %{}

  @type t :: %Chaperon.Master{
          id: atom,
          sessions: %{atom => Chaperon.Session.t()},
          tasks: %{atom => pid},
          non_worker_nodes: [atom],
          scheduled_load_tests: %{String.t() => Chaperon.LoadTest.t()}
        }

  use GenServer
  require Logger
  alias Chaperon.Util

  @name {:global, __MODULE__}

  def start do
    Chaperon.Master.Supervisor.start_master()
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  def init([]) do
    id = Node.self()
    Logger.info("Starting Chaperon.Master #{id}")
    {:ok, %Chaperon.Master{id: id}}
  end

  @spec run_load_test(module, Keyword.t()) :: Chaperon.Session.t()
  def run_load_test(lt_mod, options \\ []) do
    timeout = Chaperon.LoadTest.timeout(lt_mod)

    result = GenServer.call(@name, {:run_load_test, lt_mod, run_options(options)}, timeout)

    case result do
      {:remote, session, data} ->
        options
        |> Chaperon.exporter()
        |> apply(:write_output, [
          lt_mod,
          Keyword.get(options, :config, %{}),
          data,
          options[:output]
        ])

        session

      session ->
        session
    end
  end

  def running_load_tests() do
    GenServer.call(@name, :running_load_tests)
  end

  def schedule_load_test(lt) do
    GenServer.call(@name, {:schedule_load_test, lt})
  end

  def scheduled_load_tests() do
    GenServer.call(@name, :scheduled_load_tests)
  end

  @spec ignore_node_as_worker(atom) :: :ok
  def ignore_node_as_worker(node) do
    GenServer.call(@name, {:ignore_node_as_worker, node})
  end

  def handle_call({:run_load_test, lt_mod, options}, client, state) do
    Logger.info("Starting LoadTest #{Chaperon.LoadTest.name(lt_mod)} @ Master #{state.id}")
    task_id = UUID.uuid4()

    {:ok, _} =
      Task.start_link(fn ->
        session = Chaperon.run_load_test(lt_mod, options)
        GenServer.cast(@name, {:load_test_finished, lt_mod, task_id, session})
      end)

    state = update_in(state.tasks, &Map.put(&1, {lt_mod, task_id}, client))
    {:noreply, state}
  end

  def handle_call({:ignore_node_as_worker, node}, _, state) do
    state = update_in(state.non_worker_nodes, &[node | &1])
    {:reply, :ok, state}
  end

  def handle_call(:running_load_tests, client, state) do
    Logger.info("Requesting running load tests")

    {:reply, Map.keys(state.tasks), state}
  end

  def handle_call(
        {:schedule_load_test, lt = %{name: name, scenarios: _, config: _}},
        _,
        state
      ) do
    Logger.info("Scheduling load test with name: #{name}")
    id = UUID.uuid4()

    state = update_in(state.scheduled_load_tests, &Map.put(&1, id, lt))
    {:reply, id, state}
  end

  def handle_call(:scheduled_load_tests, _, state) do
    Logger.info("Requesting scheduled load tests")
    {:reply, state.scheduled_load_tests, state}
  end

  def handle_cast({:load_test_finished, lt_mod, task_id, session}, state) do
    lt_name = Chaperon.LoadTest.name(lt_mod)
    Logger.info("LoadTest finished: #{lt_name}")

    case state.tasks[{lt_mod, task_id}] do
      nil ->
        Logger.error("No client found for finished load test: #{lt_name} @ #{task_id}")

      client ->
        GenServer.reply(client, session)
    end

    state = update_in(state.tasks, &Map.delete(&1, {lt_mod, task_id}))
    {:noreply, state}
  end

  defp run_options(options) do
    case {:global.whereis_name(Chaperon.Master), options[:output]} do
      {_, nil} ->
        options

      {pid, _} when is_pid(pid) ->
        if Util.local_pid?(pid) do
          options
        else
          options
          |> Keyword.merge(output: :remote)
        end
    end
  end
end
