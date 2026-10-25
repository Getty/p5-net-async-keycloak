# Net-Async-Keycloak House Rules

The shared house rules come from skilletor — bundle `getty-cpan-dist@getty`: engineering
discipline, the delegation lock, the publish gate, karr coordination, CPAN release. They load
as `.claude/rules/.local.*.md`; if they are missing, run `skilletor sync` and publish nothing
until they load. This file adds what is true only here, and wins where it differs.

## What this repo is

Async Perl client for Keycloak identity management (IO::Async + Future) — the async twin of
`WWW::Keycloak`. Read first: the callers and the same method in the sync twin
(`~/dev/p5-www-keycloak`).

## Agent team

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `net-async-keycloak-worker` (default) |
| Write/extend tests | `net-async-keycloak-test-writer` |
| Commits, `Changes`, card → done, pre-release audit | `net-async-keycloak-release-manager` |
| Write/maintain POD | `net-async-keycloak-doc-writer` |
| Read-only research, audit, gap analysis | `net-async-keycloak-worker` ("read-only, change nothing") |

Behavior-relevant = runtime behavior, the public API (`Net::Async::Keycloak`, `::OIDC`,
`::Admin`), the sync/async sibling invariant, error handling, tests and performance. Pure
prose docs and `Changes` notes are not.

## Hazards

- **Live tests hit a real Keycloak.** Opt-in via `KEYCLOAK_LIVE_TEST=1 KEYCLOAK_URL=…`, off
  by default. Never run them uncontrolled, and never enable them in a fanned-out or
  parallel context. A default `prove -lr t` must pass with them skipped.
- **Sync twin leads.** `p5-www-keycloak` defines the API; this repo mirrors it with `_f`
  suffixes. Do not invent API here, and do not edit the other repo from here — ticket it.
- **Never block the loop.** No `->get` inside library code, no synchronous HTTP.
- **Keycloak facts come from a running instance or its documentation,** never from memory.
- **Test runner trap.** Plain `prove -l t/` is non-recursive; always use `prove -lr t` so
  subdir tests are never silently skipped.

## Perl specifics — reference, don't restate

Module loading, Moo patterns, dependency pinning, release metadata, POD directives and house
style live in skills `getty-perl-core`, `getty-perl-moo`, `perl-release-dist-ini`,
`getty-perl-release-author-getty` and `net-async-keycloak-core`.
