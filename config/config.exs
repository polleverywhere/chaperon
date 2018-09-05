# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger, :console,
  level: :info,
  format: "$date $time [$level] $metadata$message\n",
  metadata: [:user_id]

config :chaperon, Chaperon.Export.InfluxDB,
  database: System.get_env("CHAPERON_INFLUX_DB") || "chaperon",
  host: System.get_env("CHAPERON_INFLUX_HOST") || "localhost",
  http_opts: [insecure: false],
  pool: [max_overflow: 10, size: 5],
  port: System.get_env("CHAPERON_INFLUX_PORT") || 8086,
  scheme: "https",
  auth: [
    method: :basic,
    username: System.get_env("CHAPERON_INFLUX_USER") || "chaperon",
    password: System.get_env("CHAPERON_INFLUX_PW")
  ],
  writer: Instream.Writer.Line

# Custom per env config files override values defined here (if they exist)
if File.exists?("#{__DIR__}/#{Mix.env()}.exs") do
  import_config "#{Mix.env()}.exs"
end
