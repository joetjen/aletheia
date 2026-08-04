# Cheatsheet

Quick lookup once you already know Prolog and just need the Aletheia
API/syntax specifics. For explanations, see the
[tutorial](TUTORIAL.md); for full semantics, see the
[reference](REFERENCE.md).

## Load and query

```elixir
{:ok, db} = Aletheia.consult_string(source)     # from a string
{:ok, db} = Aletheia.consult(path)              # from a .alp file

Aletheia.query(goal_text, db)
#=> {:ok, [%{"Var" => value}, ...]} | {:error, term}

Aletheia.query_once(goal_text, db)
#=> {:ok, %{"Var" => value}} | :none | {:error, term}

{:ok, {stream, vars}} = Aletheia.query_lazy(goal_text, db)
Aletheia.next_solution(stream, vars)
#=> {:solution, %{"Var" => value}, rest} | :none | {:error, term}
```

`db` accumulates across calls — `consult_string/2`'s second argument
defaults to a fresh `Episteme.Database.new()`, but pass a previous
`db` to keep adding clauses to the same one.

## REPL

```sh
mix run -e 'Aletheia.Repl.start(["path/to/file.alp"])'
```

```text
?- goal
Var = value
;              % ask for the next solution
?-             % anything else stops
```

## Syntax at a glance

```prolog
foo                  % atom
'John Doe'           % quoted atom
X, _Acc, _           % variables (bare _ is always fresh)
42, 3.14             % integer, float
[], [1,2,3], [H|T]   % lists
foo(a, b)            % compound
1 + 2                % sugar for +(1, 2)
% comment            % line comment
/* comment */         % block comment
fact.                 % a fact
head :- body.         % a rule
:- goal.              % a directive (only op/3 does anything)
```

## Default operator table

Bigger priority number = looser binding (ISO convention):

```text
1100  xfy   ;
1050  xfy   ->
1000  xfy   ,
 900  fy    \+
 700  xfx   = \= == \== is =:= =\= < > =< >=
 500  yfx   + -
 400  yfx   * / // mod rem
 200  xfy   ^
 200  yfx   **
 200  fy    - +   (prefix)
```

Extend with `:- op(Priority, Type, Name).` — takes effect for clauses
parsed after it in the same source.

## Control

```prolog
A, B                  % conjunction
A ; B                 % disjunction
Cond -> Then          % if-then (fails if Cond fails, no else)
Cond -> Then ; Else   % if-then-else
!                     % cut -- see below
\+ Goal               % negation as failure
call(Goal, Extra...)  % call/1..8, cut-opaque
once(Goal)            % first solution only, cut-opaque -- NOT the same as !
forall(Cond, Action)  % every solution of Cond has a solution of Action
true. fail. false.
```

## Cut, in one example

```prolog
p(1) :- !, fail.
p(2).
```

```elixir
Aletheia.query("p(X)", db)  #=> {:ok, []}
```

Real cut, not `once/1`: commits to clause 1 before `fail` runs, so
clause 2 never gets a chance. See
[`REFERENCE.md#cut`](REFERENCE.md#cut) for the full rules.

## Unification / comparison

```prolog
X = Term        % unify
X \= Term       % fails if it WOULD unify
A == B          % structural equal (int/float never equal)
A \== B
```

## Type checks

```prolog
var(X)  nonvar(X)  atom(X)  atomic(X)  number(X)
integer(X)  float(X)  compound(X)  callable(X)  is_list(X)
```

## Arithmetic

```prolog
X is 2 + 3 * 4        % standard precedence, is/2 evaluates the RHS
+ - * / // mod rem ** ^ abs/1 sign/1 min/2 max/2 sqrt/1
=:= =\= < > =< >=      % arithmetic comparison (evaluates both sides)
between(Low, High, X)  % X unbound: enumerates; X bound: membership check
```

## Exceptions

```prolog
throw(Term)
catch(Goal, Catcher, Recovery)
type_error(Type, Culprit)
domain_error(Domain, Culprit)
instantiation_error(_)
```

Uncaught -> `{:error, term}` from `Aletheia.query/2`, not a crash.
Undefined predicate -> `existence_error(procedure, Name/Arity)`.

## Database and aggregation

```prolog
assert(Clause)  assertz(Clause)  asserta(Clause)  % assert is a classic alias of assertz
retract(Clause)  retractall(HeadPattern)
findall(Template, Goal, List)   % [] when Goal has no solutions, not failure
```

## Lists

```prolog
length(List, N)
append(A, B, C)          % also works with A unbound (splits C)
member(X, List)
reverse(List, Reversed)
nth0(I, List, X)  nth1(I, List, X)
last(List, X)
```

## I/O

```prolog
write(Term)  writeln(Term)  print(Term)  nl
```

## Development

```sh
mix deps.get
mix test
mix format --check-formatted
mix compile --warnings-as-errors
mix gen.grammar   # regenerate grammar_generated.ex after editing grammar.aether
mix docs
mix precommit     # format, compile --warnings-as-errors, credo, sobelow, test, dialyzer
```
