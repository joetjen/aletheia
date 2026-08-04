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
"hello"               % string (real Elixir binary, not a code list)
X, _Acc, _           % variables (bare _ is always fresh)
42, 3.14             % integer, float
[], [1,2,3], [H|T]   % lists
foo(a, b)            % compound
{Goal}                % '{}'/1 -- ordinary syntax, special meaning in a DCG body
1 + 2                % sugar for +(1, 2)
% comment            % line comment
/* comment */         % block comment
fact.                 % a fact
head :- body.         % a rule
head --> body.        % a DCG rule
:- goal.              % a directive (only op/3 does anything)
```

## Default operator table

Bigger priority number = looser binding (ISO convention):

```text
1100  xfy   ;
1050  xfy   ->
1000  xfy   ,
 900  fy    \+
 700  xfx   = \= == \== is =:= =\= < > =< >= @< @> @=< @>=
 500  yfx   + -
 400  yfx   * / // mod rem
 200  xfy   ^
 200  yfx   **
 200  fy    - +   (prefix)
```

`-->` isn't in this table -- a DCG rule is its own dedicated clause
form, not parsed through the operator table.

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
ignore(Goal)          % like once/1, but never fails
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
unify_with_occurs_check(X, Term)   % like =, but rejects X = f(...,X,...)
A @< B  A @> B  A @=< B  A @>= B   % standard order of terms
compare(Order, A, B)               % Order = <, =, or >
```

## Type checks

```prolog
var(X)  nonvar(X)  atom(X)  string(X)  atomic(X)  number(X)
integer(X)  float(X)  compound(X)  callable(X)  is_list(X)  ground(X)
```

## Arithmetic

```prolog
X is 2 + 3 * 4        % standard precedence, is/2 evaluates the RHS
+ - * / // mod rem ** ^ abs/1 sign/1 min/2 max/2 sqrt/1
sin/1 cos/1 tan/1 exp/1 log/1
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
dynamic(Name/Arity)  abolish(Name/Arity)  clause(Head, Body)
findall(Template, Goal, List)   % [] when Goal has no solutions, not failure
bagof(Template, Goal, List)     % fails (not List = []) on no solutions; groups by free vars
setof(Template, Goal, List)     % like bagof/3, sorted + deduped
```

## Lists

```prolog
length(List, N)
append(A, B, C)          % also works with A unbound (splits C)
member(X, List)
reverse(List, Reversed)
nth0(I, List, X)  nth1(I, List, X)
last(List, X)
msort(List, Sorted)  sort(List, Sorted)   % msort keeps dups, sort dedups
permutation(List, Perm)
sum_list(List, Sum)  max_list(List, Max)  min_list(List, Min)
list_to_set(List, Set)
include(Goal, List, Kept)  exclude(Goal, List, Kept)
foldl(Goal, List, V0, V)   % also /5, /6 for 2-3 lists in lockstep
maplist(Goal, List1, ..., ListN)
```

## Atom/number/string conversions

`atom_*`/`number_*` work with atoms (`atom_chars/2`'s chars are
single-char *atoms*); `string_*`/`split_string` work with real strings
(`string_chars/2`'s chars are single-char *strings*).

```prolog
atom_codes(A, Codes)  atom_chars(A, Chars)  atom_length(A, Len)
atom_concat(A1, A2, A3)   % A3 only bound: enumerates every split
sub_atom(Atom, Before, Len, After, Sub)   % Sub always an atom
char_code(Char, Code)
number_codes(N, Codes)  number_chars(N, Chars)
upcase_atom(A, U)  downcase_atom(A, D)
atomic_list_concat(List, A)  atomic_list_concat(List, Sep, A)
atom_string(A, S)  string_to_atom(S, A)
string_concat(S1, S2, S3)  string_chars(S, Chars)  string_codes(S, Codes)
string_length(S, Len)  number_string(N, S)
split_string(S, SepChars, PadChars, SubStrings)
```

## I/O

```prolog
write(Term)  writeln(Term)  print(Term)  nl
format(Format, Args)   % also format/1, Args = []
```

`format/2` directives: `~w`/`~p`/`~q` (term text), `~a` (atom text),
`~d` (integer text), `~s` (code-list/string text), `~i` (skip an
argument), `~n` (newline), `~~` (literal `~`).

## DCG

```prolog
greeting --> [hello], [world].
digit(D) --> [D], { integer(D) }.
```

```prolog
phrase(Body, List)          % Body must consume all of List
phrase(Body, List, Rest)    % leaves what's unconsumed in Rest
dcg_translate(Rule, Clause) % the readable alias for -->/2 itself
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
