# Cheatsheet: embedding Aletheia

Quick reference for common library tasks. For a language-syntax
cheatsheet, see
[language/ALETHEIA_CHEATSHEET.md](language/ALETHEIA_CHEATSHEET.md).

## Setup

| Task | Code |
|---|---|
| Add the dependency | `{:aletheia, path: "path/to/aletheia"}` in `mix.exs` |
| Fresh database from source text | `{:ok, db} = Aletheia.consult_string(source)` |
| Fresh database from a `.alp` file | `{:ok, db} = Aletheia.consult(path)` |
| Add more source to an existing `db` | `{:ok, db} = Aletheia.consult_string(source, db)` |

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

| Task | Code |
|---|---|
| Every solution, eagerly | `Aletheia.query(goal, db)` |
| Just the first solution | `Aletheia.query_once(goal, db)` |
| One solution at a time (no forced search) | `{:ok, {stream, vars}} = Aletheia.query_lazy(goal, db)`<br>`Aletheia.next_solution(stream, vars)` |
| Query an already-parsed term instead of text | pass the term directly — `query/2`/`query_lazy/2` accept either |

`db` accumulates across calls — `consult_string/2`'s second argument
defaults to a fresh `Episteme.Database.new()`, but pass a previous
`db` to keep adding clauses to the same one. Nothing about a `db` is a
global singleton — each one you build is fully independent.

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

Built on `query_lazy/2` + `next_solution/2` — never forces more of the
search than you ask to see via `;`.

## Errors

| Task | Code |
|---|---|
| Handle a failed query | `{:error, %Episteme.Term.Compound{args: [formal, _]}} = result` |
| Inspect what went wrong | `formal` is e.g. `%Episteme.Term.Compound{name: :domain_error, args: [...]}` |

Uncaught Prolog exception -> `{:error, term}` from `query/2`/
`query_once/2`/`next_solution/2`, never a crash in your Elixir process.
Undefined predicate -> `existence_error(procedure, Name/Arity)`, same
shape as any other automatically-raised error.
