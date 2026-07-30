defmodule Aletheia.ListsTest do
  use ExUnit.Case, async: true
  import Aletheia.QueryHelper

  test "length/2" do
    assert solutions("", "length([a,b,c], N)") == [%{"N" => 3}]
    assert [%{"L" => list}] = solutions("", "length(L, 2)")
    assert length(list) == 2
    assert Enum.all?(list, &match?(%Aletheia.Term.Var{}, &1))
  end

  test "append/3 forwards mode" do
    assert solutions("", "append([1,2], [3,4], X)") == [%{"X" => [1, 2, 3, 4]}]
  end

  test "append/3 splitting mode (first argument unbound)" do
    result = solutions("", "append(X, Y, [1,2,3])")
    assert length(result) == 4
    assert %{"X" => [], "Y" => [1, 2, 3]} in result
    assert %{"X" => [1, 2, 3], "Y" => []} in result
  end

  test "member/2 enumerates every element in order" do
    assert solutions("", "member(X, [a,b,c])") == [%{"X" => :a}, %{"X" => :b}, %{"X" => :c}]
    assert solutions("", "member(z, [a,b,c])") == []
  end

  test "reverse/2" do
    assert solutions("", "reverse([1,2,3], X)") == [%{"X" => [3, 2, 1]}]
  end

  test "nth0/3 and nth1/3" do
    assert solutions("", "nth0(1, [a,b,c], X)") == [%{"X" => :b}]
    assert solutions("", "nth1(1, [a,b,c], X)") == [%{"X" => :a}]
  end

  test "last/2" do
    assert solutions("", "last([a,b,c], X)") == [%{"X" => :c}]
    assert solutions("", "last([], X)") == []
  end
end
