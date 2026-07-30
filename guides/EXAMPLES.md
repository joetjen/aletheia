# Examples

Complete, runnable programs — the source for each lives under
`examples/` in this repository (linked per-file below); every query
below was run against that exact source and its output pasted in
verbatim.

```elixir
{:ok, db} = Aletheia.consult("examples/family.alp")
```

## Family tree ([`examples/family.alp`](../examples/family.alp))

Facts, simple rules built on them, and one recursive rule
(`ancestor/2`):

```elixir
Aletheia.query("parent(tom, X)", db)
#=> {:ok, [%{"X" => :bob}, %{"X" => :liz}]}

Aletheia.query("father(X, Y)", db)
#=> {:ok, [%{"X" => :tom, "Y" => :bob}, %{"X" => :tom, "Y" => :liz},
#          %{"X" => :bob, "Y" => :ann}, %{"X" => :bob, "Y" => :pat}]}

Aletheia.query("grandparent(tom, Who)", db)
#=> {:ok, [%{"Who" => :ann}, %{"Who" => :pat}]}

Aletheia.query("ancestor(tom, Who)", db)
#=> {:ok, [%{"Who" => :bob}, %{"Who" => :liz}, %{"Who" => :ann},
#          %{"Who" => :pat}, %{"Who" => :jim}]}

Aletheia.query("sibling(ann, Y)", db)
#=> {:ok, [%{"Y" => :pat}]}
```

`father/2` and `mother/2` show rules layering a type-check (`male/1`/
`female/1`) on top of a plain fact; `ancestor/2` shows genuine recursion
through `parent/2` — the second clause calls `ancestor/2` from inside
its own body, and the engine's real SLD-resolution loop handles it
exactly like any other Prolog.

## List processing ([`examples/lists.alp`](../examples/lists.alp))

Ordinary recursive list predicates, on top of the v0.1 builtins:

```elixir
{:ok, db} = Aletheia.consult("examples/lists.alp")

Aletheia.query("sum([1,2,3,4], S)", db)
#=> {:ok, [%{"S" => 10}]}

Aletheia.query("max_of([3,7,2,9,4], M)", db)
#=> {:ok, [%{"M" => 9}]}

Aletheia.query("double_all([1,2,3], D)", db)
#=> {:ok, [%{"D" => [2, 4, 6]}]}

Aletheia.query("count(a, [a,b,a,c,a], N)", db)
#=> {:ok, [%{"N" => 3}]}
```

`count/3` is worth a second look — its middle clause has a cut right
after matching the element being counted:

```prolog
count(_, [], 0).
count(X, [X|T], N) :- !, count(X, T, N0), N is N0 + 1.
count(X, [_|T], N) :- count(X, T, N).
```

Without the `!`, a call like `count(a, [a|T], N)` could also (wrongly)
match the third clause — `[X|T]` unifying `X` with the head of the list
doesn't *prevent* `[_|T]` from also matching the same list. The cut
commits to "this element matched" the moment it has, so the third
clause is never even attempted for that position.

## Cut and control flow ([`examples/cut_control.alp`](../examples/cut_control.alp))

Three ways to write "classify by ranges," side by side, plus a direct
cut-vs-`once/1` comparison:

```elixir
{:ok, db} = Aletheia.consult("examples/cut_control.alp")

Aletheia.query("classify(-5, R)", db)  #=> {:ok, [%{"R" => :negative}]}
Aletheia.query("classify(0, R)", db)   #=> {:ok, [%{"R" => :zero}]}
Aletheia.query("classify(5, R)", db)   #=> {:ok, [%{"R" => :positive}]}

Aletheia.query("sign(-3, R)", db)      #=> {:ok, [%{"R" => :negative}]}
Aletheia.query("max(3, 7, M)", db)     #=> {:ok, [%{"M" => 7}]}
Aletheia.query("max(7, 3, M)", db)     #=> {:ok, [%{"M" => 7}]}
```

`classify/2` uses cut + clause order (the classic Prolog idiom); `sign/2`
gets the same result from a single clause with nested if-then-else;
`max/3` shows why the cut in `max(X, Y, X) :- X >= Y, !.` matters — the
head alone would still let `max(3, 7, M)` try to unify `M` with the
*first* argument on backtracking if nothing stopped it.

The cut/`once/1` distinction, made concrete:

```prolog
picked_cut(a) :- !.
picked_cut(b).

picked_once(a) :- once(true).
picked_once(b).
```

```elixir
Aletheia.query("picked_cut(X)", db)   #=> {:ok, [%{"X" => :a}]}
Aletheia.query("picked_once(X)", db)  #=> {:ok, [%{"X" => :a}, %{"X" => :b}]}
```

Both clauses *look* similar, but `!` and `once/1` are not
interchangeable: cut commits to the clause it appears in, so
`picked_cut/1`'s second clause is never tried; `once/1` only limits the
solution count of the goal it wraps, so it has no effect at all on
whether `picked_once/1`'s second clause gets tried — both `a` and `b`
come back. See [`REFERENCE.md#cut`](REFERENCE.md#cut) for the complete
rules.

## Exception handling ([`examples/exceptions.alp`](../examples/exceptions.alp))

Two different guard styles, plus recovering from a thrown error:

```elixir
{:ok, db} = Aletheia.consult("examples/exceptions.alp")

Aletheia.query("safe_div(10, 2, R)", db)    #=> {:ok, [%{"R" => 5}]}
Aletheia.query("safe_div(10, 0, R)", db)    #=> {:ok, [%{"R" => :undefined}]}
Aletheia.query("safe_div(10, foo, R)", db)  #=> {:ok, [%{"R" => :undefined}]}

Aletheia.query("safe_head([], H)", db)         #=> {:ok, [%{"H" => :none}]}
Aletheia.query("safe_head([1,2,3], H)", db)    #=> {:ok, [%{"H" => 1}]}

Aletheia.query("safe_eval(2 + 3, R)", db)  #=> {:ok, [%{"R" => 5}]}
Aletheia.query("safe_eval(foo, R)", db)    #=> {:ok, [%{"R" => :undefined}]}
```

`safe_div/3`'s first clause guards *before* attempting arithmetic
(`\+ number(Y), !`) — for a non-numeric divisor, which would otherwise
raise a `type_error(evaluable, _)` the moment `is/2` tried to evaluate
it. Its second clause instead lets the (numeric) division attempt run
and recovers from whatever it throws via `catch/3` — division by zero
raises a `domain_error`, which `error(_, _)`'s wildcard pattern catches
just as well. `safe_eval/2` shows the general "try, catch a specific
shape, otherwise pass the real value through" pattern:

```prolog
safe_eval(Expr, R) :-
  catch(R0 is Expr, error(type_error(evaluable, _), _), R0 = caught),
  (R0 == caught -> R = undefined ; R = R0).
```

`R0` is either the real evaluated result or the sentinel atom `caught`
(if `catch/3`'s recovery goal ran); the `->` then picks `R` accordingly.

## Where next

- **[Reference](REFERENCE.md)** for the complete predicate list this
  built on.
- **[Cheatsheet](CHEATSHEET.md)** for a condensed lookup once you've
  internalized the above.
