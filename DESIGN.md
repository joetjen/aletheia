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
  hex_availability_checked: 2026-07-29 (ichor 0.2.1, ichor_runtime 0.1.0 both published)
  host_language: Elixir
  host_platform: BEAM
  status: v0.1 implemented and tested (see roadmap); v0.2+ not started
  local_path: "~/Projects/__mine__/aletheia"
  hard_dependency: "ichor_runtime ~> 0.1.0 (real runtime dep, own Hex package/repo) + ichor ~> 0.2.0 (only: :dev, runtime: false) -- both published to Hex; see ichor_runtime_split"
  license: MIT (see LICENSE)
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
term data, using Ichor's lexer and Pratt parser directly) and a
**resolution engine** (term data + clause database → solutions, using
Ichor's `Backtrack` search substrate plus Aletheia's own SLD-resolution
layer, clause database, and builtin predicates — none of which Ichor
provides, since Ichor's own `Actions` evaluation model is a single-pass
fold and cannot represent multi-solution backtracking search on its own).

### 3.0 The `ichor`/`ichor_runtime` split

Ichor split itself into two independently published Hex packages —
`ichor ~> 0.2.0` and `ichor_runtime ~> 0.1.0` (`ichor_runtime` is its
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
  term_ir,Aletheia.Term,aletheia,implemented
  unify,Ichor.Backtrack.Bindings,ichor_runtime,available
  search,Ichor.Backtrack.Tree,ichor_runtime,available
  resolve,Aletheia.Engine (SLD-resolution over Backtrack primitives + clause DB + cut barriers),aletheia,implemented
```

```toon
ichor_primitives[8]{module,role,prolog_concept,status}:
  Aletheia.Reader.Grammar.run_sequence/2,"mix ichor.gen-generated equivalent of Grammar.VM.run_sequence/4 -- parses source as a sequence of top-level clauses, threading context (the growing op/3 operator table) from each into the next",reader driver,implemented (generated ahead of time, not at compile time)
  Ichor.Toolkit.Pratt,"precedence-climbing parse over a runtime-mutable prefix/infix/postfix operator table",op/3-driven term reading,"available (ichor_runtime, moved from ichor -- see 3.0)"
  Ichor.Backtrack,"behaviour: unit/fail/disjunction/conjunction/once over a goal := bindings -> solutions",true/fail/;//,/cut-ish,"available (ichor_runtime, moved from ichor -- see 3.0)"
  Ichor.Backtrack.Tree,"concrete engine: manually-unfolded lazy search tree, depth-first clause-order",SLD search tree,"available (ichor_runtime, moved from ichor -- see 3.0)"
  Ichor.Backtrack.Bindings,"structural unification; occurs-check off by default (matches ISO), occurs-check variant available",=/2 and unify_with_occurs_check/2,"available (ichor_runtime, moved from ichor -- see 3.0)"
  Ichor.Backtrack.Term,"behaviour: variable?/1, var_id/1, compound?/1, deconstruct/1, reconstruct/2 (optional)",pluggable term representation,implemented_by_aletheia (Aletheia.Term; lists decompose as '.'/2)
  Ichor.Toolkit.TermWalk,"fold/2 and rewrite/3 over any Backtrack.Term implementation",variable-renaming-apart on clause instantiation + resolve_deep/2,"implemented_and_used (ichor_runtime, moved from ichor -- see 3.0)"
  Ichor.Toolkit.Result,"Result.reduce_ok and friends over {:ok,_}/:fail-shaped pipelines",used inside Bindings.unify_compound; reusable in engine code,available (ichor_runtime)
```

### 3.1 Known hard problem: cut vs `once/1`

```toon
risk:
  id: cut-scoping
  severity: high
  statement: "Ichor.Backtrack.once/1 is Prolog's once/1 builtin (first solution of a goal), not Prolog's ! (cut). Cut commits to choices made since entering the CURRENT CLAUSE specifically — a narrower, clause-scoped commitment, not 'stop after one solution of whatever goal contains it'. once/1 will pass naive tests and diverge on nested-clause cases."
  mitigation: "Design cut as a distinct primitive in Aletheia.Engine: thread a clause-scoped cut barrier/signal through conjunction that once/1 alone does not provide. Do not implement ! as a thin wrapper over Backtrack.once/1 without a barrier check. Write cut-specific tests (cut inside disjunction inside a clause; cut inside a called predicate must NOT affect the caller) before considering cut done."
  status: "resolved -- implemented via throw/catch barriers (see decisions_log cut_implementation), both named tests plus the p:-!,fail. p:-true. distinguishing case pass (test/aletheia/cut_test.exs)"
```

### 3.2 Known hard problem: atom exhaustion

```toon
risk:
  id: atom-table-exhaustion
  severity: medium
  statement: "Representing Prolog atoms as raw Elixir atoms is convenient (native ==/2, cheap) but the BEAM atom table is not garbage collected. A long-running process reading untrusted or generated Prolog source repeatedly is a DoS vector."
  mitigation: "Acceptable for v0.1-v0.5 (library embedded in your own trusted programs). Before ever exposing Aletheia to untrusted/generated source input, revisit: interned-string atoms or a bounded atom cache instead of raw BEAM atoms."
  status: accepted for now, documented, revisit before any untrusted-input use case
```

## 4. Term representation

```toon
terms[6]{prolog_term,elixir_representation,notes}:
  atom,":name (raw Elixir atom)","see risk atom-table-exhaustion"
  integer,integer,"native BEAM bignum, no overflow handling needed"
  float,float,"native; IEEE 754 double, matches ISO float semantics closely enough for v0.1"
  variable,"%Aletheia.Term.Var{ref: reference(), name: String.t()}","ref is var_id/1 for Backtrack.Term; name is display-only, never used for identity"
  compound,"%Aletheia.Term.Compound{name: atom(), args: [term]}","deconstruct/1 -> {name,args}; reconstruct/2 rebuilds"
  list,"[h | t] using native Elixir lists","proper AND improper lists both representable natively; [] is the empty-list atom, same as Prolog"
```

```toon
term_deferred_decisions[1]{topic,options,status}:
  string_type,"code-list (ISO default) vs real Elixir binary-backed string type",deferred to milestone v0.4; ISO default (code-list) NOT chosen as final, just not yet decided
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
predicate_catalog[97]{category,classic_name,arity,modern_alias,milestone,notes}:
  control,true,0,,v0.1,
  control,fail,0,,v0.1,"false/0 is a standard alias, both classic"
  control,",",2,,v0.1,"conjunction; maps to Backtrack.conjunction/2"
  control,;,2,,v0.1,"disjunction; maps to Backtrack.disjunction/2"
  control,->,2,,v0.1,if-then
  control,!,0,cut,v0.1,"see risk cut-scoping; NOT a thin once/1 wrapper"
  control,\+,1,,v0.1,negation as failure
  control,call,1,,v0.1,
  control,call,2,,v0.1,"call/N up to at least 8, partial application"
  control,once,1,,v0.1,"this one genuinely IS Backtrack.once/1 directly"
  control,forall,2,,v0.2,"expressible via \\+ (Cond, \\+ Action)"
  control,ignore,1,,v0.2,
  unify,=,2,,v0.1,"Backtrack.Bindings.unify/4"
  unify,\=,2,,v0.1,
  unify,unify_with_occurs_check,2,,v0.2,"Backtrack.Bindings.unify_occurs_check/4 already exists"
  compare,==,2,,v0.1,structural equality
  compare,\==,2,not_equal,v0.1,
  compare,@<,2,,v0.2,standard order of terms
  compare,@>,2,,v0.2,standard order of terms
  compare,@=<,2,,v0.2,standard order of terms
  compare,@>=,2,,v0.2,standard order of terms
  compare,compare,3,,v0.2,standard order of terms
  type_check,var,1,,v0.1,
  type_check,nonvar,1,,v0.1,
  type_check,atom,1,,v0.1,
  type_check,atomic,1,,v0.1,
  type_check,number,1,,v0.1,
  type_check,integer,1,,v0.1,
  type_check,float,1,,v0.1,
  type_check,compound,1,,v0.1,
  type_check,callable,1,,v0.1,
  type_check,is_list,1,,v0.1,
  type_check,ground,1,,v0.2,"needs recursive var-freedom check"
  term_inspect,functor,3,,v0.2,
  term_inspect,arg,3,,v0.2,
  term_inspect,=..,2,univ,v0.2,
  term_inspect,copy_term,2,,v0.1,"internal machinery too: needed for clause instantiation on every resolution step, expose as predicate in v0.1"
  arithmetic,is,2,,v0.1,
  arithmetic,+,2,,v0.1,"as arithmetic functor inside is/2 expressions"
  arithmetic,-,2,,v0.1,
  arithmetic,*,2,,v0.1,
  arithmetic,/,2,,v0.1,
  arithmetic,//,2,,v0.1,integer division
  arithmetic,mod,2,,v0.1,
  arithmetic,rem,2,,v0.1,
  arithmetic,abs,1,,v0.1,
  arithmetic,sign,1,,v0.1,
  arithmetic,min,2,,v0.1,
  arithmetic,max,2,,v0.1,
  arithmetic,sqrt,1,,v0.1,
  arithmetic,**,2,,v0.1,
  arithmetic,^,2,,v0.1,
  arithmetic,sin,1,,v0.2,
  arithmetic,cos,1,,v0.2,
  arithmetic,tan,1,,v0.2,
  arithmetic,exp,1,,v0.2,
  arithmetic,log,1,,v0.2,
  arith_compare,=:=,2,,v0.1,
  arith_compare,=\=,2,,v0.1,
  arith_compare,<,2,,v0.1,
  arith_compare,>,2,,v0.1,
  arith_compare,=<,2,,v0.1,
  arith_compare,>=,2,,v0.1,
  exception,throw,1,,v0.1,
  exception,catch,3,,v0.1,
  exception,type_error,2,,v0.1,"standard error-term constructor helper"
  exception,domain_error,2,,v0.1,"standard error-term constructor helper"
  exception,instantiation_error,1,,v0.1,"standard error-term constructor helper"
  exception,existence_error,2,,v0.2,"standard error-term constructor helper"
  operator,op,3,,v0.1,"feeds Ichor.Toolkit.Pratt table directly"
  database,dynamic,1,,v0.2,directive
  database,assert,1,assertz_alias,v0.2,"classic alias of assertz/1"
  database,asserta,1,,v0.2,
  database,assertz,1,,v0.2,
  database,retract,1,,v0.2,
  database,retractall,1,,v0.2,
  database,abolish,1,,v0.2,
  database,clause,2,,v0.2,
  aggregate,findall,3,,v0.3,
  aggregate,bagof,3,,v0.3,
  aggregate,setof,3,,v0.3,
  aggregate,aggregate_all,3,,later,
  list,length,2,,v0.1,
  list,append,3,,v0.1,
  list,member,2,,v0.1,
  list,reverse,2,,v0.1,
  list,nth0,3,,v0.1,
  list,nth1,3,,v0.1,
  list,last,2,,v0.1,
  list,msort,2,,v0.2,"needs standard order of terms"
  list,sort,2,,v0.2,dedups + sorts by standard order
  list,sort,4,,later,key/order variants
  list,permutation,2,,v0.2,
  list,sum_list,2,sumlist_alias,v0.2,
  list,max_list,2,,v0.2,
  list,min_list,2,,v0.2,
  list,list_to_set,2,,v0.2,
  list,exclude,3,,v0.2,
  list,include,3,,v0.2,
  list,foldl,4,,v0.2,"foldl/4..6 family for 1-3 list args"
  list,maplist,2,,v0.2,"maplist/2..6 family"
  atom_string,atom_codes,2,,v0.4,
  atom_string,atom_chars,2,,v0.4,
  atom_string,atom_length,2,,v0.4,
  atom_string,atom_concat,3,,v0.4,
  atom_string,char_code,2,,v0.4,
  atom_string,number_codes,2,,v0.4,
  atom_string,number_chars,2,,v0.4,
  atom_string,upcase_atom,2,,v0.4,
  atom_string,downcase_atom,2,,v0.4,
  atom_string,sub_atom,5,,v0.4,
  atom_string,split_string,4,,v0.4,"needs real string type decision, see term_deferred_decisions"
  atom_string,atomic_list_concat,2,,v0.4,"rule_2 alias candidate: opaque name"
  atom_string,atomic_list_concat,3,,v0.4,"rule_2 alias candidate: opaque name"
  io,write,1,,v0.1,"minimal REPL output need"
  io,writeln,1,,v0.1,
  io,print,1,write_alias,v0.1,"rule_2: readable alias of write/1"
  io,nl,0,,v0.1,
  io,format,2,,v0.4,
  io,read_term,2,,later,
  dcg,-->,2,dcg_translate,v0.5,"grammar-rule clause translation at load time"
  dcg,phrase,2,,v0.5,
  dcg,phrase,3,,v0.5,
```

## 7. Roadmap

```toon
roadmap[7]{version,theme,status}:
  v0.1,"minimal true core: reader (lexer+Pratt), Term IR, unification, SLD-resolution, cut (real, not once/1-only), core control, is/2 arithmetic, exceptions, op/3, minimal I/O, REPL/consult",done
  v0.2,"dynamic database (assert/retract family), term inspection (functor/arg/univ), standard order of terms, ground/1, more list predicates, forall/ignore",not_started
  v0.3,"aggregation: findall/bagof/setof",not_started
  v0.4,"real string type decision + atom/string predicate family + format/2",not_started
  v0.5,"DCG (-->/phrase)",not_started
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
decisions_log[15]{date,decision,choice,status}:
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
  2026-07-29,ichor_runtime_hex_release,"both packages published independently to Hex -- ichor 0.2.1 (Aether front-end, Grammar.Analysis, both codegen backends, plus new Ichor.GrammarImport for ABNF/BNF/EBNF/PEG sources; still only: :dev, runtime: false here) and ichor_runtime 0.1.0 (now its own repository, github.com/joetjen/ichor_runtime, not a subdirectory of ichor's; the sole real runtime dependency). mix.exs deps simplified from git+branch+sparse+override to plain {:ichor_runtime, \"~> 0.1.0\"} / {:ichor, \"~> 0.2.0\", only: :dev, runtime: false}. Regenerated grammar_generated.ex against the published mix ichor.gen to confirm codegen output is unaffected by the version bump; full precommit (format/credo --strict/sobelow/test/dialyzer) still clean",final
  2026-07-28,cut_implementation,"! succeeds once, but its own backtrack-past-me continuation throws {:aletheia_cut, barrier} (a barrier = make_ref() minted fresh per predicate call / call//N / once/1 / \\+ per ISO cut-opacity); Aletheia.Engine.guard_cut/2 wraps each call's own lazy solution stream, catching only its own barrier and re-throwing anything else. Ichor.Backtrack.Tree's combinators need zero changes: they're plain function calls with no try inside them, so a throw passes through conjunction/disjunction/once untouched. A bindings-borne \"cut fired\" marker was considered and rejected: `p :- !, fail.` with a second clause `p :- true.` must fail p outright, but a clause body that never produces a solution gives a marker-on-solutions scheme nothing to inspect -- cut has an effect even along a path that ultimately fails",final
  2026-07-28,control_constructs_module_placement,"true/fail/,/;/->/!/\\+/call/once live directly in Aletheia.Engine, not a separate Builtins.Control module as DESIGN.md's original module-layout table sketched -- once actually implemented they turned out inseparable from the cut-barrier machinery (guard_cut, fresh barriers per call), not independent predicates dispatchable through a generic table",final
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

```toon
modules[15]{path,purpose,milestone}:
  lib/aletheia.ex,"top-level API: consult/1, consult_string/2, query/2, query_once/2, query_lazy/2 + next_solution/2",v0.1
  lib/aletheia/reader.ex,"exposes consult_string/2 over Aletheia.Reader.Grammar.run_sequence/2 (the generated module below)",v0.1
  lib/aletheia/reader/grammar.aether,"the real Aletheia lexical+syntactic grammar (Aether) -- source grammar, hand-edited",v0.1
  lib/aletheia/reader/grammar_generated.ex,"mix ichor.gen (mix gen.grammar) output from grammar.aether -- checked in, not regenerated on mix compile; only calls ichor_runtime at actual runtime",v0.1
  lib/aletheia/reader/pratt.ex,"the term/arg_term @native(...) callback over Ichor.Toolkit.Pratt",v0.1
  lib/aletheia/reader/actions.ex,"Ichor.Actions impl: raw capture tree -> Aletheia.Term, default operator table, op/3 directive application, per-clause variable freshening",v0.1
  lib/aletheia/term.ex,"Term IR + Ichor.Backtrack.Term implementation (incl. list-as-'.'/2 encoding), resolve_deep/2, fresh_copy/1, structurally_equal?/2",v0.1
  lib/aletheia/database.ex,"clause storage/indexing (populated by consult; assert/retract callable predicates are v0.2)",v0.1
  lib/aletheia/engine.ex,"SLD-resolution over Ichor.Backtrack + clause DB; true/fail/,/;/-> /!/\\+/call/once and the cut-barrier/guard_cut mechanism all live here directly, not in a separate builtins module -- see decisions_log control_constructs_module_placement",v0.1
  lib/aletheia/builtins/arithmetic.ex,"is/2 evaluator + the six arithmetic comparisons",v0.1
  lib/aletheia/builtins/exceptions.ex,"type_error/2, domain_error/2, instantiation_error/1, existence_error/2 (term constructors) + the real throw/catch Elixir tag",v0.1
  lib/aletheia/builtins/lists.ex,"length/2 append/3 member/2 reverse/2 nth0/3 nth1/3 last/2",v0.1
  lib/aletheia/builtins/io.ex,"write/1 writeln/1 print/1 nl/0 (canonical-form text only, no operator-aware pretty-printing yet)",v0.1
  lib/aletheia/repl.ex,"consult + interactive query loop, genuinely lazy (pulls one solution at a time via query_lazy/2+next_solution/2)",v0.1
  test/support/query_helper.ex,"consult+query test shorthand",n/a
```
