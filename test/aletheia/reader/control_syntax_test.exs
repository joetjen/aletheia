defmodule Aletheia.Reader.ControlSyntaxTest do
  use ExUnit.Case, async: true

  alias Aletheia.Reader.ControlSyntax
  alias Episteme.Term.Compound

  describe "simple control constructs and comparisons" do
    test "translates every ISO-punctuation name to Episteme's own" do
      cases = [
        {%Compound{name: :",", args: [:a, :b]}, %Compound{name: :and, args: [:a, :b]}},
        {%Compound{name: :";", args: [:a, :b]}, %Compound{name: :or, args: [:a, :b]}},
        {%Compound{name: :"\\+", args: [:a]}, %Compound{name: :not, args: [:a]}},
        {%Compound{name: :=, args: [:a, :b]}, %Compound{name: :unify, args: [:a, :b]}},
        {%Compound{name: :"\\=", args: [:a, :b]}, %Compound{name: :not_unify, args: [:a, :b]}},
        {%Compound{name: :==, args: [:a, :b]}, %Compound{name: :equal, args: [:a, :b]}},
        {%Compound{name: :"\\==", args: [:a, :b]}, %Compound{name: :not_equal, args: [:a, :b]}},
        {%Compound{name: :"=:=", args: [1, 2]}, %Compound{name: :numeric_equal, args: [1, 2]}},
        {%Compound{name: :"=\\=", args: [1, 2]},
         %Compound{name: :numeric_not_equal, args: [1, 2]}},
        {%Compound{name: :"=<", args: [1, 2]}, %Compound{name: :less_or_equal, args: [1, 2]}},
        {%Compound{name: :>=, args: [1, 2]}, %Compound{name: :greater_or_equal, args: [1, 2]}}
      ]

      for {input, expected} <- cases do
        assert ControlSyntax.to_goal(input) == expected
      end
    end

    test "! (cut) translates to the bare :cut atom" do
      assert ControlSyntax.to_goal(:!) == :cut
    end

    test "a bare -> without a wrapping ; translates to if_then/2" do
      assert ControlSyntax.to_goal(%Compound{name: :->, args: [:a, :b]}) ==
               %Compound{name: :if_then, args: [:a, :b]}
    end

    test "arithmetic functors that were never control syntax pass through unchanged" do
      term = %Compound{name: :+, args: [1, %Compound{name: :*, args: [2, 3]}]}
      assert ControlSyntax.to_goal(term) == term
    end

    test "non-compound, non-cut terms (atoms, numbers, variables) pass through unchanged" do
      assert ControlSyntax.to_goal(:hello) == :hello
      assert ControlSyntax.to_goal(42) == 42
    end
  end

  describe "if-then-else" do
    test "(Cond -> Then ; Else) becomes if_then_else/3, not or(if_then(...), Else)" do
      nested = %Compound{
        name: :";",
        args: [%Compound{name: :->, args: [:cond_, :then_]}, :else_]
      }

      assert ControlSyntax.to_goal(nested) ==
               %Compound{name: :if_then_else, args: [:cond_, :then_, :else_]}
    end

    test "translation recurses into the condition/then/else branches themselves" do
      nested = %Compound{
        name: :";",
        args: [
          %Compound{
            name: :->,
            args: [%Compound{name: :=, args: [:x, 1]}, %Compound{name: :",", args: [:a, :b]}]
          },
          %Compound{name: :"\\+", args: [:c]}
        ]
      }

      assert ControlSyntax.to_goal(nested) ==
               %Compound{
                 name: :if_then_else,
                 args: [
                   %Compound{name: :unify, args: [:x, 1]},
                   %Compound{name: :and, args: [:a, :b]},
                   %Compound{name: :not, args: [:c]}
                 ]
               }
    end
  end

  describe "recursion into ordinary nested goals" do
    test "translates control constructs nested inside \\+ and other goals" do
      term = %Compound{
        name: :"\\+",
        args: [%Compound{name: :",", args: [:a, %Compound{name: :";", args: [:b, :c]}]}]
      }

      assert ControlSyntax.to_goal(term) ==
               %Compound{
                 name: :not,
                 args: [%Compound{name: :and, args: [:a, %Compound{name: :or, args: [:b, :c]}]}]
               }
    end
  end
end
