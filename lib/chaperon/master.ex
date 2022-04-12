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
          tasks: %{UUID.uuid4() => pid},
          non_worker_nodes: [atom],
          scheduled_load_tests: EQ.t()
        }

  @derive {Inspect, only: [:id]}

  @load_test_pause_interval Chaperon.Timing.seconds(30)

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

  def cancel_all() do
    GenServer.call(@name, :cancel_all)
  end

  def cancel_running_or_scheduled(id) do
    GenServer.call(@name, {:cancel_running_or_scheduled, id})
  end

  def cancel_scheduled() do
    GenServer.call(@name, :cancel_scheduled)
  end

  @spec ignore_node_as_worker(atom) :: :ok
  def ignore_node_as_worker(node) do
    GenServer.call(@name, {:ignore_node_as_worker, node})
  end

  def handle_call({:run_load_test, lt_mod, options}, client, state) do
    Logger.info(
      "Chaperon.Master | Starting LoadTest #{Chaperon.LoadTest.name(lt_mod)} @ Master #{state.id}"
    )

    %{state: state, id: _task_id} =
      start_load_test(state, client, %{test: lt_mod, options: options})

    {:noreply, state}
  end

  def handle_call({:ignore_node_as_worker, node}, _, state) do
    state = update_in(state.non_worker_nodes, &[node | &1])
    {:reply, :ok, state}
  end

  def handle_call(:running_load_tests, _, state) do
    Logger.info("Chaperon.Master | Requesting running load tests")

    running =
      for {id, %{load_test: lt_conf, options: options}} <- state.tasks do
        Logger.debug("Got load test options: #{inspect(options)}")
        %{name: Chaperon.LoadTest.name(lt_conf), id: id, tag: options[:tag]}
      end

    {:reply, running, state}
  end

  def handle_call(:scheduled_load_tests, _, state) do
    Logger.info("Chaperon.Master | Requesting scheduled load tests")

    scheduled =
      for %{test: lt_conf, id: id, options: options} <- EQ.to_list(state.scheduled_load_tests) do
        %{name: Chaperon.LoadTest.name(lt_conf), id: id, tag: options[:tag]}
      end

    {:reply, scheduled, state}
  end

  def handle_call(
        {:schedule_load_test, lt = %{test: lt_mod, options: _}},
        _client,
        state
      ) do
    name = Chaperon.LoadTest.name(lt_mod)
    Logger.info("Chaperon.Master | Scheduling load test with name: #{name}")

    %{state: state, id: id} =
      if running_load_test?(state) do
        state |> add_load_test(lt)
      else
        state |> start_load_test(nil, lt)
      end

    {:reply, id, state}
  end

  def handle_call({:schedule_load_tests, []}, client, state) do
    Logger.warn(
      "Chaperon.Master | Client #{inspect(client)} tried to schedule empty list of load tests - Aborting"
    )

    {:reply, {:error, :no_load_tests_given}, state}
  end

  def handle_call({:schedule_load_tests, load_tests}, _, state) do
    lt_names = for %{test: lt_mod} <- load_tests, do: Chaperon.LoadTest.name(lt_mod)

    Logger.info(
      "Chaperon.Master | Scheduling #{Enum.count(load_tests)} load tests with names: #{
        inspect(lt_names)
      }"
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

  def handle_call(:cancel_all, _, state) do
    for {task_id, %{task: task}} <- state.tasks do
      state
      |> cancel_running_task(task_id, task)
    end

    {:reply, :ok, %{state | tasks: %{}, scheduled_load_tests: EQ.new()}}
  end

  def handle_call({:cancel_running_or_scheduled, id}, _, state) do
    state =
      case state.tasks[id] do
        nil ->
          state
          |> remove_scheduled(id)

        %{task: task} ->
          state
          |> cancel_running_task(id, task)
          |> schedule_next()
      end

    {:reply, :ok, state}
  end

  def handle_call(:cancel_scheduled, _, state) do
    {:reply, :ok, %{state | scheduled_load_tests: EQ.new()}}
  end

  def handle_cast({:load_test_finished, {lt_mod, task_id}, session}, state) do
    lt_name = Chaperon.LoadTest.name(lt_mod)
    Logger.info("Chaperon.Master | LoadTest finished: #{lt_name} / #{task_id}")

    case state.tasks[task_id] do
      nil ->
        Logger.error(
          "Chaperon.Master | No client found for finished load test: #{lt_name} @ #{task_id}"
        )

      %{client: client} ->
        if client do
          GenServer.reply(client, session)
        end
    end

    state =
      state
      |> remove_task(task_id)
      |> schedule_next()

    {:noreply, state}
  end

  def handle_cast({:load_test_failed, {lt_mod, task_id}, err}, state) do
    case state.tasks[task_id] do
      %{client: client} ->
        lt_name = Chaperon.LoadTest.name(lt_mod)

        Logger.info(
          "Chaperon.Master | LoadTest failed: #{lt_name} / #{task_id} with error: #{inspect(err)}"
        )

        if client do
          GenServer.reply(client, {:error, err})
        end

      nil ->
        Logger.info(
          "Chaperon.Master | Unknown LoadTest with id #{task_id} failed with error: #{
            inspect(err)
          }"
        )
    end

    state
    |> remove_task(task_id)
    |> schedule_next()

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, :normal}, state) do
    Logger.debug("Chaperon.Master | Load test finished: #{inspect(pid)}")
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, {error, _context}}, state) do
    task_id = find_task_id(state, pid, ref)
    Logger.error("Chaperon.Master | LoadTest died: #{task_id} | #{inspect(error)}")

    state =
      state
      |> remove_task(task_id)
      |> schedule_next()

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.error("Chaperon.Master | Ignoring unknown message: #{inspect(msg)}")

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
    Logger.debug("Chaperon.Master | Scheduling load test #{name} with ID #{id}")
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
    {:ok, task_pid} =
      Task.start(fn ->
        Process.sleep(@load_test_pause_interval)

        try do
          session = Chaperon.run_load_test(lt_mod, options)
          GenServer.cast(@name, {:load_test_finished, {lt_mod, task_id}, session})
        catch
          err ->
            GenServer.cast(@name, {:load_test_failed, {lt_mod, task_id}, err})
        end
      end)

    task_ref = Process.monitor(task_pid)

    state =
      update_in(
        state.tasks,
        &Map.put(&1, task_id, %{
          client: client,
          load_test: lt_mod,
          options: options,
          task: {task_pid, task_ref}
        })
      )

    %{state: state, id: task_id}
  end

  defp remove_task(state, task_id) do
    update_in(state.tasks, &Map.delete(&1, task_id))
  end

  defp remove_scheduled(state, id) do
    remaining =
      state.scheduled_load_tests
      |> EQ.filter(fn s -> s.id != id end)

    %{state | scheduled_load_tests: remaining}
  end

  defp schedule_next(state) do
    if EQ.empty?(state.scheduled_load_tests) do
      Logger.warn("Chaperon.Master | No other load tests scheduled - aborting schedule_next")
      state
    else
      case EQ.pop(state.scheduled_load_tests) do
        {{:value, next}, remaining} ->
          Logger.info("Chaperon.Master | Starting next scheduled load test with id #{next.id}")
          %{state: state, id: _} = state |> start_load_test(nil, next, next.id)
          %{state | scheduled_load_tests: remaining}

        {:empty, _remaining} ->
          Logger.warn(
            "Chaperon.Master | No remaining scheduled load tests available. Doing nothing for now..."
          )

          state
      end
    end
  end

  defp cancel_running_task(state, task_id, task = {pid, _ref}) do
    Logger.info("Chaperon.Master | Canceling running task #{inspect(task)}")
    Process.exit(pid, :kill)

    state
    |> remove_task(task_id)
  end

  defp find_task_id(state, pid, ref) do
    for {task_id, %{task: {^pid, ^ref}}} <- state.tasks do
      task_id
    end
    |> Enum.at(0)
  end
end
