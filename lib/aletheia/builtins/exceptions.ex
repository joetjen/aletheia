defmodule Aletheia.Builtins.Exceptions do
  @moduledoc """
  Standard ISO error-term constructors (`type_error/2`, `domain_error/2`,
  `instantiation_error/1`) plus the raw Elixir `throw` tag Aletheia's own
  `throw/1`/`catch/3` (in `Aletheia.Engine`, which needs to `solve` the
  recovery goal) and every builtin that detects bad input raise through.

  Deliberately a *different* Elixir throw tag from cut's own
  `{:aletheia_cut, barrier}` (`Aletheia.Engine`) -- the two mechanisms
  are unrelated non-local exits sharing nothing but the `throw/catch`
  primitive, and must never be caught by each other's guard.
  """

  alias Aletheia.Term.Compound

  @doc "Raises a real Prolog exception carrying `term` -- caught by `catch/3`, or escapes to the top level otherwise."
  @spec prolog_throw(term()) :: no_return()
  def prolog_throw(term), do: throw({:aletheia_throw, term})

  @doc "`error(type_error(Type, Culprit), _)` -- ISO's standard shape for \"wrong kind of value\"."
  @spec type_error(atom(), term()) :: term()
  def type_error(type, culprit) do
    error(%Compound{name: :type_error, args: [type, culprit]})
  end

  @doc "`error(domain_error(Domain, Culprit), _)` -- ISO's standard shape for \"right kind, wrong value\"."
  @spec domain_error(atom(), term()) :: term()
  def domain_error(domain, culprit) do
    error(%Compound{name: :domain_error, args: [domain, culprit]})
  end

  @doc "`error(instantiation_error, _)` -- ISO's standard shape for \"needed a bound term, got an unbound variable\"."
  @spec instantiation_error() :: term()
  def instantiation_error do
    error(:instantiation_error)
  end

  @doc "`error(existence_error(Type, Culprit), _)` -- ISO's standard shape for \"no such procedure/entity\"."
  @spec existence_error(atom(), term()) :: term()
  def existence_error(type, culprit) do
    error(%Compound{name: :existence_error, args: [type, culprit]})
  end

  defp error(formal), do: %Compound{name: :error, args: [formal, Aletheia.Term.new_var("_")]}
end
