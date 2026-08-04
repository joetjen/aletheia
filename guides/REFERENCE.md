# Reference

Every predicate implemented and reachable from `.alp` source today,
with its signature, semantics, and enough of an example to use it
correctly. As of `DESIGN.md`'s `aletheia_episteme_path_dependency_interim`
decision, this covers the *entire* v0.1-v0.5 roadmap — the whole
numbered milestone list is done. Two genuine, deliberate gaps remain,
both called out where relevant below: `=../2` (`univ/2` works, but the
ISO punctuation form can't be tokenized by this reader's own simplified
lexer — see [Term inspection](#term-inspection)), and `format/2`'s
column/radix directives (`~t`, `~|`, `~Nr`, numeric-prefixed `~Nd` — see
[I/O](#io)). Past v0.5, only the roadmap's explicitly unscheduled,
need-driven `later` bucket (module system, tabling, CLP(FD)) remains,
and isn't started.

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
- **Strings**: double-quoted (`"hello"`) — a real, native Elixir binary
  under the hood (see `DESIGN.md`'s `string_type_decision`), a genuinely
  distinct term class from atoms, never a code list. No escape
  processing (a literal `"` can't appear inside one at all), same
  simplification quoted atoms already have.
- **Lists**: `[]` (empty), `[1, 2, 3]` (proper), `[H|T]` (cons, `T` can
  be a variable or another list) — backed by native Elixir lists,
  decomposing as ISO's own `'.'/2` cons functor so unification recurses
  into them correctly.
- **Compounds**: `functor(Arg1, Arg2, ...)`, plus operator syntax as
  sugar for the same thing — `1 + 2` *is* `+(1, 2)`.
- **`{Goal}`**: ISO's own `'{}'/1` term shape, valid anywhere a term is
  — ordinary syntax, not DCG-specific, though a [DCG](#dcg) body is
  where it takes on special meaning (an embedded plain goal, no
  difference-list threading). Requires non-empty content; the bare atom
  `{}` isn't supported.
- **Comments**: `%` to end of line, `/* ... */` block comments.
- **Clauses**: `Head.` (a fact), `Head :- Body.` (a rule), `Head -->
  Body.` (a [DCG](#dcg) rule), `:- Goal.` (a directive — currently only
  `op/3` has any effect as one). Every clause ends with a bare `.`.

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
| 700 | `xfx` | `=` `\=` `==` `\==` `is` `=:=` `=\=` `<` `>` `=<` `>=` `@<` `@>` `@=<` `@>=` |
| 500 | `yfx` | `+` `-` |
| 400 | `yfx` | `*` `/` `//` `mod` `rem` |
| 200 | `xfy` | `^` |
| 200 | `yfx` | `**` |
| 200 | `fy` | `-` `+` (prefix) |

`Head --> Body.` (DCG rules, see [DCG](#dcg)) is handled as its own
dedicated clause form, not through this operator table — `-->` never
needs an `op/3` entry to work at the top level of a clause.

Extend the table itself at read time with `op/3` (see
[Operators](#operators) below).

Two documented simplifications: no genuine `xfx` (non-associative) vs.
`yfx` (left-associative) distinction yet, inherited from the underlying
parsing substrate ([Ichor](https://hex.pm/packages/ichor)) — an `a is b
is c`-style chain parses left-associatively instead of being rejected
the way ISO would reject it outright; and an operator symbol can't yet
be used as an explicit compound functor the way ISO allows (`=(X, Y)`
as another way to write `X = Y`) — a compound's functor position only
accepts a plain or quoted atom today, not a bare operator token. A
third, narrower one: `=../2` (`univ`)'s own ISO punctuation can't be
tokenized by this reader's simplified lexer (a lone `.` inside a longer
operator token is indistinguishable from end-of-clause) — use
`univ/2` directly (see [Term inspection](#term-inspection)).

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
| `ignore/1` | Like `once/1`, but never fails — if the goal has no solution, still succeeds, with bindings left as they were. Equivalent to `(call(Goal) -> true ; true)`. |
| `forall/2` | `forall(Cond, Action)` — succeeds iff every solution of `Cond` has at least one solution of `Action`. Never binds anything, like `\+/1`. Cut-opaque in both arguments. |

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
| `unify_with_occurs_check/2` | Like `=/2`, but rejects a variable binding to a compound term that already contains it, instead of silently building an infinite term. |
| `@</2`, `@>/2` | Standard order of terms — `Var < Number < Atom < String < Compound`, alphabetical/by-value within a class. |
| `@=</2`, `@>=/2` | Standard order, inclusive. |
| `compare/3` | `compare(Order, A, B)` unifies `Order` with `<`, `=`, or `>` per the standard order of terms. |

```elixir
Aletheia.query("X = foo(1, 2)", db)
#=> {:ok, [%{"X" => %Episteme.Term.Compound{name: :foo, args: [1, 2]}}]}

Aletheia.query("1 == 1.0", db)   #=> {:ok, []}          -- different types
Aletheia.query("X = 2, X \\= 1", db)  #=> {:ok, [%{"X" => 2}]}

Aletheia.query("unify_with_occurs_check(X, f(X))", db)  #=> {:ok, []}
Aletheia.query("zzz @< aaa", db)                        #=> {:ok, []}
Aletheia.query("aaa @< zzz", db)                        #=> {:ok, [%{}]}
```

## Type checking

Each of these inspects its (fully-resolved) argument's shape and
succeeds or fails accordingly — none of them bind anything.

| Predicate | Succeeds when the argument is... |
| --- | --- |
| `var/1` | an unbound variable |
| `nonvar/1` | anything *but* an unbound variable |
| `atom/1` | a plain atom |
| `string/1` | a real string (never true for an atom with the same characters, even one written `'like this'`) |
| `atomic/1` | an atom, number, or string — anything with no internal structure |
| `number/1` | an integer or a float |
| `integer/1` | an integer |
| `float/1` | a float |
| `compound/1` | a compound term or a non-empty list |
| `callable/1` | an atom or a compound term (i.e. something `call/1` could run) |
| `is_list/1` | a *proper* list (every tail eventually reaches `[]`) |
| `ground/1` | contains no unbound variable anywhere, at any depth |

## Term inspection

| Predicate | Description |
| --- | --- |
| `copy_term/2` | Copies term 1 into term 2, renaming every distinct unbound variable apart (consistently — two occurrences of the same variable stay shared in the copy) while resolving anything already bound. |
| `functor/3` | `functor(Term, Name, Arity)` — decomposes a bound `Term` into its name/arity, or (with `Term` unbound) builds a fresh compound of `Arity` fresh variables from a bound `Name`/`Arity`. |
| `arg/3` | `arg(N, Term, Arg)` — 1-based, `Arg` is `Term`'s `N`th argument. |
| `univ/2` | `univ(Term, List)` — real Prolog `=..`, not reader-supported as punctuation (see [Syntax](#syntax)): `List` is `[Name \| Args]` (or `[Term]` if atomic) for a bound `Term`; builds `Term` from a bound, fully-instantiated `List` the other way. |

```elixir
Aletheia.query("copy_term(f(X, X), Y)", db)
#=> {:ok, [%{"Y" => %Episteme.Term.Compound{name: :f, args: [freshA, freshA]}}]}

Aletheia.query("functor(foo(a, b), Name, Arity)", db)
#=> {:ok, [%{"Name" => :foo, "Arity" => 2}]}

Aletheia.query("univ(foo(1, 2), L)", db)
#=> {:ok, [%{"L" => [:foo, 1, 2]}]}
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
| `sin/1`, `cos/1`, `tan/1` | Trig, radians. |
| `exp/1` | `e^X`. |
| `log/1` | Natural log (base `e`). |
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

`between/3` is a goal, not an expression functor (not ISO, but a de
facto standard across most Prolog implementations): `between(Low,
High, X)` enumerates every integer in `[Low, High]` on backtracking
when `X` is unbound, or just checks membership when it's bound. `Low`/
`High` are evaluated as arithmetic expressions, same as `is/2`'s
right-hand side.

```elixir
Aletheia.query("between(1, 5, X)", db)
#=> {:ok, [%{"X" => 1}, %{"X" => 2}, %{"X" => 3}, %{"X" => 4}, %{"X" => 5}]}
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

## Database

Mutating the clause database at query time — effects persist across
separate `Aletheia.query/2` calls against the same database, not just
within one. No `dynamic/1` declaration is required first: `assert`ing a
brand-new predicate works immediately, unlike strict ISO Prolog.

| Predicate | Description |
| --- | --- |
| `assert/1`, `assertz/1` | Adds a clause (`Head` or `Head :- Body`) at the *end* of its predicate's clause list. `assert/1` is a classic alias of `assertz/1`. |
| `asserta/1` | Like `assertz/1`, but adds the clause at the *front*. |
| `retract/1` | Removes the first stored clause (in declared/assert order) whose head and body both unify with the argument (a bare `Head` matches a fact, i.e. body `true`). Fails, without side effects, if nothing matches. Deterministic on success — backtracking into it does not try the next match. |
| `retractall/1` | Removes every stored clause whose *head* unifies with the argument (bodies ignored). Always succeeds, even against an undefined or already-empty predicate. Never binds anything. |
| `dynamic/1` | `dynamic(Name/Arity)` (or a list of indicators) — declares a predicate defined with zero clauses, so calling it fails instead of raising `existence_error`, and `assert`/`retract` work on it immediately. |
| `abolish/1` | `abolish(Name/Arity)` — unlike `retractall/1`, undefines the predicate too; a later call raises `existence_error` again. |
| `clause/2` | `clause(Head, Body)` — enumerates every stored clause whose head unifies with `Head`, one per backtrack, unifying `Body` with that clause's own body (`true` for a fact). |

```elixir
{:ok, db} = Aletheia.consult_string("p(a). p(b).")
Aletheia.query("assertz(p(c)), findall(X, p(X), L)", db)
#=> {:ok, [%{"L" => [:a, :b, :c]}]}

Aletheia.query_once("assert(q(1)), retract(q(1)), \\+ q(1)", db)
#=> {:ok, %{}}
```

## Aggregation

| Predicate | Description |
| --- | --- |
| `findall/3` | `findall(Template, Goal, List)` — `List` is every instantiation of `Template` across every solution of `Goal`, in order. `[]` (not failure) when `Goal` has no solutions. Cut-opaque. |
| `bagof/3` | Like `findall/3`, but fails outright (not `List = []`) when `Goal` has no solutions, and groups solutions by `Goal`'s own free variables (mentioned in `Goal`, not in `Template`, not existentially quantified via `Var^Goal`) — backtracks one solution per distinct group. |
| `setof/3` | Like `bagof/3`, but each group's `List` is sorted and deduped by standard order of terms, and the groups themselves are ordered by their witness value. |

```elixir
{:ok, db} = Aletheia.consult_string("parent(tom, bob). parent(tom, liz).")
Aletheia.query("findall(X, parent(tom, X), L)", db)
#=> {:ok, [%{"L" => [:bob, :liz], "X" => %Episteme.Term.Var{...}}]}
#   (X, used only inside findall/3's own template/goal, comes back too, still unbound --
#   every named query variable does, whether or not it ends up bound; use an
#   anonymous _ instead if you don't want it in the result map)

{:ok, db2} =
  Aletheia.consult_string(
    "likes(mary, apples). likes(mary, pears). likes(john, apples)."
  )

Aletheia.query("bagof(X, likes(mary, X), L)", db2)
#=> {:ok, [%{"L" => [:apples, :pears], "X" => %Episteme.Term.Var{...}}]}

Aletheia.query("bagof(X, likes(nobody, X), L)", db2)  #=> {:ok, []}    -- fails, not L = []
```

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
| `msort/2` | Sorts by standard order of terms, no deduping. |
| `sort/2` | Like `msort/2`, but also dedups (by standard order, so `1` and `1.0` are distinct). |
| `permutation/2` | Every permutation of the list, one per backtrack. |
| `sum_list/2`, `max_list/2`, `min_list/2` | The obvious. |
| `list_to_set/2` | Removes duplicates, keeping first-occurrence order. |
| `include/3`, `exclude/3` | `include(Goal, List, Kept)`/`exclude/3` — elements where `call(Goal, Elem)` succeeds (or doesn't). |
| `foldl/4` (also `/5`, `/6` for 2-3 lists) | Threads an accumulator: `call(Goal, Elem, AccIn, AccOut)` per element, in lockstep across every list argument. |
| `maplist/2..N` | Succeeds iff `call(Goal, E1_i, ..., EN_i)` succeeds for every row. At least one list must be bound; the rest get built fresh. |

```elixir
Aletheia.query("append([1, 2], [3, 4], X)", db)
#=> {:ok, [%{"X" => [1, 2, 3, 4]}]}

Aletheia.query("append(X, Y, [1, 2, 3])", db)
#=> {:ok, [%{"X" => [], "Y" => [1, 2, 3]}, %{"X" => [1], "Y" => [2, 3]},
#          %{"X" => [1, 2], "Y" => [3]}, %{"X" => [1, 2, 3], "Y" => []}]}

Aletheia.query("sort([3, 1, 2, 1], L)", db)
#=> {:ok, [%{"L" => [1, 2, 3]}]}
```

## Atom, number, and string conversions

Two families: `atom_*`/`number_*` (classic ISO/de-facto, working with
atoms — `atom_chars/2`'s own chars are single-character *atoms*) and
`string_*`/`split_string` (SWI-style, working with real strings —
`string_chars/2`'s chars are single-character *strings*). Not
interchangeable.

| Predicate | Description |
| --- | --- |
| `atom_codes/2`, `atom_chars/2` | Atom ↔ code list / single-char-atom list, either direction. |
| `atom_length/2` | Character count of any atomic term's text. |
| `atom_concat/3` | Both parts bound: concatenates. Only the whole bound: enumerates every split on backtracking. |
| `sub_atom/5` | `sub_atom(Atom, Before, Length, After, Sub)` — relates `Atom` to every substring; unbound args enumerate, bound ones narrow. `Sub` is always an atom. |
| `char_code/2` | Single-character atom ↔ its character code. |
| `number_codes/2`, `number_chars/2` | Number ↔ code list / single-char-atom list. |
| `upcase_atom/2`, `downcase_atom/2` | Case conversion. |
| `atomic_list_concat/2` | Concatenates a bound list of atomics (no splitting mode). |
| `atomic_list_concat/3` | List bound: joins with a separator. List unbound, result bound: splits on the separator (deterministic). |
| `atom_string/2`, `string_to_atom/2` | Atom ↔ string, either direction (same conversion, argument order swapped). |
| `string_concat/3`, `string_chars/2`, `string_codes/2`, `string_length/2` | Same shape as the `atom_*` versions above, string-producing. |
| `number_string/2` | Like `atom_string/2`, for numbers. |
| `split_string/4` | `split_string(String, SepChars, PadChars, SubStrings)` — splits on any char in `SepChars` (`""` = don't split), then trims `PadChars` from each field's ends. Always strings. |

```elixir
Aletheia.query("atom_concat(foo, bar, X)", db)
#=> {:ok, [%{"X" => :foobar}]}

Aletheia.query("sub_atom(abc, 1, 2, After, Sub)", db)
#=> {:ok, [%{"After" => 0, "Sub" => :bc}]}

Aletheia.query("atom_string(hello, S)", db)
#=> {:ok, [%{"S" => "hello"}]}
```

## I/O

| Predicate | Description |
| --- | --- |
| `write/1` | Prints a term in canonical `functor(args)` form (no operator-aware pretty-printing yet). |
| `writeln/1` | Like `write/1`, followed by a newline. |
| `print/1` | An alias of `write/1`. |
| `nl/0` | Prints a newline. |
| `format/1`, `format/2` | `format(Format, Args)` prints `Format`'s text with each `~`-directive consuming the next element of `Args` (`format/1` is `format/2` with `Args = []`; a single non-list `Args` is treated as `[Args]`). Directives: `~w`/`~p`/`~q` (term text, all the same here), `~a` (atom text), `~d` (integer text), `~s` (code-list/string text), `~i` (skip an argument), `~n` (newline), `~~` (literal `~`). No column/radix directives (`~t`, `~\|`, `~Nr`, numeric-prefixed `~Nd`). |

```elixir
Aletheia.query("format(\"~w and ~d~n\", [hello, 42])", db)
#=> prints "hello and 42\n", then {:ok, [%{}]}
```

## DCG

A DCG rule (`Head --> Body`) threads an incoming/outgoing
difference-list pair through every nonterminal call, so a grammar
reads like a sequence of things matched rather than explicit list
splitting. A practical subset of real DCG translation: terminals
(`[t1, ..., tn]`), `{Goal}` (embedded plain goal, no list threading —
see [Syntax](#syntax)), `!`, `,`/`;`/`->`, `\+`, a bare nonterminal
(atom or compound), and a variable body. No `call//N` pushback
(parameterized higher-order nonterminals).

| Predicate | Description |
| --- | --- |
| `phrase/2` | `phrase(Body, List)` — runs `Body` against `List`, which must be fully consumed. Cut-opaque, like `call/N`. |
| `phrase/3` | `phrase(Body, List, Rest)` — like `phrase/2`, but leaves whatever's unconsumed in `Rest`. |
| `dcg_translate/2` | `dcg_translate(Rule, Clause)` — the readable alias for `-->/2` itself: unifies `Clause` with the ordinary clause `Rule` translates to, without storing anything. |

```prolog
greeting --> [hello], [world].
digit(D) --> [D], { integer(D) }.
```

```elixir
Aletheia.query("phrase(greeting, [hello, world])", db)
#=> {:ok, [%{}]}

Aletheia.query("phrase(greeting, [hello, world, extra], Rest)", db)
#=> {:ok, [%{"Rest" => [:extra]}]}

Aletheia.query("phrase(digit(X), [5])", db)
#=> {:ok, [%{"X" => 5}]}
```

A `-->/2`-shaped clause term passed to `assert/1` translates and stores
the same way, dynamically.

## Top-level Elixir API

| Function | Description |
| --- | --- |
| `Aletheia.consult/1` | Loads a `.alp` file into a fresh database. |
| `Aletheia.consult_string/2` | Loads source text into a database (default: a fresh one). |
| `Aletheia.query/2` | Every solution of a goal, as a list of `%{"Var" => value}` maps. |
| `Aletheia.query_once/2` | Just the first solution (or `:none`). |
| `Aletheia.query_lazy/2` + `Aletheia.next_solution/2` | Pulls solutions one at a time instead of forcing the whole (possibly-infinite) search — what `Aletheia.Repl` is built on. |
