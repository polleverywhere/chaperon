# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger, :console,
  level: :info,
  format: "$date $time [$level] $metadata$message\n",
  metadata: [:user_id]

# Custom per env config files override values defined here (if they exist)
if File.exists?("#{__DIR__}/#{Mix.env}.exs") do
  import_config "#{Mix.env}.exs"
end
