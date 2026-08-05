# Aletheia

[![CI](https://github.com/joetjen/aletheia/actions/workflows/ci.yml/badge.svg)](https://github.com/joetjen/aletheia/actions/workflows/ci.yml)
[![Docs](https://github.com/joetjen/aletheia/actions/workflows/docs.yml/badge.svg)](https://joetjen.github.io/aletheia/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**New to Prolog or logic programming?** This README assumes some
familiarity with the vocabulary (facts, rules, unification,
backtracking, cut...) since it's written for evaluating Aletheia as a
dependency. [guides/language/TUTORIAL.md](guides/language/TUTORIAL.md)
explains every one of those terms from scratch, with plain-English
walkthroughs and no assumed background at all — start there instead if
any of the paragraph below is unfamiliar.

Aletheia is an embedded Prolog dialect for Elixir — Clojure is to
Common Lisp as Aletheia is to Prolog. Classic Prolog surface syntax
(`:-`, `,`/`;`/`->`, `=`, double-quoted strings, DCG's `-->`, a
runtime-mutable `op/3` operator table — existing Prolog knowledge
transfers directly, no bespoke syntax to learn) on top of the BEAM, via
a reader built on [Ichor](https://hex.pm/packages/ichor)'s parsing
substrate and [Episteme](https://hex.pm/packages/episteme), the
standalone resolution engine and clause database (unification,
SLD-resolution, backtracking, a genuine clause-scoped cut) this package
is a syntax front-end for.

In plain English: this program stores four **facts** about who's a
parent of whom, then a **rule** — `grandparent(X, Z)` holds whenever
some `Y` exists with `X` a parent of `Y` *and* `Y` a parent of `Z`.
Asking `grandparent(tom, Who)` doesn't specify `Who` at all; Aletheia
**backtracks** through every value that makes the rule true and hands
back all of them, not just the first.

```elixir
{:ok, db} = Aletheia.consult_string("""
parent(tom, bob).
parent(tom, liz).
parent(bob, ann).
parent(bob, pat).

grandparent(X, Z) :- parent(X, Y), parent(Y, Z).
""")

Aletheia.query("grandparent(tom, Who)", db)
#=> {:ok, [%{"Who" => :ann}, %{"Who" => :pat}]}
```

See [guides/language/TUTORIAL.md](guides/language/TUTORIAL.md) for a
full walkthrough of the language, or
[guides/language/ALETHEIA_CHEATSHEET.md](guides/language/ALETHEIA_CHEATSHEET.md)
if you already know Prolog and just want the syntax at a glance. For
*embedding* Aletheia into an Elixir application specifically, see
[guides/TUTORIAL.md](guides/TUTORIAL.md) instead.

## Why embed a Prolog dialect in Elixir?

Some problems are naturally *relational* and *searchy* — "given these
facts and rules, find every X that satisfies these constraints,
backtracking through alternatives automatically" — a rules engine, an
expert-system-style diagnosis/eligibility check, a permissions/access-
control policy expressed as facts instead of nested conditionals, a
small parser or configuration DSL (Aletheia ships real
[DCG support](guides/language/ALETHEIA.md#dcg) for exactly that), or a
relational query over in-memory facts that would otherwise be a tangle
of nested `Enum.filter`/`Enum.flat_map` calls hand-rolling what
unification and backtracking already do for free. Prolog's own
strength — a real, load-bearing distinction between *facts* (what's
true), *rules* (what follows from what), and *goals* (what you're
asking), searched exhaustively via backtracking rather than evaluated
top-to-bottom like ordinary code — is exactly the shape those problems
already have; forcing them into imperative control flow is usually the
harder path, not the easier one.

Aletheia specifically (rather than reaching for
[Episteme](https://hex.pm/packages/episteme) directly) is for when you
want that as real, classic Prolog syntax you can write, read, and
consult from `.alp` source files — existing Prolog books/tutorials/
muscle memory transfer directly, and `op/3` lets you extend the grammar
itself at read time, the same way real Prolog does.

## Components

```text
   Aletheia source (.alp)
         │
         ▼
  Aletheia.Reader  ──── lib/aletheia/reader/grammar.aether (an Aether
         │               grammar), generated ahead of time via
         │               `mix ichor.gen` into grammar_generated.ex,
         │               with Ichor.Toolkit.Pratt wired in via @native
         │               for op/3-driven operator-precedence parsing
         ▼
   Episteme.Term IR  ──── Var/Compound structs + native lists/strings,
         │                implementing Ichor.Backtrack.Term
         ▼
  Episteme.Database  ──── clause storage, populated by consult
         │
         ▼
   Episteme.Engine  ──── SLD-resolution over Ichor.Backtrack.Tree/
         │                Bindings, plus Episteme's own cut-barrier
         │                mechanism and builtin predicate dispatch
         ▼
      solutions
```

Everything below `Aletheia.Reader` in that diagram — the term IR,
clause database, resolution engine, cut, and builtin predicates —
lives in [Episteme](https://hex.pm/packages/episteme), a separate
package with no dependency on Aletheia's reader or concrete syntax at
all. This package (Aletheia) is the syntax front-end: the reader plus
a REPL.

- **Reader** (`Aletheia.Reader`, `Aletheia.Reader.Actions`,
  `Aletheia.Reader.Pratt`) — parses source into clause forms
  (`{:fact, _}`/`{:rule, _, _}`/`{:dcg, _, _}`/`{:directive, _}`), one
  top-level clause at a time, threading the operator table `op/3`
  directives mutate from each into the next. `Aletheia.Reader.Pratt` is
  the `@native(...)` callback doing the actual precedence-climbing;
  `Aletheia.Reader.ControlSyntax` bridges the reader's own
  ISO-punctuation term shapes (`,`/2, `;`/2, `=`/2, ...) to the
  plain-English names `Episteme.Engine` dispatches on.
- **Term IR** (`Episteme.Term`) — atoms/numbers/strings are plain
  Elixir atoms/integers-floats/binaries, lists are native Elixir lists
  (decomposing as ISO's own `.`/2 cons functor so unification can
  recurse into them), variables and compounds get dedicated structs.
- **Database** (`Episteme.Database`) — clause storage, indexed by
  `{name, arity}`, pluggable backend (in-memory ETS by default, DETS
  for on-disk persistence).
- **Engine** (`Episteme.Engine`) — the resolution engine: clause
  selection, subgoal sequencing, control constructs (`and`/`or`/
  `if_then`/`cut`/`not`/`call/N`/`once`/`ignore`/`phrase`) over
  `Ichor.Backtrack`, plus a real clause-scoped cut (see
  [the reference](guides/language/ALETHEIA.md#cut)) and `Episteme.Dcg`
  (DCG rule/body translation).
- **Builtins** (`Episteme.Builtins.*`) — arithmetic, exceptions, the
  full list-predicate family (including higher-order `include`/
  `exclude`/`foldl`/`maplist`), aggregation (`findall`/`bagof`/
  `setof`), the dynamic database (`assert`/`retract`/`dynamic`/
  `abolish`/`clause`), the atom/number/string conversion family, and
  I/O (`write`/`format`/...).
- **REPL** (`Aletheia.Repl`) — a consult + interactive query loop,
  genuinely lazy (pulls one solution at a time via `query_lazy/2` +
  `next_solution/2`, never forcing more of a search than you actually
  ask to see via `;`).

Aletheia depends on [`ichor_runtime`](https://hex.pm/packages/ichor_runtime)
directly (`Ichor.Toolkit.Pratt`, used by the reader itself), on
[`ichor`](https://hex.pm/packages/ichor) only at dev time (`mix
ichor.gen`, ahead-of-time grammar codegen — see
[`lib/aletheia/reader/grammar_generated.ex`](lib/aletheia/reader/grammar_generated.ex),
never ships in a release build), and on
[`episteme`](https://hex.pm/packages/episteme) for everything past
parsing (which in turn depends on `ichor_runtime` for
`Ichor.Backtrack`/`Ichor.Toolkit.TermWalk`).

## Installation

Not yet published to Hex. For now, add it as a path or git dependency
alongside a checkout of this repository:

```elixir
def deps do
  [
    {:aletheia, path: "../aletheia"}
  ]
end
```

Aletheia's own `mix.exs` depends on
[Episteme](https://hex.pm/packages/episteme) as a regular Hex
dependency (`{:episteme, "~> 0.2"}`) — no sibling checkout needed.

## Documentation

- **[Generated API docs](https://joetjen.github.io/aletheia/)** —
  module and function reference, rebuilt from `main` on every push.
- **[guides/TUTORIAL.md](guides/TUTORIAL.md)** — embedding Aletheia
  into an Elixir application, step by step: adding the dependency,
  consulting a program, querying it (eagerly, once, or lazily), errors
  at the host boundary, the REPL, and a worked example. Start here if
  you're new to Aletheia and already know Prolog.
- **[guides/EXAMPLES.md](guides/EXAMPLES.md)** — concrete, complete
  embedding examples (incremental consulting, multi-tenant database
  isolation, error handling, paginating a large search).
- **[CASE_STUDY.md](CASE_STUDY.md)** — a single larger, real-world
  worked example: a structured-log auditor combining a DCG grammar,
  the dynamic database, and grouped aggregation, written as one real
  `.alp` program, with the intent, solution, and result spelled out end
  to end.
- **[guides/CHEATSHEET.md](guides/CHEATSHEET.md)** — quick reference
  for that same embedding API.
- **[CHANGELOG.md](CHANGELOG.md)** — release history.
- **[LICENSE](LICENSE)** — MIT.

- **[Language tutorial](guides/language/TUTORIAL.md)** and
  **[Language reference](guides/language/ALETHEIA.md)** — everything
  about the Aletheia language itself (the Prolog dialect), independent
  of how it's embedded. Start here if you're new to Prolog.
- **[Language examples](guides/language/ALETHEIA_EXAMPLES.md)** and
  **[Language cheatsheet](guides/language/ALETHEIA_CHEATSHEET.md)**.

## Development

```sh
mix deps.get
mix precommit
```

`mix precommit` runs the whole gate in one shot — `format`, `compile
--warnings-as-errors`, `credo --strict`, `sobelow --skip`, `test`,
`dialyzer` — the same checks CI runs, in fast-to-slow order. After
editing `lib/aletheia/reader/grammar.aether`, regenerate the checked-in
parser with `MIX_ENV=dev mix gen.grammar` before running the suite
again.

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

MIT — see [LICENSE](LICENSE).
