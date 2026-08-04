defmodule Aletheia.Reader.ControlSyntax do
  @moduledoc """
  Translates a parsed goal from `Aletheia.Reader`'s own ISO-punctuation
  term shape (`','/2`, `';'/2`, `'->'/2`, `!`, `'='/2`, ...) into the
  plain-English control-construct/comparison names `Episteme.Engine`
  dispatches on (`and/2`, `or/2`, `if_then/2`, `cut`, `unify/2`, ...) --
  see `episteme`'s own `CHANGELOG.md` under its `0.1.0` release: as of
  its first Hex publish, Episteme no longer accepts ISO punctuation
  directly, since it has no reader of its own for that punctuation to
  be conventional syntax against. Bridging that gap is squarely this
  reader's job, not the engine's.

  Only applied to goals (rule bodies, directive/query goals) -- never
  to fact terms or rule heads, which are plain data matched structurally
  by the engine, not dispatched as goals.
  """

  alias Episteme.Term
  alias Episteme.Term.Compound
  alias Ichor.Toolkit.TermWalk

  @simple_map %{
    {:",", 2} => :and,
    {:";", 2} => :or,
    {:->, 2} => :if_then,
    {:"\\+", 1} => :not,
    {:=, 2} => :unify,
    {:"\\=", 2} => :not_unify,
    {:==, 2} => :equal,
    {:"\\==", 2} => :not_equal,
    {:"=:=", 2} => :numeric_equal,
    {:"=\\=", 2} => :numeric_not_equal,
    {:"=<", 2} => :less_or_equal,
    {:>=, 2} => :greater_or_equal
  }

  @doc """
  Rewrites `goal` from ISO-punctuation control/comparison names to
  Episteme's own. Recognizes the ISO `(Cond -> Then ; Else)` nested
  pattern (`';'/2` wrapping `'->'/2` as its first argument) and rewrites
  it to the explicit `if_then_else/3` Episteme now requires -- a plain
  per-node translation would instead produce `or(if_then(Cond, Then),
  Else)`, which wrongly retries `Else` if `Cond` succeeds but `Then`
  fails.
  """
  @spec to_goal(term()) :: term()
  def to_goal(goal), do: TermWalk.rewrite(Term, goal, &translate_node/1)

  defp translate_node(%Compound{
         name: :";",
         args: [%Compound{name: :->, args: [cond_, then_]}, else_]
       }) do
    %Compound{name: :if_then_else, args: [cond_, then_, else_]}
  end

  defp translate_node(%Compound{name: name, args: args} = compound) do
    case Map.fetch(@simple_map, {name, length(args)}) do
      {:ok, new_name} -> %Compound{name: new_name, args: args}
      :error -> compound
    end
  end

  defp translate_node(:!), do: :cut
  defp translate_node(other), do: other
end
