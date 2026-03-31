defmodule Scrutinex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mphfish/scrutinex"

  def project do
    [
      app: :scrutinex,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Scrutinex",
      source_url: @source_url,
      homepage_url: @source_url,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ],
      assay: [
        dialyzer: [
          apps: [:scrutinex, :elixir, :kernel, :stdlib, :erts, :compiler],
          warning_apps: [:scrutinex]
        ]
      ],
      aliases: aliases()
    ]
  end

  def application do
    []
  end

  defp description do
    "Declarative data validation for tabular data (lists of maps). " <>
      "Define schemas with an Ecto-style macro DSL, validate columns, types, " <>
      "ranges, formats, cross-column relationships, and more."
  end

  defp package do
    [
      maintainers: ["Mike Fisher"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "Scrutinex",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      groups_for_modules: [
        Core: [Scrutinex, Scrutinex.Schema],
        "Data Structures": [
          Scrutinex.Column,
          Scrutinex.Check,
          Scrutinex.Error,
          Scrutinex.Result,
          Scrutinex.Schema.Definition,
          Scrutinex.ValidationError
        ],
        Checks: [
          Scrutinex.Checks.Number,
          Scrutinex.Checks.Inclusion,
          Scrutinex.Checks.Exclusion,
          Scrutinex.Checks.Format,
          Scrutinex.Checks.Length,
          Scrutinex.Checks.Custom
        ],
        Internal: [Scrutinex.Validator, Scrutinex.Coercion]
      ]
    ]
  end

  defp deps do
    [
      {:ex_check, "~> 0.16", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:assay, "~> 0.5", only: :dev, runtime: false},
      {:doctor, "~> 0.22", only: :dev, runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      {:benchee_html, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "bench.baseline": "run bench/baseline_bench.exs",
      "bench.coercion": "run bench/coercion_bench.exs",
      "bench.checks": "run bench/checks_bench.exs",
      "bench.scaling": "run bench/scaling_bench.exs",
      "bench.strict": "run bench/strict_bench.exs",
      "bench.regex": "run bench/regex_columns_bench.exs",
      "bench.cross": "run bench/cross_column_bench.exs",
      "bench.errors": "run bench/error_path_bench.exs",
      "profile.eprof": "run bench/profile/eprof_profile.exs",
      "profile.fprof": "run bench/profile/fprof_profile.exs",
      "profile.tprof": "run bench/profile/tprof_profile.exs",
      "profile.cprof": "run bench/profile/call_count_profile.exs"
    ]
  end
end
