defmodule Aletheia.TermTest do
  use ExUnit.Case, async: true

  alias Aletheia.Term
  alias Aletheia.Term.Compound
  alias Ichor.Backtrack.Bindings

  describe "Ichor.Backtrack.Term behaviour" do
    test "variables are identified by ref, everything else is atomic" do
      var = Term.new_var("X")
      refute Term.variable?(:atom)
      assert Term.variable?(var)
      assert Term.var_id(var) == var.ref
    end

    test "compounds deconstruct/reconstruct via functor+args" do
      c = %Compound{name: :foo, args: [1, 2]}
      assert Term.compound?(c)
      assert Term.deconstruct(c) == {:foo, [1, 2]}
      assert Term.reconstruct(:foo, [1, 2]) == c
    end

    test "a non-empty list decomposes as the '.'/2 cons functor, [] stays atomic" do
      refute Term.compound?([])
      assert Term.compound?([1, 2])
      assert Term.deconstruct([1, 2]) == {:., [1, [2]]}
      assert Term.reconstruct(:., [1, [2]]) == [1, 2]
    end
  end

  describe "unification (delegated to Ichor.Backtrack.Bindings, exercised through Aletheia.Term)" do
    test "list unification binds head/tail through the cons encoding" do
      h = Term.new_var("H")
      t = Term.new_var("T")
      assert {:ok, bindings} = Bindings.unify(Term, Bindings.new(), [h | t], [1, 2, 3])
      assert Bindings.resolve(Term, bindings, h) == 1
      assert Bindings.resolve(Term, bindings, t) == [2, 3]
    end

    test "[] does not unify with a non-empty list" do
      assert Bindings.unify(Term, Bindings.new(), [], [1]) == :fail
    end

    test "compound unification requires matching functor and arity" do
      a = %Compound{name: :foo, args: [1, 2]}
      b = %Compound{name: :foo, args: [1, 2]}
      c = %Compound{name: :bar, args: [1, 2]}
      assert {:ok, _} = Bindings.unify(Term, Bindings.new(), a, b)
      assert Bindings.unify(Term, Bindings.new(), a, c) == :fail
    end
  end

  describe "resolve_deep/2" do
    test "resolves variables nested inside compounds and lists" do
      x = Term.new_var("X")
      {:ok, bindings} = Bindings.unify(Term, Bindings.new(), x, 42)
      term = %Compound{name: :f, args: [x, [x, 1]]}
      assert Term.resolve_deep(term, bindings) == %Compound{name: :f, args: [42, [42, 1]]}
    end
  end

  describe "fresh_copy/1" do
    test "renames every distinct variable apart while preserving sharing" do
      x = Term.new_var("X")
      term = %Compound{name: :f, args: [x, x]}
      %Compound{args: [a, b]} = Term.fresh_copy(term)
      assert a.ref == b.ref
      refute a.ref == x.ref
    end
  end

  describe "structurally_equal?/2" do
    test "same shape and value is equal" do
      assert Term.structurally_equal?(%Compound{name: :f, args: [1, :a]}, %Compound{
               name: :f,
               args: [1, :a]
             })
    end

    test "an integer never equals a float" do
      refute Term.structurally_equal?(1, 1.0)
    end

    test "two distinct unbound variables are not equal" do
      refute Term.structurally_equal?(Term.new_var("X"), Term.new_var("Y"))
    end

    test "lists compare element-wise" do
      assert Term.structurally_equal?([1, 2, 3], [1, 2, 3])
      refute Term.structurally_equal?([1, 2], [1, 2, 3])
    end
  end
end
