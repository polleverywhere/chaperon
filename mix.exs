defmodule Chaperon.Mixfile do
  use Mix.Project

  @source_url "https://github.com/polleverywhere/chaperon"
  @version "0.3.1"

  def project do
    [
      app: :chaperon,
      version: @version,
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_add_apps: [
          :httpoison,
          :uuid,
          :poison,
          :histogrex
        ],
        flags: [
          # "-Woverspecs",
          # "-Wunderspecs"
        ],
        # skip unkown function warnings
        remove_defaults: [:unknown]
      ],
    ]
  end

  def application do
    [
      extra_applications: [
        :logger,
        :inets
      ],
      mod: {Chaperon, []}
    ]
  end

  defp package do
    [
      description: "An Elixir based HTTP load & performance testing framework",
      name: "chaperon",
      files: [
        "lib",
        "docs",
        "examples",
        "mix.exs",
        "README*",
        "LICENSE.md"
      ],
      maintainers: [
        "Christopher Bertels"
      ],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp deps do
    [
      {:httpoison, "~> 1.5"},
      {:uuid, "~> 1.1"},
      {:poison, "~> 3.0"},
      {:histogrex, "~> 0.0.5"},
      {:websockex, "~> 0.4"},
      {:e_q, "~> 1.0.0"},
      {:instream, "~> 0.21.0"},
      {:deep_merge, "~> 1.0"},
      {:cowboy, "~> 2.6"},
      {:plug, "~> 1.8"},
      {:plug_cowboy, "~> 2.0"},
      {:basic_auth, "~> 2.2"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      extras: [
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"],
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end
end
