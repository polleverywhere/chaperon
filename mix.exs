defmodule Chaperon.Mixfile do
  use Mix.Project

  def project do
    [
      app: :chaperon,
      version: "0.1.0",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_add_apps: [
          :httpoison, :uuid, :poison, :hdr_histogram
        ],
        flags: [
          # "-Woverspecs",
          # "-Wunderspecs"
        ],
        remove_defaults: [:unknown] # skip unkown function warnings
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      applications: [
        :logger, :httpoison, :uuid, :poison, :hdr_histogram, :gun
      ],
      mod: {Chaperon, []}
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:httpoison, "~> 0.10.0"},
      {:uuid, "~> 1.1"},
      {:poison, "~> 3.0"},
      {:hdr_histogram, "~> 0.2.0"},
      {:gun, "~> 1.0.0-pre.2"},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.14", only: :dev}
    ]
  end
end
