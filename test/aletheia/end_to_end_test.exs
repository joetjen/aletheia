defmodule Aletheia.EndToEndTest do
  @moduledoc "One small program exercised through the full pipeline: reader -> database -> engine, no shortcuts."

  use ExUnit.Case, async: true

  @family """
  parent(tom, bob).
  parent(tom, liz).
  parent(bob, ann).
  parent(bob, pat).
  parent(pat, jim).

  ancestor(X, Y) :- parent(X, Y).
  ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).
  """

  test "consult + query a small recursive program end to end" do
    assert {:ok, db} = Aletheia.consult_string(@family)
    assert {:ok, solutions} = Aletheia.query("ancestor(tom, Who)", db)

    people = solutions |> Enum.map(& &1["Who"]) |> Enum.sort()
    assert people == Enum.sort([:bob, :liz, :ann, :pat, :jim])
  end

  test "query_once/2 returns just the first solution" do
    {:ok, db} = Aletheia.consult_string(@family)
    assert {:ok, %{"Who" => :bob}} = Aletheia.query_once("ancestor(tom, Who)", db)
  end

  test "query_lazy/2 + next_solution/2 pull one at a time" do
    {:ok, db} = Aletheia.consult_string(@family)
    {:ok, {stream, vars}} = Aletheia.query_lazy("ancestor(tom, Who)", db)

    assert {:solution, %{"Who" => :bob}, rest} = Aletheia.next_solution(stream, vars)
    assert {:solution, %{"Who" => :liz}, _rest2} = Aletheia.next_solution(rest, vars)
  end

  test "consulting a file via consult/1" do
    path = Path.join(System.tmp_dir!(), "aletheia_e2e_#{System.unique_integer([:positive])}.alp")
    File.write!(path, @family)

    on_exit(fn -> File.rm(path) end)

    assert {:ok, db} = Aletheia.consult(path)

    assert {:ok, [%{"X" => :bob}]} =
             Aletheia.query("parent(tom, X), \\+ parent(_, tom)", db) |> take_first()
  end

  defp take_first({:ok, [first | _]}), do: {:ok, [first]}
  defp take_first(other), do: other
end
