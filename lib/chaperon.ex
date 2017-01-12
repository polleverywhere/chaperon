defmodule Chaperon do
  use Application
  require Logger

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    HTTPoison.start

    # Define workers and child supervisors to be supervised
    children = [
      # Starts a worker by calling: Chaperon.Worker.start_link(arg1, arg2, arg3)
      # worker(Chaperon.Worker, [arg1, arg2, arg3]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Chaperon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def run_environment(env_mod, opts \\ []) do
    sessions = apply(env_mod, :run, [])

    if opts[:print_results] do
      print_results(sessions)
    end

    session = sessions
              |> Chaperon.Environment.merge_sessions

    Logger.info("Metrics:")
    for {k, v} <- session.metrics do
      k = inspect k
      delimiter = for _ <- 1..byte_size(k), do: "="
      IO.puts("#{delimiter}\n#{k}\n#{delimiter}")
      IO.inspect(v)
      IO.puts("")
    end

    IO.puts Chaperon.Export.CSV.encode(session)
  end

  def print_results(sessions) do
    for session <- sessions do
      for {action, results} <- session.results do
        for res <- results |> Chaperon.Util.as_list do
          case res do
            {:async, name, res} ->
              Logger.info "~> #{name} -> #{res.status_code}"
            res ->
              Logger.info "#{action} -> #{res.status_code}"
          end
        end
      end
    end
  end
end
