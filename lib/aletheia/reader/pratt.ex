defmodule Aletheia.Reader.Pratt do
  @moduledoc """
  The `@native(...)` callback `lib/aletheia/reader/grammar.aether`'s
  `term`/`arg_term` rules delegate to -- precedence-climbing over
  `context.operators` (an `Ichor.Toolkit.Pratt` table), mirroring
  ichor's own `test/support/prolog_grammar.ex` worked example, with one
  addition: `parse_arg_term/4` raises the floor to `@arg_min_prec`,
  ISO's real "an argument is a term of priority =< 999" rule
  (`Ichor.Toolkit.Pratt.parse/4`'s own `min_prec` parameter), so `,` --
  a genuine operator here, unlike that fixture's grammar-structural
  comma -- never gets swallowed into a single argument or list element.
  """

  alias Grammar.VM.Token
  alias Ichor.Toolkit.Pratt

  @doc "ISO Prolog priority (bigger number = looser binding) -> Ichor.Toolkit.Pratt precedence (bigger = tighter)."
  @spec iso_to_pratt(non_neg_integer()) :: non_neg_integer()
  def iso_to_pratt(iso_prec), do: 1200 - iso_prec

  @arg_min_prec 1200 - 999

  @doc "Full-priority parse -- rule bodies, directive goals, parenthesized sub-terms."
  def parse_term(stream, pos, context, deps), do: do_parse(stream, pos, context, deps, 0)

  @doc "Restricted-priority parse (ISO's argument/list-element rule) -- compound arguments, list elements."
  def parse_arg_term(stream, pos, context, deps),
    do: do_parse(stream, pos, context, deps, @arg_min_prec)

  defp do_parse(stream, pos, context, %{primary: primary}, min_prec) do
    callbacks = %{
      peek_op: fn pos -> operator_at(stream, pos, context.operators) end,
      parse_primary: fn pos -> primary.(stream, skip_trivia(stream, pos)) end,
      build: fn
        :prefix, op, [arg] -> {:rule, :compound, %{functor: {:token, :OP, op}, args: [arg]}}
        :infix, op, [l, r] -> {:rule, :compound, %{functor: {:token, :OP, op}, args: [l, r]}}
      end
    }

    Pratt.parse(context.operators, pos, callbacks, min_prec)
  end

  defp operator_at(stream, pos, table) do
    pos = skip_trivia(stream, pos)

    with true <- pos < tuple_size(stream),
         %Token{name: name, text: text} <- elem(stream, pos),
         true <- name in [:OP, :ATOM, :COMMA, :SEMI],
         true <- Map.has_key?(table, text) do
      {text, pos + 1}
    else
      _ -> nil
    end
  end

  defp skip_trivia(stream, pos) do
    case pos < tuple_size(stream) && elem(stream, pos) do
      %Token{name: :TRIVIA} -> skip_trivia(stream, pos + 1)
      _ -> pos
    end
  end
end
