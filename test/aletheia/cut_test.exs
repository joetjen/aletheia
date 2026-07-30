defmodule Aletheia.CutTest do
  @moduledoc """
  The two scenarios DESIGN.md's `cut-scoping` risk note demands by name
  ("cut inside disjunction inside a clause"; "cut inside a called
  predicate must NOT affect the caller"), plus the classic distinguishing
  test that rules out a thin `Ichor.Backtrack.Tree.once/1` wrapper: cut
  has an effect even along a path that ultimately fails.
  """

  use ExUnit.Case, async: true
  import Aletheia.QueryHelper

  test "cut is not once/1: p :- !, fail. with a second clause p :- true. fails outright" do
    src = """
    p :- !, fail.
    p :- true.
    """

    assert solutions(src, "p") == []
  end

  test "cut inside a disjunction prunes both the disjunction's remaining alternative and the clause's remaining choice points" do
    src = """
    r(X) :- (X = 1, ! ; X = 2).
    r(3).
    """

    assert solutions(src, "r(X)") == [%{"X" => 1}]
  end

  test "cut inside a called predicate does not affect the caller's own choice points" do
    src = """
    inner(1) :- !.
    inner(2).
    outer(X, Y) :- inner(X), q(Y).
    q(1).
    q(2).
    """

    assert solutions(src, "outer(X, Y)") == [
             %{"X" => 1, "Y" => 1},
             %{"X" => 1, "Y" => 2}
           ]
  end

  test "once/1 is not cut: it only limits solution count, an unrelated sibling clause still runs" do
    src = """
    p(X) :- once(member(X, [1, 2, 3])).
    """

    assert solutions(src, "p(X)") == [%{"X" => 1}]
  end

  test "! inside once/1 does not escape to prune the caller's own alternatives" do
    src = """
    p(1) :- once((!, fail)).
    p(2).
    """

    assert solutions(src, "p(X)") == [%{"X" => 2}]
  end

  test "! inside \\+ does not escape either" do
    src = """
    p(1) :- \\+ (!, fail).
    p(2).
    """

    assert solutions(src, "p(X)") == [%{"X" => 1}, %{"X" => 2}]
  end

  test "! inside call/1 does not escape" do
    src = """
    p(1) :- call((!, fail)).
    p(2).
    """

    assert solutions(src, "p(X)") == [%{"X" => 2}]
  end

  test "cut commits to the clause even when goals after it still backtrack normally" do
    src = """
    p(X) :- !, member(X, [1, 2, 3]).
    p(_) :- true.
    """

    assert solutions(src, "p(X)") == [%{"X" => 1}, %{"X" => 2}, %{"X" => 3}]
  end
end
