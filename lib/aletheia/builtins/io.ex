defmodule Aletheia.Builtins.Io do
  @moduledoc """
  Minimal v0.1 I/O: `write/1 writeln/1 print/1 nl/0` -- canonical
  `functor(args)` text via `Aletheia.Term.to_text/1` (no operator-aware
  pretty-printing yet, DESIGN.md's `write/1` note only asks for "minimal
  REPL output need"). Each succeeds exactly once, side effect aside.
  """

  alias Aletheia.Term
  alias Ichor.Backtrack.Tree

  @spec dispatch(atom(), non_neg_integer(), [term()]) :: Ichor.Backtrack.goal() | :not_handled
  def dispatch(:write, 1, [t]), do: fn b -> print_term(t, b, "") end
  def dispatch(:writeln, 1, [t]), do: fn b -> print_term(t, b, "\n") end
  def dispatch(:print, 1, [t]), do: fn b -> print_term(t, b, "") end

  def dispatch(:nl, 0, []),
    do: fn b ->
      IO.write("\n")
      Tree.unit().(b)
    end

  def dispatch(_, _, _), do: :not_handled

  defp print_term(t, bindings, suffix) do
    IO.write(Term.to_text(Term.resolve_deep(t, bindings)) <> suffix)
    Tree.unit().(bindings)
  end
end
