defmodule Aletheia do
  @moduledoc """
  Top-level API: `consult/1`/`consult_string/2` load source into an
  `Episteme.Database`, `query/2` solves a goal (source text or an
  already-parsed term) against one. Parses text via `Aletheia.Reader`
  and delegates the actual solving to `Episteme`, the standalone
  engine/database package this reader is a front-end for -- everything
  past parsing (terms, unification, SLD-resolution, cut, builtins) lives
  there, not here. Uncaught Prolog exceptions (a real `throw/1` no
  `catch/3` in the program itself caught) surface as `{:error, term}`
  here, at the outermost boundary, rather than as a raw Elixir `throw`
  escaping to the caller.
  """

  alias Aletheia.Reader
  alias Episteme.{Database, Term}
  alias Ichor.Backtrack.Tree

  @type solution :: Episteme.solution()

  @doc "Loads a `.alp` source file into a fresh database."
  @spec consult(String.t()) :: {:ok, Database.t()} | {:error, term()}
  def consult(path) do
    consult_string(File.read!(path))
  end

  @doc "Loads Aletheia source text into `db` (default: a fresh database)."
  @spec consult_string(String.t(), Database.t()) :: {:ok, Database.t()} | {:error, term()}
  def consult_string(source, db \\ Database.new()) do
    case Reader.consult_string(source) do
      {:ok, forms, _ctx} -> {:ok, Database.consult_forms(db, forms)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Solves `goal` (source text or an already-parsed term) against `db`,
  returning every solution's variable bindings as `%{name => term}`
  maps (`Episteme.Term.to_text/1`-ready values, already fully resolved).
  A real Prolog `throw/1` that escapes uncaught surfaces as `{:error, term}`.
  """
  @spec query(String.t() | term(), Database.t()) :: {:ok, [solution()]} | {:error, term()}
  def query(goal, db) when is_binary(goal) do
    case parse_goal(goal) do
      {:ok, term} -> Episteme.query(term, db)
      {:error, _} = err -> err
    end
  end

  def query(goal, db), do: Episteme.query(goal, db)

  @doc "Like `query/2`, but returns only the first solution (or `:none`)."
  @spec query_once(String.t() | term(), Database.t()) ::
          {:ok, solution()} | :none | {:error, term()}
  def query_once(goal, db) do
    case query(goal, db) do
      {:ok, [first | _]} -> {:ok, first}
      {:ok, []} -> :none
      {:error, _} = err -> err
    end
  end

  @doc """
  Like `query/2`, but doesn't force every solution eagerly -- returns the
  raw lazy solution stream plus the goal's own named variables, both
  meant to be passed straight to `next_solution/2`. For a REPL (or any
  caller that only wants the first few solutions of a possibly-infinite
  search) instead of `query/2`'s own "pull the whole list" behavior.
  """
  @spec query_lazy(String.t() | term(), Database.t()) ::
          {:ok, {Tree.t(), MapSet.t(Term.Var.t())}} | {:error, term()}
  def query_lazy(goal, db) when is_binary(goal) do
    case parse_goal(goal) do
      {:ok, term} -> {:ok, Episteme.query_lazy(term, db)}
      {:error, _} = err -> err
    end
  end

  def query_lazy(goal, db), do: {:ok, Episteme.query_lazy(goal, db)}

  @doc "Pulls one solution from a `query_lazy/2` stream -- see `Episteme.next_solution/2`."
  @spec next_solution(Tree.t(), MapSet.t(Term.Var.t())) ::
          {:solution, solution(), Tree.t()} | :none | {:error, term()}
  defdelegate next_solution(stream, vars), to: Episteme

  # A query goal has to parse through the reader's own full-priority
  # `term` rule (comma/semicolon/arrow all allowed at the top, exactly
  # real Prolog's `?- Goal.` toplevel) -- wrapping it as `:- Goal.` (a
  # directive) gets that for free. Wrapping it as a fake predicate call's
  # own *argument* instead (an earlier, wrong approach) parses through
  # the restricted `arg_term` rule, which deliberately excludes `,`/`;`/
  # `->` (ISO's own "argument priority =< 999" rule) -- breaking any
  # goal with a top-level conjunction, i.e. almost every real query.
  defp parse_goal(text) do
    case Reader.consult_string(":- " <> text <> ".") do
      {:ok, [{:directive, goal}], _ctx} -> {:ok, goal}
      {:error, _} = err -> err
    end
  end
end
