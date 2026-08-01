# Reference

Every predicate implemented in Aletheia's current milestone (v0.1),
with its signature, semantics, and enough of an example to use it
correctly. What's coming in v0.2+ (a dynamic database with `assert`/
`retract`, `findall`/`bagof`/`setof`, the atom/string predicate family,
DCGs) is staged, need-first, not chased ahead of actual need.

## Syntax

Classic Prolog surface syntax, read by `Aletheia.Reader`:

- **Atoms**: lowercase-start identifiers (`foo`, `parent42`) or
  single-quoted for anything else (`'John Doe'`, `';'`).
- **Variables**: uppercase- or `_`-start identifiers (`X`, `_Acc`). A
  bare `_` is anonymous — every occurrence is a distinct fresh
  variable, even within the same clause.
- **Numbers**: integers (`42`) and floats (`3.14`) — an integer never
  unifies or compares equal (`==/2`) with a float holding the same
  value, matching ISO.
- **Lists**: `[]` (empty), `[1, 2, 3]` (proper), `[H|T]` (cons, `T` can
  be a variable or another list) — backed by native Elixir lists,
  decomposing as ISO's own `'.'/2` cons functor so unification recurses
  into them correctly.
- **Compounds**: `functor(Arg1, Arg2, ...)`, plus operator syntax as
  sugar for the same thing — `1 + 2` *is* `+(1, 2)`.
- **Comments**: `%` to end of line, `/* ... */` block comments.
- **Clauses**: `Head.` (a fact), `Head :- Body.` (a rule), `:- Goal.` (a
  directive — currently only `op/3` has any effect as one). Every
  clause ends with a bare `.`.

**Comma is a real operator** here (`xfy`, ISO priority 1000) — unlike a
few textbook-simplified Prolog-in-X implementations that treat it as
pure grammar structure, `p :- a, (b ; c).` composes exactly like real
Prolog. The trade-off: inside a compound's arguments or a list's
elements, only operators of priority ≤ 999 are accepted (ISO's own
rule) — so a bare `,`/`;`/`->` there needs parentheses, exactly as in
any other conforming Prolog.

**Default operator table** (ISO priorities; bigger number binds
looser):

| Priority | Type | Operators |
| --- | --- | --- |
| 1100 | `xfy` | `;` |
| 1050 | `xfy` | `->` |
| 1000 | `xfy` | `,` |
| 900 | `fy` | `\+` |
| 700 | `xfx` | `=` `\=` `==` `\==` `is` `=:=` `=\=` `<` `>` `=<` `>=` |
| 500 | `yfx` | `+` `-` |
| 400 | `yfx` | `*` `/` `//` `mod` `rem` |
| 200 | `xfy` | `^` |
| 200 | `yfx` | `**` |
| 200 | `fy` | `-` `+` (prefix) |

Extend it at read time with `op/3` (see [Operators](#operators) below).

Three documented simplifications: no genuine `xfx` (non-associative)
vs. `yfx` (left-associative) distinction yet, inherited from the
underlying parsing substrate ([Ichor](https://hex.pm/packages/ichor))
— an `a is b is c`-style chain parses left-associatively instead of
being rejected the way ISO would reject it outright; no double-quoted
string literals yet (the underlying representation — code list vs. a
real string type — is an open decision, deferred to a later milestone);
and an operator symbol can't yet be used as an explicit compound
functor the way ISO allows (`=(X, Y)` as another way to write `X = Y`)
— a compound's functor position only accepts a plain or quoted atom
today, not a bare operator token.

## Control

| Predicate | Description |
| --- | --- |
| `true/0` | Always succeeds once. |
| `fail/0`, `false/0` | Always fails. |
| `,/2` | Conjunction — both goals must succeed. |
| `;/2` | Disjunction — either goal succeeding succeeds; backtracks into both in order. |
| `->/2` | If-then: commits to the first solution of the left goal, then runs the right; fails outright if the left goal has no solution (no implicit else). |
| `!/0` | Cut — see [Cut](#cut) below. |
| `\+/1` | Negation as failure — succeeds iff the argument goal has no solution; never binds anything. |
| `call/1..8` | Calls a goal built from a (possibly partially-applied) term, plus any extra arguments appended to it. Opaque to cut — a `!` inside `call/1` never escapes to the caller. |
| `once/1` | The first solution of a goal, discarding the rest — *not* the same as cut (see [Cut](#cut)). Also cut-opaque. |

```prolog
% if-then-else
sign(X, R) :- (X > 0 -> R = pos ; X < 0 -> R = neg ; R = zero).

% call/N: call(Goal, Extra1, ..., ExtraN) appends Extra1..ExtraN to Goal's own args
add(X, Y, Z) :- Z is X + Y.
add_five(Y, Z) :- call(add(5), Y, Z).   % call(add(5), Y, Z) runs add(5, Y, Z)
```

## Cut

`!` commits to every choice made **since entering the current clause**
— pruning both (a) any remaining alternatives for goals earlier in the
same clause body, and (b) any remaining sibling clauses of the same
predicate call. This is a real, clause-scoped commitment, genuinely
different from "stop after the first solution of whatever goal contains
it" (that's `once/1`) — the difference is observable the moment a cut
is followed by something that fails:

```prolog
p(1) :- !, fail.
p(2).
```

```elixir
Aletheia.query("p(X)", db)
#=> {:ok, []}
```

`p(X)` fails outright — cut commits to clause 1 *before* `fail` runs, so
clause 2 is never tried. Swap `!` for a hypothetical "run once" and
`p(2)` would still fire; real cut never lets that happen.

Cut is transparent within the clause it appears in — including inside
a disjunction:

```prolog
r(X) :- (X = 1, ! ; X = 2).
r(3).
```

```elixir
Aletheia.query("r(X)", db)
#=> {:ok, [%{"X" => 1}]}
```

— but goals *after* the cut in the same clause still backtrack among
themselves normally:

```prolog
p(X) :- !, member(X, [1, 2, 3]).
p(_) :- true.
```

```elixir
Aletheia.query("p(X)", db)
#=> {:ok, [%{"X" => 1}, %{"X" => 2}, %{"X" => 3}]}
```

— all three solutions of `member/2` come through (cut doesn't limit
*that*), but once they're exhausted, the second clause `p(_) :- true.`
is never tried (cut already committed to the first).

Cut is **opaque** inside `call/1..N`, `once/1`, and `\+/1` (per ISO): a
`!` inside any of those only commits within that sub-call, never
escaping to prune the caller's own choice points.

## Unification & comparison

| Predicate | Description |
| --- | --- |
| `=/2` | Unifies both sides, binding variables as needed. |
| `\=/2` | Succeeds iff the two sides do *not* unify; never binds anything (an unbound variable unifies with anything, so `X \= 1` fails while `X` is still free). |
| `==/2` | Structural equality — same shape, same variable *identity*, and (unlike Elixir's own `==`) an integer never equals a float. |
| `\==/2` | Negation of `==/2`. |

```elixir
Aletheia.query("X = foo(1, 2)", db)
#=> {:ok, [%{"X" => %Episteme.Term.Compound{name: :foo, args: [1, 2]}}]}

Aletheia.query("1 == 1.0", db)   #=> {:ok, []}          -- different types
Aletheia.query("X = 2, X \\= 1", db)  #=> {:ok, [%{"X" => 2}]}
```

## Type checking

Each of these inspects its (fully-resolved) argument's shape and
succeeds or fails accordingly — none of them bind anything.

| Predicate | Succeeds when the argument is... |
| --- | --- |
| `var/1` | an unbound variable |
| `nonvar/1` | anything *but* an unbound variable |
| `atom/1` | a plain atom |
| `atomic/1` | an atom, number — anything with no internal structure |
| `number/1` | an integer or a float |
| `integer/1` | an integer |
| `float/1` | a float |
| `compound/1` | a compound term or a non-empty list |
| `callable/1` | an atom or a compound term (i.e. something `call/1` could run) |
| `is_list/1` | a *proper* list (every tail eventually reaches `[]`) |

## Term inspection

| Predicate | Description |
| --- | --- |
| `copy_term/2` | Copies term 1 into term 2, renaming every distinct unbound variable apart (consistently — two occurrences of the same variable stay shared in the copy) while resolving anything already bound. |

```elixir
Aletheia.query("copy_term(f(X, X), Y)", db)
#=> {:ok, [%{"Y" => %Episteme.Term.Compound{name: :f, args: [freshA, freshA]}}]}
```

## Arithmetic

`is/2` evaluates its right-hand side as an arithmetic expression and
unifies the result with its left-hand side:

| Functor | Meaning |
| --- | --- |
| `+/2`, `-/2`, `*/2`, `//2` | The usual four; `/` produces a float unless the division is exact between two integers. |
| `///2` | Integer (floor) division. |
| `mod/2`, `rem/2` | Modulo (sign follows the divisor) and remainder (sign follows the dividend). |
| `-/1`, `+/1` | Unary minus/plus. |
| `abs/1` | Absolute value. |
| `sign/1` | `-1`, `0`, or `1`. |
| `min/2`, `max/2` | The smaller/larger of two numbers. |
| `sqrt/1` | Square root (always a float). |
| `**/2`, `^/2` | Exponentiation. |

Division/mod/rem/integer-division by zero raise a `domain_error`; a
non-numeric, non-variable, non-evaluable expression raises a
`type_error(evaluable, _)` (see [Exceptions](#exceptions)).

Arithmetic comparisons evaluate both sides the same way `is/2` does:
`=:=/2`, `=\=/2`, `</2`, `>/2`, `=</2`, `>=/2`.

```elixir
Aletheia.query("X is 2 + 3 * 4", db)  #=> {:ok, [%{"X" => 14}]}
Aletheia.query("X is 7 // 2", db)     #=> {:ok, [%{"X" => 3}]}
Aletheia.query("3 =:= 3.0", db)       #=> {:ok, [%{}]}
```

## Exceptions

| Predicate | Description |
| --- | --- |
| `throw/1` | Raises its argument as a Prolog exception. |
| `catch/3` | `catch(Goal, Catcher, Recovery)` runs `Goal`; if it throws a term that unifies with `Catcher`, runs `Recovery` (with that unification's bindings) instead of propagating further. |
| `type_error/2` | `type_error(Type, Culprit)` throws the standard `error(type_error(Type, Culprit), _)`. |
| `domain_error/2` | `domain_error(Domain, Culprit)` throws `error(domain_error(Domain, Culprit), _)`. |
| `instantiation_error/1` | Throws `error(instantiation_error, _)` — a value was needed but an unbound variable was given. |

An exception nothing in your program catches surfaces at the top level
as `{:error, term}` from `Aletheia.query/2`/`query_once/2` (and as
`:none`-adjacent text in the REPL), rather than crashing the calling
Elixir process. Calling an undefined predicate raises a standard
`existence_error(procedure, Name/Arity)` the same way.

```elixir
{:ok, db} = Aletheia.consult_string(
  "safe_div(X, Y, R) :- catch(R is X / Y, error(_, _), R = undefined)."
)
Aletheia.query("safe_div(10, 0, R)", db)  #=> {:ok, [%{"R" => :undefined}]}
```

## Operators

| Predicate | Description |
| --- | --- |
| `op/3` | `:- op(Priority, Type, Name).` — extends the operator table for every clause parsed *after* this directive in the same source. `Type` is one of `fx`/`fy` (prefix), `xf`/`yf` (postfix), `xfx`/`yfx`/`xfy` (infix). |

```prolog
:- op(700, xfx, likes).
example(X) :- X = (tom likes wine).
```

```elixir
Aletheia.query("example(X)", db)
#=> {:ok, [%{"X" => %Episteme.Term.Compound{name: :likes, args: [:tom, :wine]}}]}
```

`op/3` takes effect at **read time** — it's a directive processed while
consulting a source (extending how *later clauses in that same source*
get parsed), not a callable goal at query time, and not something the
arithmetic evaluator picks up automatically: registering a new operator
only changes what parses, not what `is/2` knows how to compute — `X is
1 likes 2` would still raise a `type_error(evaluable, _)` unless
`likes` also happened to be one of the functors
[Arithmetic](#arithmetic) already recognizes.

## Lists

Over native `[H|T]` lists:

| Predicate | Description |
| --- | --- |
| `length/2` | `length(List, N)` — `N` is `List`'s length; with `List` unbound and `N` bound, builds a list of `N` fresh variables. |
| `append/3` | `append(A, B, C)` — `C` is `A` followed by `B`. With `A` unbound and `C` bound, enumerates every way to split `C`. |
| `member/2` | `member(X, List)` — `X` is (in turn, on backtracking) each element of `List`. |
| `reverse/2` | `reverse(List, Reversed)`. |
| `nth0/3`, `nth1/3` | `nth0(Index, List, Elem)`/`nth1/3` — 0- or 1-based indexing; with `Index` unbound, enumerates every index/element pair. |
| `last/2` | `last(List, Elem)` — `Elem` is `List`'s last element (fails on `[]`). |

```elixir
Aletheia.query("append([1, 2], [3, 4], X)", db)
#=> {:ok, [%{"X" => [1, 2, 3, 4]}]}

Aletheia.query("append(X, Y, [1, 2, 3])", db)
#=> {:ok, [%{"X" => [], "Y" => [1, 2, 3]}, %{"X" => [1], "Y" => [2, 3]},
#          %{"X" => [1, 2], "Y" => [3]}, %{"X" => [1, 2, 3], "Y" => []}]}
```

## I/O

| Predicate | Description |
| --- | --- |
| `write/1` | Prints a term in canonical `functor(args)` form (no operator-aware pretty-printing yet). |
| `writeln/1` | Like `write/1`, followed by a newline. |
| `print/1` | An alias of `write/1`. |
| `nl/0` | Prints a newline. |

## Top-level Elixir API

| Function | Description |
| --- | --- |
| `Aletheia.consult/1` | Loads a `.alp` file into a fresh database. |
| `Aletheia.consult_string/2` | Loads source text into a database (default: a fresh one). |
| `Aletheia.query/2` | Every solution of a goal, as a list of `%{"Var" => value}` maps. |
| `Aletheia.query_once/2` | Just the first solution (or `:none`). |
| `Aletheia.query_lazy/2` + `Aletheia.next_solution/2` | Pulls solutions one at a time instead of forcing the whole (possibly-infinite) search — what `Aletheia.Repl` is built on. |
