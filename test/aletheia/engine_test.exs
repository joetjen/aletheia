defmodule Aletheia.EngineTest do
  use ExUnit.Case, async: true
  import Aletheia.QueryHelper

  describe "unification and backtracking over facts" do
    test "a query with one variable backtracks through every matching fact, in declared order" do
      src = """
      parent(tom, bob).
      parent(tom, liz).
      parent(bob, ann).
      parent(bob, pat).
      """

      assert solutions(src, "parent(tom, Y)") == [%{"Y" => :bob}, %{"Y" => :liz}]
      assert solutions(src, "parent(tom, ann)") == []
    end

    test "a rule sequences subgoals via conjunction" do
      src = """
      parent(tom, bob).
      parent(bob, ann).
      parent(bob, pat).
      grandparent(X, Z) :- parent(X, Y), parent(Y, Z).
      """

      assert solutions(src, "grandparent(tom, W)") == [%{"W" => :ann}, %{"W" => :pat}]
    end
  end

  describe "if-then-else" do
    test "commits to the first solution of the condition" do
      src = """
      sign(X, R) :- (X > 0 -> R = pos ; X < 0 -> R = neg ; R = zero).
      """

      assert solutions(src, "sign(5, R)") == [%{"R" => :pos}]
      assert solutions(src, "sign(-5, R)") == [%{"R" => :neg}]
      assert solutions(src, "sign(0, R)") == [%{"R" => :zero}]
    end

    test "if-then without else fails when the condition fails" do
      src = "t(X) :- (X > 0 -> true)."
      assert solutions(src, "t(-1)") == []
      assert solutions(src, "t(1)") == [%{}]
    end
  end

  describe "negation as failure" do
    test "\\+ succeeds when the goal has no solution, without binding anything" do
      src = """
      even(X) :- 0 is X mod 2.
      odd(X) :- \\+ even(X).
      """

      assert solutions(src, "odd(3)") == [%{}]
      assert solutions(src, "odd(4)") == []
    end
  end

  describe "arithmetic" do
    test "is/2 and standard precedence" do
      assert solutions("", "X is 2 + 3 * 4") == [%{"X" => 14}]
      assert solutions("", "X is 7 // 2") == [%{"X" => 3}]
      assert solutions("", "X is 7 / 2") == [%{"X" => 3.5}]
      assert solutions("", "X is 2 ** 10") == [%{"X" => 1024}]
      assert solutions("", "X is -(3)") == [%{"X" => -3}]
    end

    test "arithmetic comparisons" do
      assert solutions("", "3 =:= 3.0") == [%{}]
      assert solutions("", "3 < 4") == [%{}]
      assert solutions("", "4 < 3") == []
    end
  end

  describe "type checks and unify/compare" do
    test "var/nonvar" do
      # X stays unbound, so it shows up bound to itself in the answer --
      # exactly real Prolog's own `?- var(X).` toplevel behavior (`X = _G1`),
      # not omitted.
      assert [%{"X" => %Aletheia.Term.Var{}}] = solutions("", "var(X)")
      assert solutions("", "nonvar(foo)") == [%{}]
      assert solutions("", "var(foo)") == []
    end

    test "==/2 and \\==/2 respect variable identity and numeric type" do
      assert solutions("", "foo(X, X) == foo(1, 1)") == []
      assert solutions("", "X = 1, foo(X, X) == foo(1, 1)") == [%{"X" => 1}]
      assert solutions("", "1 == 1.0") == []
      assert solutions("", "1 \\== 1.0") == [%{}]
    end

    test "=/2 unifies, \\=/2 checks non-unifiability without binding" do
      assert solutions("", "X = foo(1, 2)") == [
               %{"X" => %Aletheia.Term.Compound{name: :foo, args: [1, 2]}}
             ]

      assert solutions("", "1 \\= 2") == [%{}]
      # an unbound X unifies with anything, so \=/2 fails here -- it only
      # succeeds once X is already bound to something incompatible.
      assert solutions("", "X \\= 1") == []
      assert solutions("", "X = 2, X \\= 1") == [%{"X" => 2}]
    end
  end

  describe "exceptions" do
    test "catch/3 catches a thrown error and unifies the catcher" do
      src = "safe_div(X, Y, R) :- catch(R is X / Y, error(_, _), R = undefined)."
      assert solutions(src, "safe_div(10, 2, R)") == [%{"R" => 5}]
      assert solutions(src, "safe_div(10, 0, R)") == [%{"R" => :undefined}]
    end

    test "an uncaught throw surfaces as an engine-level error" do
      assert {:error, _} = solutions("", "throw(my_error)")
    end

    test "calling an undefined predicate raises existence_error" do
      assert {:error, %Aletheia.Term.Compound{name: :error, args: [formal, _]}} =
               solutions("", "nonexistent_pred(1, 2)")

      assert %Aletheia.Term.Compound{name: :existence_error, args: [:procedure, _]} = formal
    end
  end

  describe "copy_term/2" do
    test "renames unbound variables apart" do
      assert [%{"Y" => %Aletheia.Term.Compound{name: :f, args: [a, b]}}] =
               solutions("", "copy_term(f(X, X), Y)")

      assert a.ref == b.ref
    end
  end
end
