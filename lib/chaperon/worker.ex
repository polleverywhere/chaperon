defmodule Chaperon.Worker do
  require Logger

  def start(amount, scenario_mod, config)
  when is_integer(amount) and amount > 0
  do
    Chaperon.Worker.Supervisor.start_workers(nodes, amount, scenario_mod, config)
  end

  def start(scenario_mod, config) do
    Chaperon.Worker.Supervisor.start_worker(random_node, scenario_mod, config)
  end

  def await(%Task{} = worker, timeout \\ 5000) do
    Task.await(worker, timeout)
  end

  def random_node do
    nodes
    |> Enum.shuffle
    |> List.first
  end

  def nodes do
    [Node.self | Node.list]
  end
end
