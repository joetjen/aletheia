# Aletheia — Design Reference

Primary audience: an AI coding agent implementing this project. Secondary
audience: Jan. Tabular/uniform data below is [TOON](https://github.com/toon-format/spec)
(compact, token-efficient for LLMs); narrative sections are plain Markdown.
This file is the source of truth for scope and status — if code and this
file disagree, this file wins until updated in the same change.

## 0. How to use this document (agent instructions)

```toon
usage:
  authority: "This file is the canonical scope/status record for Aletheia."
  before_implementing_a_predicate: "Check predicate_catalog for its milestone tag. Do not implement items tagged beyond the milestone currently in progress without updating this doc in the same change."
  before_adding_a_dependency: "Prefer Ichor primitives (see ichor_primitives) over hand-rolled equivalents. Check ichor_primitives and decisions_log first."
  on_design_change: "Update decisions_log with a new row (do not delete superseded rows, mark them superseded) and update the affected section in the same change."
  on_milestone_completion: "Update roadmap status field. Do not mark 'done' until the predicate_catalog rows for that milestone are all status=implemented."
  source_of_truth_conflict: "This file over code comments over memory. If code contradicts this file, either the code is wrong or this file is stale — fix whichever is actually wrong, do not silently follow the code."
```

## 1. Identity

```toon
project:
  name: Aletheia
  meaning: "Greek: truth / unconcealment"
  tagline: "Embedded Prolog dialect for Elixir — Clojure is to Common Lisp as Aletheia is to Prolog"
  file_extension: .alp
  hex_package_name: aletheia
  hex_availability_checked: 2026-08-04 (ichor 0.3.0, ichor_runtime 0.2.0, episteme 0.1.0 all published)
  docs_url: "https://joetjen.github.io/aletheia/ -- built by .github/workflows/docs.yml on push to main; Pages enabled on the repo but the workflow has not fired yet since aletheia itself has no release to main (see decisions_log's episteme_hex_release for the analogous aletheia-not-yet-on-Hex status)"
  host_language: Elixir
  host_platform: BEAM
  status: "v0.1 through v0.5 (the entire numbered roadmap) implemented AND now reachable end-to-end from .alp source via a temporary path dependency on episteme's own develop branch -- see aletheia_episteme_path_dependency_interim and aletheia_reader_v0_2_v0_5_integration; neither aletheia nor episteme has been released to Hex yet (the plan: finish+verify aletheia against episteme's current develop first, then release episteme, then bump aletheia's dependency to the release and release aletheia itself). Only 'later' (module system, tabling, CLP(FD) -- explicitly unscheduled, need-driven only) remains (see roadmap)"
  local_path: "~/Projects/__mine__/aletheia"
  hard_dependency: "ichor_runtime ~> 0.2 (real runtime dep, own Hex package/repo) + ichor ~> 0.3 (only: :dev, runtime: false) -- both published to Hex; see ichor_runtime_split -- plus episteme, the standalone engine/database this package's reader is a front-end for (see episteme_split), TEMPORARILY a path dependency ({:episteme, path: \"../episteme\"}, not a Hex version constraint) -- see aletheia_episteme_path_dependency_interim"
  license: MIT (see LICENSE)
```

```toon
sibling_project:
  name: Episteme
  meaning: "Greek: structured/justified knowledge, root of 'epistemology'"
  relationship: "the standalone resolution engine and clause database Aletheia's reader is a syntax front-end for -- see episteme_split (decisions_log) and 3.1"
  hex_package_name: episteme
  hex_status: "published, ~> 0.1 (see episteme_hex_release, decisions_log)"
  local_path: "~/Projects/__mine__/episteme"
  design_reference: "episteme's own repository does not (yet) have its own DESIGN.md; this file's 3.1/6/11 sections are the record of what moved there and why, until it does"
```

## 2. Philosophy

Clojure-to-Common-Lisp is the analogy for *taste*, not *scope*: keep the
host language's actual semantics (unification, SLD-resolution,
backtracking, cut, clause database as program), keep classic Prolog
*syntax* (`:-`, `,`/`;`, `=`, the standard operator table — existing
Prolog knowledge transfers directly, no bespoke surface syntax),
modernize *names* only (opaque classic predicate names get a readable
alias that delegates to the same predicate — additive, never a silent
behavioral fork, never a rename of names that are already clear), and
grow the standard-predicate surface need-first rather than chasing
ISO/SWI completeness up front. "Feature complete" in this document means
the catalog below is a complete map of the *intended* eventual surface,
not that all of it ships at once — see `roadmap`.

## 3. Architecture

Two genuinely separate pieces sit on top of Ichor: a **reader** (text →
term data, using Ichor's lexer and Pratt parser directly — this stays
in the `aletheia` package) and a **resolution engine** (term data +
clause database → solutions, using Ichor's `Backtrack` search substrate
plus SLD-resolution, clause database, and builtin predicates — none of
which Ichor provides, since Ichor's own `Actions` evaluation model is a
single-pass fold and cannot represent multi-solution backtracking
search on its own). As of `episteme_split` (decisions_log; see 3.1),
the second piece is its own package, `episteme`, with no dependency on
the first.

### 3.0 The `ichor`/`ichor_runtime` split

Ichor split itself into two independently published Hex packages —
`ichor ~> 0.3` and `ichor_runtime ~> 0.2` (`ichor_runtime` is its
own repository now, `github.com/joetjen/ichor_runtime`, not a
subdirectory of `ichor`'s; see decisions_log `ichor_runtime_hex_release`
for the migration off the earlier git+`sparse:`/monorepo arrangement):
the full `ichor` (Aether front-end, format importers, `Grammar.Analysis`,
both codegen backends) is **dev-only** (`only: :dev, runtime: false`)
and never ships in a release; `ichor_runtime` is the small set of
modules a *generated* parser — and, critically for Aletheia specifically,
an engine built on top of one — actually calls at runtime, and is
Aletheia's one real runtime dependency.

`lib/aletheia/reader/grammar_generated.ex` is the ahead-of-time output
of `mix ichor.gen` (aliased as `mix gen.grammar`) run against
`lib/aletheia/reader/grammar.aether` — a plain checked-in module, not
regenerated on every `mix compile` the way `use Ichor, grammar: ...`
would. Rerun `mix gen.grammar` by hand (requires `MIX_ENV=dev`, since it
needs the dev-only `ichor`) whenever `grammar.aether` changes — no
automatic staleness check exists between the two.

**A real gap found and fixed while migrating**: `ichor_runtime`, as
originally split, did not include `Ichor.Toolkit.Pratt`,
`Ichor.Toolkit.TermWalk`, or `Ichor.Backtrack` (+`.Bindings`/`.Term`/
`.Tree`) — all three are called directly by Aletheia's own runtime code
(`Aletheia.Reader.Pratt`'s `@native` callback calls `Pratt.parse/4` on
every single parse, not just at grammar-generation time; `Aletheia.Term`/
`Aletheia.Engine`/every builtin call `Bindings`/`Tree` on every
resolution step), not just by generated parser code itself. Fixed
upstream (originally as `ichor` commit `9dc5d09` on the `feature/runtime`
branch, since released as part of `ichor_runtime` 0.1.0 /
`ichor` 0.2.0 on Hex): moved all three into `ichor_runtime`, since none
of them have any dev-only dependency of their own. See `decisions_log`.

```toon
pipeline[5]{stage,module,provided_by,status}:
  lex+parse_term,"lib/aletheia/reader/grammar_generated.ex (mix ichor.gen output, checked in) via Aletheia.Reader.Grammar.run_sequence/2 + Ichor.Toolkit.Pratt via @native",aletheia+ichor_runtime,implemented
  term_ir,Episteme.Term,episteme,implemented
  unify,Ichor.Backtrack.Bindings,ichor_runtime,available
  search,Ichor.Backtrack.Tree,ichor_runtime,available
  resolve,Episteme.Engine (SLD-resolution over Backtrack primitives + clause DB + cut barriers),episteme,implemented
```

```toon
ichor_primitives[8]{module,role,prolog_concept,status,consumed_by}:
  Aletheia.Reader.Grammar.run_sequence/2,"mix ichor.gen-generated equivalent of Grammar.VM.run_sequence/4 -- parses source as a sequence of top-level clauses, threading context (the growing op/3 operator table) from each into the next",reader driver,implemented (generated ahead of time, not at compile time),aletheia
  Ichor.Toolkit.Pratt,"precedence-climbing parse over a runtime-mutable prefix/infix/postfix operator table",op/3-driven term reading,"available (ichor_runtime, moved from ichor -- see 3.0)",aletheia
  Ichor.Backtrack,"behaviour: unit/fail/disjunction/conjunction/once over a goal := bindings -> solutions",true/fail/;//,/cut-ish,"available (ichor_runtime, moved from ichor -- see 3.0)",episteme
  Ichor.Backtrack.Tree,"concrete engine: manually-unfolded lazy search tree, depth-first clause-order",SLD search tree,"available (ichor_runtime, moved from ichor -- see 3.0)",episteme
  Ichor.Backtrack.Bindings,"structural unification; occurs-check off by default (matches ISO), occurs-check variant available",=/2 and unify_with_occurs_check/2,"available (ichor_runtime, moved from ichor -- see 3.0)",episteme
  Ichor.Backtrack.Term,"behaviour: variable?/1, var_id/1, compound?/1, deconstruct/1, reconstruct/2 (optional)",pluggable term representation,implemented_by_episteme (Episteme.Term; lists decompose as '.'/2),episteme
  Ichor.Toolkit.TermWalk,"fold/2 and rewrite/3 over any Backtrack.Term implementation",variable-renaming-apart on clause instantiation + resolve_deep/2,"implemented_and_used (ichor_runtime, moved from ichor -- see 3.0)",episteme
  Ichor.Toolkit.Result,"Result.reduce_ok and friends over {:ok,_}/:fail-shaped pipelines",used inside Bindings.unify_compound; reusable in engine code,available (ichor_runtime),episteme
```

### 3.1 The `aletheia`/`episteme` split

`Aletheia.Term`, `Aletheia.Database`, `Aletheia.Engine`, and
`Aletheia.Builtins.*` moved out of this repository entirely, into a new
sibling package, `episteme` (`Episteme.Term`, `Episteme.Database`,
`Episteme.Engine`, `Episteme.Builtins.*`, plus a top-level `Episteme`
module exposing `query/2`/`query_once/2`/`query_lazy/2`/
`next_solution/2` over an already-built term goal — the same shape as
this package's own top-level `Aletheia` module, minus the text-parsing
step). See `episteme_split` in `decisions_log` for the date and
rationale; see `11` for what `aletheia`'s own module layout looks like
after the move.

The motivating distinction: nothing about unification, SLD-resolution,
the clause database, cut, or the builtin predicates depends on Aletheia
concretely being classic Prolog *syntax* — `Episteme.Database` is built
from `{:fact, head}`/`{:rule, head, body}` forms or directly via
`add_clause/2`/`add_fact/2`, and a goal is always an already-built term,
never source text. Aletheia's reader is one way to produce those terms;
it is not the only possible one, and Episteme has zero knowledge of it.
Splitting them means Episteme is independently useful as a Prolog-like
rule engine/query layer in Elixir for anyone who does not want
Aletheia's `.alp` syntax at all, and keeps this repository's own scope
honestly limited to "the syntax front-end."

`aletheia`'s own dependency on `episteme` is a regular Hex dependency
(`{:episteme, "~> 0.1"}`) as of `episteme_hex_release` — see
`decisions_log`.

### 3.2 Known hard problem: cut vs `once/1`

```toon
risk:
  id: cut-scoping
  severity: high
  statement: "Ichor.Backtrack.once/1 is Prolog's once/1 builtin (first solution of a goal), not Prolog's ! (cut). Cut commits to choices made since entering the CURRENT CLAUSE specifically — a narrower, clause-scoped commitment, not 'stop after one solution of whatever goal contains it'. once/1 will pass naive tests and diverge on nested-clause cases."
  mitigation: "Design cut as a distinct primitive in Aletheia.Engine: thread a clause-scoped cut barrier/signal through conjunction that once/1 alone does not provide. Do not implement ! as a thin wrapper over Backtrack.once/1 without a barrier check. Write cut-specific tests (cut inside disjunction inside a clause; cut inside a called predicate must NOT affect the caller) before considering cut done."
  status: "resolved -- implemented via throw/catch barriers (see decisions_log cut_implementation), both named tests plus the p:-!,fail. p:-true. distinguishing case pass (now in episteme's own repo, test/episteme/cut_test.exs, since Episteme.Engine owns cut -- see episteme_split)"
```

### 3.3 Known hard problem: atom exhaustion

```toon
risk:
  id: atom-table-exhaustion
  severity: medium
  statement: "Representing Prolog atoms as raw Elixir atoms is convenient (native ==/2, cheap) but the BEAM atom table is not garbage collected. A long-running process reading untrusted or generated Prolog source repeatedly is a DoS vector."
  mitigation: "Acceptable for v0.1-v0.5 (library embedded in your own trusted programs). Before ever exposing Aletheia to untrusted/generated source input, revisit: interned-string atoms or a bounded atom cache instead of raw BEAM atoms."
  status: accepted for now, documented, revisit before any untrusted-input use case
```

## 4. Term representation

This is `Episteme.Term`'s representation now (see `episteme_split`),
not Aletheia's own -- Aletheia's reader produces exactly these shapes
but the type definitions and the `Ichor.Backtrack.Term` implementation
both live in the `episteme` package.

```toon
terms[7]{prolog_term,elixir_representation,notes}:
  atom,":name (raw Elixir atom)","see risk atom-table-exhaustion"
  integer,integer,"native BEAM bignum, no overflow handling needed"
  float,float,"native; IEEE 754 double, matches ISO float semantics closely enough for v0.1"
  string,"binary (String.t())","see string_type_decision; native Elixir UTF-8 binary, a genuinely new atomic term class (not a list of codes) -- matches by plain ==/2 (exact byte equality), never structurally decomposed by unify (compound?/1 is false for it); standard order of terms places it between atom and compound (Var < Number < Atom < String < Compound); Aletheia's own double-quoted \"...\" reader syntax not yet wired up -- see decisions_log"
  variable,"%Episteme.Term.Var{ref: reference(), name: String.t()}","ref is var_id/1 for Backtrack.Term; name is display-only, never used for identity"
  compound,"%Episteme.Term.Compound{name: atom(), args: [term]}","deconstruct/1 -> {name,args}; reconstruct/2 rebuilds"
  list,"[h | t] using native Elixir lists","proper AND improper lists both representable natively; [] is the empty-list atom, same as Prolog"
```

```toon
term_deferred_decisions[1]{topic,options,status}:
  string_type,"code-list (ISO default) vs real Elixir binary-backed string type","decided 2026-08-04: real Elixir binary-backed string type -- see string_type_decision in decisions_log"
```

## 5. Naming convention rule

```toon
naming_rule:
  rule_1: "Every ISO/classic predicate name still exists under its classic name. Non-negotiable — existing Prolog tutorials/books must keep working."
  rule_2: "Where a classic name is genuinely opaque (\\==, =.., assertz, atomic_list_concat), add a readable alias that DELEGATES to the same predicate. Alias, never a replacement, never a behavioral fork."
  rule_3: "Do not rename names that are already clear (length/2, append/3, member/2 stay as-is). Resist improving what isn't broken."
```

## 6. Predicate catalog

Every row is one predicate (or predicate family). `milestone` is the
roadmap tag it ships in (§7). `classic_name` is always the ISO/canonical
name; `modern_alias` is empty when rule_3 applies (name already clear).

```toon
predicate_catalog[133]{category,classic_name,arity,modern_alias,milestone,status,notes}:
  control,true,0,,v0.1,implemented,
  control,fail,0,,v0.1,implemented,"false/0 is a standard alias, both classic"
  control,",",2,,v0.1,implemented,"conjunction; maps to Backtrack.conjunction/2"
  control,;,2,,v0.1,implemented,"disjunction; maps to Backtrack.disjunction/2"
  control,->,2,,v0.1,implemented,if-then
  control,!,0,cut,v0.1,implemented,"see risk cut-scoping; NOT a thin once/1 wrapper"
  control,\+,1,,v0.1,implemented,negation as failure
  control,call,1,,v0.1,implemented,
  control,call,2,,v0.1,implemented,"call/N up to at least 8, partial application"
  control,once,1,,v0.1,implemented,"this one genuinely IS Backtrack.once/1 directly"
  control,forall,2,,v0.2,implemented,"expressible via \\+ (Cond, \\+ Action); shipped ahead of schedule as part of episteme 0.1.0 -- see episteme_ahead_of_schedule"
  control,ignore,1,,v0.2,implemented,"see episteme_v0_2_completed; like once/1 but never fails"
  unify,=,2,,v0.1,implemented,"Backtrack.Bindings.unify/4"
  unify,\=,2,,v0.1,implemented,
  unify,unify_with_occurs_check,2,,v0.2,implemented,"Backtrack.Bindings.unify_occurs_check/4 already existed in ichor_runtime; now wired up as a callable goal -- see episteme_v0_2_completed"
  compare,==,2,,v0.1,implemented,structural equality
  compare,\==,2,not_equal,v0.1,implemented,
  compare,@<,2,,v0.2,implemented,"standard order of terms -- see episteme_v0_2_completed"
  compare,@>,2,,v0.2,implemented,"standard order of terms -- see episteme_v0_2_completed"
  compare,@=<,2,,v0.2,implemented,"standard order of terms -- see episteme_v0_2_completed"
  compare,@>=,2,,v0.2,implemented,"standard order of terms -- see episteme_v0_2_completed"
  compare,compare,3,,v0.2,implemented,"standard order of terms -- see episteme_v0_2_completed"
  type_check,var,1,,v0.1,implemented,
  type_check,nonvar,1,,v0.1,implemented,
  type_check,atom,1,,v0.1,implemented,
  type_check,atomic,1,,v0.1,implemented,
  type_check,number,1,,v0.1,implemented,
  type_check,integer,1,,v0.1,implemented,
  type_check,float,1,,v0.1,implemented,
  type_check,compound,1,,v0.1,implemented,
  type_check,callable,1,,v0.1,implemented,
  type_check,is_list,1,,v0.1,implemented,
  type_check,ground,1,,v0.2,implemented,"recursive var-freedom check -- see episteme_v0_2_completed"
  term_inspect,functor,3,,v0.2,implemented,"see episteme_v0_2_completed"
  term_inspect,arg,3,,v0.2,implemented,"see episteme_v0_2_completed"
  term_inspect,=..,2,univ,v0.2,implemented,"see episteme_v0_2_completed"
  term_inspect,copy_term,2,,v0.1,implemented,"internal machinery too: needed for clause instantiation on every resolution step, expose as predicate in v0.1"
  arithmetic,is,2,,v0.1,implemented,
  arithmetic,+,2,,v0.1,implemented,"as arithmetic functor inside is/2 expressions"
  arithmetic,-,2,,v0.1,implemented,
  arithmetic,*,2,,v0.1,implemented,
  arithmetic,/,2,,v0.1,implemented,
  arithmetic,//,2,,v0.1,implemented,integer division
  arithmetic,mod,2,,v0.1,implemented,
  arithmetic,rem,2,,v0.1,implemented,
  arithmetic,abs,1,,v0.1,implemented,
  arithmetic,sign,1,,v0.1,implemented,
  arithmetic,min,2,,v0.1,implemented,
  arithmetic,max,2,,v0.1,implemented,
  arithmetic,sqrt,1,,v0.1,implemented,
  arithmetic,**,2,,v0.1,implemented,
  arithmetic,^,2,,v0.1,implemented,
  arithmetic,between,3,,v0.1,implemented,"not ISO -- de facto library predicate (SWI etc). Not originally scoped in this catalog at all; shipped as part of episteme 0.1.0's initial extraction and exposed via Aletheia automatically, since it's a plain atom functor with nothing for ControlSyntax to translate -- see episteme_ahead_of_schedule"
  arithmetic,sin,1,,v0.2,implemented,"radians -- see episteme_v0_2_completed"
  arithmetic,cos,1,,v0.2,implemented,"radians -- see episteme_v0_2_completed"
  arithmetic,tan,1,,v0.2,implemented,"radians -- see episteme_v0_2_completed"
  arithmetic,exp,1,,v0.2,implemented,"e^X -- see episteme_v0_2_completed"
  arithmetic,log,1,,v0.2,implemented,"natural log -- see episteme_v0_2_completed"
  arith_compare,=:=,2,,v0.1,implemented,
  arith_compare,=\=,2,,v0.1,implemented,
  arith_compare,<,2,,v0.1,implemented,
  arith_compare,>,2,,v0.1,implemented,
  arith_compare,=<,2,,v0.1,implemented,
  arith_compare,>=,2,,v0.1,implemented,
  exception,throw,1,,v0.1,implemented,
  exception,catch,3,,v0.1,implemented,
  exception,type_error,2,,v0.1,implemented,"standard error-term constructor helper"
  exception,domain_error,2,,v0.1,implemented,"standard error-term constructor helper"
  exception,instantiation_error,1,,v0.1,implemented,"standard error-term constructor helper"
  exception,existence_error,2,,v0.2,implemented,"standard error-term constructor helper; thrown internally on an undefined-predicate call (Episteme.Engine.solve_user_predicate/2) and now also exposed as a directly-callable goal, same as type_error/2 and friends -- see episteme_v0_2_completed"
  operator,op,3,,v0.1,implemented,"feeds Ichor.Toolkit.Pratt table directly"
  database,dynamic,1,,v0.2,implemented,"directive -- see episteme_v0_2_completed"
  database,assert,1,assertz_alias,v0.2,implemented,"classic alias of assertz/1; shipped ahead of schedule -- see episteme_ahead_of_schedule"
  database,asserta,1,,v0.2,implemented,"shipped ahead of schedule -- see episteme_ahead_of_schedule"
  database,assertz,1,,v0.2,implemented,"shipped ahead of schedule -- see episteme_ahead_of_schedule"
  database,retract,1,,v0.2,implemented,"shipped ahead of schedule -- see episteme_ahead_of_schedule"
  database,retractall,1,,v0.2,implemented,"shipped ahead of schedule -- see episteme_ahead_of_schedule"
  database,abolish,1,,v0.2,implemented,"see episteme_v0_2_completed"
  database,clause,2,,v0.2,implemented,"now exposed as a callable goal, on top of the existing internal Episteme.Database.clauses_for/3 -- see episteme_v0_2_completed"
  aggregate,findall,3,,v0.3,implemented,"shipped ahead of schedule -- see episteme_ahead_of_schedule"
  aggregate,bagof,3,,v0.3,implemented,"groups by Goal's own free variables (not in Template, not Var^Goal-quantified); fails outright on no solutions, unlike findall/3 -- see episteme_v0_3_completed"
  aggregate,setof,3,,v0.3,implemented,"bagof/3 plus per-group sort+dedup and group ordering by standard order of terms -- see episteme_v0_3_completed"
  aggregate,aggregate_all,3,,later,not_started,
  list,length,2,,v0.1,implemented,
  list,append,3,,v0.1,implemented,
  list,member,2,,v0.1,implemented,
  list,reverse,2,,v0.1,implemented,
  list,nth0,3,,v0.1,implemented,
  list,nth1,3,,v0.1,implemented,
  list,last,2,,v0.1,implemented,
  list,msort,2,,v0.2,implemented,"see episteme_v0_2_completed"
  list,sort,2,,v0.2,implemented,"dedups + sorts by standard order -- see episteme_v0_2_completed"
  list,sort,4,,later,not_started,key/order variants
  list,permutation,2,,v0.2,implemented,"see episteme_v0_2_completed"
  list,sum_list,2,sumlist_alias,v0.2,implemented,"see episteme_v0_2_completed"
  list,max_list,2,,v0.2,implemented,"see episteme_v0_2_completed"
  list,min_list,2,,v0.2,implemented,"see episteme_v0_2_completed"
  list,list_to_set,2,,v0.2,implemented,"see episteme_v0_2_completed"
  list,exclude,3,,v0.2,implemented,"see episteme_v0_2_completed"
  list,include,3,,v0.2,implemented,"see episteme_v0_2_completed"
  list,foldl,4,,v0.2,implemented,"foldl/4..6 family for 1-3 list args -- see episteme_v0_2_completed"
  list,maplist,2,,v0.2,implemented,"maplist/2..6 family -- see episteme_v0_2_completed"
  atom_string,atom_codes,2,,v0.4,implemented,"see episteme_v0_4_atom_string_family"
  atom_string,atom_chars,2,,v0.4,implemented,"see episteme_v0_4_atom_string_family"
  atom_string,atom_length,2,,v0.4,implemented,"see episteme_v0_4_atom_string_family"
  atom_string,atom_concat,3,,v0.4,implemented,"enumerates every split on backtracking when only the whole is bound -- see episteme_v0_4_atom_string_family"
  atom_string,char_code,2,,v0.4,implemented,"see episteme_v0_4_atom_string_family"
  atom_string,number_codes,2,,v0.4,implemented,"see episteme_v0_4_atom_string_family"
  atom_string,number_chars,2,,v0.4,implemented,"see episteme_v0_4_atom_string_family"
  atom_string,upcase_atom,2,,v0.4,implemented,"see episteme_v0_4_atom_string_family"
  atom_string,downcase_atom,2,,v0.4,implemented,"see episteme_v0_4_atom_string_family"
  atom_string,sub_atom,5,,v0.4,implemented,"enumerates every decomposition on backtracking; Sub always an atom -- see episteme_v0_4_atom_string_family"
  atom_string,split_string,4,,v0.4,implemented,"real string type now decided (see string_type_decision) and implemented -- always produces strings, see episteme_v0_4_atom_string_family"
  atom_string,atomic_list_concat,2,,v0.4,implemented,"rule_2 alias candidate: opaque name -- not yet given a modern alias, see episteme_v0_4_atom_string_family"
  atom_string,atomic_list_concat,3,,v0.4,implemented,"rule_2 alias candidate: opaque name -- not yet given a modern alias; splits (not just joins) when the list is unbound, see episteme_v0_4_atom_string_family"
  atom_string,atom_string,2,,v0.4,implemented,"not in the original catalog -- added alongside the atom_* family once the string type was decided, SWI-style atom<->string conversion; see episteme_v0_4_atom_string_family"
  atom_string,string_to_atom,2,,v0.4,implemented,"not in the original catalog -- atom_string/2 with swapped argument order, see episteme_v0_4_atom_string_family"
  atom_string,string_concat,3,,v0.4,implemented,"not in the original catalog -- string-producing counterpart of atom_concat/3, see episteme_v0_4_atom_string_family"
  atom_string,string_chars,2,,v0.4,implemented,"not in the original catalog -- string-producing counterpart of atom_chars/2 (single-char strings, not atoms), see episteme_v0_4_atom_string_family"
  atom_string,string_codes,2,,v0.4,implemented,"not in the original catalog -- string-producing counterpart of atom_codes/2, see episteme_v0_4_atom_string_family"
  atom_string,string_length,2,,v0.4,implemented,"not in the original catalog -- string-producing counterpart of atom_length/2, see episteme_v0_4_atom_string_family"
  atom_string,number_string,2,,v0.4,implemented,"not in the original catalog -- string-producing counterpart of atom_string/2 for numbers, see episteme_v0_4_atom_string_family"
  type_check,string,1,,v0.4,implemented,"not in the original catalog -- added alongside the new string term class; true only for a real string, never for an atom -- see episteme_v0_4_atom_string_family"
  io,write,1,,v0.1,implemented,"minimal REPL output need"
  io,writeln,1,,v0.1,implemented,
  io,print,1,write_alias,v0.1,implemented,"rule_2: readable alias of write/1"
  io,nl,0,,v0.1,implemented,
  io,format,2,,v0.4,implemented,"practical directive subset (~w/~p/~q/~a/~d/~s/~i/~n/~~, no column/radix directives, no numeric-prefixed ~Nd) -- see episteme_v0_4_format"
  io,format,1,,v0.4,implemented,"not in the original catalog -- format/2 with Args = [], added alongside it since it's nearly free -- see episteme_v0_4_format"
  io,read_term,2,,later,not_started,
  dcg,-->,2,dcg_translate,v0.5,implemented,"clause translation via Episteme.Dcg.translate_rule/2, applied by Database.consult_forms/2's {:dcg, head, body} form and by assert/1 for a -->/2-shaped clause term (not load-time-only, also dynamic); dcg_translate/2 exposed as a directly-callable goal for introspection -- see episteme_v0_5_dcg"
  dcg,phrase,2,,v0.5,implemented,"cut-opaque, like call/N -- see episteme_v0_5_dcg"
  dcg,phrase,3,,v0.5,implemented,"see episteme_v0_5_dcg"
```

## 7. Roadmap

```toon
roadmap[6]{version,theme,status}:
  v0.1,"minimal true core: reader (lexer+Pratt), Term IR, unification, SLD-resolution, cut (real, not once/1-only), core control, is/2 arithmetic, exceptions, op/3, minimal I/O, REPL/consult",done
  v0.2,"dynamic database (assert/retract family), term inspection (functor/arg/univ), standard order of terms, ground/1, more list predicates, forall/ignore -- every predicate_catalog row tagged v0.2 is status=implemented in episteme (episteme_v0_2_completed) AND reachable end-to-end from .alp source (aletheia_reader_v0_2_v0_5_integration) via aletheia's temporary path dependency on episteme's develop branch (aletheia_episteme_path_dependency_interim). Not yet released to Hex (neither package)",done_pending_hex_release
  v0.3,"aggregation: findall/bagof/setof -- findall/3 shipped ahead of schedule (episteme_ahead_of_schedule); bagof/3 and setof/3 completed episteme-side (episteme_v0_3_completed) and are reachable from .alp source the same way as v0.2 (both are plain atom-functor goals, no reader changes needed) -- see aletheia_reader_v0_2_v0_5_integration. Not yet released to Hex",done_pending_hex_release
  v0.4,"real string type decision + atom/string predicate family + format/2 -- string type decided (real Elixir binary, string_type_decision) and implemented episteme-side (episteme_v0_4_atom_string_family, episteme_v0_4_format), AND now reachable from .alp source: double-quoted string literals added to the reader grammar, the atom/string predicate family and format/1,2 needed no reader changes (plain atom-functor goals) -- see aletheia_reader_v0_2_v0_5_integration. Only genuine gap: =../2's ISO punctuation can't be tokenized by this reader's simplified lexer (a lone '.' inside a longer operator token is indistinguishable from end-of-clause); univ/2 works directly. Not yet released to Hex",done_pending_hex_release
  v0.5,"DCG (-->/phrase) -- implemented episteme-side (episteme_v0_5_dcg): Episteme.Dcg translates a Head --> Body rule into an ordinary clause threading an S0/S difference-list pair through every nonterminal call (practical subset -- terminals, {Goal}, cut, and/or/if_then/if_then_else/not, a bare nonterminal, a variable body -- no call//N pushback); phrase/2,3 runs a DCG body as a goal, dcg_translate/2 is the readable --> alias. Now reachable from .alp source too: a dedicated Head --> Body. clause form added to the reader grammar (not parsed through the operator table), plus {Goal} (ISO's own '{}'/1 term shape, general syntax) -- see aletheia_reader_v0_2_v0_5_integration. Every v0.5-tagged predicate_catalog row is status=implemented AND reachable. Not yet released to Hex",done_pending_hex_release
  later,"module system, tabling, CLP(FD) — explicitly unscheduled, need-driven only",not_started
```

## 8. Interop and execution model

```toon
interop:
  model: "isolated engine state + Elixir-callable FFI"
  rejected_alternative: "deep OTP integration (GenServer-per-session, supervised concurrent queries) — explicitly deferred, not ruled out forever, just not v0.1-v0.5 scope"
  backtracking_representation: "Ichor.Backtrack.Tree directly — lazy, manually-unfolded search tree, depth-first/clause-order. No hand-rolled alternative needed; this was an open question, now resolved by Ichor already providing it."
```

## 9. Decisions log

```toon
decisions_log[27]{date,decision,choice,status}:
  2026-07-27,embedding_model,"classic Prolog syntax via reader (not Elixir-native macros)",final
  2026-07-27,engine_strategy,"tree-walking / lazy-search interpreter (not WAM bytecode compilation)",final_for_v0.1-v0.5
  2026-07-27,initial_scope,"minimal true core first, staged expansion need-first (not full-ISO-upfront)",final
  2026-07-27,interop_model,"isolated engine state + FFI (not deep OTP integration)",final_for_v0.1-v0.5
  2026-07-27,project_name,Aletheia,final
  2026-07-27,file_extension,.alp,final
  2026-07-28,backtracking_representation,"Ichor.Backtrack.Tree (resolved by Ichor update, not by prior A/B choice)",final
  2026-07-28,operator_precedence_reader,"Ichor.Toolkit.Pratt (resolved by Ichor update; previously scoped as hand-rolled)",final
  2026-07-28,cut_semantics,"implemented as a distinct clause-scoped primitive via throw/catch, NOT a thin wrapper over Backtrack.once/1 -- see cut_implementation below",final_implemented_and_tested
  2026-07-28,reader_mechanism,"a real .aether grammar (lib/aletheia/reader/grammar.aether) + Ichor.Toolkit.Pratt via @native, driven by Grammar.VM.run_sequence/4 -- not literal reuse of Aether.Lexer, which is Ichor's own grammar-DSL lexer, not a general-purpose one. Comma is a genuine xfy(1000) operator here (unlike ichor's own test/prolog/prolog.aether fixture, which leaves it grammar-structural), needing a second @native entry point (arg_term) parsed at a raised min_prec for ISO's own \"argument priority =< 999\" rule",superseded_by_ichor_runtime_migration_2026-07-29 (Grammar.VM.run_sequence/4 replaced by a checked-in mix ichor.gen output's own run_sequence/2 -- same mechanism, no longer parsed at runtime; rest of this decision still holds)
  2026-07-29,ichor_runtime_migration,"switched from {:ichor, path: \"../ichor\"} to two git deps pinned to github.com/joetjen/ichor@feature/runtime -- {:ichor_runtime, ..., sparse: \"packages/ichor_runtime\"} as the one real runtime dependency, {:ichor, ..., only: :dev, runtime: false}. The reader's grammar is now generated ahead of time via mix ichor.gen (aliased mix gen.grammar) into lib/aletheia/reader/grammar_generated.ex (checked in), instead of Aether.Parser.parse/Grammar.Analysis.run being called at every consult_string/2 -- the latter literally cannot work once ichor is dev-only, since Aether.Parser/Grammar.Analysis aren't loaded outside :dev. Verified: full test suite green under MIX_ENV=test (where ichor is genuinely absent), and MIX_ENV=prod mix compile pulls in only ichor_runtime, not ichor",superseded_by_ichor_runtime_hex_release_2026-07-29 (git+sparse dependency mechanism replaced by plain Hex version constraints once both packages were published; the mix ichor.gen/dev-only-ichor architecture itself is unchanged and still holds)
  2026-07-29,ichor_runtime_split_gap,"ichor_runtime (as originally split) didn't include Ichor.Toolkit.Pratt/TermWalk or Ichor.Backtrack(+Bindings/Term/Tree) -- all called directly by Aletheia's own runtime code (the @native Pratt callback, Term, Engine, every builtin), not just by generated parser code. Fixed upstream in ichor's own repo (commit 9dc5d09 on feature/runtime, pushed): moved all three into ichor_runtime, since none have any dev-only dependency of their own. Documented in ichor's own CHANGELOG.md as the same class of gap as its earlier evaluate_node/3 fix",final
  2026-07-29,ichor_runtime_hex_release,"both packages published independently to Hex -- ichor 0.2.1 (Aether front-end, Grammar.Analysis, both codegen backends, plus new Ichor.GrammarImport for ABNF/BNF/EBNF/PEG sources; still only: :dev, runtime: false here) and ichor_runtime 0.1.0 (now its own repository, github.com/joetjen/ichor_runtime, not a subdirectory of ichor's; the sole real runtime dependency). mix.exs deps simplified from git+branch+sparse+override to plain {:ichor_runtime, \"~> 0.1.0\"} / {:ichor, \"~> 0.2.0\", only: :dev, runtime: false}. Regenerated grammar_generated.ex against the published mix ichor.gen to confirm codegen output is unaffected by the version bump; full precommit (format/credo --strict/sobelow/test/dialyzer) still clean",superseded_by_episteme_hex_release_2026-08-04 (ichor_runtime/ichor version constraints bumped again, to ~> 0.2/~> 0.3, pulled in transitively by episteme's own Hex release; the git+sparse -> plain-Hex-constraint switch documented here still holds)
  2026-07-28,cut_implementation,"! succeeds once, but its own backtrack-past-me continuation throws {:aletheia_cut, barrier} (a barrier = make_ref() minted fresh per predicate call / call//N / once/1 / \\+ per ISO cut-opacity); Aletheia.Engine.guard_cut/2 wraps each call's own lazy solution stream, catching only its own barrier and re-throwing anything else. Ichor.Backtrack.Tree's combinators need zero changes: they're plain function calls with no try inside them, so a throw passes through conjunction/disjunction/once untouched. A bindings-borne \"cut fired\" marker was considered and rejected: `p :- !, fail.` with a second clause `p :- true.` must fail p outright, but a clause body that never produces a solution gives a marker-on-solutions scheme nothing to inspect -- cut has an effect even along a path that ultimately fails",final
  2026-07-28,control_constructs_module_placement,"true/fail/,/;/->/!/\\+/call/once live directly in Aletheia.Engine, not a separate Builtins.Control module as DESIGN.md's original module-layout table sketched -- once actually implemented they turned out inseparable from the cut-barrier machinery (guard_cut, fresh barriers per call), not independent predicates dispatchable through a generic table",final
  2026-08-01,episteme_split,"split Aletheia.Term/Database/Engine/Builtins.* out into a new sibling package, episteme (Episteme.Term/Database/Engine/Builtins.*, plus a top-level Episteme module mirroring Aletheia's own query/2 family but over already-built terms, no text parsing). Rationale: none of unification/SLD-resolution/clause storage/cut/builtins depend on Aletheia's syntax concretely -- Aletheia's reader is one producer of Episteme terms, not the only possible one, and the split lets Episteme stand alone as a Prolog-like rule engine/query layer for Elixir callers who don't want .alp syntax at all. Internal-only Elixir throw tags renamed :aletheia_throw/:aletheia_cut -> :episteme_throw/:episteme_cut (Episteme.Engine/Episteme.Builtins.Exceptions), since they're now Episteme's own implementation detail, not Aletheia's. aletheia depends on episteme via {:episteme, path: \"../episteme\"} (both still pre-Hex-release); ichor_runtime is now a dependency of both packages directly (episteme for Backtrack/TermWalk, aletheia for Toolkit.Pratt in the reader itself) -- see 3.1",superseded_by_episteme_hex_release_2026-08-04 (path dependency replaced by a plain Hex version constraint once episteme was published; the split itself is unchanged and still holds)
  2026-08-04,episteme_hex_release,"episteme published to Hex as episteme 0.1.0 (own repository, github.com/joetjen/episteme, independent release cadence from aletheia). aletheia's mix.exs dependency simplified from {:episteme, path: \"../episteme\"} to plain {:episteme, \"~> 0.1\"} -- no sibling checkout required to build aletheia anymore. Pulled in ichor_runtime ~> 0.2 and ichor ~> 0.3 transitively (episteme's own runtime dependency), both bumped here too; regenerated grammar_generated.ex against ichor 0.3's codegen (raw capture shape change, map -> ordered list -- see ichor's own CHANGELOG 0.3.0) to stay current",final
  2026-08-04,episteme_control_syntax_translation,"episteme 0.1.0's own first Hex release renamed every ISO-punctuation control construct/comparison operator it dispatches on to a plain-English name (,/2 -> and/2, ;/2 -> or/2, ! -> cut, \\+/1 -> not/1, (Cond->Then;Else) -> if_then_else/3 (explicit, replacing an old implicit ;-wrapping-> pattern match the engine no longer does), (Cond->Then) -> if_then/2, =/2 -> unify/2, \\=/2 -> not_unify/2, ==/2 -> equal/2, \\==/2 -> not_equal/2, =:=/2 -> numeric_equal/2, =\\=/2 -> numeric_not_equal/2, =</2 -> less_or_equal/2, >=/2 -> greater_or_equal/2; +,-,*,/,<,> unchanged, never punctuation-as-control to begin with) -- Episteme has no reader of its own for ISO punctuation to be conventional syntax against. Aletheia.Reader itself keeps producing ISO-punctuation-named terms unchanged (reader_test.exs asserts this directly, and it is the correct, syntax-faithful reading of `.alp` source); the new Aletheia.Reader.ControlSyntax.to_goal/1 bridges the gap, applied by lib/aletheia.ex to rule bodies (before Database.consult_forms/2) and query/query_lazy goals (after parse_goal/1), never to fact terms or rule heads (plain data, matched structurally, never dispatched as goals). Implemented as an Ichor.Toolkit.TermWalk.rewrite/3 pass: transform is applied top-down before TermWalk's own recursion into the (possibly-just-returned) compound's args, so the if-then-else special case can pattern-match the still-untranslated ;-wrapping-> shape directly at the parent node and emit if_then_else/3 in one step, while every other node falls through to a plain {name,arity} -> new_name table lookup",final
  2026-08-05,episteme_ahead_of_schedule,"audit against predicate_catalog found episteme 0.1.0's initial extraction (see episteme_split) shipped several predicates beyond aletheia's own originally-scoped v0.1 catalog: assert/1, asserta/1, assertz/1, retract/1, retractall/1, forall/2, and findall/3 (all catalog-tagged v0.2/v0.3, roadmap-tagged not_started), plus between/3 (not in the catalog at all). None needed any Aletheia-side work to reach `.alp` callers -- none involve ISO punctuation, so Aletheia.Reader.ControlSyntax never touches them; a plain atom-functor goal like assert(foo(1)) already flows untouched from the reader straight through to Episteme.Engine. Verified end-to-end via Aletheia.query/2 (assert+retract, assertz+findall, forall, between all producing correct solutions) before updating this doc. predicate_catalog retrofitted with a status column (implemented/partial/not_started) to make this distinction from milestone (the intended scope grouping) explicit going forward -- see `0`'s own on_milestone_completion rule, which already presumed this column existed. Also found and fixed three stale TOON row-count headers unrelated to this specific gap: predicate_catalog[97] (actually 123 rows before this change), roadmap[7] (actually 6), decisions_log[16] (actually 18, from two earlier entries added without updating the header)",final
  2026-08-04,episteme_v0_2_completed,"closed out the entire v0.2 predicate_catalog slice in episteme's own repository, across three feature branches merged to episteme's develop via --no-ff: ignore/1 and unify_with_occurs_check/2 (feature/ignore-and-occurs-check); existence_error/2 exposed as a directly-callable goal alongside type_error/2/domain_error/2/instantiation_error/1 (feature/existence-error-goal); and the five remaining evaluable functors sin/1, cos/1, tan/1, exp/1, log/1 (feature/trig-and-log-functors, found missing only after the first two branches were already merged and this doc's own catalog was re-checked row by row) -- the six v0.2 rows that were still not_started/partial. Every other v0.2 row (standard order of terms, term inspection, dynamic/abolish/clause, the full list-predicate family) was already implemented on episteme's develop branch but this doc had not been updated to say so. All three changes tested (episteme's own mix precommit: format/credo --strict/sobelow/196 tests/dialyzer, all clean) -- not yet pushed to episteme's origin, and not yet released to Hex. aletheia's own mix.exs dependency is unchanged ({:episteme, \"~> 0.1\"}, still resolving to the published 0.1.0 release) -- see the roadmap's own v0.2 entry for why that means v0.2 is not yet actually usable through Aletheia.query/2 despite being catalog-complete in episteme",final
  2026-08-04,episteme_v0_3_completed,"added bagof/3 and setof/3 to episteme (feature/bagof-setof, merged to episteme's develop via --no-ff), closing out v0.3 -- both fail outright (not List = []) on no solutions, unlike findall/3, and group solutions by Goal's own free variables (mentioned in Goal, not in Template, not existentially quantified via Var^Goal), backtracking one solution per distinct group; setof/3 additionally sorts/dedups each group and orders the groups themselves by standard order of terms. Built on two new Episteme.Term functions -- term_variables/1 (real Prolog's term_variables/2, not itself exposed as a goal) and sort_by_order/1/sort_unique/1, the latter two also now shared by msort/2/sort/2 (replacing what had been private duplicate logic in Episteme.Builtins.Lists). Tested (mix precommit clean, 202 tests) and merged to episteme's develop, same not-yet-pushed/not-yet-released status as episteme_v0_2_completed -- v0.3 is catalog-complete in episteme but, like v0.2, not yet consumable via Aletheia.query/2 until a new episteme Hex release and an aletheia dependency bump",final
  2026-08-04,string_type_decision,"resolved term_deferred_decisions' string_type row: a real Elixir binary-backed string type (SWI-Prolog-style, not ISO's code-list default) -- a genuinely new atomic term class, not a list of codes. User's explicit call, made when starting v0.4: modern ergonomics/performance over strict ISO purity, consistent with this project's own stated philosophy (2 Philosophy: 'modernize names only' already accepts diverging from raw ISO where it clearly helps; a real string type is the same kind of call applied to term representation rather than naming). Implemented as plain native Elixir binaries (String.t()) with NO wrapper struct -- exactly the same pattern atoms/integers/floats already use (raw host-language values, not a dedicated Episteme.Term struct) -- unify's existing 'anything else compares via plain ==/2' fallback (compound?/1 already false for a binary by the existing catch-all clause) makes unify/not_unify/equal/not_equal all work correctly with zero Ichor.Backtrack.Bindings changes. Two places in Episteme.Term genuinely needed new code: standard order of terms (term_class/1 needed an explicit string case -- without it every binary would hit the compound catch-all and crash decompose/1) placed between atom and compound (Var < Number < Atom < String < Compound, matching SWI's own convention), and to_text/1 (double-quoted rendering). See 4's own terms table for the row.",final
  2026-08-04,episteme_v0_4_atom_string_family,"implemented the entire v0.4 atom_string-tagged predicate_catalog slice in episteme's own repository (feature/string-type, merged to episteme's develop via --no-ff), in a new Episteme.Builtins.Strings module: atom_codes/2, atom_chars/2, atom_length/2, atom_concat/3, sub_atom/5, char_code/2, number_codes/2, number_chars/2, upcase_atom/2, downcase_atom/2, atomic_list_concat/2,3 (the original catalog rows) plus atom_string/2, string_to_atom/2, string_concat/3, string_chars/2, string_codes/2, string_length/2, number_string/2 (SWI-style real-string counterparts, added beyond the original catalog once string_type_decision settled what they'd even produce) and a new string/1 type check (atomic/1 now also true for strings). atom_concat/3, string_concat/3, and sub_atom/5 all enumerate every matching decomposition on backtracking when only one side is bound, via a shared unify_pairs/2 helper -- the same 'generate every candidate, let unify filter it' shape append/3 already uses over lists, rather than separate deterministic/nondeterministic code paths. Every String.to_atom/1 call site (a dozen, across this one module) routes through one private to_prolog_atom/1 carrying a single sobelow_skip justification (the same accepted atom-table-exhaustion risk already documented for the reader) instead of the low-confidence DOS.StringToAtom finding repeated a dozen times. Tested (mix precommit clean: format/credo --strict/sobelow/dialyzer, 236 tests) and merged to episteme's develop -- not yet pushed to episteme's origin, not yet released to Hex, so not yet consumable via Aletheia.query/2, same as episteme_v0_2_completed/episteme_v0_3_completed. Only format/2 remains not_started for v0.4 (see roadmap)",final
  2026-08-04,episteme_v0_4_format,"implemented format/1,2 in episteme's own repository (feature/format, merged to episteme's develop via --no-ff), closing out v0.4's predicate_catalog entirely -- a practical directive subset (~w/~p/~q all Term.to_text/1, since there's no operator-aware or quoted writer yet to tell them apart with; ~a, ~d, ~s, ~i, ~n, ~~), deliberately not ISO/SWI's full one (no column/radix directives, no numeric-prefixed ~Nd). format/1 (Args = []) added alongside format/2 despite not being in the original catalog, the same 'cheap enough to add once you're already there' judgment call as several v0.1-v0.2 predicates before it. A single non-list Args is treated as [Args], matching SWI's own leniency. Lives in Episteme.Builtins.Io, reusing Episteme.Builtins.Strings.require_atomic_text/2 for the format string itself. Tested (mix precommit clean, 246 tests) and merged to episteme's develop -- same not-yet-pushed/not-yet-released status as episteme_v0_2_completed/episteme_v0_3_completed/episteme_v0_4_atom_string_family. Every v0.4-tagged predicate_catalog row is now status=implemented",final
  2026-08-05,episteme_v0_5_dcg,"implemented DCG (Definite Clause Grammar) support in episteme's own repository (feature/dcg, merged to episteme's develop via --no-ff), closing out v0.5 -- the last roadmap-numbered milestone (later is need-driven only, see roadmap). New Episteme.Dcg module (translate_rule/2, translate_body/3) translates a Head --> Body rule into an ordinary clause, threading an incoming/outgoing difference-list pair (S0/S) through every nonterminal call -- a practical subset of real DCG translation (terminals, {Goal} via ISO's own '{}'/1 embedded-goal shape, cut, and/2, or/2, if_then/2, if_then_else/3, not/1, a bare nonterminal, and a variable body translated to phrase(Var, S0, S)), deliberately not all of it (no call//N pushback -- parameterized higher-order nonterminals, not yet needed). phrase/2,3 (Episteme.Engine) runs a DCG body as an ordinary goal, cut-opaque like call/N; dcg_translate/2 is the readable --> alias (predicate_catalog's own modern_alias column already named it) for introspection, unifying its second argument with the translated clause without storing it; a new {:dcg, head, body} Database.consult_forms/2 form and a -->/2-shaped clause term passed to assert/1 (same as :-/2 is already special-cased in store_clause/3) both translate and store. Tested (mix precommit clean: format/credo --strict/sobelow/dialyzer, 267 tests) and merged to episteme's develop -- same not-yet-pushed/not-yet-released status as every v0.2-v0.4 entry before it. Every v0.5-tagged predicate_catalog row is now status=implemented",final
  2026-08-05,aletheia_episteme_path_dependency_interim,"switched aletheia's own mix.exs dependency on episteme from {:episteme, \"~> 0.1\"} (the published Hex release, which predates every v0.2-v0.5 predicate) to {:episteme, path: \"../episteme\"} -- a sibling checkout, same shape episteme_split's own pre-episteme_hex_release phase used. User's explicit plan, stated directly: finish implementing aletheia against episteme's current develop branch first, verify it all actually works end-to-end; only once that's done and working, release episteme to Hex, bump aletheia's dependency to that release, and release aletheia itself. Switch back to a plain Hex version constraint once episteme is released -- this is deliberately an interim state, not a final one",final
  2026-08-05,aletheia_reader_v0_2_v0_5_integration,"wired aletheia's reader up to reach the entire v0.2-v0.5 predicate surface episteme_v0_2_completed through episteme_v0_5_dcg shipped, closing the gap those entries' own 'not yet consumable via Aletheia' caveats described (see aletheia_episteme_path_dependency_interim for the dependency side of that). Three genuine reader/grammar additions were needed -- everything else (ignore/1, unify_with_occurs_check/2, bagof/3/setof/3, term inspection, the dynamic-database round-out, the list-predicate family, the atom/string conversion family, format/1,2) is a plain atom-functor goal already flowing through untouched, the same as episteme_ahead_of_schedule's own items: (1) double-quoted STRING literals (grammar.aether), no escape processing, same simplification QATOM already has, producing a real Elixir binary via Aletheia.Reader.Actions' new handle_token(:STRING, ...); (2) {Goal} (ISO's own '{}'/1 term shape) as a new `curly` primary alternative -- ordinary syntax anywhere, not DCG-specific, though Episteme.Dcg.translate_body/3 is what gives it special meaning in a DCG body; (3) `Head --> Body.` as a dedicated `dcg_rule` clause production (a new DCG_OP '-->' token, structurally parallel to RULE_OP/':-', not routed through the Pratt operator table at all -- no op/3 entry needed), producing a {:dcg, head, body} form Aletheia.to_engine_form/1 control-syntax-translates the same way an ordinary rule body already is (a DCG body uses the same ISO punctuation, and Episteme.Dcg.translate_body/3 expects Episteme's own plain-English names already). Also added: @</2, @>/2, @=</2, @>=/2 to the default operator table (priority 700, same class as =/==) and to Aletheia.Reader.ControlSyntax's translation table (order_less/order_greater/order_less_or_equal/order_greater_or_equal) -- standard order of terms has real ISO punctuation forms this reader had simply never been taught, unlike compare/3 which was already a plain word. Deliberately NOT attempted: =../2 (univ) -- this reader's DOT token always means end-of-clause, so a '.' embedded inside a longer operator-symbol run (as in '=..') can't be tokenized as one atom without deeper lexer surgery (distinguishing clause-terminating-dot from part-of-a-longer-token-dot, a well-known hard part of real Prolog lexers); univ/2 already works directly with zero reader changes, so this is a documented gap, not a blocker. grammar_generated.ex regenerated via `MIX_ENV=dev mix gen.grammar` per usual. Found and fixed a real pre-existing gap along the way: aletheia's own mix.exs precommit alias ran plain `sobelow`, not `sobelow --skip` (episteme's already had this right) -- meaning every #sobelow_skip comment in aletheia's own codebase was silently being ignored; fixed, and used it to consolidate the reader's own String.to_atom/1 call sites (ATOM/QATOM/BANG/SEMI/OP token handlers -- the same atom-table-exhaustion risk already documented) through one to_prolog_atom/1, mirroring episteme's own Episteme.Builtins.Strings precedent. Tested (mix precommit clean: format/credo --strict/sobelow --skip/test/dialyzer, 47 tests) on feature/reader-v0.2-v0.5-integration",final
```

## 10. Glossary (Prolog terms, for an agent without Prolog background)

```toon
glossary[12]{term,meaning}:
  goal,"a term to be proved/solved, e.g. member(X, [1,2,3])"
  clause,"head :- body. (a rule) or head. (a fact) — one unit of the program"
  functor,"the name+arity identity of a compound term, e.g. foo/2 for foo(a,b)"
  unification,"making two terms structurally identical by binding variables, the core operation of Prolog"
  backtracking,"on failure, undo bindings back to the last choice point and try the next alternative"
  choice_point,"a point in execution where more than one clause/disjunct could still be tried"
  cut,"! — commits to choices made since entering the current clause, pruning remaining choice points within that clause"
  SLD_resolution,"Selective Linear Definite clause resolution — the specific proof procedure Prolog uses"
  resolvent,"the goal(s) remaining to be proved after one resolution step"
  Horn_clause,"a clause with at most one positive literal — the logical foundation Prolog programs are built from"
  occurs_check,"a unification safeguard preventing a variable from binding to a term that contains itself (off by default in ISO Prolog)"
  DCG,"Definite Clause Grammar — Prolog's built-in notation (-->) for writing parsers as grammar rules"
```

## 11. Planned module layout

Only `aletheia`'s own modules are listed here (the reader, REPL, and
top-level API) -- `Episteme.Term`/`Database`/`Engine`/`Builtins.*` moved
to the separate `episteme` package as of `episteme_split`
(decisions_log) and are that repository's own module layout to
document, not this one's.

```toon
modules[9]{path,purpose,milestone}:
  lib/aletheia.ex,"top-level API: consult/1, consult_string/2, query/2, query_once/2, query_lazy/2 + next_solution/2 -- parses via Aletheia.Reader, translates rule bodies/query goals via Aletheia.Reader.ControlSyntax, delegates solving to Episteme (query/query_lazy/next_solution are thin wrappers over Episteme's own, query_once reuses this module's own query/2)",v0.1
  lib/aletheia/reader.ex,"exposes consult_string/2 over Aletheia.Reader.Grammar.run_sequence/2 (the generated module below)",v0.1
  lib/aletheia/reader/grammar.aether,"the real Aletheia lexical+syntactic grammar (Aether) -- source grammar, hand-edited",v0.1
  lib/aletheia/reader/grammar_generated.ex,"mix ichor.gen (mix gen.grammar) output from grammar.aether -- checked in, not regenerated on mix compile; only calls ichor_runtime at actual runtime",v0.1
  lib/aletheia/reader/pratt.ex,"the term/arg_term @native(...) callback over Ichor.Toolkit.Pratt",v0.1
  lib/aletheia/reader/actions.ex,"Ichor.Actions impl: raw capture tree -> Episteme.Term, default operator table, op/3 directive application, per-clause variable freshening",v0.1
  lib/aletheia/reader/control_syntax.ex,"rewrites a parsed goal from Aletheia.Reader's own ISO-punctuation names (,/2, ;/2, ->/2, !, =/2, ...) to the plain-English control-construct/comparison names Episteme.Engine dispatches on (and/2, or/2, cut, unify/2, ...), as of episteme_hex_release -- Episteme itself no longer accepts ISO punctuation directly",v0.1
  lib/aletheia/repl.ex,"consult + interactive query loop, genuinely lazy (pulls one solution at a time via query_lazy/2+next_solution/2)",v0.1
  test/support/query_helper.ex,"consult+query test shorthand",n/a
```
