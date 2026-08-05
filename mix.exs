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
      {:ichor_runtime, "~> 0.2"},
      {:ichor, "~> 0.3", only: :dev, runtime: false},
      # Episteme is the standalone engine/database this reader is a
      # front-end for -- terms, unification, SLD-resolution, cut, and the
      # builtin predicates all live there now, not in this package. Path
      # dependency for now (interim) -- episteme's develop branch has all
      # of v0.2-v0.5, but hasn't been released to Hex yet. Switch back to
      # a plain Hex version constraint once it is.
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
        "sobelow --skip",
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
      links: %{
        "GitHub" => "https://github.com/joetjen/aletheia",
        "Docs" => "https://joetjen.github.io/aletheia/"
      },
      files:
        ~w(lib .formatter.exs mix.exs README.md CASE_STUDY.md CHANGELOG.md LICENSE guides examples)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/joetjen/aletheia",
      source_ref: "v#{@version}",
      # Deployed by .github/workflows/docs.yml on every push to `main`.
      homepage_url: "https://joetjen.github.io/aletheia/",
      canonical: "https://joetjen.github.io/aletheia/",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules()
    ]
  end

  # Doc navigation order, mirroring logos's own `extras/0`: README
  # first (it's `main`), then the embedding-layer guides (tutorial,
  # examples, cheatsheet -- using Aletheia as a library from Elixir),
  # then the language-layer guides in the same tutorial/reference/
  # examples/cheatsheet shape (the Prolog dialect itself, independent
  # of embedding), then the single large real-world case study, then
  # project-process docs last.
  defp extras do
    [
      "README.md",
      "guides/TUTORIAL.md",
      "guides/EXAMPLES.md",
      "guides/CHEATSHEET.md",
      "guides/language/TUTORIAL.md",
      # `:filename` is required here, not cosmetic: ExDoc's default extras
      # filename is the source basename lowercased ("aletheia"), which is
      # the exact same output path (`aletheia.html`) the top-level
      # `Aletheia` module's own API page gets. On a case-insensitive
      # filesystem (the default on macOS) those collide -- whichever
      # ExDoc writes last silently overwrites the other on disk, so this
      # guide's page either never renders or clobbers the module page
      # depending on generation order, with no warning from ExDoc either
      # way (it has no visibility into the underlying filesystem's
      # case-folding). Same fix logos's own `mix.exs` applies to its
      # analogous `guides/language/LOGOS.md`.
      {"guides/language/ALETHEIA.md", [filename: "aletheia-language-reference"]},
      "guides/language/ALETHEIA_EXAMPLES.md",
      "guides/language/ALETHEIA_CHEATSHEET.md",
      "CASE_STUDY.md",
      "CHANGELOG.md",
      "LICENSE"
    ]
  end

  defp groups_for_extras do
    [
      Guides: Path.wildcard("guides/*.md"),
      Language: Path.wildcard("guides/language/*.md")
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
