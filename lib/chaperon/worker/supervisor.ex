defmodule Chaperon.Worker.Supervisor do
  @moduledoc """
  Chaperon worker process supervisor.
  Each `Chaperon.Scenario` is executed with a `Chaperon.Session` inside a
  `Chaperon.Worker` `Task` processes supervised by this supervisor.
  """

  require Logger

  @name Chaperon.Worker.Supervisor

  def start_link do
    opts = [strategy: :simple_one_for_one, name: @name]
    Task.Supervisor.start_link(opts)
  end

  def start_workers(nodes, amount, scenario_mod, config, timeout) do
    nodes
    |> Stream.cycle
    |> Stream.take(amount)
    |> Enum.map(&start_worker(&1, scenario_mod, config, timeout))
  end

  def start_worker(node, scenario_mod, config, timeout) do
    start_worker_via(node, scenario_mod, :execute, [config], timeout)
  end

  def start_nested_worker(node, scenario_mod, session, config, timeout) do
    start_worker_via(node, scenario_mod, :execute_nested, [session, config], timeout)
  end

  defp start_worker_via(node, scenario_mod, function, args, timeout) do
    async(node, __MODULE__, :worker_task, [node, scenario_mod, function, args, timeout])
  end

  def worker_task(node, scenario_mod, function, args, timeout) do
    # This starts the actual worker scenario task and yields to it for the given
    # timeout. if the task hasn't finished within the timeout, return nil,
    # otherwise return the worker task's session return value.
    t = async(node, Chaperon.Scenario, function, [scenario_mod | args])
    case Task.yield(t, timeout) do
      {:ok, session} ->
        Logger.info "Worker finished: #{session.id}"
        session

      {:exit, reason} ->
        Logger.info "Worker exited with reason: #{scenario_mod} : #{inspect reason}"
        nil

      nil ->
        Logger.info "Worker timed out: #{scenario_mod}"
        nil
    end
  end

  def schedule_async(mod, func, args) do
    async Chaperon.Worker.random_node(), mod, func, args
  end

  def schedule_async(func) do
    async Chaperon.Worker.random_node(), func
  end

  def async(node, mod, func, args) do
    Task.Supervisor.async({@name, node}, mod, func, args)
  end

  def async(func) do
    Task.Supervisor.async(@name, func)
  end

  def async(node, func) do
    Task.Supervisor.async({@name, node}, func)
  end
end
