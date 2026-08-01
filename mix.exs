defmodule Aletheia.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :aletheia,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:mix]],
      description: description(),
      package: package(),
      name: "Aletheia",
      docs: docs()
    ]
  end

  # `precommit`'s own "test" step otherwise runs under whatever env the
  # alias itself started in (:dev by default) instead of :test, since Mix
  # only auto-switches env for the top-level invoked task, not nested
  # alias steps.
  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # === CODE QUALITY & STATIC ANALYSIS ===
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false},
      # Credo is invoked via `MIX_ENV=test mix credo`
      # Dialyzer is invoked via `MIX_ENV=test mix dialyzer`
      # Sobelow is invoked via `MIX_ENV=test mix sobelow`
      # Coveralls is invoked via `MIX_ENV=test mix coveralls

      # === TESTING ===
      {:mox, "~> 1.2", only: [:dev, :test]},
      {:faker, "~> 0.19", only: [:test]},
      {:stream_data, "~> 1.4", only: [:test]},

      # === DEVELOPMENT TOOLING ===
      # Mix, and Hex are built-in (no deps needed)
      {:ex_doc, "~> 0.40", only: [:dev], runtime: false},
      # ExDoc is invoked via `MIX_ENV=dev mix docs`

      # === RUNTIME ===
      # ichor_runtime is the only piece a generated parser (Aletheia.Reader,
      # via Ichor.Toolkit.Pratt) needs at actual runtime; ichor itself (the
      # Aether front-end, Grammar.Analysis, both codegen backends) is only
      # ever invoked via `mix ichor.gen`, ahead of time, so it's dev-only
      # and never ships in a release. Both published to Hex now
      # (independent packages, independent release cadence -- ichor_runtime
      # is its own repo, not a subdirectory of ichor's).
      {:ichor_runtime, "~> 0.1.0"},
      {:ichor, "~> 0.2.0", only: :dev, runtime: false},
      # Episteme is the standalone engine/database this reader is a
      # front-end for -- terms, unification, SLD-resolution, cut, and the
      # builtin predicates all live there now, not in this package (see
      # DESIGN.md's `episteme_split`). Not yet published to Hex, so a path
      # dependency onto a sibling checkout for now.
      {:episteme, path: "../episteme"}
    ]
  end

  # Fast/cheap checks first so a broken commit fails quickly; dialyzer
  # (slowest, especially its first PLT build) runs last.
  defp aliases do
    [
      precommit: [
        "format",
        "compile --warnings-as-errors",
        "credo --strict",
        "sobelow",
        "test",
        "dialyzer"
      ],
      # Regenerates lib/aletheia/reader/grammar_generated.ex from
      # lib/aletheia/reader/grammar.aether. Requires ichor (dev-only), so
      # this only works under MIX_ENV=dev. No automatic staleness check
      # between the checked-in file and its source grammar -- rerun this
      # by hand whenever grammar.aether changes.
      "gen.grammar": [
        "ichor.gen lib/aletheia/reader/grammar.aether --module Aletheia.Reader.Grammar --actions Aletheia.Reader.Actions --out lib/aletheia/reader/grammar_generated.ex"
      ]
    ]
  end

  defp description do
    "An embedded Prolog dialect for Elixir -- classic Prolog syntax (`:-`, `,`/`;`, `=`, " <>
      "a mutable op/3 operator table) via a reader built on top of Ichor and Episteme, " <>
      "the standalone resolution engine and clause database (unification, SLD-resolution, " <>
      "backtracking, a real clause-scoped cut) this package is a syntax front-end for."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/joetjen/aletheia"},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE guides examples)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/joetjen/aletheia",
      source_ref: "v#{@version}",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules()
    ]
  end

  defp extras do
    [
      "README.md",
      "guides/TUTORIAL.md",
      "guides/REFERENCE.md",
      "guides/CHEATSHEET.md",
      "guides/EXAMPLES.md",
      "CHANGELOG.md",
      "LICENSE"
    ]
  end

  defp groups_for_extras do
    [
      Guides: Path.wildcard("guides/*.md")
    ]
  end

  defp groups_for_modules do
    [
      "Top-level API": [
        Aletheia
      ],
      Reader: [
        Aletheia.Reader,
        Aletheia.Reader.Actions,
        Aletheia.Reader.Pratt
      ],
      REPL: [
        Aletheia.Repl
      ]
    ]
  end
end
