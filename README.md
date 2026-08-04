# Aletheia

An embedded Prolog dialect for Elixir — Clojure is to Common Lisp as
Aletheia is to Prolog. Classic Prolog syntax (`:-`, `,`/`;`, `=`, the
standard operator table, a runtime-mutable `op/3` operator table) on
top of the BEAM, via a reader built on
[Ichor](https://hex.pm/packages/ichor)'s parsing substrate and
[Episteme](https://hex.pm/packages/episteme), the standalone
resolution engine and clause database (unification, SLD-resolution,
backtracking, a genuine clause-scoped cut) this package is a syntax
front-end for.

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

See the [tutorial](guides/TUTORIAL.md) for a full walkthrough, or the
[cheatsheet](guides/CHEATSHEET.md) if you already know Prolog and just
want the syntax/API at a glance.

## Why

Clojure-to-Common-Lisp is the analogy for *taste*, not *scope*: keep the
host language's actual semantics (existing Prolog knowledge transfers
directly — no bespoke surface syntax), modernize opaque classic names
only via an additive alias that delegates to the same predicate (never
a silent behavioral fork), and grow the standard-predicate surface
need-first rather than chasing full ISO/SWI completeness up front.

## Status

**v0.1 is implemented and tested**: the reader (real Prolog syntax,
`op/3`-driven operator precedence), the term representation, real
unification and backtracking, a genuinely clause-scoped cut (not a
`once/1` stand-in — see [the reference](guides/REFERENCE.md#cut) for
why that distinction is load-bearing), core control constructs,
`is/2` arithmetic, exceptions (`throw/catch` + the standard ISO error
terms), a runtime-mutable `op/3` operator table, the v0.1 list
predicate family, minimal I/O, and a REPL. Everything past that
(dynamic database/`assert`+`retract`, `findall`/`bagof`/`setof`, the
atom/string predicate family, DCGs) is staged, need-first, across
later milestones — see [the reference](guides/REFERENCE.md) for
exactly which predicates exist today.

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
[Episteme](https://hex.pm/packages/episteme) as a regular Hex dependency
(`{:episteme, "~> 0.1"}`) — no sibling checkout needed.

## How it fits together

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
   Episteme.Term IR  ──── Var/Compound structs + native lists,
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
clause database, resolution engine, cut, and builtins — lives in
[Episteme](https://hex.pm/packages/episteme), a separate package with
no dependency on Aletheia's reader or concrete syntax at all. This
package (Aletheia) is the syntax front-end: the reader plus a REPL.

- **`Aletheia.Reader`** — parses source into clause forms
  (`{:fact, _}`/`{:rule, _, _}`/`{:directive, _}`), one top-level clause
  at a time, threading the operator table `op/3` directives mutate from
  each into the next. `Aletheia.Reader.Pratt` is the `@native(...)`
  callback that does the actual precedence-climbing.
- **`Episteme.Term`** — the term representation: atoms/numbers are
  plain Elixir atoms/integers/floats, lists are native Elixir lists
  (decomposing as ISO's own `'.'/2` cons functor so unification can
  recurse into them), variables and compounds get dedicated structs.
- **`Episteme.Database`** — clause storage, indexed by `{name, arity}`.
- **`Episteme.Engine`** — the resolution engine: clause selection,
  subgoal sequencing, and control constructs (`,`/`;`/`->`/`!`/`\+`/
  `call/N`/`once/1`) over `Ichor.Backtrack`, plus a real clause-scoped
  cut (see [the reference](guides/REFERENCE.md#cut)).
- **`Episteme.Builtins.*`** — arithmetic, exceptions, the list
  predicate family, and minimal I/O.
- **`Aletheia.Repl`** — a consult + interactive query loop, pulling
  solutions one at a time (never forcing more of a search than you
  actually ask to see via `;`).

Aletheia depends on [`ichor_runtime`](https://hex.pm/packages/ichor_runtime)
directly (`Ichor.Toolkit.Pratt`, used by the reader itself), on
[`ichor`](https://hex.pm/packages/ichor) only at dev time (`mix
ichor.gen`, ahead-of-time grammar codegen — see
[`lib/aletheia/reader/grammar_generated.ex`](lib/aletheia/reader/grammar_generated.ex),
never ships in a release build), and on
[`episteme`](https://hex.pm/packages/episteme) for everything past
parsing (which in turn depends on `ichor_runtime` for
`Ichor.Backtrack`/`Ichor.Toolkit.TermWalk`).

## Where to go next

- **[Tutorial](guides/TUTORIAL.md)** — a step-by-step walkthrough:
  install, consult a program, query it, backtracking, cut, arithmetic,
  exceptions, lists, and the REPL.
- **[Reference](guides/REFERENCE.md)** — every implemented predicate,
  with its signature, semantics, and an example.
- **[Cheatsheet](guides/CHEATSHEET.md)** — quick syntax and API lookup
  for when you already know Prolog.
- **[Examples](guides/EXAMPLES.md)** — worked, runnable programs (a
  family tree, list processing, cut-based control flow, exception
  handling), with runnable source under `examples/`.

## Development

```sh
mix deps.get
mix test
mix format --check-formatted
mix compile --warnings-as-errors
mix gen.grammar  # regenerate grammar_generated.ex after editing grammar.aether
mix docs
```

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

MIT — see [LICENSE](LICENSE).
