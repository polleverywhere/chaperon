defmodule Chaperon.API.HTTP do
  require Logger
  require Poison

  use Plug.Router
  use Plug.Builder
  import Plug.Conn

  if Mix.env() == :dev do
    use Plug.Debugger, otp_app: :cutlass
  end

  plug(Plug.RequestId)
  plug(:self_logger)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Poison)
  plug(:match)
  plug(:dispatch)

  def start_link(port) do
    Logger.info("Starting Chaperon.API.HTTP on port #{port}")

    # make sure master is running
    Chaperon.Master.start()
    Plug.Adapters.Cowboy.http(__MODULE__, [acceptors: 20], port: port)
  end

  get "/" do
    conn
    |> send_resp(200, "Chaperon @ #{Chaperon.version()}")
  end

  get "/load_tests" do
    conn
    |> send_json_resp(200, %{load_tests: Chaperon.Master.running_load_tests()})
  end

  post "/load_tests" do
    load_tests = conn.params["load_tests"] || []

    for lt <- load_tests do
      Chaperon.Master.schedule_load_test(lt)
    end

    conn
    |> send_resp(202, "")
  end

  get "/version" do
    conn
    |> send_resp(200, Chaperon.version())
  end

  get "/*_" do
    conn
    |> send_resp(404, "")
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
end
