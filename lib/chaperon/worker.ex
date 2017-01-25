defmodule Chaperon.Worker do
  use GenServer

  defstruct [
    id: nil,
    session: nil
  ]

  @type t :: %Chaperon.Worker{
    id: {atom, String.t},
    session: Chaperon.Session.t
  }

  use GenServer
  require Logger
  alias Chaperon.Scenario

  def start_link(scenario_mod, config) do
    GenServer.start_link(__MODULE__, [scenario_mod, config])
  end

  def init(scenario_mod, config) do
    session =
      %Scenario{module: scenario_mod}
      |> Scenario.new_session(config)

    id = {Node.self, session.id}
    Logger.info "Starting Chaperon.Worker #{inspect id}"
    GenServer.cast(self, :run)
    {:ok, %Chaperon.Worker{id: id, session: session}}
  end

  def handle_cast(:run, state) do
    # TODO
    {:noreply, state}
  end
end
