defmodule Aletheia.Repl do
  @moduledoc """
  Minimal consult + interactive query loop: `?- ` prompts for a goal,
  prints each solution's bindings, and (matching real Prolog UX) offers
  `;` for the next solution or any other input to stop.
  """

  alias Episteme.{Database, Term}

  @spec start([String.t()]) :: :ok
  def start(paths \\ []) do
    db = Enum.reduce(paths, Database.new(), &consult_into!/2)
    loop(db)
  end

  defp consult_into!(path, db) do
    case Aletheia.consult_string(File.read!(path), db) do
      {:ok, db} ->
        db

      {:error, error} ->
        IO.puts("error consulting #{path}: #{inspect(error)}")
        db
    end
  end

  defp loop(db) do
    case IO.gets("?- ") do
      :eof ->
        :ok

      {:error, reason} ->
        IO.puts("read error: #{inspect(reason)}")

      input ->
        db = handle_input(String.trim(input), db)
        loop(db)
    end
  end

  defp handle_input("", db), do: db
  defp handle_input("halt", _db), do: exit(:normal)

  defp handle_input(goal_text, db) do
    case Aletheia.query_lazy(goal_text, db) do
      {:ok, {stream, vars}} -> print_next(stream, vars)
      {:error, term} -> IO.puts("uncaught exception: " <> Term.to_text(term))
    end

    db
  end

  # Pulls and prints solutions one at a time -- never forces more of the
  # (possibly infinite) search than the user actually asks to see via `;`.
  defp print_next(stream, vars) do
    case Aletheia.next_solution(stream, vars) do
      :none ->
        IO.puts("false.")

      {:error, term} ->
        IO.puts("uncaught exception: " <> Term.to_text(term))

      {:solution, solution, rest} ->
        if map_size(solution) == 0 do
          IO.puts("true.")
        else
          IO.puts(format_solution(solution))

          case IO.gets(" ") do
            input when is_binary(input) ->
              if String.trim(input) == ";", do: print_next(rest, vars)

            _ ->
              :ok
          end
        end
    end
  end

  defp format_solution(solution) do
    solution
    |> Enum.map_join(",\n", fn {name, value} -> "#{name} = #{Term.to_text(value)}" end)
  end
end
