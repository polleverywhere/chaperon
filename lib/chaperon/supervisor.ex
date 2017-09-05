defmodule Chaperon.Supervisor do
  @moduledoc """
  Root supervisor for all Chaperon processes & supervisors.
  """

  import Supervisor.Spec

  def start_link do
    children = [
      supervisor(Chaperon.Master.Supervisor, []),
      supervisor(Chaperon.Worker.Supervisor, []),
      worker(Chaperon.Scenario.Metrics, []),
      :hackney_pool.child_spec(:chaperon, [timeout: 20_000, max_connections: 200_000])
    ]

    opts = [strategy: :one_for_one, name: Chaperon.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
