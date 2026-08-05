# Examples: embedding Aletheia

Concrete, complete embedding examples — the Elixir side of using
Aletheia as a library. For examples of the Aletheia *language* itself
(complete `.alp` programs), see
[language/ALETHEIA_EXAMPLES.md](language/ALETHEIA_EXAMPLES.md)
instead.

## Example 1: one-off query against a consulted file

```elixir
{:ok, db} = Aletheia.consult("examples/family.alp")
Aletheia.query_once("grandparent(tom, Who)", db)
#=> {:ok, %{"Who" => :ann}}
```

The common case: load a `.alp` file once, ask it one question, done.
See [language/ALETHEIA_EXAMPLES.md](language/ALETHEIA_EXAMPLES.md) for
what's actually in `examples/family.alp`.

## Example 2: building a database incrementally

`consult_string/2`'s second argument defaults to a fresh database, but
passing a previous one keeps adding clauses to it — useful for loading
a program across several sources (a base ruleset plus a
site-specific override file, say) without gluing the text together
yourself first:

```elixir
{:ok, db} = Aletheia.consult_string("base(1).")
{:ok, db} = Aletheia.consult_string("derived(X) :- base(X).", db)

Aletheia.query("derived(X)", db)
#=> {:ok, [%{"X" => 1}]}
```

`derived/1` resolves against `base/1` even though they were consulted
in two separate calls — both landed in the same `db`.

## Example 3: multiple independent databases (multi-tenant isolation)

Nothing about an `Episteme.Database` is a global singleton — every
`consult_string/2`/`consult/1` call you don't explicitly thread a
previous `db` into builds a completely fresh one, so an application
embedding Aletheia once per tenant (or per request, or per test case)
gets genuinely independent worlds with no shared, mutable global state
to worry about:

```elixir
{:ok, tenant_a} = Aletheia.consult_string("setting(color, blue).")
{:ok, tenant_b} = Aletheia.consult_string("setting(color, red).")

Aletheia.query_once("setting(color, C)", tenant_a)
#=> {:ok, %{"C" => :blue}}

Aletheia.query_once("setting(color, C)", tenant_b)
#=> {:ok, %{"C" => :red}}
```

## Example 4: catching an Aletheia-level error at the host boundary

Every query entry point returns `{:ok, _}` or `{:error, term}` — an
uncaught Prolog exception never raises into your Elixir process, so a
host application only ever needs to handle one error shape:

```elixir
case Aletheia.query("X is 1 / 0", db) do
  {:ok, solutions} ->
    solutions

  {:error, %Episteme.Term.Compound{args: [formal, _]}} ->
    # formal is e.g. %Episteme.Term.Compound{name: :domain_error, args: [:non_zero, 0]}
    {:error, formal}
end
#=> {:error, %Episteme.Term.Compound{name: :domain_error, args: [:non_zero, 0]}}
```

Every automatically-raised error, and anything your own program
`throw/1`s, follows the same `error(Formal, _)` shape (see
[Exceptions](language/ALETHEIA.md#exceptions)) — pattern-match on
`Formal`'s own functor to handle specific cases.

## Example 5: paginating a large (or unbounded) search

`query/2` forces every solution before returning, which is the wrong
tool once a goal has more solutions than you actually want to look at.
`query_lazy/2` + `next_solution/2` compute exactly as many as you ask
for and no more — here, the first 3 solutions of a goal with a million:

```elixir
{:ok, {stream, vars}} = Aletheia.query_lazy("between(1, 1000000, X)", db)

{first_three, _rest} =
  Enum.reduce(1..3, {[], stream}, fn _, {acc, s} ->
    {:solution, sol, rest} = Aletheia.next_solution(s, vars)
    {[sol | acc], rest}
  end)

Enum.reverse(first_three)
#=> [%{"X" => 1}, %{"X" => 2}, %{"X" => 3}]
```

`rest` (discarded above after the third pull) is itself just another
lazy stream — keep threading it through `next_solution/2` to keep
paginating, exactly what `Aletheia.Repl` does one `;` at a time.

## Where next

- **[Tutorial](TUTORIAL.md)** — the step-by-step version of the above.
- **[Cheatsheet](CHEATSHEET.md)** for a condensed lookup of this same
  embedding API.
- **[CASE_STUDY.md](../CASE_STUDY.md)** — a single larger, real-world
  worked example.
- **[language/ALETHEIA_EXAMPLES.md](language/ALETHEIA_EXAMPLES.md)**
  for complete `.alp` programs (the language side, not the embedding
  side).
