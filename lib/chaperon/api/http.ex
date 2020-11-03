defmodule Chaperon.API.HTTP do
  @moduledoc """
  HTTP API handler used for remote control of chaperon cluster.
  Allows scheduling new load tests, aborting currently running or scheduled ones
  as well as listing all currently running and scheduled load tests.
  """

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

    case api_ip() do
      nil -> Plug.Adapters.Cowboy.http(__MODULE__, [acceptors: 20], port: port)
      ip -> Plug.Adapters.Cowboy.http(__MODULE__, [acceptors: 20], port: port, ip: ip)
    end
  end

  def enabled?() do
    api_port() != nil
  end

  def api_ip() do
    case System.get_env("CHAPERON_IP") do
      nil ->
        Application.get_env(:chaperon, __MODULE__)[:ip]

      ip ->
        String.to_charlist(ip) |> :inet.parse_address() |> elem(1)
    end
  end

  def api_port() do
    case System.get_env("CHAPERON_PORT") do
      nil -> Application.get_env(:chaperon, __MODULE__)[:port]
      port -> port |> String.to_integer()
    end
  end

  get "/load_tests" do
    conn
    |> send_json_resp(200, %{
      running: Chaperon.Master.running_load_tests(),
      scheduled: Chaperon.Master.scheduled_load_tests()
    })
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
        cfg
        |> Map.take(["test", "options"])
        |> symbolize_keys()
        |> parse_options()
      end
      |> List.flatten()

    case Chaperon.Master.schedule_load_tests(load_tests) do
      {:error, reason} ->
        conn
        |> send_json_resp(400, %{error: reason |> inspect})

      {:ok, ids} ->
        conn
        |> send_json_resp(200, %{scheduled: ids})
    end
  end

  delete "/load_tests" do
    case Chaperon.Master.cancel_all() do
      {:error, reason} ->
        conn
        |> send_json_resp(400, %{
          error: inspect(reason)
        })

      :ok ->
        conn
        |> send_resp(202, "")
    end
  end

  delete "/load_tests/scheduled" do
    case Chaperon.Master.cancel_scheduled() do
      {:error, reason} ->
        conn
        |> send_json_resp(400, %{
          error: inspect(reason)
        })

      :ok ->
        conn
        |> send_resp(202, "")
    end
  end

  delete "/load_tests/:id" do
    case Chaperon.Master.cancel_running_or_scheduled(conn.params["id"]) do
      {:error, reason} ->
        conn
        |> send_json_resp(400, %{
          error: inspect(reason)
        })

      :ok ->
        conn
        |> send_resp(202, "")
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

  def parse_options(args) do
    parser = Application.get_env(:chaperon, __MODULE__)[:option_parser]
    Logger.info("Chaperon.API.HTTP | Using option parser: #{inspect(parser)}")

    case parser.parse_options(args) do
      {:ok, lt_configs} ->
        for {lt, options} <- lt_configs do
          %{test: lt, options: options}
        end

      {:ok, lt, options} ->
        %{test: lt, options: options}

      {:error, reason} ->
        Logger.error("Error parsing options using parser #{inspect(parser)}: #{inspect(reason)}")
        raise ArgumentError, message: inspect(reason)
    end
  end
end
