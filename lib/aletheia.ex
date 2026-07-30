defmodule Aletheia do
  @moduledoc """
  Top-level API: `consult/1`/`consult_string/2` load source into an
  `Aletheia.Database`, `query/2` solves a goal against one. Uncaught
  Prolog exceptions (a real `throw/1` no `catch/3` in the program
  itself caught) surface as `{:error, term}` here, at the outermost
  boundary, rather than as a raw Elixir `throw` escaping to the caller.
  """

  alias Aletheia.{Database, Engine, Reader, Term}
  alias Ichor.Backtrack.Tree

  @type solution :: %{optional(String.t()) => term()}

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
  maps (`Aletheia.Term.to_text/1`-ready values, already fully resolved).
  A real Prolog `throw/1` that escapes uncaught surfaces as `{:error, term}`.
  """
  @spec query(String.t() | term(), Database.t()) :: {:ok, [solution()]} | {:error, term()}
  def query(goal, db) when is_binary(goal) do
    case parse_goal(goal) do
      {:ok, term} -> wrap_query_result(run_query(term, db))
      {:error, _} = err -> err
    end
  end

  def query(goal, db), do: wrap_query_result(run_query(goal, db))

  defp wrap_query_result({:error, _} = err), do: err
  defp wrap_query_result(solutions) when is_list(solutions), do: {:ok, solutions}

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
      {:ok, term} -> {:ok, lazy_stream(term, db)}
      {:error, _} = err -> err
    end
  end

  def query_lazy(goal, db), do: {:ok, lazy_stream(goal, db)}

  defp lazy_stream(goal_term, db) do
    {Engine.solve_query(goal_term, db), collect_named_vars(goal_term, MapSet.new())}
  end

  @doc """
  Pulls one solution from a `query_lazy/2` stream: `{:solution, bindings,
  rest}`, `:none` when exhausted, or `{:error, term}` for an uncaught
  Prolog exception raised while solving *this* solution (each pull is
  independently guarded, since a lazy caller may pull solutions across
  arbitrarily many separate calls, unlike `query/2`'s one eager pass).
  """
  @spec next_solution(Tree.t(), MapSet.t(Term.Var.t())) ::
          {:solution, solution(), Tree.t()} | :none | {:error, term()}
  def next_solution(stream, vars) do
    case Tree.next(stream) do
      :empty -> :none
      {:solution, bindings, rest} -> {:solution, solution_map(bindings, vars), rest}
    end
  catch
    {:aletheia_throw, ball} -> {:error, ball}
  end

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

  defp run_query(goal_term, db) do
    {stream, vars} = lazy_stream(goal_term, db)
    collect_all(stream, vars)
  end

  defp collect_all(stream, vars) do
    case next_solution(stream, vars) do
      :none ->
        []

      {:error, _} = err ->
        err

      {:solution, solution, rest} ->
        case collect_all(rest, vars) do
          {:error, _} = err -> err
          more -> [solution | more]
        end
    end
  end

  defp solution_map(bindings, vars) do
    Map.new(vars, fn %Term.Var{ref: ref, name: name} ->
      {name, Term.resolve_deep(%Term.Var{ref: ref, name: name}, bindings)}
    end)
  end

  defp collect_named_vars(%Term.Var{name: name} = var, acc) do
    if name == "_", do: acc, else: MapSet.put(acc, var)
  end

  defp collect_named_vars(%Term.Compound{args: args}, acc) do
    Enum.reduce(args, acc, &collect_named_vars/2)
  end

  defp collect_named_vars(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_named_vars/2)
  end

  defp collect_named_vars(_other, acc), do: acc
end
