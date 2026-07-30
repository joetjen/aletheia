defmodule Aletheia.Term do
  @moduledoc """
  Aletheia's term representation (DESIGN.md §4): atoms and numbers are
  plain Elixir atoms/integers/floats, lists are native Elixir lists,
  variables and compounds get dedicated structs. This module is the
  `Ichor.Backtrack.Term` implementation passed explicitly to every
  `Ichor.Backtrack.Bindings` call, plus the handful of whole-term
  operations (deep resolve, rename-apart) built on
  `Ichor.Toolkit.TermWalk` that unification itself doesn't need but the
  engine does.
  """

  alias Ichor.Backtrack.Bindings
  alias Ichor.Toolkit.TermWalk

  defmodule Var do
    @moduledoc "A logic variable: `ref` is its identity, `name` is display-only."
    @enforce_keys [:ref]
    defstruct [:ref, name: "_"]
    @type t :: %__MODULE__{ref: reference(), name: String.t()}
  end

  defmodule Compound do
    @moduledoc "A compound term `name(args...)`."
    @enforce_keys [:name, :args]
    defstruct [:name, :args]
    @type t :: %__MODULE__{name: atom(), args: [term()]}
  end

  @behaviour Ichor.Backtrack.Term

  @impl true
  def variable?(%Var{}), do: true
  def variable?(_), do: false

  @impl true
  def var_id(%Var{ref: ref}), do: ref

  @impl true
  def compound?(%Compound{}), do: true
  def compound?([_ | _]), do: true
  def compound?(_), do: false

  @doc """
  A non-empty native Elixir list decomposes as ISO's own `'.'/2` cons
  functor (`[H|T]` <-> `'.'(H, T)`) -- the encoding that lets
  `Ichor.Backtrack.Bindings.unify/4` recurse into list structure at all
  (without this, `[H|T]` vs `[1,2,3]` would only ever compare via plain
  `==/2`, never binding `H`/`T`). `[]` is the atomic empty-list atom,
  same as real Prolog -- not a `'.'/2` cell, so it stays out of
  `compound?/1` above.
  """
  @impl true
  def deconstruct(%Compound{name: name, args: args}), do: {name, args}
  def deconstruct([h | t]), do: {:., [h, t]}

  @impl true
  def reconstruct(:., [h, t]), do: [h | t]
  def reconstruct(name, args), do: %Compound{name: name, args: args}

  @doc "A fresh variable, optionally named for display."
  @spec new_var(String.t()) :: Var.t()
  def new_var(name \\ "_"), do: %Var{ref: make_ref(), name: name}

  @doc """
  Fully dereferences `term` and every subterm reachable through it under
  `bindings` -- unlike `Ichor.Backtrack.Bindings.resolve/3`, which only
  chases the outermost variable one level deep, this also resolves
  inside compound-term arguments (and, since `rewrite/3` re-examines a
  freshly resolved variable's own value, transitively through however
  many bindings a chain passes through).
  """
  @spec resolve_deep(term(), Bindings.t()) :: term()
  def resolve_deep(term, bindings) do
    TermWalk.rewrite(__MODULE__, term, &Bindings.resolve(__MODULE__, bindings, &1))
  end

  @doc """
  Renames every distinct variable in `term` apart to a brand new one,
  preserving sharing (two occurrences of the same variable become two
  occurrences of the same fresh variable) -- the "discover names, build
  a fresh-ref map, rewrite" shape, keyed by `ref` identity rather than
  source name since `term` has already been through the reader's own
  per-clause freshening by the time this runs. Used both for
  `copy_term/2` and to instantiate a stored clause fresh on every call.
  """
  @spec fresh_copy(term()) :: term()
  def fresh_copy(term) do
    refs =
      TermWalk.fold(__MODULE__, term, %{}, fn
        %Var{ref: ref, name: name}, acc -> Map.put_new(acc, ref, new_var(name))
        _other, acc -> acc
      end)

    TermWalk.rewrite(__MODULE__, term, fn
      %Var{ref: ref} -> Map.fetch!(refs, ref)
      other -> other
    end)
  end

  @doc "Structural equality (`==/2`) on two already-resolved terms -- same shape, same variable identity, and (unlike plain Elixir `==`) an integer never equals a float."
  @spec structurally_equal?(term(), term()) :: boolean()
  def structurally_equal?(%Var{ref: a}, %Var{ref: b}), do: a == b
  def structurally_equal?(%Var{}, _), do: false
  def structurally_equal?(_, %Var{}), do: false

  def structurally_equal?(%Compound{name: n, args: a1}, %Compound{name: n, args: a2})
      when length(a1) == length(a2) do
    Enum.zip(a1, a2) |> Enum.all?(fn {x, y} -> structurally_equal?(x, y) end)
  end

  def structurally_equal?(%Compound{}, _), do: false
  def structurally_equal?(_, %Compound{}), do: false

  def structurally_equal?([], []), do: true

  def structurally_equal?([h1 | t1], [h2 | t2]),
    do: structurally_equal?(h1, h2) and structurally_equal?(t1, t2)

  def structurally_equal?([], _), do: false
  def structurally_equal?(_, []), do: false

  def structurally_equal?(a, b) when is_number(a) and is_number(b),
    do: a == b and is_float(a) == is_float(b)

  def structurally_equal?(a, b), do: a == b

  @doc "Canonical `functor(args)` text for an already fully-resolved term -- no operator-aware pretty-printing in v0.1."
  @spec to_text(term()) :: String.t()
  def to_text(%Var{name: name}), do: name

  def to_text(%Compound{name: name, args: args}) do
    Atom.to_string(name) <> "(" <> Enum.map_join(args, ", ", &to_text/1) <> ")"
  end

  def to_text([]), do: "[]"

  def to_text(list) when is_list(list) do
    "[" <> to_text_list(list) <> "]"
  end

  def to_text(atom) when is_atom(atom), do: Atom.to_string(atom)
  def to_text(number) when is_number(number), do: to_string(number)
  def to_text(other), do: inspect(other)

  defp to_text_list([h]), do: to_text(h)
  defp to_text_list([h | t]) when is_list(t), do: to_text(h) <> ", " <> to_text_list(t)
  defp to_text_list([h | t]), do: to_text(h) <> "|" <> to_text(t)
end
