defmodule Aletheia.Database do
  @moduledoc """
  Clause storage: `{name, arity} -> ordered list of {head, body}`
  clauses, `body` a single term (`true` for a fact, matching real
  Prolog's own internal `Head :- Body` shape) -- populated by
  `consult`, looked up by `Aletheia.Engine` on every user-predicate
  call. `assert`/`retract` as callable predicates are v0.2, but
  `add_clause/2` is the internal primitive both `consult` today and
  `assert` later build on.
  """

  alias Aletheia.Term.Compound

  defstruct clauses: %{}

  @type clause :: {head :: term(), body :: term()}
  @type indicator :: {atom(), non_neg_integer()}
  @type t :: %__MODULE__{clauses: %{indicator() => [clause()]}}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec add_clause(t(), clause()) :: t()
  def add_clause(%__MODULE__{} = db, {head, _body} = clause) do
    key = indicator(head)
    %{db | clauses: Map.update(db.clauses, key, [clause], &(&1 ++ [clause]))}
  end

  @spec add_fact(t(), term()) :: t()
  def add_fact(db, head), do: add_clause(db, {head, true})

  @spec clauses_for(t(), atom(), non_neg_integer()) :: [clause()]
  def clauses_for(%__MODULE__{} = db, name, arity), do: Map.get(db.clauses, {name, arity}, [])

  @spec defined?(t(), atom(), non_neg_integer()) :: boolean()
  def defined?(%__MODULE__{} = db, name, arity), do: Map.has_key?(db.clauses, {name, arity})

  @spec indicator(term()) :: indicator()
  def indicator(%Compound{name: name, args: args}), do: {name, length(args)}
  def indicator(atom) when is_atom(atom), do: {atom, 0}

  @doc """
  Loads every `{:fact, head}`/`{:rule, head, body}` form (as returned by
  `Aletheia.Reader.consult_string/2`) into `db`. `{:directive, _}` forms
  are ignored here -- `op/3` directives already took effect at parse
  time, against the reader's own operator table, not the database.
  """
  @spec consult_forms(t(), list()) :: t()
  def consult_forms(db, forms) do
    Enum.reduce(forms, db, fn
      {:fact, head}, db -> add_fact(db, head)
      {:rule, head, body}, db -> add_clause(db, {head, body})
      {:directive, _goal}, db -> db
    end)
  end
end
