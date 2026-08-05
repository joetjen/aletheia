# AGENTS.md

Instructions for AI agents working in this Elixir codebase.

## Communication

- Every response starts with the user's first name. Determine it from `git config user.name` (take the first name); if that's unavailable or ambiguous, ask once. Remember the answer for the rest of the session rather than re-deriving or re-asking.

## Before every commit

- Run `mix precommit` and make sure it passes. No exceptions.
- If `mix precommit` isn't defined yet, add an alias in `mix.exs` (typically `compile --warnings-as-errors`, `format`, `deps.unlock --check-unused`, `test`, `dialyzer`/`credo` if configured).

## Tests

- Tests must stay current with behavior: a change to what code does needs its tests updated in the same commit, not "later" — a passing suite that no longer exercises real current behavior is worse than a failing one.
- Add tests for new behavior as you write it, not as a follow-up.
- Where inputs form a space bigger than a handful of examples usefully covers (parsers, encoders/decoders, merge/normalization logic, anything with an invariant that should hold for *all* inputs, not just the ones you thought of), prefer a property-based test (this project already depends on `stream_data`) over enumerating more example cases by hand. Use ordinary example-based tests for fixed, specific scenarios and regressions.

## Documentation

- Treat every documentation surface touched by a change as part of that change, not optional polish — moduledocs/docstrings, README, guides, changelog, code comments explaining non-obvious behavior. None of it is allowed to go stale.
- Every public module needs a `@moduledoc`. Every public function needs a `@doc`.
- Update `@moduledoc`/`@doc` whenever behavior changes — stale docs are worse than none.
- Keep external docs (README, guides, wikis) in sync with code changes in the same commit/PR.
- Update `CHANGELOG.md` for every user-facing change, following [Keep a Changelog](https://keepachangelog.com/):
  - Add entries under `[Unreleased]` as you work.
  - Move them under a version heading on release, and remove the (now-empty) `[Unreleased]` section — a published release's changelog must not contain one.

## Generated/checked-in code

- If a file is produced by a generator (codegen, a compiler step, a `mix gen.*`/`mix *.gen` task) and checked into the repo, never hand-edit it. Edit the source it's generated from, then re-run the generator and re-run the test suite.
- Say so at the top of the generated file and of its hand-written source, so this isn't tribal knowledge.

## Parity between multiple implementations

- If the codebase deliberately keeps two implementations of the same behavior (e.g. a fast/default path and a reference/interpreted path kept for benchmarking or verification), a behavior change to either one needs a passing parity test against the other before it's done — not just green tests on whichever one you touched.

## Dependency boundaries

- When a dependency is scoped `only: [:dev, :test]`/`runtime: false` (or the equivalent in another ecosystem) specifically to keep it out of a production build, verify that boundary after touching deps or `lib/` — e.g. a prod-env compile/dependency-tree check — rather than assuming the scoping still holds.

## Dependency versions

- Default to `~> x.y` (major.minor, no patch) for version requirements in `mix.exs`, e.g. `{:jason, "~> 1.4"}` rather than `{:jason, "~> 1.4.2"}`. Only pin a patch version when explicitly told to, or when a specific patch is genuinely required (e.g. to pull in a fix or work around a known bug).

## Static analysis findings

- A new low-confidence Sobelow/Dialyzer (or equivalent linter) finding is not automatically wrong, but isn't automatically fine either. Give it a specific justification — a code comment or a targeted ignore-file entry naming the exact function/reason — never a blanket suppression.

## Traceability

- If the repo maintains a coverage/traceability table (e.g. mapping spec sections or requirements to their tests), update it in the same commit as the change it's tracking, not as an afterthought.

## Git workflow

- Use [git flow](https://nvie.com/posts/a-successful-git-branching-model/): `main` (releases), `develop` (integration), `feature/*`, `release/*`, `hotfix/*`, `support/*`.
- No direct commits to `main` or `develop`. Branch, then merge/PR back.
- Before starting work, check out onto a git flow branch (`feature/*`, `release/*`, `hotfix/*`, `support/*`) — never work directly on `develop`, unless explicitly told to.

## Commits

- Use [Conventional Commits](https://www.conventionalcommits.org/): `<type>[optional scope]: <description>`.
- Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci`.
- Breaking changes: `!` after type/scope, or a `BREAKING CHANGE:` footer.

## Versioning

- Use [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.
- `MAJOR` — breaking changes. `MINOR` — backward-compatible features. `PATCH` — backward-compatible fixes.
- Bump the version in `mix.exs` as part of the release, matching the changelog entry.
