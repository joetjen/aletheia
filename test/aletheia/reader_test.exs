defmodule Aletheia.ReaderTest do
  use ExUnit.Case, async: true

  alias Aletheia.Reader
  alias Episteme.Term.Compound

  describe "facts" do
    test "a ground compound term" do
      assert {:ok, [{:fact, %Compound{name: :father, args: [:tom, :bob]}}], _ctx} =
               Reader.consult_string("father(tom, bob).")
    end

    test "several facts in one file, in order" do
      assert {:ok, facts, _ctx} =
               Reader.consult_string("""
               father(tom, bob).
               father(bob, ann).
               """)

      assert [
               {:fact, %Compound{name: :father, args: [:tom, :bob]}},
               {:fact, %Compound{name: :father, args: [:bob, :ann]}}
             ] = facts
    end

    test "quoted atoms" do
      assert {:ok, [{:fact, %Compound{name: :likes, args: [:"John Doe", :pizza]}}], _ctx} =
               Reader.consult_string("likes('John Doe', pizza).")
    end
  end

  describe "rules, conjunction, and variable scoping" do
    test "a rule's head and body share the same variable, freshened once per clause" do
      assert {:ok, [{:rule, head, body}], _ctx} =
               Reader.consult_string("grandparent(X, Z) :- father(X, Y), father(Y, Z).")

      assert %Compound{name: :grandparent, args: [x1, z1]} = head
      assert %Compound{name: :",", args: [%Compound{name: :father, args: [x2, y1]}, rest]} = body
      assert %Compound{name: :father, args: [y2, z2]} = rest

      assert x1.ref == x2.ref
      assert y1.ref == y2.ref
      assert z1.ref == z2.ref
      refute x1.ref == y1.ref
    end

    test "the same variable name in a later clause is a different variable" do
      assert {:ok, [{:rule, %Compound{args: [x1]}, _}, {:rule, %Compound{args: [x2]}, _}], _ctx} =
               Reader.consult_string("""
               p(X) :- father(X, bob).
               q(X) :- father(X, ann).
               """)

      refute x1.ref == x2.ref
    end
  end

  describe "operator precedence" do
    test "* binds tighter than +, both looser than is" do
      assert {:ok, [{:rule, _head, body}], _ctx} =
               Reader.consult_string("age(N) :- N is 2 + 3 * 4.")

      assert %Compound{
               name: :is,
               args: [_n, %Compound{name: :+, args: [2, %Compound{name: :*, args: [3, 4]}]}]
             } = body
    end

    test "unary minus (prefix) binds tighter than binary minus (infix), same operator name" do
      assert {:ok, [{:rule, _head, body}], _ctx} = Reader.consult_string("neg(N) :- N is -5 - 2.")

      assert %Compound{
               name: :is,
               args: [_n, %Compound{name: :-, args: [%Compound{name: :-, args: [5]}, 2]}]
             } = body
    end

    test "comma is a real xfy operator: a, (b ; c) composes without extra parens around the whole body" do
      assert {:ok, [{:rule, _head, body}], _ctx} = Reader.consult_string("p :- a, (b ; c), !.")

      assert %Compound{
               name: :",",
               args: [
                 :a,
                 %Compound{name: :",", args: [%Compound{name: :";", args: [:b, :c]}, :!]}
               ]
             } = body
    end
  end

  describe "lists" do
    test "proper and improper list syntax" do
      assert {:ok, [{:fact, %Compound{args: [[]]}}], _ctx} = Reader.consult_string("empty([]).")

      assert {:ok, [{:fact, %Compound{args: [[1, 2, 3]]}}], _ctx} =
               Reader.consult_string("l([1,2,3]).")

      assert {:ok, [{:fact, %Compound{args: [[1, 2 | tail]]}}], _ctx} =
               Reader.consult_string("l([1,2|T]).")

      assert tail.name == "T"
    end
  end

  describe "op/3 directives genuinely extend the operator table mid-file" do
    test "an operator not in the default table can't be used before it's declared" do
      assert {:error, _} = Reader.consult_string("weird(X) :- X is 2 @@ 3.")
    end

    test "after a directive declares it, later clauses can use it" do
      assert {:ok, results, _ctx} =
               Reader.consult_string("""
               :- op(200, xfy, @@).
               weird(X) :- X is 2 @@ 3.
               """)

      assert [
               {:directive, %Compound{name: :op, args: [200, :xfy, :"@@"]}},
               {:rule, %Compound{name: :weird}, body}
             ] = results

      assert %Compound{name: :is, args: [_, %Compound{name: :"@@", args: [2, 3]}]} = body
    end
  end
end
