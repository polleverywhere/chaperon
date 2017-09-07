defmodule Chaperon do
  @moduledoc """
  Chaperon is a HTTP service load & performance testing tool.
  """

  use Application
  require Logger

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    HTTPoison.start
    Chaperon.Supervisor.start_link
  end

  @spec connect_to_master(atom) :: :ok | {:error, any}
  def connect_to_master(node_name) do
    if Node.connect(node_name) do
      :ok
    else
      {:error, "Connecting to Chaperon master node failed: #{node_name}"}
    end
  end

  @doc """
  Runs a given load_test module's scenarios concurrently, outputting metrics
  at the end.

  - `lt_mod` LoadTest module to be executed
  - `options` List of options to be used. Valid values are:
      - `:print_results` If set to `true`, will print all action results.
      - `:encode` Can be set to `:json`, defaults to `:csv`
      - `:output` Can be set to a file path, defaults to `:stdio`
      - `:tag` Can be set to be used when using the default export filename.
        Allows adding a custom 'tag' string as a prefix to the generated result
        output filename.
  ## Example

      Chaperon.run_load_test MyLoadTest, print_results: true
      # => Prints results & outputs metrics in CSV (default) format at the end

      Chaperon.run_load_test MyLoadTest, export: :json
      # => Doesn't print results & outputs metrics in JSON format at the end

      Chaperon.run_load_test MyLoadTest, output: "metrics.csv"
      # => Outputs metrics in CSV format to metrics.csv file

      Chaperon.run_load_test MyLoadTest, export: :json, output: "metrics.json"
      # => Outputs metrics in JSON format to metrics.json file

      Chaperon.run_load_test MyLoadTest, tag: "master"
      # => Outputs metrics in CCSV format to "results/<date>/MyLoadTest/master-<timestamp>.csv"

      Chaperon.run_load_test MyLoadTest, export: :json, tag: "master"
      # => Outputs metrics in JSON format to "results/<date>/MyLoadTest/master-<timestamp>.json"
  """
  def run_load_test(lt_mod, options \\ []) do
    timeout = Chaperon.LoadTest.default_config(lt_mod)[:loadtest_timeout] || :infinity
    config = Keyword.get(options, :config, %{})

    results =
      Chaperon.LoadTest
      |> Task.async(:run, [lt_mod, config])
      |> Task.await(timeout)

    duration_s = results.duration_ms / 1_000
    duration_min = Float.round(results.duration_ms / 60_000, 2)
    Logger.info "#{lt_mod} finished in #{results.duration_ms} ms (#{duration_s} s / #{duration_min} min)"

    if results.timed_out > 0 do
      succeeded = Enum.count(results.sessions)
      Logger.warn "#{lt_mod} : #{results.timed_out} sessions timed out. #{succeeded} sessions succeeded."
    end

    if options[:print_results] do
      print_results(results)
    end

    session = results
              |> Chaperon.LoadTest.merge_sessions

    session =
      if session.config[:merge_scenario_sessions] do
        session
        |> Chaperon.Scenario.Metrics.add_histogram_metrics
      else
        session
      end

    if options[:print_metrics] do
      print_metrics(session)
    end

    print_separator()

    data =
      options
      |> encoder
      |> apply(:encode, [session])

    case options |> output(lt_mod) do
      :remote ->
        {:remote, session, data}

      output ->
        write_output(lt_mod, data, output)

        session
    end
  end

  defp encoder(options) do
    case export_format(options) do
      :csv  -> Chaperon.Export.CSV
      :json -> Chaperon.Export.JSON
    end
  end

  defp output(options, lt_mod) do
    Keyword.get(options, :output, default_output_file(options, lt_mod))
  end

  defp export_format(options) do
    Keyword.get(options, :export, :csv)
  end

  # if output not defined by user, use default output format and file name
  defp default_output_file(options, lt_mod) do
    mod_name =
      lt_mod
      |> Module.split
      |> Enum.join("/")

    timestamp =
      DateTime.utc_now
      |> DateTime.to_unix

    format = export_format(options)
    dir = "results/#{Date.utc_today}/#{mod_name}"

    case options[:tag] do
      nil -> "#{dir}/#{timestamp}.#{format}"
      t   -> "#{dir}/#{t}-#{timestamp}.#{format}"
    end
  end

  def write_output(lt_mod, output, :stdio) do
    IO.puts(output)
    print_separator()
    IO.inspect(%{
      scenarios: lt_mod.scenarios,
      default_config: Chaperon.LoadTest.default_config(lt_mod)
    }, pretty: true)
  end

  def write_output(lt_mod, output, path) do
    path
    |> Path.dirname
    |> File.mkdir_p!

    File.write!(path, output)
    File.write!(path <> ".config.exs", inspect(%{
      scenarios: lt_mod.scenarios,
      default_config: Chaperon.LoadTest.default_config(lt_mod)
    }, pretty: true))
  end

  defp print_separator do
    IO.puts ""
    IO.puts(for _ <- 1..80, do: "=")
    IO.puts ""
  end

  defp print_metrics(session) do
    print_separator()
    Logger.info("Metrics:")
    for {k, v} <- session.metrics do
      k = inspect k
      delimiter = for _ <- 1..byte_size(k), do: "="
      IO.puts("#{delimiter}\n#{k}\n#{delimiter}")
      IO.inspect(v)
      IO.puts("")
    end
  end

  defp print_results(results) do
    print_separator()
    Logger.info("Results:")
    for session <- results.sessions do
      for {action, results} <- session.results do
        for res <- results |> Chaperon.Util.as_list |> List.flatten do
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

  defp print_result(action, %HTTPoison.Response{status_code: status_code}) do
    Logger.info "#{action} -> #{status_code}"
  end

  defp print_result(action, result) when is_binary(result) do
    Logger.info "#{action} -> #{result}"
  end
end
