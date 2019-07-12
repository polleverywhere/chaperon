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
            scheduled_load_tests: EQ.new()

  @type t :: %Chaperon.Master{
          id: atom,
          sessions: %{atom => Chaperon.Session.t()},
          tasks: %{atom => pid},
          non_worker_nodes: [atom],
          scheduled_load_tests: EQ.t()
        }

  @derive {Inspect, only: [:id]}

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
        {exporter, options} = options |> Chaperon.exporter()

        exporter
        |> apply(:write_output, [
          lt_mod,
          options,
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

  def schedule_load_tests(lts) do
    GenServer.call(@name, {:schedule_load_tests, lts})
  end

  def scheduled_load_tests() do
    GenServer.call(@name, :scheduled_load_tests)
  end

  def cancel_running_or_scheduled(id) do
    GenServer.call(@name, {:cancel_running_or_scheduled, id})
  end

  @spec ignore_node_as_worker(atom) :: :ok
  def ignore_node_as_worker(node) do
    GenServer.call(@name, {:ignore_node_as_worker, node})
  end

  def handle_call({:run_load_test, lt_mod, options}, client, state) do
    Logger.info("Starting LoadTest #{Chaperon.LoadTest.name(lt_mod)} @ Master #{state.id}")

    %{state: state, id: _task_id} =
      start_load_test(state, client, %{test: lt_mod, options: options})

    {:noreply, state}
  end

  def handle_call({:ignore_node_as_worker, node}, _, state) do
    state = update_in(state.non_worker_nodes, &[node | &1])
    {:reply, :ok, state}
  end

  def handle_call(:running_load_tests, _, state) do
    Logger.info("Requesting running load tests")

    running =
      for {lt_conf, id, _pid} <- Map.keys(state.tasks) do
        %{name: Chaperon.LoadTest.name(lt_conf), id: id}
      end

    {:reply, running, state}
  end

  def handle_call(:scheduled_load_tests, _, state) do
    Logger.info("Requesting scheduled load tests")

    scheduled =
      for %{test: lt_conf, id: id} <- EQ.to_list(state.scheduled_load_tests) do
        %{name: Chaperon.LoadTest.name(lt_conf), id: id}
      end

    {:reply, scheduled, state}
  end

  def handle_call(
        {:schedule_load_test, lt = %{test: lt_mod, options: _}},
        _client,
        state
      ) do
    name = Chaperon.LoadTest.name(lt_mod)
    Logger.info("Scheduling load test with name: #{name}")

    %{state: state, id: id} =
      if running_load_test?(state) do
        state |> add_load_test(lt)
      else
        state |> start_load_test(nil, lt)
      end

    {:reply, id, state}
  end

  def handle_call({:schedule_load_tests, []}, client, state) do
    Logger.warn("Client #{inspect(client)} tried to schedule empty list of load tests - Aborting")
    {:reply, {:error, :no_load_tests_given}, state}
  end

  def handle_call({:schedule_load_tests, load_tests}, _, state) do
    lt_names = for %{test: lt_mod} <- load_tests, do: Chaperon.LoadTest.name(lt_mod)

    Logger.info(
      "Scheduling #{Enum.count(load_tests)} load tests with names: #{inspect(lt_names)}"
    )

    %{state: state, ids: ids} = state |> add_load_tests(load_tests)

    state =
      if running_load_test?(state) do
        state
      else
        state
        |> schedule_next()
      end

    {:reply, {:ok, ids}, state}
  end

  def handle_call({:cancel_running_or_scheduled, id}, _, state) do
    state =
      case state |> running_task_key(id) do
        nil ->
          state
          |> remove_scheduled(id)

        task_key ->
          state
          |> cancel_running_task(task_key)
          |> schedule_next()
      end

    {:reply, :ok, state}
  end

  def handle_cast({:load_test_finished, {lt_mod, task_id}, session}, state) do
    lt_name = Chaperon.LoadTest.name(lt_mod)
    Logger.info("LoadTest finished: #{lt_name} / #{task_id}")

    case state.tasks[state |> running_task_key(task_id)] do
      nil ->
        Logger.error("No client found for finished load test: #{lt_name} @ #{task_id}")

      client ->
        GenServer.reply(client, session)
    end

    state
    |> remove_task(task_id)
    |> schedule_next()

    {:noreply, state}
  end

  def handle_cast({:load_test_failed, {lt_mod, task_id}, err}, state) do
    lt_name = Chaperon.LoadTest.name(lt_mod)
    Logger.info("LoadTest failed: #{lt_name} / #{task_id} with error: #{inspect(err)}")

    if client = state.tasks[state |> running_task_key(task_id)] do
      GenServer.reply(client, {:error, err})
    end

    state
    |> remove_task(task_id)
    |> schedule_next()

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

  defp add_load_test(state, lt = %{test: lt_mod, options: _}) do
    id = UUID.uuid4()
    name = Chaperon.LoadTest.name(lt_mod)
    Logger.debug("Scheduling load test #{name} with ID #{id}")
    state = update_in(state.scheduled_load_tests, &EQ.push(&1, Map.merge(%{id: id}, lt)))
    %{state: state, id: id}
  end

  defp add_load_tests(state, load_tests) when is_list(load_tests) do
    init_acc = %{state: state, ids: []}

    %{state: state, ids: ids} =
      load_tests
      |> Enum.reduce(init_acc, fn lt, %{state: state, ids: ids} ->
        %{state: state, id: id} = state |> add_load_test(lt)
        %{state: state, ids: [id | ids]}
      end)

    %{state: state, ids: ids |> Enum.reverse()}
  end

  defp running_load_test?(state) do
    Map.size(state.tasks) > 0
  end

  defp start_load_test(state, client, %{test: lt_mod, options: options}, task_id \\ UUID.uuid4()) do
    task =
      Task.async(fn ->
        try do
          session = Chaperon.run_load_test(lt_mod, options)
          GenServer.cast(@name, {:load_test_finished, {lt_mod, task_id}, session})
        catch
          err ->
            GenServer.cast(@name, {:load_test_failed, {lt_mod, task_id}, err})
        end
      end)

    state = update_in(state.tasks, &Map.put(&1, {lt_mod, task_id, task}, client))

    %{state: state, id: task_id}
  end

  defp remove_task(state, task_key = {_lt_mod, _task_id, _task}) do
    update_in(state.tasks, &Map.delete(&1, task_key))
  end

  defp remove_task(state, task_id) when is_binary(task_id) do
    state
    |> remove_task(state |> running_task_key(task_id))
  end

  defp remove_scheduled(state, id) do
    remaining =
      state.scheduled_load_tests
      |> EQ.filter(fn s -> s.id != id end)

    %{state | scheduled_load_tests: remaining}
  end

  defp schedule_next(state) do
    if EQ.empty?(state.scheduled_load_tests) do
      state
    else
      case EQ.pop(state.scheduled_load_tests) do
        {{:value, next}, remaining} ->
          Logger.info("Starting next scheduled load test with id #{next.id}")
          %{state: state, id: _} = state |> start_load_test(nil, next, next.id)
          %{state | scheduled_load_tests: remaining}

        {:empty, _remaining} ->
          state
      end
    end
  end

  defp cancel_running_task(state, task_key = {lt_mod, task_id, task}) do
    Logger.info("Canceling running task #{inspect(task)}")
    Task.shutdown(task)

    state
    |> remove_task(task_key)
  end

  defp running_task_key(state, id) do
    state.tasks
    |> Map.keys()
    |> Enum.find(fn {_lt_mod, task_id, _task} ->
      task_id == id
    end)
  end
end
