defmodule Aletheia.Builtins.Arithmetic do
  @moduledoc """
  Evaluates a Prolog arithmetic expression term to an Elixir number
  under `bindings` -- `is/2`'s own right-hand side, and both sides of
  every arithmetic comparison (`=:=`, `<`, ...). Raises (via
  `Aletheia.Builtins.Exceptions.prolog_throw/1`) a standard `type_error`
  for anything that isn't a number, a bound variable, or a recognized
  evaluable functor.
  """

  alias Aletheia.Builtins.Exceptions
  alias Aletheia.Term
  alias Aletheia.Term.{Compound, Var}
  alias Ichor.Backtrack.Bindings

  @spec eval(term(), Bindings.t()) :: number()
  def eval(expr, bindings) do
    case Bindings.resolve(Term, bindings, expr) do
      %Var{} ->
        Exceptions.prolog_throw(Exceptions.instantiation_error())

      n when is_number(n) ->
        n

      %Compound{name: name, args: args} ->
        eval_compound(name, Enum.map(args, &eval(&1, bindings)))

      other ->
        Exceptions.prolog_throw(Exceptions.type_error(:evaluable, other))
    end
  end

  defp eval_compound(:+, [a, b]), do: a + b
  defp eval_compound(:-, [a, b]), do: a - b
  defp eval_compound(:*, [a, b]), do: a * b
  defp eval_compound(:/, [a, b]), do: divide(a, b)
  defp eval_compound(:"//", [a, b]), do: int_div(a, b)
  defp eval_compound(:mod, [a, b]), do: floor_mod(a, b)
  defp eval_compound(:rem, [a, b]), do: rem_check(a, b)
  defp eval_compound(:**, [a, b]), do: pow(a, b)
  defp eval_compound(:^, [a, b]), do: pow(a, b)
  defp eval_compound(:abs, [a]), do: abs(a)
  defp eval_compound(:sign, [a]) when a > 0, do: 1
  defp eval_compound(:sign, [a]) when a < 0, do: -1
  defp eval_compound(:sign, [_]), do: 0
  defp eval_compound(:min, [a, b]), do: min(a, b)
  defp eval_compound(:max, [a, b]), do: max(a, b)
  defp eval_compound(:sqrt, [a]), do: :math.sqrt(a)
  defp eval_compound(:-, [a]), do: -a
  defp eval_compound(:+, [a]), do: a

  defp eval_compound(name, args) do
    Exceptions.prolog_throw(Exceptions.type_error(:evaluable, %Compound{name: name, args: args}))
  end

  defp divide(_a, b) when b == 0,
    do: Exceptions.prolog_throw(Exceptions.domain_error(:non_zero, 0))

  defp divide(a, b) do
    if is_integer(a) and is_integer(b) and rem(a, b) == 0, do: div(a, b), else: a / b
  end

  defp int_div(_a, 0), do: Exceptions.prolog_throw(Exceptions.domain_error(:non_zero, 0))
  defp int_div(a, b) when is_integer(a) and is_integer(b), do: Integer.floor_div(a, b)

  defp floor_mod(_a, 0), do: Exceptions.prolog_throw(Exceptions.domain_error(:non_zero, 0))
  defp floor_mod(a, b) when is_integer(a) and is_integer(b), do: Integer.mod(a, b)

  defp rem_check(_a, 0), do: Exceptions.prolog_throw(Exceptions.domain_error(:non_zero, 0))
  defp rem_check(a, b) when is_integer(a) and is_integer(b), do: rem(a, b)

  defp pow(a, b) when is_integer(a) and is_integer(b) and b >= 0, do: trunc(:math.pow(a, b))
  defp pow(a, b), do: :math.pow(a, b)

  @doc "`is/2`, `=:=/2`, `<`/2 and friends share this: evaluate both sides then apply `cmp`."
  @spec compare(term(), term(), Bindings.t(), (number(), number() -> boolean())) :: boolean()
  def compare(a, b, bindings, cmp), do: cmp.(eval(a, bindings), eval(b, bindings))
end
