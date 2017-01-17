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

    if opts[:print_metrics] do
      print_metrics(session)
    end

    print_seperator
    IO.puts apply(encoder(opts), :encode, [session])
  end

  def encoder(opts) do
    case Keyword.get(opts, :export, :csv) do
      :csv  -> Chaperon.Export.CSV
      :json -> Chaperon.Export.JSON
    end
  end

  defp print_seperator do
    IO.puts ""
    IO.puts(for _ <- 1..80, do: "=")
    IO.puts ""
  end

  defp print_metrics(session) do
    print_seperator
    Logger.info("Metrics:")
    for {k, v} <- session.metrics do
      k = inspect k
      delimiter = for _ <- 1..byte_size(k), do: "="
      IO.puts("#{delimiter}\n#{k}\n#{delimiter}")
      IO.inspect(v)
      IO.puts("")
    end
  end

  defp print_results(sessions) do
    print_seperator
    Logger.info("Results:")
    for session <- sessions do
      for {action, results} <- session.results do
        for res <- results |> Chaperon.Util.as_list do
          case res do
            {:async, name, results} when is_list(results) ->
              results
              |> Enum.each(&print_result(name, &1))

            {:async, name, res} ->
              Logger.info "~> #{name} -> #{res.status_code}"

            results when is_list(results) ->
              results
              |> Enum.each(&print_result(action, &1))

            res ->
              print_result(action, res)
          end
        end
      end
    end
  end

  defp print_result(action, res) do
    Logger.info "#{action} -> #{res.status_code}"
  end
end
