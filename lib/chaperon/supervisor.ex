defmodule Chaperon.Supervisor do
  @moduledoc """
  Root supervisor for all Chaperon processes & supervisors.
  """

  import Supervisor.Spec

  def start_link do
    opts = [strategy: :one_for_one, name: Chaperon.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  def children do
    common_children = [
      supervisor(Chaperon.Master.Supervisor, []),
      supervisor(Chaperon.Worker.Supervisor, []),
      worker(Chaperon.Scenario.Metrics, [])
    ]

    case Application.get_env(:chaperon, Chaperon.Export.InfluxDB, nil) do
      nil ->
        common_children

      _ ->
        [Chaperon.Export.InfluxDB.child_spec() | common_children]
    end
  end
end
