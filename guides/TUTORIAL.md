# Tutorial: embedding Aletheia in an Elixir application

This tutorial is about *using Aletheia as a library from Elixir host
code* — building databases, consulting source, running queries,
calling back and forth between Aletheia and Elixir. If you want to
learn the Aletheia language itself (the Prolog dialect: facts, rules,
cut, DCG) instead, see the
[language tutorial](language/TUTORIAL.md) — this one assumes no more
Prolog knowledge than `parent(tom, bob).`.

## 1. Add the dependency

```elixir
# mix.exs
def deps do
  [
    {:aletheia, path: "path/to/aletheia"}
  ]
end
```

Not yet published to Hex — see the [README](../README.md#installation)
for the current path/git dependency form. Then `mix deps.get`.

## 2. Load a program

An `Episteme.Database` (Aletheia's clause store) starts empty;
`Aletheia.consult_string/2` parses source text and adds every fact/rule
it finds to one, returning `{:ok, db}`:

```elixir
{:ok, db} = Aletheia.consult_string("""
parent(tom, bob).
parent(tom, liz).
parent(bob, ann).
parent(bob, pat).
""")
```

`Aletheia.consult/1` does the same from a `.alp` file on disk. Nothing
about a database is a global singleton — each `consult_string/2`/
`consult/1` call you *don't* pass a previous `db` into builds a
completely fresh, independent one, so an application embedding
Aletheia several times over (one database per tenant, say) gets
genuinely isolated worlds:

```elixir
{:ok, db2} = Aletheia.consult_string("parent(x, y).")
Aletheia.query("parent(tom, _)", db2)
#=> {:ok, []}   -- db2 never saw db's own facts
```

Pass a previous `db` as the second argument to keep adding clauses to
the *same* database instead — useful for loading a program across
several files, or letting a running application `assertz` new facts
into a database it already has open (see
[the dynamic database](language/ALETHEIA.md#database)).

## 3. Query it

```elixir
Aletheia.query("parent(tom, X)", db)
#=> {:ok, [%{"X" => :bob}, %{"X" => :liz}]}
```

`Aletheia.query/2` returns *every* solution, eagerly, as a list of
`%{"VarName" => value}` maps — one per way the goal can succeed. The
values are already fully resolved `Episteme.Term`-shaped data (plain
Elixir atoms/numbers/strings/lists, or `%Episteme.Term.Compound{}`/
`%Episteme.Term.Var{}` structs for anything more structured), ready to
pattern-match on in ordinary Elixir code.

If you only want the first solution, `Aletheia.query_once/2` is
cheaper — it stops searching the moment it finds one, returning `{:ok,
solution}` or `:none` instead of a list:

```elixir
Aletheia.query_once("parent(tom, X)", db)
#=> {:ok, %{"X" => :bob}}

Aletheia.query_once("parent(nonexistent, X)", db)
#=> :none
```

## 4. Pulling solutions lazily

`query/2` forces the *entire* search before returning — fine for a
goal with a handful of solutions, but wasteful (or outright non-
terminating) for one with an unbounded number.
`Aletheia.query_lazy/2` + `Aletheia.next_solution/2` pull one solution
at a time instead, computing no more of the search than you actually
ask to see:

```elixir
{:ok, {stream, vars}} = Aletheia.query_lazy("parent(tom, X)", db)

{:solution, solution, rest} = Aletheia.next_solution(stream, vars)
solution
#=> %{"X" => :bob}

{:solution, solution2, _rest2} = Aletheia.next_solution(rest, vars)
solution2
#=> %{"X" => :liz}
```

`next_solution/2` returns `:none` once the search is exhausted (or
`{:error, term}` if evaluating the next solution raises). This is
exactly what `Aletheia.Repl` is built on (§6 below) — a real Prolog
REPL can't force a whole infinite search just to show you the first
answer.

## 5. Errors

An uncaught Prolog exception — a real `throw/1` nothing in the program
caught, or one of the standard errors Aletheia raises automatically
(dividing by zero, calling an undefined predicate, ...) — surfaces as
`{:error, term}` from `query/2`/`query_once/2`/`next_solution/2`,
never as a crash in your Elixir process:

```elixir
Aletheia.query("X is 1 / 0", db)
#=> {:error, %Episteme.Term.Compound{name: :error, args: [
#     %Episteme.Term.Compound{name: :domain_error, args: [:non_zero, 0]},
#     _
#   ]}}

Aletheia.query("nonexistent_predicate(X)", db)
#=> {:error, %Episteme.Term.Compound{name: :error, args: [
#     %Episteme.Term.Compound{name: :existence_error, args: [
#       :procedure, %Episteme.Term.Compound{name: :/, args: [:nonexistent_predicate, 1]}
#     ]}, _
#   ]}}
```

Both follow ISO's own `error(Formal, _)` shape (see
[Exceptions](language/ALETHEIA.md#exceptions)) — pattern-match on
`Formal`'s own functor (`domain_error`, `existence_error`,
`type_error`, or whatever your own program `throw/1`s) to handle
specific cases, or just treat any `{:error, _}` as "this query failed
badly" if you don't need to distinguish why.

## 6. The REPL

`Aletheia.Repl.start/1` takes a list of files to consult, then drops
you into a `?- ` prompt — type a goal, see its bindings, and (matching
real Prolog UX) type `;` to backtrack into the next solution or
anything else to stop:

```sh
$ mix run -e 'Aletheia.Repl.start(["examples/family.alp"])'
?- parent(tom, X)
X = bob
;
X = liz
?-
```

It's built directly on `query_lazy/2` + `next_solution/2` (§4 above) —
pulling one solution at a time is what makes it safe to run a REPL
query with an unbounded (or infinite) number of solutions; it only
ever computes as many as you actually ask to see via `;`.

## 7. A worked example: a scripted rules engine

A realistic reason to embed Aletheia: letting a host application load
small, user-editable rules without recompiling — a discount policy,
here, backed by a handful of facts and clause-order-plus-cut picking
the first rule that applies:

```elixir
rules = """
vip(alice).
orders(bob, 15).
orders(carol, 3).

discount(Customer, 20) :- vip(Customer), !.
discount(Customer, 10) :- orders(Customer, N), N >= 10, !.
discount(_, 0).
"""

{:ok, db} = Aletheia.consult_string(rules)

for customer <- [:alice, :bob, :carol, :dave] do
  {:ok, %{"D" => percent}} = Aletheia.query_once("discount(#{customer}, D)", db)
  {customer, percent}
end
#=> [alice: 20, bob: 10, carol: 0, dave: 0]
```

`alice` matches the first rule (`vip/1`) and stops there via `!` — the
second rule never even runs for her. `bob` has enough orders to match
the second rule; `carol` doesn't (only 3), so she falls through to the
catch-all `discount(_, 0)`, same as `dave`, who isn't mentioned in the
rules at all. Swap `rules` for text read from a file, a database
column, or a config-management system, and the host application never
needs to know the specific policy in advance — only that querying
`discount(Customer, D)` against whatever it loaded answers the
question.

## Where next

- **[Language tutorial](language/TUTORIAL.md)** — the Aletheia
  language itself: facts, rules, cut, arithmetic, exceptions, lists,
  and more, step by step.
- **[Language reference](language/ALETHEIA.md)** — every predicate and
  syntax feature, in full.
- **[Cheatsheet](CHEATSHEET.md)** — quick reference for this same
  embedding API.
- **[Examples](EXAMPLES.md)** — more complete, concrete embedding
  examples.
- **[CASE_STUDY.md](../CASE_STUDY.md)** — a single larger, real-world
  worked example.
