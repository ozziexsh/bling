defmodule Bling.MixProject do
  use Mix.Project

  def project do
    [
      app: :bling,
      version: "0.4.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Add recurring billing to your Phoenix application",
      package: [
        licenses: ["MIT"],
        links: %{
          "GitHub" => "https://github.com/ozziexsh/bling"
        },
        files: ~w(priv/static lib stubs mix.exs README.md .formatter.exs)
      ],
      docs: [
        main: "readme",
        extras: ["README.md"]
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      consolidate_protocols: Mix.env() != :test
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.29.4"},
      {:ecto_sql, "~> 3.6"},
      {:phoenix, "~> 1.7.2"},
      {:phoenix_live_view, "~> 1.0.0"},
      {:plug, "~> 1.14"},
      {:stripity_stripe, "~> 3.0"},
      {:postgrex, ">= 0.0.0", only: :test},
      {:faker, "~> 0.17", only: :test},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
