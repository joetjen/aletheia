defmodule Aletheia.Reader.Actions do
  @moduledoc """
  Turns `lib/aletheia/reader/grammar.aether`'s raw capture tree into
  `Episteme.Term`-shaped data -- mirrors ichor's own
  `test/support/prolog_actions.ex` worked example closely, adapted to
  build real `Episteme.Term.Var`/`Compound` structs (and native lists,
  via the `.`/2 encoding `Episteme.Term.deconstruct/1` implements)
  instead of that fixture's plain tuples.

  Variable names are scoped to one clause: every `X` within one clause
  (head and whole body) must share one ref, but two clauses using `X`
  never share one. `handle_token(:VAR, ...)` deliberately does NOT mint
  a ref directly -- it produces a `{:var_ref, name}` placeholder, only
  ever resolved by `freshen/1`'s own fold-then-rewrite pass over the
  *whole* clause at once (same reason ichor's fixture does this: a
  variable can't be freshened consistently until every occurrence of
  its name within the clause is known first).
  """

  alias Aletheia.Reader.Pratt
  alias Episteme.Term
  alias Episteme.Term.Compound
  alias Ichor.Toolkit.Pratt, as: OpTable
  alias Ichor.Toolkit.TermWalk

  @behaviour Ichor.Actions

  @doc "A fresh context, seeded with the default Prolog operator table."
  @spec new_context() :: %{operators: OpTable.table()}
  def new_context, do: %{operators: default_operators()}

  defp iso(prec), do: Pratt.iso_to_pratt(prec)

  defp default_operators do
    OpTable.new()
    |> OpTable.prefix("-", iso(200))
    |> OpTable.prefix("+", iso(200))
    |> OpTable.prefix("\\+", iso(900))
    |> OpTable.infix(";", iso(1100), :right)
    |> OpTable.infix("->", iso(1050), :right)
    |> OpTable.infix(",", iso(1000), :right)
    |> OpTable.infix("=", iso(700), :left)
    |> OpTable.infix("\\=", iso(700), :left)
    |> OpTable.infix("==", iso(700), :left)
    |> OpTable.infix("\\==", iso(700), :left)
    |> OpTable.infix("is", iso(700), :left)
    |> OpTable.infix("=:=", iso(700), :left)
    |> OpTable.infix("=\\=", iso(700), :left)
    |> OpTable.infix("<", iso(700), :left)
    |> OpTable.infix(">", iso(700), :left)
    |> OpTable.infix("=<", iso(700), :left)
    |> OpTable.infix(">=", iso(700), :left)
    |> OpTable.infix("@<", iso(700), :left)
    |> OpTable.infix("@>", iso(700), :left)
    |> OpTable.infix("@=<", iso(700), :left)
    |> OpTable.infix("@>=", iso(700), :left)
    |> OpTable.infix("+", iso(500), :left)
    |> OpTable.infix("-", iso(500), :left)
    |> OpTable.infix("*", iso(400), :left)
    |> OpTable.infix("/", iso(400), :left)
    |> OpTable.infix("//", iso(400), :left)
    |> OpTable.infix("mod", iso(400), :left)
    |> OpTable.infix("rem", iso(400), :left)
    |> OpTable.infix("**", iso(200), :left)
    |> OpTable.infix("^", iso(200), :right)
  end

  @impl true
  def handle_token(:NUMBER, text, _ctx) do
    if String.contains?(text, ".") do
      {:ok, String.to_float(text)}
    else
      {:ok, String.to_integer(text)}
    end
  end

  def handle_token(:VAR, "_", _ctx), do: {:ok, {:var_ref, make_ref()}}
  def handle_token(:VAR, text, _ctx), do: {:ok, {:var_ref, text}}
  def handle_token(:ATOM, text, _ctx), do: {:ok, to_prolog_atom(text)}

  def handle_token(:QATOM, text, _ctx),
    do: {:ok, text |> String.slice(1..-2//1) |> to_prolog_atom()}

  # A real string -- a plain Elixir binary, no wrapper struct, same as
  # `Episteme.Term`'s own representation for one.
  def handle_token(:STRING, text, _ctx), do: {:ok, String.slice(text, 1..-2//1)}

  def handle_token(:BANG, text, _ctx), do: {:ok, to_prolog_atom(text)}
  def handle_token(:SEMI, text, _ctx), do: {:ok, to_prolog_atom(text)}
  def handle_token(:OP, text, _ctx), do: {:ok, to_prolog_atom(text)}

  # sobelow_skip ["DOS.StringToAtom"]
  # Every atom this reader ever produces (plain atoms, quoted atoms,
  # `!`/`;` as atoms, operator symbols) comes from source text via one
  # of the `handle_token/3` clauses above -- the BEAM atom table isn't
  # garbage collected, so this is an accepted atom-table-exhaustion risk
  # (fine for a library embedded in trusted programs; revisit before any
  # untrusted/generated-source use case). Routing every
  # `String.to_atom/1` call through here instead of five separate call
  # sites keeps that justification in one place instead of a skip
  # comment repeated five times over.
  @spec to_prolog_atom(String.t()) :: atom()
  defp to_prolog_atom(text), do: String.to_atom(text)

  @impl true
  def handle_rule(:clause, captures, ctx) do
    cap =
      Map.get(captures, :fact) || Map.get(captures, :rule) || Map.get(captures, :dcg_rule) ||
        Map.get(captures, :directive)

    cap.eval.(ctx)
  end

  # `args_cap` is a single `%Capture{}` wrapping a real `arglist` rule
  # match for genuine `f(a, b)` syntax, but a *raw list* of capture
  # nodes when this same rule name is reached via
  # `Aletheia.Reader.Pratt`'s synthetic `{:rule, :compound, %{args: [l, r]}}`
  # build for an operator application (`a + b`) -- `eval_list/3` (built
  # on `Ichor.Actions.eval_all/2`, which is polymorphic over exactly
  # this "one capture or a list of them" distinction) handles both.
  def handle_rule(:compound, %{functor: functor_cap, args: args_cap}, ctx) do
    with {:ok, functor, ctx} <- functor_cap.eval.(ctx),
         {:ok, args, ctx} <- eval_list(:args, args_cap, ctx) do
      {:ok, %Compound{name: functor, args: args}, ctx}
    end
  end

  def handle_rule(:arglist, %{arg_term: caps}, ctx), do: eval_list(:arg_term, caps, ctx)

  def handle_rule(:list, captures, ctx) do
    cond do
      Map.has_key?(captures, :tail) ->
        with {:ok, items, ctx} <- Map.fetch!(captures, :items).eval.(ctx),
             {:ok, tail, ctx} <- Map.fetch!(captures, :tail).eval.(ctx) do
          {:ok, build_list(items, tail), ctx}
        end

      Map.has_key?(captures, :items) ->
        Map.fetch!(captures, :items).eval.(ctx)

      true ->
        {:ok, [], ctx}
    end
  end

  def handle_rule(:primary, captures, ctx) do
    case Map.fetch(captures, :inner) do
      {:ok, cap} ->
        cap.eval.(ctx)

      :error ->
        [cap] = Map.values(captures)
        cap.eval.(ctx)
    end
  end

  def handle_rule(:fact, %{compound_or_atom: cap}, ctx) do
    with {:ok, term, ctx} <- cap.eval.(ctx) do
      {:ok, {:fact, freshen(term)}, ctx}
    end
  end

  def handle_rule(:rule, %{head: head_cap, body: body_cap}, ctx) do
    with {:ok, head, ctx} <- head_cap.eval.(ctx),
         {:ok, body, ctx} <- body_cap.eval.(ctx) do
      {fresh_head, fresh_body} = freshen_pair(head, body)
      {:ok, {:rule, fresh_head, fresh_body}, ctx}
    end
  end

  # A DCG rule (`Head --> Body`) -- same shape as an ordinary `:rule`,
  # tagged `:dcg` instead of `:rule` so `Aletheia.to_engine_form/1` (and,
  # past that, `Episteme.Database.consult_forms/2`) know to route `body`
  # through DCG translation instead of storing it as an ordinary clause
  # body directly.
  def handle_rule(:dcg_rule, %{head: head_cap, body: body_cap}, ctx) do
    with {:ok, head, ctx} <- head_cap.eval.(ctx),
         {:ok, body, ctx} <- body_cap.eval.(ctx) do
      {fresh_head, fresh_body} = freshen_pair(head, body)
      {:ok, {:dcg, fresh_head, fresh_body}, ctx}
    end
  end

  def handle_rule(:curly, %{inner: cap}, ctx) do
    with {:ok, inner, ctx} <- cap.eval.(ctx) do
      {:ok, %Compound{name: :{}, args: [inner]}, ctx}
    end
  end

  def handle_rule(:directive, %{goal: goal_cap}, ctx) do
    with {:ok, goal, ctx} <- goal_cap.eval.(ctx) do
      goal = freshen(goal)
      {:ok, {:directive, goal}, apply_directive(goal, ctx)}
    end
  end

  defp apply_directive(%Compound{name: :op, args: [prec, type, name]}, ctx)
       when is_integer(prec) and is_atom(type) and is_atom(name) do
    op_name = Atom.to_string(name)
    pratt_prec = iso(prec)

    table =
      case type do
        t when t in [:fy, :fx] ->
          Ichor.Toolkit.Pratt.prefix(ctx.operators, op_name, pratt_prec)

        t when t in [:xf, :yf] ->
          Ichor.Toolkit.Pratt.postfix(ctx.operators, op_name, pratt_prec)

        :xfy ->
          Ichor.Toolkit.Pratt.infix(ctx.operators, op_name, pratt_prec, :right)

        t when t in [:xfx, :yfx] ->
          Ichor.Toolkit.Pratt.infix(ctx.operators, op_name, pratt_prec, :left)
      end

    %{ctx | operators: table}
  end

  defp apply_directive(_goal, ctx), do: ctx

  defp eval_list(key, caps, ctx) do
    with {:ok, wrapped, ctx} <- Ichor.Actions.eval_all(%{key => caps}, ctx) do
      {:ok, Map.fetch!(wrapped, key), ctx}
    end
  end

  defp build_list(items, tail), do: Enum.reduce(Enum.reverse(items), tail, &[&1 | &2])

  defp freshen(term), do: term |> List.wrap() |> freshen_all() |> hd()

  defp freshen_pair(head, body) do
    [fresh_head, fresh_body] = freshen_all([head, body])
    {fresh_head, fresh_body}
  end

  defp freshen_all(terms) do
    wrapped = %Compound{name: :"$group", args: terms}

    names =
      TermWalk.fold(Term, wrapped, MapSet.new(), fn
        {:var_ref, name}, acc -> MapSet.put(acc, name)
        _other, acc -> acc
      end)

    refs = Map.new(names, fn name -> {name, Term.new_var(var_display_name(name))} end)

    %Compound{name: :"$group", args: freshened} =
      TermWalk.rewrite(Term, wrapped, fn
        {:var_ref, name} -> Map.fetch!(refs, name)
        other -> other
      end)

    freshened
  end

  defp var_display_name(name) when is_binary(name), do: name
  defp var_display_name(_ref), do: "_"
end
