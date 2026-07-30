defmodule Aletheia.Engine do
  @moduledoc """
  SLD-resolution over `Ichor.Backtrack.Tree` + `Ichor.Backtrack.Bindings`
  plus `Aletheia.Database` (DESIGN.md §3/§11) -- clause selection is
  `disjunction/2` folded over a predicate's clauses in declared order,
  subgoal sequencing is `conjunction/2`, both reused unmodified from
  Ichor. Control constructs (`,` `;` `->` `!` `\\+` `call/N` `once/1`)
  live directly here rather than in a separate builtins module (as
  DESIGN.md's original module-layout sketch proposed): they turned out,
  once actually implemented, to be inseparable from the cut-barrier
  machinery below, not independent predicates dispatchable through a
  generic table.

  ## Cut

  `Ichor.Backtrack.Tree`'s `once/1` is not cut (see DESIGN.md's `cut-scoping`
  risk note) -- cut commits to every choice made since entering the
  *current clause* specifically, including pruning alternatives for
  goals that already SUCCEEDED earlier in the same body, which a
  bindings-borne "cut fired" marker can't express: `p :- !, fail.` with
  a second clause `p :- true.` must fail `p` outright (cut commits to
  clause 1 before `fail` ever runs), but a clause body that never
  produces a solution never gives a marker-on-solutions scheme anything
  to inspect.

  So `!` succeeds once normally, but its "give me another solution"
  continuation `throw({:aletheia_cut, barrier})`s instead of returning
  `:empty`. Every predicate call (and `call/N`, `once/1`, `\\+/1` --
  each cut-opaque per ISO) mints a fresh `barrier = make_ref()` and
  wraps its own clause-disjunction's lazy solution stream in
  `guard_cut/2`, which re-wraps every successive `rest` thunk so the
  guard is active no matter how many times -- or how much later -- a
  caller pulls another solution, catching only throws tagged with its
  *own* barrier (`catch {:aletheia_cut, ^barrier} -> :empty`) and
  re-throwing (letting Elixir's own catch semantics do it for free) any
  other tag, so a cut inside a called predicate never escapes past its
  own frame to affect the caller.

  Because `Ichor.Backtrack.Tree`'s combinators are plain function calls
  with no `try` anywhere inside them, a throw passes through
  `conjunction`/`disjunction`/`once` completely untouched -- this needs
  zero changes to Ichor itself.
  """

  alias Aletheia.Builtins.{Arithmetic, Exceptions, Io, Lists}
  alias Aletheia.{Database, Term}
  alias Aletheia.Term.{Compound, Var}
  alias Ichor.Backtrack.{Bindings, Tree}

  @type barrier :: reference()

  @doc """
  Solves `goal_term` against `db` from empty bindings -- the top-level
  query entry point. Genuinely lazy even in the very first dispatch
  step: a goal function call is itself eager (only the *rest* of a
  search tree is deferred by `Ichor.Backtrack.Tree`'s own combinators),
  so a builtin that throws immediately on its first attempt (calling an
  undefined predicate, say) would otherwise escape before a caller
  pulling solutions one at a time (`Aletheia.next_solution/2`) ever gets
  a chance to guard it -- wrapping everything in one more thunk here
  defers that first dispatch until whoever holds this value actually
  calls `Ichor.Backtrack.Tree`'s `next/1` on it.
  """
  @spec solve_query(term(), Database.t()) :: Ichor.Backtrack.Tree.t()
  def solve_query(goal_term, db) do
    barrier = make_ref()
    fn -> guard_cut(goal(goal_term, db, barrier).(Bindings.new()), barrier).() end
  end

  @doc "A goal (`bindings -> solutions`) for `term`, resolved under whatever `barrier` is currently in scope."
  @spec goal(term(), Database.t(), barrier()) :: Ichor.Backtrack.goal()
  def goal(term, db, barrier) do
    fn bindings -> solve(term, bindings, db, barrier) end
  end

  # ---- cut mechanism --------------------------------------------------------

  defp cut_goal(barrier) do
    fn bindings ->
      fn -> {:solution, bindings, fn -> throw({:aletheia_cut, barrier}) end} end
    end
  end

  @doc false
  @spec guard_cut(Tree.t(), barrier()) :: Tree.t()
  def guard_cut(thunk, barrier) do
    fn ->
      case safe_next(thunk, barrier) do
        :empty -> :empty
        {:solution, value, rest} -> {:solution, value, guard_cut(rest, barrier)}
      end
    end
  end

  defp safe_next(thunk, barrier) do
    thunk.()
  catch
    {:aletheia_cut, ^barrier} -> :empty
  end

  # ---- dispatch --------------------------------------------------------------

  defp solve(term, bindings, db, barrier) do
    case Bindings.resolve(Term, bindings, term) do
      %Var{} -> prolog_throw(Exceptions.instantiation_error())
      resolved -> dispatch(resolved, bindings, db, barrier)
    end
  end

  # -- control --

  defp dispatch(true, bindings, _db, _barrier), do: Tree.unit().(bindings)
  defp dispatch(:fail, bindings, _db, _barrier), do: Tree.fail().(bindings)
  defp dispatch(false, bindings, _db, _barrier), do: Tree.fail().(bindings)
  defp dispatch(:!, bindings, _db, barrier), do: cut_goal(barrier).(bindings)

  defp dispatch(%Compound{name: :",", args: [a, b]}, bindings, db, barrier) do
    Tree.conjunction(goal(a, db, barrier), goal(b, db, barrier)).(bindings)
  end

  defp dispatch(
         %Compound{name: :";", args: [%Compound{name: :->, args: [cond_, then_]}, else_]},
         bindings,
         db,
         barrier
       ) do
    if_then_else(cond_, then_, else_, bindings, db, barrier)
  end

  defp dispatch(%Compound{name: :";", args: [a, b]}, bindings, db, barrier) do
    Tree.disjunction(goal(a, db, barrier), goal(b, db, barrier)).(bindings)
  end

  defp dispatch(%Compound{name: :->, args: [cond_, then_]}, bindings, db, barrier) do
    if_then_else(cond_, then_, :fail, bindings, db, barrier)
  end

  defp dispatch(%Compound{name: :"\\+", args: [g]}, bindings, db, _barrier) do
    negation_as_failure(g, bindings, db)
  end

  defp dispatch(%Compound{name: :once, args: [g]}, bindings, db, _barrier) do
    inner_barrier = make_ref()
    Tree.once(fn b -> guard_cut(goal(g, db, inner_barrier).(b), inner_barrier) end).(bindings)
  end

  defp dispatch(%Compound{name: :call, args: [g | extra]}, bindings, db, _barrier) do
    inner_barrier = make_ref()
    built = build_call(g, extra, bindings)
    guard_cut(goal(built, db, inner_barrier).(bindings), inner_barrier)
  end

  # -- unification / comparison --

  defp dispatch(%Compound{name: :=, args: [a, b]}, bindings, _db, _barrier) do
    case Bindings.unify(Term, bindings, a, b) do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  defp dispatch(%Compound{name: :"\\=", args: [a, b]}, bindings, _db, _barrier) do
    case Bindings.unify(Term, bindings, a, b) do
      {:ok, _} -> Tree.fail().(bindings)
      :fail -> Tree.unit().(bindings)
    end
  end

  defp dispatch(%Compound{name: :==, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(structurally_equal?(a, b, bindings), bindings)

  defp dispatch(%Compound{name: :"\\==", args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(not structurally_equal?(a, b, bindings), bindings)

  # -- type checks --

  defp dispatch(%Compound{name: :var, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(match?(%Var{}, Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :nonvar, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(not match?(%Var{}, Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :atom, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(is_atom(Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :atomic, args: [x]}, bindings, _db, _barrier) do
    case Bindings.resolve(Term, bindings, x) do
      %Var{} -> bool_goal(false, bindings)
      %Compound{} -> bool_goal(false, bindings)
      [_ | _] -> bool_goal(false, bindings)
      _ -> bool_goal(true, bindings)
    end
  end

  defp dispatch(%Compound{name: :number, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(is_number(Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :integer, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(is_integer(Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :float, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(is_float(Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :compound, args: [x]}, bindings, _db, _barrier) do
    case Bindings.resolve(Term, bindings, x) do
      %Compound{} -> bool_goal(true, bindings)
      [_ | _] -> bool_goal(true, bindings)
      _ -> bool_goal(false, bindings)
    end
  end

  defp dispatch(%Compound{name: :callable, args: [x]}, bindings, _db, _barrier) do
    case Bindings.resolve(Term, bindings, x) do
      %Var{} -> bool_goal(false, bindings)
      %Compound{} -> bool_goal(true, bindings)
      [_ | _] -> bool_goal(true, bindings)
      atom when is_atom(atom) -> bool_goal(true, bindings)
      _ -> bool_goal(false, bindings)
    end
  end

  defp dispatch(%Compound{name: :is_list, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(proper_list?(x, bindings), bindings)

  # -- arithmetic --

  defp dispatch(%Compound{name: :is, args: [result, expr]}, bindings, _db, _barrier) do
    value = Arithmetic.eval(expr, bindings)

    case Bindings.unify(Term, bindings, result, value) do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  defp dispatch(%Compound{name: :"=:=", args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &==/2), bindings)

  defp dispatch(%Compound{name: :"=\\=", args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &!=/2), bindings)

  defp dispatch(%Compound{name: :<, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &</2), bindings)

  defp dispatch(%Compound{name: :>, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &>/2), bindings)

  defp dispatch(%Compound{name: :"=<", args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &<=/2), bindings)

  defp dispatch(%Compound{name: :>=, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &>=/2), bindings)

  # -- exceptions --

  defp dispatch(%Compound{name: :throw, args: [t]}, bindings, _db, _barrier) do
    prolog_throw(Term.resolve_deep(t, bindings))
  end

  defp dispatch(%Compound{name: :catch, args: [g, catcher, recovery]}, bindings, db, barrier) do
    catch_goal(g, catcher, recovery, bindings, db, barrier)
  end

  defp dispatch(%Compound{name: :type_error, args: [type, culprit]}, bindings, _db, _barrier) do
    prolog_throw(
      Exceptions.type_error(
        Bindings.resolve(Term, bindings, type),
        Term.resolve_deep(culprit, bindings)
      )
    )
  end

  defp dispatch(%Compound{name: :domain_error, args: [domain, culprit]}, bindings, _db, _barrier) do
    prolog_throw(
      Exceptions.domain_error(
        Bindings.resolve(Term, bindings, domain),
        Term.resolve_deep(culprit, bindings)
      )
    )
  end

  defp dispatch(%Compound{name: :instantiation_error, args: [_]}, _bindings, _db, _barrier) do
    prolog_throw(Exceptions.instantiation_error())
  end

  # -- copy_term/2 --

  defp dispatch(%Compound{name: :copy_term, args: [t, copy]}, bindings, _db, _barrier) do
    fresh = t |> Term.resolve_deep(bindings) |> Term.fresh_copy()

    case Bindings.unify(Term, bindings, copy, fresh) do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  # -- lists / io, then user-defined predicates --

  defp dispatch(%Compound{name: name, args: args}, bindings, db, _barrier) do
    with :not_handled <- Lists.dispatch(name, length(args), args),
         :not_handled <- Io.dispatch(name, length(args), args) do
      solve_user_predicate(name, args, bindings, db)
    else
      goal_fun when is_function(goal_fun, 1) -> goal_fun.(bindings)
    end
  end

  defp dispatch(atom, bindings, db, _barrier) when is_atom(atom) do
    case Io.dispatch(atom, 0, []) do
      :not_handled -> solve_user_predicate(atom, [], bindings, db)
      goal_fun -> goal_fun.(bindings)
    end
  end

  # ---- helpers ---------------------------------------------------------------

  defp bool_goal(true, bindings), do: Tree.unit().(bindings)
  defp bool_goal(false, bindings), do: Tree.fail().(bindings)

  defp structurally_equal?(a, b, bindings) do
    Term.structurally_equal?(Term.resolve_deep(a, bindings), Term.resolve_deep(b, bindings))
  end

  defp proper_list?(x, bindings) do
    case Bindings.resolve(Term, bindings, x) do
      [] -> true
      [_ | t] -> proper_list?(t, bindings)
      _ -> false
    end
  end

  defp if_then_else(cond_, then_, else_, bindings, db, barrier) do
    cond_barrier = make_ref()
    cond_stream = guard_cut(goal(cond_, db, cond_barrier).(bindings), cond_barrier)

    case Tree.next(cond_stream) do
      {:solution, cond_bindings, _rest} -> goal(then_, db, barrier).(cond_bindings)
      :empty -> goal(else_, db, barrier).(bindings)
    end
  end

  defp negation_as_failure(g, bindings, db) do
    inner_barrier = make_ref()
    stream = guard_cut(goal(g, db, inner_barrier).(bindings), inner_barrier)

    case Tree.next(stream) do
      {:solution, _bindings, _rest} -> Tree.fail().(bindings)
      :empty -> Tree.unit().(bindings)
    end
  end

  defp build_call(g, [], _bindings), do: g

  defp build_call(g, extra, bindings) do
    case Bindings.resolve(Term, bindings, g) do
      %Compound{name: name, args: args} -> %Compound{name: name, args: args ++ extra}
      atom when is_atom(atom) -> %Compound{name: atom, args: extra}
      %Var{} -> prolog_throw(Exceptions.instantiation_error())
    end
  end

  defp catch_goal(g, catcher, recovery, bindings, db, barrier) do
    inner_barrier = make_ref()

    try do
      guard_cut(goal(g, db, inner_barrier).(bindings), inner_barrier)
    catch
      {:aletheia_throw, ball} ->
        case Bindings.unify(Term, bindings, catcher, ball) do
          {:ok, extended} -> goal(recovery, db, barrier).(extended)
          :fail -> prolog_throw(ball)
        end
    end
  end

  defp solve_user_predicate(name, args, bindings, db) do
    arity = length(args)
    clauses = Database.clauses_for(db, name, arity)

    if clauses == [] do
      indicator = %Compound{name: :/, args: [name, arity]}
      prolog_throw(Exceptions.existence_error(:procedure, indicator))
    else
      call_term = if arity == 0, do: name, else: %Compound{name: name, args: args}
      try_clauses(clauses, call_term, bindings, db)
    end
  end

  defp try_clauses(clauses, call_term, bindings, db) do
    barrier = make_ref()

    stream =
      Enum.reduce(clauses, Tree.fail(), fn clause, acc ->
        Tree.disjunction(acc, clause_goal(clause, call_term, db, barrier))
      end)

    guard_cut(stream.(bindings), barrier)
  end

  defp clause_goal({head, body}, call_term, db, barrier) do
    fn bindings ->
      %Compound{args: [fresh_head, fresh_body]} =
        Term.fresh_copy(%Compound{name: :"$clause", args: [head, body]})

      case Bindings.unify(Term, bindings, call_term, fresh_head) do
        {:ok, extended} -> goal(fresh_body, db, barrier).(extended)
        :fail -> Tree.fail().(bindings)
      end
    end
  end

  @spec prolog_throw(term()) :: no_return()
  defp prolog_throw(term), do: Exceptions.prolog_throw(term)
end
