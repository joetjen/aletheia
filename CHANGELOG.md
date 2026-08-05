# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Documentation overhaul, matching the depth of sibling projects
  (logos, episteme)**: README.md rewritten with a "Why embed a Prolog
  dialect in Elixir?" section, a `## Components` breakdown of the
  reader/term-IR/database/engine/builtins/REPL pipeline, CI/Docs/
  License badges, and a full `## Documentation` index. New
  **CASE_STUDY.md**: a single larger, real-world worked example (a
  structured-log auditor combining a DCG grammar, real strings, the
  dynamic database, and grouped aggregation), written as one complete
  `.alp` program rather than Elixir term-building — the same problem
  [Episteme's own `CASE_STUDY.md`](https://hex.pm/packages/episteme)
  solves the other way, worth comparing side by side. Wired into
  `mix.exs`'s `extras`/`package.files`.
- **The reader now reaches everything episteme's v0.2-v0.5 work
  shipped**, closing out the entire numbered roadmap end to end through
  `.alp` source:
  - **Double-quoted string literals** (`"hello"`) — a real Elixir
    binary, matching `DESIGN.md`'s `string_type_decision`, no escape
    processing (same simplification quoted atoms already have).
  - **`{Goal}`** (ISO's own `{}`/1 term shape) — ordinary syntax
    anywhere a term can appear.
  - **DCG rules** (`Head --> Body.`) — a dedicated clause form (not
    parsed through the operator table), producing a `{:dcg, head,
    body}` form `Episteme.Database.consult_forms/2` translates and
    stores; `phrase/2,3` and `dcg_translate/2` were already
    plain-atom-functor goals needing no reader changes.
  - **Standard order of terms operators** (`@<`, `@>`, `@=<`, `@>=`) —
    added to the default operator table (priority 700, same class as
    `=`/`==`) and to `Aletheia.Reader.ControlSyntax`'s translation
    table (`order_less`/`order_greater`/`order_less_or_equal`/
    `order_greater_or_equal`).
  - Every other v0.2-v0.5 addition (`ignore/1`,
    `unify_with_occurs_check/2`, `bagof/3`/`setof/3`, term inspection,
    the dynamic-database round-out, the list-predicate family, the
    atom/string conversion family, `format/1,2`) was already reachable
    with zero reader changes — plain atom-functor goals flow through
    untouched, the same way `between/3` and friends did in
    `episteme_ahead_of_schedule`.
  - **Known, deliberate gap**: `=../2` (`univ/2` works, but its ISO
    punctuation can't be tokenized by this reader's simplified lexer —
    a lone `.` inside a longer operator token is indistinguishable from
    end-of-clause).
  - `mix.exs`'s `episteme` dependency switched to a **path** dependency
    (`{:episteme, path: "../episteme"}`), interim until episteme's own
    v0.2-v0.5 work is released to Hex — see `DESIGN.md`'s
    `aletheia_episteme_path_dependency_interim`.
  - Fixed a pre-existing gap found along the way: `mix precommit`'s
    `sobelow` step ran without `--skip`, silently ignoring every
    `#sobelow_skip` comment in the codebase (episteme's own equivalent
    alias already had this right). Now `"sobelow --skip"`, matching
    episteme; used it to justify the reader's own atom-creation risk
    (routed through one `to_prolog_atom/1` instead of five separate
    call sites) the same way episteme's `Episteme.Builtins.Strings`
    already does.
  - `guides/REFERENCE.md`/`CHEATSHEET.md`/`README.md` updated
    throughout; see `test/aletheia/reader_test.exs`,
    `test/aletheia/reader/control_syntax_test.exs`, and
    `test/aletheia/end_to_end_test.exs` for the new coverage.
- **Docs are now cross-referenced from the project config**: `mix.exs`
  sets `homepage_url`/`canonical` (docs) and a `"Docs"` package link
  pointing at the GitHub Pages site
  (`https://joetjen.github.io/aletheia/`), and the README/`DESIGN.md`
  reference it too. The site itself is built by
  `.github/workflows/docs.yml` on every push to `main`; it won't
  actually be live until aletheia's first release reaches `main`.
- **A handful of v0.2/v0.3 predicates already work, ahead of schedule**:
  `assert/1`, `asserta/1`, `assertz/1`, `retract/1`, `retractall/1`
  (dynamic database), `findall/3` (aggregation), `forall/2`, and
  `between/3` (not even ISO, a de facto library predicate) — all
  shipped as part of `episteme` 0.1.0's own initial extraction and
  confirmed working end-to-end through `.alp` source and
  `Aletheia`'s top-level API with zero Aletheia-side code changes
  (none involve ISO punctuation, so `Aletheia.Reader.ControlSyntax`
  never needed to touch them). Previously undocumented and untested at
  this level; now covered in
  [`guides/REFERENCE.md`](guides/REFERENCE.md#database) and
  `test/aletheia/end_to_end_test.exs`. See `DESIGN.md`'s
  `episteme_ahead_of_schedule` decisions_log entry.
- **v0.1 milestone, complete**: reader, term representation,
  unification, SLD-resolution, a genuinely clause-scoped cut, core
  control constructs, `is/2` arithmetic, exceptions, a runtime-mutable
  `op/3` operator table, the v0.1 list predicate family, minimal I/O,
  and consult/REPL. See [`guides/REFERENCE.md`](guides/REFERENCE.md)
  for the full predicate list.
- **Reader**: a real Aether grammar
  (`lib/aletheia/reader/grammar.aether`) with `Ichor.Toolkit.Pratt`
  wired in via `@native(...)` for operator-precedence parsing — comma
  is a genuine `xfy(1000)` operator (unlike Ichor's own
  `test/prolog/prolog.aether` fixture, which leaves it
  grammar-structural), needing a second `@native` entry point
  (`arg_term`) parsed at a raised minimum precedence for ISO's own
  "argument priority =< 999" rule. `:- op(Prec, Type, Name).`
  directives genuinely extend the operator table mid-file.
- **Cut**: implemented as a distinct clause-scoped primitive via
  `throw`/`catch` barriers, *not* a thin wrapper over `Ichor.Backtrack.Tree`'s
  `once/1` (which only limits solution count, not
  clause commitment) — see
  [`guides/REFERENCE.md#cut`](guides/REFERENCE.md#cut) for the
  distinguishing test cases. Every predicate call (and `call/N`,
  `once/1`, `\+/1`, each cut-opaque per ISO) mints its own barrier.
- **Ahead-of-time grammar generation**: the grammar is compiled via
  `mix ichor.gen` (aliased `mix gen.grammar`) into a checked-in
  `lib/aletheia/reader/grammar_generated.ex`, rather than parsed at
  runtime — `ichor` (the Aether front-end, `Grammar.Analysis`, both
  codegen backends) is a dev-only dependency (`only: :dev, runtime:
  false`) and never ships in a release; `ichor_runtime` is the one real
  runtime dependency.
- **Top-level API**: `Aletheia.consult/1`, `consult_string/2`,
  `query/2`, `query_once/2`, and a genuinely lazy `query_lazy/2` +
  `next_solution/2` pair (pulls one solution at a time instead of
  forcing an entire, possibly-infinite search) — the REPL is built on
  the lazy pair specifically so it never over-computes past what a
  user actually asks to see via `;`.

### Changed

- **Split into two packages**: `Aletheia.Term`, `Aletheia.Database`,
  `Aletheia.Engine`, and `Aletheia.Builtins.*` moved out of this
  repository into a new sibling package,
  [`episteme`](https://hex.pm/packages/episteme)
  (`Episteme.Term`/`Database`/`Engine`/`Builtins.*`, plus a top-level
  `Episteme` module for querying an already-built term against an
  already-built database, with no parser involved). This package
  (`aletheia`) is now the syntax front-end only: the reader and REPL,
  depending on `episteme` for everything past parsing. The top-level
  `Aletheia.consult/1`, `consult_string/2`, `query/2`, `query_once/2`,
  `query_lazy/2`, and `next_solution/2` API is unchanged for existing
  callers; code that referenced `Aletheia.Term`/`Database`/`Engine`/
  `Builtins.*` directly needs to reference `Episteme.*` instead. See
  `DESIGN.md` §3.1 ("The `aletheia`/`episteme` split") for the
  rationale.
- **`episteme` published to Hex**: the dependency on
  [`episteme`](https://hex.pm/packages/episteme) is now a plain Hex
  version requirement (`{:episteme, "~> 0.1"}`) instead of a path
  dependency onto a sibling checkout — no local `episteme` checkout is
  needed to build `aletheia` anymore. Pulled in `ichor_runtime ~> 0.2`
  and `ichor ~> 0.3` transitively, both bumped here too.
- **New `Aletheia.Reader.ControlSyntax` module**: `episteme` 0.1.0
  renamed the control constructs and comparison operators it dispatches
  on from ISO Prolog punctuation to plain-English names (`,` → `and/2`,
  `;` → `or/2`, `!` → `cut`, `\+` → `not/1`, `=` → `unify/2`, and so on
  — see `episteme`'s own `CHANGELOG.md`). `Aletheia.Reader` itself still
  parses and produces the classic punctuation-named terms (unchanged,
  and still the correct reading of `.alp` source); `Aletheia`'s
  top-level API now translates rule bodies and query goals through
  `Aletheia.Reader.ControlSyntax.to_goal/1` before handing them to
  `Episteme`, including rewriting the ISO `(Cond -> Then ; Else)`
  nested pattern to the explicit `if_then_else/3` `episteme` now
  requires. No change to `.alp` source syntax or to any public
  `Aletheia` function signature.

### Fixed

- Found (and fixed upstream, in `ichor`/`ichor_runtime`) a real gap in
  the `ichor`/`ichor_runtime` package split: `ichor_runtime`, as
  originally split, did not include `Ichor.Toolkit.Pratt`,
  `Ichor.Toolkit.TermWalk`, or `Ichor.Backtrack` (+`.Bindings`/`.Term`/
  `.Tree`) — all three are called directly by Aletheia's own runtime
  code (the `@native` Pratt callback, the term/engine/builtin layers),
  not just by generated parser code. Released as part of
  `ichor_runtime` 0.1.0 / `ichor` 0.2.0.

[Unreleased]: https://github.com/joetjen/aletheia
