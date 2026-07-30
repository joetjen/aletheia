defmodule Aletheia.Builtins.Lists do
  @moduledoc """
  The v0.1 list predicate family -- `length/2 append/3 member/2
  reverse/2 nth0/3 nth1/3 last/2` -- over native Elixir lists (DESIGN.md
  §4: Aletheia lists are plain `[h|t]`, not cons compounds). Same
  hand-rolled-goal style as ichor's own `test/support/prolog.ex`
  (`Prolog.DB.member/2`), generalized to real unification via
  `Ichor.Backtrack.Bindings` instead of hand-built ground terms.
  """

  alias Aletheia.Term
  alias Aletheia.Term.Var
  alias Ichor.Backtrack.{Bindings, Tree}

  @spec dispatch(atom(), non_neg_integer(), [term()]) :: Ichor.Backtrack.goal() | :not_handled
  def dispatch(:length, 2, [list, len]), do: fn b -> length_goal(list, len, b) end
  def dispatch(:append, 3, [a, b, c]), do: fn bindings -> append_goal(a, b, c, bindings) end
  def dispatch(:member, 2, [x, list]), do: fn bindings -> member_goal(x, list, bindings) end
  def dispatch(:reverse, 2, [a, b]), do: fn bindings -> reverse_goal(a, b, bindings) end
  def dispatch(:nth0, 3, [i, list, e]), do: fn bindings -> nth_goal(i, list, e, bindings, 0) end
  def dispatch(:nth1, 3, [i, list, e]), do: fn bindings -> nth_goal(i, list, e, bindings, 1) end
  def dispatch(:last, 2, [list, e]), do: fn bindings -> last_goal(list, e, bindings) end
  def dispatch(_, _, _), do: :not_handled

  defp unify_goal(a, b, bindings) do
    case Bindings.unify(Term, bindings, a, b) do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  defp resolved_list(list, bindings), do: Bindings.resolve(Term, bindings, list)

  defp length_goal(list, len, bindings) do
    case resolved_list(list, bindings) do
      %Var{} ->
        case Bindings.resolve(Term, bindings, len) do
          n when is_integer(n) and n >= 0 ->
            unify_goal(list, List.duplicate(Term.new_var("_"), n), bindings)

          _ ->
            Tree.fail().(bindings)
        end

      resolved ->
        case proper_length(resolved, bindings) do
          {:ok, n} -> unify_goal(len, n, bindings)
          :error -> Tree.fail().(bindings)
        end
    end
  end

  defp proper_length(list, bindings, acc \\ 0) do
    case Bindings.resolve(Term, bindings, list) do
      [] -> {:ok, acc}
      [_ | t] -> proper_length(t, bindings, acc + 1)
      _ -> :error
    end
  end

  defp append_goal(a, b, c, bindings) do
    case resolved_list(a, bindings) do
      %Var{} -> append_by_splitting(a, b, c, bindings)
      [] -> unify_goal(b, c, bindings)
      [h | t] -> append_cons(h, t, b, c, bindings)
      _not_a_list -> Tree.fail().(bindings)
    end
  end

  # `[h | tail_var]` is a deliberately improper list -- `tail_var` is an
  # unbound logic variable, not a list, exactly real Prolog's own
  # `append/3` building a partial list one cons cell at a time as it
  # recurses. Dialyzer's `improper_list_constr` check assumes a cons
  # tail should itself be list-typed, a reasonable default for ordinary
  # Elixir code but not for this domain.
  @dialyzer {:nowarn_function, append_cons: 5}
  defp append_cons(h, t, b, c, bindings) do
    tail_var = Term.new_var("_")
    goal1 = fn bindings -> unify_goal(c, [h | tail_var], bindings) end
    goal2 = fn bindings -> append_goal(t, b, tail_var, bindings) end
    Tree.conjunction(goal1, goal2).(bindings)
  end

  # `A` unbound: enumerate every way to split `C` into `A ++ B`, in order --
  # the classic `append/3` "generate the split" mode.
  defp append_by_splitting(a, b, c, bindings) do
    case resolved_list(c, bindings) do
      %Var{} ->
        Tree.fail().(bindings)

      resolved_c ->
        splits(resolved_c, bindings)
        |> Enum.reduce(Tree.fail(), fn {front, back}, acc ->
          Tree.disjunction(acc, fn bindings ->
            unify_goal_all([{a, front}, {b, back}], bindings)
          end)
        end)
        |> then(& &1.(bindings))
    end
  end

  defp unify_goal_all(pairs, bindings) do
    Enum.reduce(pairs, Tree.unit(), fn {x, y}, acc ->
      Tree.conjunction(acc, fn bindings -> unify_goal(x, y, bindings) end)
    end).(bindings)
  end

  defp splits(list, bindings, front \\ []) do
    case Bindings.resolve(Term, bindings, list) do
      [] ->
        [{Enum.reverse(front), []}]

      [h | t] = l when is_list(t) or t == [] ->
        [{Enum.reverse(front), l} | splits(t, bindings, [h | front])]

      _improper ->
        [{Enum.reverse(front), list}]
    end
  end

  defp member_goal(x, list, bindings) do
    case resolved_list(list, bindings) do
      [h | t] ->
        Tree.disjunction(fn b -> unify_goal(x, h, b) end, fn b -> member_goal(x, t, b) end).(
          bindings
        )

      _ ->
        Tree.fail().(bindings)
    end
  end

  defp reverse_goal(a, b, bindings) do
    case proper_length(a, bindings) do
      {:ok, _} ->
        unify_goal(b, Enum.reverse(Bindings.resolve(Term, bindings, a)), bindings)

      :error ->
        case proper_length(b, bindings) do
          {:ok, _} -> unify_goal(a, Enum.reverse(Bindings.resolve(Term, bindings, b)), bindings)
          :error -> Tree.fail().(bindings)
        end
    end
  end

  defp nth_goal(i, list, e, bindings, base) do
    case resolved_list(list, bindings) do
      resolved when is_list(resolved) -> nth_goal_over(resolved, i, e, bindings, base)
      _not_a_list -> Tree.fail().(bindings)
    end
  end

  defp nth_goal_over(resolved, i, e, bindings, base) do
    case Bindings.resolve(Term, bindings, i) do
      %Var{} ->
        resolved
        |> Enum.with_index(base)
        |> Enum.reduce(Tree.fail(), fn {elem, idx}, acc ->
          Tree.disjunction(acc, fn b -> unify_goal_all([{i, idx}, {e, elem}], b) end)
        end)
        |> then(& &1.(bindings))

      idx when is_integer(idx) ->
        case Enum.at(resolved, idx - base) do
          nil -> Tree.fail().(bindings)
          elem -> unify_goal(e, elem, bindings)
        end

      _ ->
        Tree.fail().(bindings)
    end
  end

  defp last_goal(list, e, bindings) do
    case resolved_list(list, bindings) do
      [] -> Tree.fail().(bindings)
      resolved when is_list(resolved) -> unify_goal(e, List.last(resolved), bindings)
      _ -> Tree.fail().(bindings)
    end
  end
end
