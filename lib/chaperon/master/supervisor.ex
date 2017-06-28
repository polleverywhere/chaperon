defmodule Chaperon.Master.Supervisor do
  @moduledoc """
  Supervisor for the globally registered `Chaperon.Master` load test runner process.
  """

  import Supervisor.Spec

  @name __MODULE__

  def start_link do
    children = [
      worker(Chaperon.Master, [])
    ]

    opts = [strategy: :simple_one_for_one, name: @name]
    Supervisor.start_link(children, opts)
  end

  def start_master do
    Supervisor.start_child(@name, [])
  end
end
