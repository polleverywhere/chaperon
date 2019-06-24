defmodule Chaperon.API.HTTP do
  require Logger
  require Poison

  defmodule HealthCheckPlug do
    import Plug.Conn
    @behaviour Plug

    @intercepted_routes [
      # root page (GET /)
      [],
      ["healthcheck"]
    ]

    def init(opts), do: opts

    def call(conn = %{method: "GET", path_info: path_info}, _opts)
        when path_info in @intercepted_routes do
      conn
      |> send_resp(200, "Chaperon @ #{Chaperon.version()}")
      |> halt()
    end

    def call(conn, _opts), do: conn
  end

  use Plug.Router
  import Plug.Conn
  import Chaperon.Util, only: [symbolize_keys: 1]

  if Mix.env() == :dev do
    use Plug.Debugger, otp_app: :cutlass
  end

  plug(Chaperon.API.HTTP.HealthCheckPlug)
  plug(:self_logger)
  plug(Plug.RequestId)
  plug(BasicAuth, use_config: {:chaperon, Chaperon.API.HTTP})
  plug(Plug.Parsers, parsers: [:json], json_decoder: Poison)
  plug(:match)
  plug(:dispatch)

  def start_link() do
    port = api_port()
    Logger.info("Starting Chaperon.API.HTTP on port #{port}")

    # make sure master is running
    Chaperon.Master.start()
    Plug.Adapters.Cowboy.http(__MODULE__, [acceptors: 20], port: port)
  end

  def enabled?() do
    api_port() != nil
  end

  def api_port() do
    case System.get_env("CHAPERON_PORT") do
      nil -> Application.get_env(:chaperon, __MODULE__)[:port]
      port -> port |> String.to_integer()
    end
  end

  get "/load_tests" do
    conn
    |> send_json_resp(200, %{load_tests: Chaperon.Master.running_load_tests()})
  end

  get "/version" do
    conn
    |> send_resp(200, Chaperon.version())
  end

  get "/*_" do
    conn
    |> send_resp(404, "")
  end

  post "/load_tests" do
    load_tests =
      for cfg <- conn.params["load_tests"] || [] do
        cfg =
          cfg
          |> Map.take(["test", "options"])
          |> symbolize_keys()

        cfg
        |> Map.update(:test, cfg[:test], &(&1 |> String.split(".") |> Module.concat()))
        |> Map.update(:options, cfg[:options], &parse_options/1)
      end

    case Chaperon.Master.schedule_load_tests(load_tests) do
      {:error, reason} ->
        conn
        |> send_json_resp(400, %{error: reason |> inspect})

      {:ok, ids} ->
        conn
        |> send_json_resp(202, %{scheduled: ids})
    end
  end

  post "/*_" do
    conn
    |> send_resp(404, "")
  end

  defp self_logger(conn, opts) do
    if conn.request_path == "/healthcheck" do
      conn
    else
      Plug.Logger.call(conn, Plug.Logger.init(opts))
    end
  end

  defp send_json_resp(conn, status_code, data) do
    conn
    |> send_resp(status_code, Poison.encode!(data))
  end

  def parse_options(options) do
    parser = Application.get_env(:chaperon, __MODULE__)[:option_parser]

    case parser.parse_options(options) do
      {:ok, options} ->
        options

      {:error, reason} ->
        Logger.error("Error parsing options using parser #{parser}: #{reason}")
        options
    end
  end
end
