defmodule Aletheia.QueryHelper do
  @moduledoc "Shared `consult source, run goal` shorthand for tests."

  @spec solutions(String.t(), String.t()) :: [Aletheia.solution()] | {:error, term()}
  def solutions(source, goal) do
    {:ok, db} = Aletheia.consult_string(source)

    case Aletheia.query(goal, db) do
      {:ok, solutions} -> solutions
      {:error, _} = err -> err
    end
  end
end
