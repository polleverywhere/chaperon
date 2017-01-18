defmodule Chaperon do
  @moduledoc """
  Chaperon is a HTTP service load & performance testing tool.
  """

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

  @doc """
  Runs a given environment module's scenarios concurrently, outputting metrics
  at the end.

  - `env_mod` Environment module to be executed
  - `options` List of options to be used. Valid values are:
      - `:print_results` If set to `true`, will print all action results.
      - `:encode` Can be set to `:json`, defaults to `:csv`
      - `:output` Can be set to a file path, defaults to `:stdio`

  ## Example

      Chaperon.run_environment MyEnvironment, print_results: true
      # => Prints results & outputs metrics in CSV (default) format at the end

      Chaperon.run_environment MyEnvironment, export: :json
      # => Doesn't print results & outputs metrics in JSON format at the end

      Chaperon.run_environment MyEnvironment, output: "metrics.csv"
      # => Outputs metrics in CSV format to metrics.csv file

      Chaperon.run_environment MyEnvironment, export: :json, output: "metrics.json"
      # => Outputs metrics in JSON format to metrics.json file
  """
  def run_environment(env_mod, options \\ []) do
    sessions = apply(env_mod, :run, [])

    if options[:print_results] do
      print_results(sessions)
    end

    session = sessions
              |> Chaperon.Environment.merge_sessions

    if options[:print_metrics] do
      print_metrics(session)
    end

    print_separator

    apply(encoder(options), :encode, [session])
    |> write_output(Keyword.get(options, :output, :stdio))
  end

  defp encoder(options) do
    case Keyword.get(options, :export, :csv) do
      :csv  -> Chaperon.Export.CSV
      :json -> Chaperon.Export.JSON
    end
  end

  defp write_output(output, :stdio), do: IO.puts(output)
  defp write_output(output, path),   do: File.write!(path, output)

  defp print_separator do
    IO.puts ""
    IO.puts(for _ <- 1..80, do: "=")
    IO.puts ""
  end

  defp print_metrics(session) do
    print_separator
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
    print_separator
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
