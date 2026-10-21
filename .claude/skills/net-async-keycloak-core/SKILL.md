---
name: net-async-keycloak-core
description: Use when working on Net::Async::Keycloak — the IO::Async/Future client for Keycloak's OIDC and Admin REST API: module layout, twin contract, ensure_*_f, errors, tests.
---

# net-async-keycloak — Kern

IO::Async-based client for Keycloak, the async twin of `WWW::Keycloak` (`~/dev/p5-www-keycloak`), modelled on
`Net::Async::Zitadel` (`~/dev/p5-net-async-zitadel`). The design is fixed in
`docs/superpowers/plans/2026-10-03-net-async-keycloak-phase-1.md`.

Nothing here talks to Keycloak on its own: requests are built and responses are read by `WWW::Keycloak::Role::HTTP`
(`build_request`, `read_response`), and the `ensure_*_f` methods compare with `WWW::Keycloak::Diff`. The sync twin owns
the semantics of Keycloak, this repo owns the async plumbing.

## Architecture — the layers and who calls whom

1. `Net::Async::Keycloak` (facade, an `IO::Async::Notifier`) holds `base_url`, `realm` and the credentials, and owns one
   `Net::Async::HTTP` as a **child notifier**. `oidc` and `admin` are lazy and share that `http`; `auth` — the admin
   login — is shared between them. Only the facade is added to a loop.
2. `::OIDC`, `::Admin` and `::Auth` each consume **two** roles: first `Net::Async::Keycloak::Role::HTTP` (sends,
   returns futures, names the error classes), then `WWW::Keycloak::Role::HTTP` (builds the request, reads the response).
3. `Net::Async::Keycloak::Auth` keeps the admin token: login, keep, renew before it expires, forget when it was refused.

**The role order is load-bearing.** In Moo the *first* role applied wins a shared method name, silently. With the async
role first, `api_error_class` and `network_error_class` stay the ones of this distribution; with the order swapped, the
sync classes win, every failure is a plain `WWW::Keycloak::Error::*`, and the async subclasses never appear. Nothing
warns about the swap — only the errors of the async dist tell.

## Module map

- `Net::Async::Keycloak` — facade: `base_url` (trailing slashes removed), `realm`, optional `username`/`password`,
  `client_id`/`client_secret` or a fixed `token`; `auth_realm` (`master` for a password login, else the realm); lazy
  `http`, `auth`, `oidc`, `admin`; `issuer`; `for_realm($realm)`.
- `::OIDC` — discovery, JWKS, token verification, userinfo, introspection, the token grants (password, client
  credentials, refresh, authorization code, device), device authorization, logout.
- `::Admin` — the Admin REST API of one realm: realms, clients, client scopes, protocol mappers, users, credentials,
  authentication flows and their configurations, plus the six `ensure_*_f` methods.
- `::Auth` — the admin token for the Admin API.
- `::Role::HTTP` — `send_request_f($method, $url, %arg)`, `fail_validation($message)` and the three error classes. It
  only sends.
- `::Error` — base, extends `WWW::Keycloak::Error`; `::Validation`, `::Network`, `::API`, one package per file.

## Vocabulary

- **Fassade** — `Net::Async::Keycloak` itself: realm, credentials, the two sub-clients.
- **`_f`-Methode** — the async twin of a sync method: same name plus `_f`, same arguments, a `Future` of the same
  result instead of the result.
- **ensure-Methode** — an idempotent write. `ensure_client_f($rep)` finds the object by its readable key, compares it
  with the wanted state and creates, updates or does nothing; it answers `{ id => …, changed => 'created' | 'updated' |
  '' }`.
- **Diff** — `WWW::Keycloak::Diff`, the comparison without I/O, shared with the sync client: `changes()` says what must
  be written, `merge()` lays the wanted keys over the current state.
- **Admin-Token** — the bearer token for the Admin API, held by `::Auth`. Three ways in: username and password through
  the `admin-cli` client, a service account with its secret, or a fixed token that is used as it is and never renewed.
- **auth_realm** — the realm the admin token is fetched from; `master` for a password login, the realm itself for a
  service account.
- **issuer** — `<base_url>/realms/<realm>`. OIDC addresses the realm under it, the Admin API under `/admin/realms/<realm>`.

## Data flows

**A token check** (`verify_token_f`): the JWKS URI comes from the discovery document (fetched once, cached), the keys
are fetched once and cached. `decode_jwt` checks the issuer, the expiry and the accepted algorithms (`RS*`, `PS*`,
`ES*`); the audience is checked only when the caller asks for one. On `kid_keys lookup failed` the keys are fetched
again once — but only if no fetch is under way and the last one is at least `jwks_min_age` (60 s) old. `type => 'Bearer'`
compares the `typ` claim; without `type` nothing is checked.

**An Admin call** (`call_f`): without credentials it fails with a validation error and without a request. Then
`auth->token_f` gives the bearer — outside the `eval`, because a failed login is not a refused token. `send_request_f`
builds the request (`Accept: application/json`, the bearer, the body as JSON or as a form), sends it through
`Net::Async::HTTP` and reads the answer into `{ status, data, location }`. A 401 with a renewable token invalidates it
and repeats the request once; a fixed token stays refused.

**An ensure** (`ensure_client_f` and its five siblings): find the object, compare it with `Diff->changes(current,
wanted)`, then create, update or do nothing.

## Invariants

- **The twin leads.** Every public method exists in `WWW::Keycloak` under the same name plus `_f`. A method the twin
  does not have is a ticket for the twin, not an invention here; the two repos are edited separately.
- **No method blocks.** Every method returns a `Future`; there is no `->get` and no synchronous HTTP client in `lib/`.
- **Nothing throws for a wrong argument.** A validation problem fails the future, so one `else` catches it next to a
  refused request.
- **The errors are the sync errors.** Every error is also the matching `WWW::Keycloak::Error::*`, so code written for
  the sync client catches it unchanged.
- **One HTTP client.** `oidc`, `admin` and `auth` share the facade's `Net::Async::HTTP`.

## Hazards

- **No loop means no request.** `Net::Async::HTTP` dies when it is in no loop; `send_request_f` catches that and fails
  the future with a network error that names the missing loop ("was the Net::Async::Keycloak added to a loop?"). Let it
  fail the future — a dying exception is not the contract.
- **A shared login survives a cancelled caller.** `Auth::token_f` hands every waiter `without_cancel` on the pending
  login; `OIDC::_shared` does the same for the discovery and the key fetches. Cancelling one waiter must not cancel the
  login for the others.
- **One refused token, one new login.** `invalidate($refused)` forgets the token only if it is still the current one —
  three calls refused together cause one new login, not three.
- **A failed login does not stick.** The next call tries again instead of inheriting the old failure, and a 2xx without
  an `access_token` (a proxy's HTML page) is a failed login that caches nothing.
- **`jwks_min_age` counts from the start of the fetch.** A key rotation is not noticed before that; a token with an
  unknown `kid` is rejected with a validation error until then.
- **`ensure_execution_config_f` writes again and again.** Keycloak masks the values (`**********`), so every run finds a
  difference; the masked values are never written back.
- **`ensure_user_f` normalises before it compares.** Keycloak lower-cases user names and e-mail addresses and stores
  every attribute as a list of strings. The write sends the whole user (`Diff->merge`) — a PUT that names only
  `attributes` drops the other profile fields.
- **`ensure_client_f` refuses `defaultClientScopes`, `optionalClientScopes` and `protocolMappers`**: Keycloak ignores
  them when a client is updated. Use `add_default_client_scope_f` and `ensure_protocol_mapper_f` for them.
- **`list_users_f` is one request** and Keycloak answers at most its default page of 100 users. `list_all_users_f` pages
  in 100er chunks — not atomic, so users created or deleted meanwhile may be missed or seen twice.
- **The status shapes are fixed.** A duplicate is 409 (`is_conflict`), something missing 404 (`is_not_found`), a refused
  token 401 (`is_unauthorized`) → one retry. A create answers 201 with a `Location` header and no body; the id comes
  from the header, and without it the call fails with "sent no Location header". An OAuth error from the token endpoint
  arrives as `oauth_error` (`invalid_grant`, `authorization_pending`).
- **A 2xx that is no JSON object is an error**, not data: a proxy or a captive portal answering 200 with an HTML page
  fails with an API error.

## Tests and commands

| File | Covers |
|---|---|
| `t/00-load.t` | every module of the namespace loads |
| `t/20-errors.t` | the error classes, the three shapes Keycloak answers errors in, no answer at all |
| `t/30-auth.t` | the admin token: login, renewal, invalidation |
| `t/31-auth-no-token.t` | a 2xx token response without a token |
| `t/40-facade.t` | the facade: lazy sub-clients, login options, `for_realm` |
| `t/50-admin.t` | the Admin REST API; a refused token is renewed once |
| `t/51-admin-ensure.t` | the `ensure_*_f` methods |
| `t/60-oidc.t` | discovery, JWKS, key rotation, the token grants |
| `t/70-async.t` | concurrency: shared login, shared fetch, cancellation |
| `t/90-live-keycloak.t` | the live suite, off unless the env vars are set |

`t/20`–`t/60` and `t/90` are `WWW::Keycloak`'s tests, ported to `_f->get`; when the sync tests change, port them
again. `t/lib/FakeKeycloak.pm` is the shared in-memory Keycloak (the sync twin's copy), `t/lib/FakeHTTP.pm` the
`Net::Async::HTTP` stand-in that answers with finished futures.

```bash
prove -lr t                    # recursive — a plain run skips subdirectories
prove -lv t/70-async.t         # one file
dzil build && dzil test        # Dist::Zilla
KEYCLOAK_LIVE_TEST=1 KEYCLOAK_URL=http://localhost:8080 prove -lv t/90-live-keycloak.t
```

Until `WWW::Keycloak` is installed, the tests need `PERL5LIB=~/dev/p5-www-keycloak/lib`; the `cpanfile` requires
`WWW::Keycloak 0.002`. The live suite creates a throwaway realm and deletes it again — an aborted run leaves it behind.

## Boundaries

- **This repo does not define the API.** `WWW::Keycloak` does; a new endpoint is added there first and mirrored here
  with `_f`.
- **It does not re-implement the protocol.** Request building, response reading and the comparison come from the sync
  twin; everything with I/O is written here.
- **It does not run Keycloak.** `t/keycloak/k8s.yaml` is a Keycloak for Kubernetes to run the live suite against.
- **It does not set up an identity system end to end.** That is what `Airlock` (`~/dev/p5-airlock`) does with this
  client.
- **It does not cut releases.** That is the release manager's business; see the release skills.

## Delegation

Behavior-relevant work — runtime behaviour, the public API (`Net::Async::Keycloak`, `::OIDC`, `::Admin`), the
sync/async twin invariant, error handling, tests, performance — belongs to the `net-async-keycloak-*` agents. The table
and the delegation lock are in `.claude/rules/net-async-keycloak-rules.md`; the main agent coordinates, inspects, plans,
reviews diffs, runs tests and edits non-behavioral docs.
