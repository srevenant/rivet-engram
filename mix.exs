defmodule Rivet.Engram.MixProject do
  use Mix.Project

  def project do
    [
      app: :rivet_engram,
      version: "1.0.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Multi-section templates with EEX and YML support",
      source_url: "https://github.com/srevenant/rivet-engram",
      docs: [main: "Rivet.Engram"],
      package: package(),
      deps: deps(),
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger, :eex]]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.14", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:test, :dev], runtime: false},
      {:transmogrify, "~> 2.0.2"},
      {:yaml_elixir, "~> 2.8"}
    ]
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/srevenant/rivet-engram"},
      source_url: "https://github.com/srevenant/rivet-engram"
    ]
  end
end
