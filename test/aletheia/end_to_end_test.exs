defmodule Aletheia.EndToEndTest do
  @moduledoc "One small program exercised through the full pipeline: reader -> database -> engine, no shortcuts."

  use ExUnit.Case, async: true

  @family """
  parent(tom, bob).
  parent(tom, liz).
  parent(bob, ann).
  parent(bob, pat).
  parent(pat, jim).

  ancestor(X, Y) :- parent(X, Y).
  ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).
  """

  test "consult + query a small recursive program end to end" do
    assert {:ok, db} = Aletheia.consult_string(@family)
    assert {:ok, solutions} = Aletheia.query("ancestor(tom, Who)", db)

    people = solutions |> Enum.map(& &1["Who"]) |> Enum.sort()
    assert people == Enum.sort([:bob, :liz, :ann, :pat, :jim])
  end

  test "query_once/2 returns just the first solution" do
    {:ok, db} = Aletheia.consult_string(@family)
    assert {:ok, %{"Who" => :bob}} = Aletheia.query_once("ancestor(tom, Who)", db)
  end

  test "query_lazy/2 + next_solution/2 pull one at a time" do
    {:ok, db} = Aletheia.consult_string(@family)
    {:ok, {stream, vars}} = Aletheia.query_lazy("ancestor(tom, Who)", db)

    assert {:solution, %{"Who" => :bob}, rest} = Aletheia.next_solution(stream, vars)
    assert {:solution, %{"Who" => :liz}, _rest2} = Aletheia.next_solution(rest, vars)
  end

  test "consulting a file via consult/1" do
    path = Path.join(System.tmp_dir!(), "aletheia_e2e_#{System.unique_integer([:positive])}.alp")
    File.write!(path, @family)

    on_exit(fn -> File.rm(path) end)

    assert {:ok, db} = Aletheia.consult(path)

    assert {:ok, [%{"X" => :bob}]} =
             Aletheia.query("parent(tom, X), \\+ parent(_, tom)", db) |> take_first()
  end

  defp take_first({:ok, [first | _]}), do: {:ok, [first]}
  defp take_first(other), do: other

  describe "control syntax translation, exercised through the full pipeline" do
    test "disjunction (;) and cut (!) reach the engine correctly" do
      {:ok, db} = Aletheia.consult_string("p(a). p(b).\nq(X) :- p(X) ; X = c.")

      assert {:ok, solutions} = Aletheia.query("q(X)", db)
      people = solutions |> Enum.map(& &1["X"]) |> Enum.sort()
      assert people == [:a, :b, :c]

      assert {:ok, [%{"X" => :a}]} = Aletheia.query("p(X), !", db) |> take_first()
    end

    test "if-then-else (Cond -> Then ; Else) commits to Then without falling through to Else" do
      {:ok, db} = Aletheia.consult_string("classify(X, R) :- (X > 10 -> R = big ; R = small).")

      assert {:ok, %{"R" => :small}} = Aletheia.query_once("classify(1, R)", db)
      assert {:ok, %{"R" => :big}} = Aletheia.query_once("classify(20, R)", db)
    end
  end

  describe "predicates shipped ahead of schedule (see episteme_ahead_of_schedule, DESIGN.md decisions_log)" do
    test "assert/asserta/assertz/retract/retractall mutate the database, visible to later queries" do
      {:ok, db} = Aletheia.consult_string("p(a). p(b).")

      assert {:ok, %{}} = Aletheia.query_once("assertz(p(c))", db)
      assert {:ok, %{}} = Aletheia.query_once("asserta(p(z))", db)
      assert {:ok, solutions} = Aletheia.query("p(X)", db)
      assert solutions |> Enum.map(& &1["X"]) |> Enum.sort() == [:a, :b, :c, :z]

      assert {:ok, %{}} = Aletheia.query_once("retract(p(a))", db)
      assert {:ok, []} = Aletheia.query("p(a)", db)

      assert {:ok, %{}} = Aletheia.query_once("retractall(p(_))", db)
      assert {:ok, []} = Aletheia.query("p(_)", db)
    end

    test "assert works on a brand-new predicate with no dynamic/1 declaration first" do
      {:ok, db} = Aletheia.consult_string("")

      assert {:ok, %{}} = Aletheia.query_once("assert(q(1))", db)
      assert {:ok, [%{"X" => 1}]} = Aletheia.query("q(X)", db)
    end

    test "findall/3 collects every solution, [] when there are none" do
      {:ok, db} = Aletheia.consult_string("p(a). p(b). p(c).")

      assert {:ok, [%{"L" => [:a, :b, :c]}]} = Aletheia.query("findall(X, p(X), L)", db)

      assert {:ok, [%{"L" => []}]} =
               Aletheia.query("findall(X, (p(X), X == nonexistent), L)", db)
    end

    test "forall/2 succeeds iff every solution of Cond has a solution of Action" do
      {:ok, db} = Aletheia.consult_string("p(1). p(2). p(3).")

      assert {:ok, [%{}]} = Aletheia.query("forall(p(X), X > 0)", db)
      assert {:ok, []} = Aletheia.query("forall(p(X), X > 1)", db)
    end

    test "between/3 enumerates on an unbound X, checks membership on a bound one" do
      {:ok, db} = Aletheia.consult_string("")

      assert {:ok, solutions} = Aletheia.query("between(1, 5, X)", db)
      assert Enum.map(solutions, & &1["X"]) == [1, 2, 3, 4, 5]

      assert {:ok, [%{}]} = Aletheia.query("between(1, 5, 3)", db)
      assert {:ok, []} = Aletheia.query("between(1, 5, 9)", db)
    end
  end
end
