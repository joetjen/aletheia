# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
