# Case study: auditing structured application logs

Every other example in [guides/EXAMPLES.md](guides/EXAMPLES.md) is
deliberately small — one feature, one paragraph, one screenful. This
one is deliberately not: a single, complete, real-world-shaped program
that walks through *why* you'd reach for Aletheia, not just *how* to
write one clause. It assumes you're comfortable with the vocabulary
from [guides/TUTORIAL.md](guides/TUTORIAL.md) and pulls in a feature
from nearly every corner of the language — a DCG grammar, real strings,
the dynamic database, aggregation with existential quantification, and
`format/2` — to solve one coherent problem rather than eight
disconnected ones, written as one real `.alp` program rather than
Elixir term-building (contrast with Episteme's own `CASE_STUDY.md`, in
its own sibling repository, which solves the identical problem the
other way, since Episteme has no reader of its own — worth comparing
side by side if you want to see exactly what a syntax front-end buys
you).

## Intent

A lot of real services — Heroku's own routing layer, most Go and Rust
web frameworks, plenty of hand-rolled ones — emit logs in
[logfmt](https://brandur.org/logfmt): one line per event, space-separated
`key=value` pairs, no fixed schema beyond a handful of conventional
fields. A line looks like this:

```text
ts=2026-08-05T10:15:32Z level=warn component=auth event=login_failed user=alice ip=203.0.113.5
```

Say you want a small audit tool over a stream of these: flag any
**user with repeated failed logins** (a brute-force indicator), and
separately flag any **IP address behind failed logins for more than
one distinct user** (a credential-stuffing indicator — one attacker,
many stolen usernames, one source). Both are real heuristics real
fraud/security tooling actually uses, and both are naturally
*relational* questions — "group these facts by X, then check something
about each group" — which is exactly the shape logic programming is
for.

Three things about Aletheia fit this well:

- **No `logfmt` reader of its own, but a DCG when you need one.**
  Nothing ships a `logfmt` parser out of the box, but
  [DCG support](guides/REFERENCE.md#dcg) lets you write the grammar as
  a grammar, right in `.alp` source, not a hand-rolled loop of string
  splits.
- **A mutable database for a line-at-a-time stream.** Log lines arrive
  one at a time, not as a batch you already have in memory; the
  [dynamic database](guides/REFERENCE.md#database) (`assertz/1`) is
  built for exactly that.
- **Aggregation that groups for you.** "Which users have ≥ 3 failed
  logins" and "which IPs are shared across users" are both grouping
  queries — [`setof/3`](guides/REFERENCE.md#aggregation)'s
  free-variable grouping does the work a hand-written accumulator
  would otherwise need.

## Solution

### Parsing: a DCG grammar for logfmt lines

Tokenizing on whitespace is just [`split_string/4`](guides/REFERENCE.md#atom-number-and-string-conversions)
— Aletheia already has that, so there's no reason to reinvent it. What
the grammar below owns is everything *after* that: recognizing the
shape of a line (four required fields in order, then a
variable-length tail of arbitrary ones) and pulling each `key=value`
token apart.

`any_field/2` consumes exactly one token and splits it around `=`:

```prolog
any_field(Key, Value) -->
    [Token],
    { split_string(Token, "=", "", [KeyStr, Value]), atom_string(Key, KeyStr) }.
```

Read the DCG body the way real Prolog reads any DCG body: `[Token]` is
a one-element *terminal* — "consume the next token from the input and
call it `Token`" (a terminal doesn't have to be a literal; a variable
inside one just captures whatever's there). The `{ ... }` half is an
ordinary goal, spliced in without touching the input list —
[`split_string/4`](guides/REFERENCE.md#atom-number-and-string-conversions)
breaks `"level=warn"` into `["level", "warn"]`, and
[`atom_string/2`](guides/REFERENCE.md#atom-number-and-string-conversions)
turns `"level"` into the atom `level` so field names can be matched and
grouped on later.

`fields/1` is the variable-length tail: zero or more `any_field/2`
matches, collected into a list — same recursive shape as writing your
own `sum_list/2` ([guides/EXAMPLES.md §7](guides/EXAMPLES.md#7-writing-your-own-recursive-list-rule)):
an empty-list base case, and a case that peels one `field(K, V)` off
the front and recurses on the rest, except here the recursion is
consuming *tokens*, not walking an already-built list.

```prolog
fields([]) --> [].
fields([field(K, V) | Rest]) --> any_field(K, V), fields(Rest).
```

`log_line/5` ties it together: four required fields in a fixed order,
each converted to an atom, then whatever's left goes through
`fields/1`. `any_field(ts, Ts)` deliberately leaves the timestamp as a
string rather than converting it to an atom — ISO 8601 timestamps sort
correctly as plain byte strings, so there's no need to parse them any
further for what this audit actually asks.

```prolog
log_line(Ts, Level, Component, Event, Fields) -->
    any_field(ts, Ts),
    any_field(level, LevelStr), { atom_string(Level, LevelStr) },
    any_field(component, ComponentStr), { atom_string(Component, ComponentStr) },
    any_field(event, EventStr), { atom_string(Event, EventStr) },
    fields(Fields).
```

`parse_log_line/6` is the seam between "a raw log line" and "a parsed
grammar" — split the whole line on spaces, then
[`phrase/2`](guides/REFERENCE.md#dcg) the grammar against the resulting
token list:

```prolog
parse_log_line(Line, Ts, Level, Component, Event, Fields) :-
    split_string(Line, " ", "", Tokens),
    phrase(log_line(Ts, Level, Component, Event, Fields), Tokens).
```

Trying it directly against one line, via `Aletheia.query/2`:

```elixir
Aletheia.query(
  "parse_log_line(\"ts=2026-08-05T10:15:32Z level=warn component=auth event=login_failed user=alice ip=203.0.113.5\", Ts, Level, Component, Event, Fields)",
  db
)
#=> {:ok, [%{
#     "Ts" => "2026-08-05T10:15:32Z",
#     "Level" => :warn,
#     "Component" => :auth,
#     "Event" => :login_failed,
#     "Fields" => [
#       %Episteme.Term.Compound{name: :field, args: [:user, "alice"]},
#       %Episteme.Term.Compound{name: :field, args: [:ip, "203.0.113.5"]}
#     ]
#   }]}
```

### Rules over the parsed facts

Every line becomes a `log_entry(Ts, Level, Component, Event, Fields)`
fact once parsed and ingested. `field_value/3` is a lookup into that
trailing `Fields` list, built directly on
[`member/2`](guides/REFERENCE.md#lists):

```prolog
field_value(Fields, Key, Value) :- member(field(Key, Value), Fields).
```

`failed_login/3` picks out the one event shape the rest of this cares
about:

```prolog
failed_login(User, Ip, Ts) :-
    log_entry(Ts, warn, auth, login_failed, Fields),
    field_value(Fields, user, User),
    field_value(Fields, ip, Ip).
```

Now the two heuristics, each a [`setof/3`](guides/REFERENCE.md#aggregation)
grouped by exactly one of `failed_login/3`'s three fields, with the
other free variable folded away via `^` (`Var^Goal` existentially
quantifies `Var` out of the grouping — see
[guides/REFERENCE.md#aggregation](guides/REFERENCE.md#aggregation)).
`brute_force_suspect/1` groups by `User`, folding `Ip` away, and checks
the group is big enough:

```prolog
brute_force_suspect(User) :-
    setof(Ts, Ip^failed_login(User, Ip, Ts), Timestamps),
    length(Timestamps, N),
    N >= 3.
```

`shared_ip_suspect/1` is the mirror image — group by `Ip`, fold `Ts`
away, check more than one distinct user shows up:

```prolog
shared_ip_suspect(Ip) :-
    setof(User, Ts^failed_login(User, Ip, Ts), Users),
    length(Users, N),
    N > 1.
```

(Ordinary `>=`/`>`, straight from the reader's own default operator
table — no plain-English equivalent needed, unlike `Ip^failed_login(...)`'s
own `^`, which is likewise just the reader's already-registered
exponentiation operator doing double duty, exactly as in real Prolog.
`setof/3` already deduplicates `Users`/`Timestamps`, so `length/2` here
is counting *distinct* values, not raw match counts.)

### Ingesting a batch of log lines

This is the dynamic-database half: parse each raw line and `assertz`
the resulting fact, one line at a time — exactly the shape a real log
stream arrives in. `ingest/1` does one line; `ingest_all/0` walks a
stored list of them via `forall/2`, the same `forall/2` from
[guides/REFERENCE.md](guides/REFERENCE.md#control):

```prolog
ingest(Line) :-
    parse_log_line(Line, Ts, Level, Component, Event, Fields),
    assertz(log_entry(Ts, Level, Component, Event, Fields)).

log_lines([
  "ts=2026-08-05T10:15:32Z level=warn component=auth event=login_failed user=alice ip=203.0.113.5",
  "ts=2026-08-05T10:15:40Z level=info component=auth event=login_success user=bob ip=198.51.100.7",
  "ts=2026-08-05T10:16:02Z level=warn component=auth event=login_failed user=alice ip=203.0.113.5",
  "ts=2026-08-05T10:16:10Z level=error component=payments event=charge_failed user=carol amount=49.99",
  "ts=2026-08-05T10:16:45Z level=warn component=auth event=login_failed user=alice ip=203.0.113.9",
  "ts=2026-08-05T10:16:51Z level=warn component=auth event=login_failed user=dave ip=203.0.113.9",
  "ts=2026-08-05T10:17:03Z level=info component=auth event=login_success user=alice ip=203.0.113.9"
]).

ingest_all :-
    log_lines(Lines),
    forall(member(Line, Lines), ingest(Line)).
```

Note `carol`'s line: a `payments`/`charge_failed` event with an
`amount` field instead of `ip` at all. `log_line/5`'s trailing `Fields`
list is exactly why that's not a problem — the grammar never
hard-codes which fields follow the first four, so entries with
completely different shapes live in the same database without any
schema migration.

### Running the audit

```prolog
audit_report :-
    findall(User, brute_force_suspect(User), Suspects),
    findall(Ip, shared_ip_suspect(Ip), SharedIps),
    format("Brute-force suspects: ~w~n", [Suspects]),
    format("Shared-IP suspects: ~w~n", [SharedIps]).
```

The whole program above — every clause from `any_field/2` through
`audit_report/0` — is one `.alp` source file. Loading and running it
end to end:

```elixir
{:ok, db} = Aletheia.consult("audit.alp")
Aletheia.query_once("ingest_all", db)
Aletheia.query_once("audit_report", db)
```

## Result

Actually running the above prints:

```text
Brute-force suspects: ["alice"]
Shared-IP suspects: ["203.0.113.9"]
```

and `audit_report`'s own `query_once/2` answers `{:ok, %{}}` (it never
binds anything itself — the report is the side effect).

Both are correct, and for different reasons — which is the point of
running two independent heuristics instead of one:

- **`alice`** is a brute-force suspect: three failed logins in the
  data, full stop. It doesn't matter that two of them came from one IP
  (`203.0.113.5`) and the third from another (`203.0.113.9`) —
  `brute_force_suspect/1` explicitly folds `Ip` away with `^` before
  counting, because "did this account get hammered" shouldn't depend
  on the attacker rotating source addresses.
- **`203.0.113.9`** is a shared-IP suspect: it shows up behind failed
  logins for two different users (`alice` and `dave`), which is
  exactly the "one attacker, many stolen credentials" shape —
  independent of the fact that `dave` alone only has one failed login
  and would never trip the brute-force check by himself.
- **`bob`** never appears in either report — his only log line is a
  `login_success`, which `failed_login/3` doesn't match at all.
- **`carol`** doesn't appear either, for a different reason: her line
  is a real, successfully-parsed `log_entry/5` fact (the DCG doesn't
  care that it's a payment event, not a login), it's just that
  `failed_login/3` only ever looks at `warn`/`auth`/`login_failed`
  entries, so a `charge_failed` payment event was never in scope for
  either audit to begin with.

That last distinction — *parsed but not relevant* vs. *never matched
the grammar at all* — is worth sitting with: nothing here had to
special-case `carol`'s line, reject it, or fail. It's a perfectly
ordinary fact in the database; it simply never satisfies a goal that
specifically asks about failed logins. A schema-first approach (a fixed
struct per log line, one JSON schema, etc.) would have had to decide up
front whether payment events belong in the same table as auth events;
here that question just never comes up.

## What this exercises

Every one of these is a full [guides/REFERENCE.md](guides/REFERENCE.md)
entry if you want the complete semantics:

- [DCG grammars](guides/REFERENCE.md#dcg) — terminals, embedded goals
  (`{Goal}`), nonterminal recursion, `phrase/2`, all as real `-->`
  syntax straight from `.alp` source.
- [Real strings](guides/REFERENCE.md#syntax) — double-quoted literals,
  a genuinely distinct term class from atoms.
- [The dynamic database](guides/REFERENCE.md#database) — `assertz/1`
  building up a fact base one line at a time.
- [`setof/3`](guides/REFERENCE.md#aggregation) — grouping by a free
  variable, existentially quantifying another away with `^`.
- [`split_string/4`](guides/REFERENCE.md#atom-number-and-string-conversions)
  and [`atom_string/2`](guides/REFERENCE.md#atom-number-and-string-conversions)
  — the string/atom conversion family, used inside the grammar itself.
- [`member/2`](guides/REFERENCE.md#lists), `length/2`, ordinary `>=`/`>`
  arithmetic comparisons, and [`findall/3`](guides/REFERENCE.md#aggregation)
  — the same everyday predicates from [guides/EXAMPLES.md](guides/EXAMPLES.md),
  doing real work here instead of toy work.
- [`format/2`](guides/REFERENCE.md#io) — turning the query's answer
  into the actual report text above.
