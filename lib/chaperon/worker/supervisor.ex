defmodule Chaperon.Worker.Supervisor do
  @name Chaperon.Worker.Supervisor

  def start_link do
    opts = [strategy: :simple_one_for_one, name: @name]
    Task.Supervisor.start_link(opts)
  end

  def start_workers(nodes, amount, scenario_mod, config) do
    nodes
    |> Stream.cycle
    |> Stream.take(amount)
    |> Enum.map(&start_worker(&1, scenario_mod, config))
  end

  def start_worker(node, scenario_mod, config) do
    Task.Supervisor.async({@name, node}, Chaperon.Scenario, :execute, [scenario_mod, config])
  end
end
