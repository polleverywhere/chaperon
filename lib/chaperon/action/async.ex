defmodule Chaperon.Action.Async do
  @moduledoc """
  Implementation module for asynchronous actions (function calls into a
  `Chaperon.Scenario` module).
  """

  defstruct [
    module: nil,
    function: nil,
    args: [],
    task_name: nil
  ]

  @type t :: %Chaperon.Action.Async{
    module: atom,
    function: atom,
    args: [any],
    task_name: atom
  }
end

defimpl Chaperon.Actionable, for: Chaperon.Action.Async do
  alias Chaperon.Session
  use Chaperon.Session.Logging
  import Chaperon.Timing

  def run(
    action = %{
      module: mod,
      function: func_name,
      args: args,
      task_name: task_name
    },
    session
  ) do
    session
    |> log_debug("Async #{task_name} : #{mod}.#{func_name}(#{inspect args})")

    task = action |> execute_task(session)

    session
    |> Session.add_async_task(task_name, task)
    |> Session.ok
  end

  def abort(action, session) do
    {:ok, action, session}
  end

  defp execute_task(
    %{
      module: mod,
      function: func_name,
      args: args,
      task_name: task_name
    },
    session
  ) do
    session = %{session | parent_pid: self()}
    Task.async fn ->
      start = timestamp()
      session = apply(mod, func_name, [session | args])
      duration = timestamp() - start

      session
      |> Session.add_metric([:duration, task_name], duration)
    end
  end
end

defimpl String.Chars, for: Chaperon.Action.Async do
  def to_string(%{module: mod, function: func_name, args: args}) do
    "Async[#{mod}.#{func_name}/#{Enum.count(args)}]"
  end
end
