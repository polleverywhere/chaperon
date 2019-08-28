defmodule Chaperon.Mixfile do
  use Mix.Project

  def project do
    [
      app: :chaperon,
      version: "0.3.0",
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "An Elixir based HTTP load & performance testing framework",
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
      # docs
      source_url: "https://github.com/polleverywhere/chaperon",
      docs: [
        extras: ["README.md"]
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
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
      name: "chaperon",
      files: [
        "lib",
        "docs",
        "examples",
        "mix.exs",
        "README*",
        "LICENSE"
      ],
      maintainers: [
        "Christopher Bertels"
      ],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/polleverywhere/chaperon"
      }
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
      {:ex_doc, "~> 0.21.1", only: :dev},
      {:credo, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end
end
