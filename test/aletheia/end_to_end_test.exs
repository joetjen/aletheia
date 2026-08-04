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

  describe "predicates from episteme's v0.2-v0.5 work (see DESIGN.md's episteme_v0_2_completed and later)" do
    test "ignore/1 and unify_with_occurs_check/2" do
      {:ok, db} = Aletheia.consult_string("")

      assert {:ok, [%{}]} = Aletheia.query("ignore(fail)", db)
      assert {:ok, []} = Aletheia.query("unify_with_occurs_check(X, f(X))", db)
    end

    test "standard order of terms, both as goals and via the @<//@>//@=<//@>= reader syntax" do
      {:ok, db} = Aletheia.consult_string("")

      assert {:ok, []} = Aletheia.query("zzz @< aaa", db)
      assert {:ok, [%{}]} = Aletheia.query("aaa @< zzz", db)
      assert {:ok, [%{"Order" => :<}]} = Aletheia.query("compare(Order, aaa, zzz)", db)
    end

    test "term inspection: functor/3, arg/3, univ/2 (=.. not reader-supported yet), ground/1" do
      {:ok, db} = Aletheia.consult_string("")

      assert {:ok, [%{"Name" => :foo, "Arity" => 2}]} =
               Aletheia.query("functor(foo(1,2), Name, Arity)", db)

      assert {:ok, [%{"A" => 2}]} = Aletheia.query("arg(2, foo(1,2), A)", db)
      assert {:ok, [%{"L" => [:foo, 1, 2]}]} = Aletheia.query("univ(foo(1,2), L)", db)
      assert {:ok, [%{}]} = Aletheia.query("ground(foo(1,2))", db)
      assert {:ok, []} = Aletheia.query("ground(foo(1,X))", db)
    end

    test "dynamic database round-out: dynamic/1, abolish/1, clause/2" do
      {:ok, db} = Aletheia.consult_string("")

      assert {:ok, [%{}]} = Aletheia.query("dynamic(p/1)", db)
      assert {:ok, []} = Aletheia.query("p(1)", db)
      assert {:ok, %{}} = Aletheia.query_once("assertz(p(1))", db)
      assert {:ok, [%{"B" => true}]} = Aletheia.query("clause(p(1), B)", db)
      assert {:ok, [%{}]} = Aletheia.query("abolish(p/1)", db)
      assert {:error, _} = Aletheia.query("p(1)", db)
    end

    test "the v0.2 list-predicate family: msort/2, sort/2, permutation/2, exclude/3" do
      {:ok, db} = Aletheia.consult_string("small(X) :- X < 3.")

      assert {:ok, [%{"L" => [1, 1, 2, 3]}]} = Aletheia.query("msort([3,1,2,1], L)", db)
      assert {:ok, [%{"L" => [1, 2, 3]}]} = Aletheia.query("sort([3,1,2,1], L)", db)
      assert {:ok, [%{"L" => [3, 4, 5]}]} = Aletheia.query("exclude(small, [1,2,3,4,5], L)", db)
    end

    test "bagof/3 and setof/3 -- fail (not L = []) on no solutions, unlike findall/3" do
      {:ok, db} =
        Aletheia.consult_string("likes(mary, apples). likes(mary, pears). likes(john, apples).")

      assert {:ok, solutions} = Aletheia.query("bagof(X, likes(mary, X), L)", db)
      assert [%{"L" => [:apples, :pears]}] = solutions

      assert {:ok, []} = Aletheia.query("bagof(X, likes(nobody, X), L)", db)
      assert {:ok, [%{"L" => []}]} = Aletheia.query("findall(X, likes(nobody, X), L)", db)
    end

    test "the atom/number/string conversion family: atom_codes, atom_concat, sub_atom, atom_string, string_concat" do
      {:ok, db} = Aletheia.consult_string("")

      assert {:ok, [%{"X" => :foobar}]} = Aletheia.query("atom_concat(foo, bar, X)", db)
      assert {:ok, [%{"Sub" => :bc}]} = Aletheia.query("sub_atom(abc, 1, 2, 0, Sub)", db)
      assert {:ok, [%{"S" => "hello"}]} = Aletheia.query("atom_string(hello, S)", db)

      assert {:ok, [%{"X" => "foobar"}]} =
               Aletheia.query("string_concat(\"foo\", \"bar\", X)", db)
    end

    test "real strings: literal syntax, string/1, unification, standard order" do
      {:ok, db} = Aletheia.consult_string("")

      assert {:ok, [%{"X" => "hi"}]} = Aletheia.query("X = \"hi\"", db)
      assert {:ok, [%{}]} = Aletheia.query("string(\"hi\")", db)
      assert {:ok, []} = Aletheia.query("string(hi)", db)
      assert {:ok, []} = Aletheia.query("\"hi\" = hi", db)
    end

    test "format/2 with a real string format and mixed directives" do
      {:ok, db} = Aletheia.consult_string("")
      assert {:ok, [%{}]} = Aletheia.query("format(\"~w and ~d~n\", [hello, 42])", db)
    end

    test "DCG: a grammar rule defined in source, run via phrase/2,3" do
      {:ok, db} =
        Aletheia.consult_string("""
        greeting --> [hello], [world].
        digit(D) --> [D], { integer(D) }.
        """)

      assert {:ok, [%{}]} = Aletheia.query("phrase(greeting, [hello, world])", db)
      assert {:ok, []} = Aletheia.query("phrase(greeting, [bye])", db)
      assert {:ok, [%{"X" => 5}]} = Aletheia.query("phrase(digit(X), [5])", db)
      assert {:ok, []} = Aletheia.query("phrase(digit(X), [not_a_digit])", db)

      assert {:ok, [%{"Rest" => [:extra]}]} =
               Aletheia.query("phrase(greeting, [hello, world, extra], Rest)", db)
    end
  end
end
