defmodule Aletheia.Reader do
  @moduledoc """
  Parses Aletheia source into a sequence of clause forms -- `{:fact,
  term}`, `{:rule, head, body}`, or `{:directive, goal}` -- via
  Aletheia.Reader.Grammar's `run_sequence/2`, a plain checked-in module
  generated ahead of time from `lib/aletheia/reader/grammar.aether` by

      mix ichor.gen lib/aletheia/reader/grammar.aether \\
        --module Aletheia.Reader.Grammar \\
        --actions Aletheia.Reader.Actions \\
        --out lib/aletheia/reader/grammar_generated.ex

  (rerun by hand whenever `grammar.aether` changes -- there's no
  automatic staleness check). This only ever calls into `ichor_runtime`
  at actual runtime; `ichor` itself (the Aether front-end,
  `Grammar.Analysis`, the codegen backend `mix ichor.gen` itself runs)
  is a dev-only dependency and never ships in a release. One top-level
  clause parsed at a time, threading context (the operator table `op/3`
  directives mutate) from each into the next -- the same mechanism
  ichor's own `test/prolog/actions_test.exs` proves out via
  `Grammar.VM.run_sequence/4` (the interpreted-backend equivalent of
  this generated module's own `run_sequence/2`).
  """

  alias Aletheia.Reader.{Actions, Grammar}
  alias Ichor.Error

  @doc """
  Parses `source` as a sequence of clauses, starting from `context`
  (default: a fresh context with the default operator table). Returns
  every clause form found plus the final context (so a caller consulting
  several sources in a row can keep growing the same operator table).
  """
  @spec consult_string(String.t(), map()) ::
          {:ok, [{:fact, term()} | {:rule, term(), term()} | {:directive, term()}], map()}
          | {:error, Error.t() | [Error.t()]}
  def consult_string(source, context \\ Actions.new_context()) do
    Grammar.run_sequence(source, context)
  end
end
