defmodule Chaperon.Worker.Supervisor do
  @name Chaperon.Worker.Supervisor

  def start_link do
    opts = [strategy: :simple_one_for_one, name: @name]
    Task.Supervisor.start_link(opts)
  end

  def start_worker(scenario_mod, config) do
    Task.Supervisor.start_child(@name, Chaperon.Worker, :start_link, [scenario_mod, config])
  end
end
