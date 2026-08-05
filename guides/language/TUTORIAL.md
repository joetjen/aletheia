# Tutorial: the Aletheia language

This tutorial introduces the Aletheia *language* itself — the Prolog
dialect — independent of how it's embedded in a host application.
Every example here can be pasted straight into `iex -S mix` from a
checkout of this repository (assuming a database `db`, built the way
each section shows), or into the REPL (`mix run -e
'Aletheia.Repl.start([])'`). If you want to learn *embedding* Aletheia
into an Elixir application instead — adding the dependency, building a
database, running the REPL — see the
[library tutorial](../TUTORIAL.md) for that side. For a systematic,
lookup-style reference once you know your way around, see
[ALETHEIA.md](ALETHEIA.md).

## 1. Your first program

Aletheia programs are made of **facts** and **rules**, exactly like any
other Prolog. Load some source with `consult_string/2` (or `consult/1`
for a file), then ask questions of it with `query/2`:

```elixir
{:ok, db} = Aletheia.consult_string("""
parent(tom, bob).
parent(tom, liz).
parent(bob, ann).
parent(bob, pat).
""")

Aletheia.query("parent(tom, X)", db)
#=> {:ok, [%{"X" => :bob}, %{"X" => :liz}]}
```

`query/2` returns *every* solution, as a list of `%{"VarName" =>
value}` maps — one map per way the goal can succeed, in the order
Aletheia found them (declaration order, depth-first). Variables you
don't care about can stay anonymous with `_`:

```elixir
Aletheia.query("parent(tom, _)", db)
#=> {:ok, [%{}, %{}]}  -- two solutions, no variables bound in either
```

If you only want the first solution, use `query_once/2`:

```elixir
Aletheia.query_once("parent(tom, X)", db)
#=> {:ok, %{"X" => :bob}}
```

## 2. Rules and recursion

A rule's head and body share whatever variables they mention; the
comma is real Prolog conjunction (a genuine `xfy(1000)` operator here,
not just grammar-level punctuation — see the
[reference](ALETHEIA.md#syntax) if you're curious why that matters):

```elixir
{:ok, db} = Aletheia.consult_string("""
parent(tom, bob).
parent(tom, liz).
parent(bob, ann).
parent(bob, pat).
parent(pat, jim).

grandparent(X, Z) :- parent(X, Y), parent(Y, Z).
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).
""")

Aletheia.query("grandparent(tom, Who)", db)
#=> {:ok, [%{"Who" => :ann}, %{"Who" => :pat}]}

Aletheia.query("ancestor(tom, Who)", db)
#=> {:ok, [%{"Who" => :bob}, %{"Who" => :liz}, %{"Who" => :ann},
#          %{"Who" => :pat}, %{"Who" => :jim}]}
```

`ancestor/2` recurses through `parent/2` exactly the way you'd expect
from any Prolog system — Aletheia's engine is a real SLD-resolution
loop over a lazy search tree, not a special-cased evaluator.

## 3. Arithmetic

`is/2` evaluates the right-hand side as an arithmetic expression and
unifies the result with the left-hand side, with the standard operator
precedence (`*`/`/` bind tighter than `+`/`-`, unary minus tighter
still):

```elixir
Aletheia.query("X is 2 + 3 * 4", Episteme.Database.new())
#=> {:ok, [%{"X" => 14}]}

Aletheia.query("X is 7 // 2", Episteme.Database.new())
#=> {:ok, [%{"X" => 3}]}
```

The six arithmetic comparisons (`=:=`, `=\=`, `<`, `>`, `=<`, `>=`)
evaluate both sides the same way `is/2` does:

```elixir
{:ok, db} = Aletheia.consult_string("""
classify(X, positive) :- X > 0.
classify(0, zero).
classify(X, negative) :- X < 0.
""")

Aletheia.query("classify(5, What)", db)
#=> {:ok, [%{"What" => :positive}]}
```

## 4. Control: disjunction and if-then-else

`;` is disjunction, `->` is if-then; together, `(Cond -> Then ; Else)`
is if-then-else, committing to the *first* solution of `Cond`:

```elixir
{:ok, db} = Aletheia.consult_string("""
sign(X, R) :- (X > 0 -> R = positive ; X < 0 -> R = negative ; R = zero).
""")

Aletheia.query("sign(5, R)", db)
#=> {:ok, [%{"R" => :positive}]}
Aletheia.query("sign(0, R)", db)
#=> {:ok, [%{"R" => :zero}]}
```

## 5. Cut

`!` commits to every choice made since entering the *current clause* —
no more alternatives for that clause's own remaining goals, and no
more sibling clauses for that predicate. This is stricter than "stop
after the first solution" (that's `once/1`); the difference shows up
the moment a cut is followed by something that fails:

```elixir
{:ok, db} = Aletheia.consult_string("""
p(1) :- !, fail.
p(2).
""")

Aletheia.query("p(X)", db)
#=> {:ok, []}
```

`p(X)` fails outright: cut commits to clause 1 *before* `fail` ever
runs, so clause 2 is never tried — a `once/1`-based cut would instead
still fall through to `p(2)`. See
[`ALETHEIA.md#cut`](ALETHEIA.md#cut) for the full set of cut-scoping
rules (and why cut inside a called predicate never affects its
caller).

## 6. Negation as failure

`\+ Goal` succeeds exactly when `Goal` has no solution, binding
nothing either way:

```elixir
{:ok, db} = Aletheia.consult_string("""
even(X) :- 0 is X mod 2.
odd(X) :- \\+ even(X).
""")

Aletheia.query("odd(3)", db)
#=> {:ok, [%{}]}
Aletheia.query("odd(4)", db)
#=> {:ok, []}
```

## 7. Exceptions

`throw/1` raises a term; `catch(Goal, Catcher, Recovery)` runs `Goal`,
and if it throws something that unifies with `Catcher`, runs `Recovery`
instead of propagating the exception further:

```elixir
{:ok, db} = Aletheia.consult_string("""
safe_div(X, Y, R) :- catch(R is X / Y, error(_, _), R = undefined).
""")

Aletheia.query("safe_div(10, 2, R)", db)
#=> {:ok, [%{"R" => 5}]}
Aletheia.query("safe_div(10, 0, R)", db)
#=> {:ok, [%{"R" => :undefined}]}
```

An exception nothing in your program catches surfaces as `{:error,
term}` from `Aletheia.query/2` itself, rather than crashing your
Elixir process.

## 8. Lists

Lists use native `[H|T]` syntax throughout, backed by real Elixir lists:

```elixir
Aletheia.query("append([1, 2], [3, 4], X)", Episteme.Database.new())
#=> {:ok, [%{"X" => [1, 2, 3, 4]}]}

Aletheia.query("member(X, [a, b, c])", Episteme.Database.new())
#=> {:ok, [%{"X" => :a}, %{"X" => :b}, %{"X" => :c}]}
```

See [`ALETHEIA.md#lists`](ALETHEIA.md#lists) for the full v0.1 list
predicate family.

## Where next

- **[Reference](ALETHEIA.md)** — every implemented predicate, in
  full, with signatures and semantics.
- **[Cheatsheet](ALETHEIA_CHEATSHEET.md)** — the same ground, condensed
  to a lookup table.
- **[Examples](ALETHEIA_EXAMPLES.md)** — complete worked programs,
  runnable from `examples/`.
- **[../TUTORIAL.md](../TUTORIAL.md)** — embedding Aletheia into an
  Elixir application: adding the dependency, building a database,
  running the REPL.
