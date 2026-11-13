---
title: "Activities Server API Reference"
description: "Every HTTP endpoint exposed by the Carrier Wave activities server: hosts, authentication, rate limits, error format, and request and response shapes"
weight: 1
showToc: true
outputs: ["html", "markdown"]
---

The activities server is the backend behind Carrier Wave: Field (iOS), CW
Sweep (macOS), Carrier Wave for Android, and the logbook web viewer. One
service exposes everything described on this page:

- a versioned JSON API under `/v1`
- an OAuth 2.0 / OpenID Connect provider so other apps can act for a user
- an end-to-end encrypted sync journal for the user's log
- server-rendered share and invite pages
- public reference data: spots, Reverse Beacon Network, POTA statistics,
  park boundaries, historic trails, satellite status, contest definitions,
  radio macros, an equipment catalog

This page is the complete wire-level reference. For how the features behave
inside the apps, see the [Reference Manual](/reference/).

> **Who this is for.** Anyone can read the public endpoints. The
> authenticated social endpoints (challenges, friends, clubs, events, feed) are
> **first-party only**: they accept Carrier Wave's own app tokens and reject
> third-party OAuth tokens. Third-party developers get the user's identity and
> the sync journal. If you need more, write to hello@carrierwave.app.
>
> **Reading this with a tool or an agent?** This page is also served as plain
> Markdown at <https://carrierwave.app/manual/developers/api/index.md>, and
> <https://carrierwave.app/llms.txt> lists everything machine-readable. The
> short version with ready-to-run requests is
> [Using the API from agents and tools](/developers/agents/).

## Hosts and versioning

| Environment | Base URL | Notes |
|---|---|---|
| Production | `https://activities.carrierwave.app` | The only host you should integrate with. |
| Staging | `https://staging.carrierwave.app` | Pre-release builds. Not for integration. |

All JSON API routes are nested under `/v1`. There is no `/v2`: changes are
made additively because shipped app builds keep calling old shapes for a long
time. Fields may be added to responses at any time; clients must ignore
unknown fields.

A few routes live at the domain root because external software expects them
at conventional paths:

- `/.well-known/openid-configuration` and
  `/.well-known/oauth-authorization-server` (OAuth discovery)
- `/.well-known/jwks.json` (token verification keys)
- `/.well-known/apple-app-site-association` (iOS universal links)
- `/invite/:token` and `/link/...` (HTML landing pages for shared URLs)
- `/metrics` (Prometheus exposition)

Unknown paths under `/v1` return a JSON `404` (see [Error format](#error-format)).

## Conventions

- **JSON everywhere** unless an endpoint says otherwise. Request and response
  bodies use `camelCase` field names. The exceptions are the OAuth token
  endpoints, which follow the RFC 6749 `snake_case` wire format and accept
  form-encoded bodies, and the Twilio webhook.
- **Identifiers** are UUIDs unless the resource has a natural key: program
  `slug`, macro `slug`, park `reference`, contest `id`, callsign.
- **Timestamps** are RFC 3339 in UTC with a `Z` suffix.
- **Callsigns** are normalised to upper case by the server. Path parameters
  that take a callsign accept any case.
- **Response envelopes.** The original challenge-era endpoints wrap their
  payload in `{"data": ...}`. Endpoints added later return the object or
  array directly. Each endpoint below shows its exact shape; do not assume.
- **Pagination** is offset-based (`limit` and `offset` query parameters) on
  list endpoints that paginate. The activity feed uses a cursor. Limits and
  maxima are listed per endpoint.
- **Request ids.** Every response carries `X-Request-Id`. Send your own and it
  is echoed back; otherwise one is generated. Quote it when reporting a
  problem.
- **Conditional requests.** Several reference-data endpoints emit an `ETag`
  and honour `If-None-Match` with `304 Not Modified`. They are called out
  individually. Use them: the datasets are large and change slowly.

## Authentication

Credentials are sent as `Authorization: Bearer <token>`. Five situations
exist:

| Credential | Looks like | Who holds it | Obtained from | Accepted on |
|---|---|---|---|---|
| None | | Anyone | | Public routes |
| Device token | `fd_…` | Older app installs | Joining a challenge or `POST /v1/register` | Public and first-party routes |
| Account token | Ed25519-signed JWT without a `cid` claim | Carrier Wave's own apps | `POST /v1/auth/token` after email verification | Everything a device token reaches, plus `/v1/auth/*` account management |
| Third-party OAuth token | Ed25519-signed JWT with a `cid` claim and `scope` | Apps written by other developers, acting for a user | `POST /v1/oauth/token` | Only the routes listed under [Third-party access](#third-party-access): the sync journal and OIDC userinfo. Everything else answers `403 FORBIDDEN`. |
| Admin token | Opaque shared secret | Carrier Wave operators | Configuration | `/v1/admin/*` only |

How routes treat a bearer:

- **Public routes** accept an optional bearer. A valid one personalises the
  response (for example a leaderboard's `userPosition`). An invalid, expired,
  revoked or out-of-scope token is silently ignored and the request proceeds
  anonymously, so public routes never return `401`.
- **First-party routes** require a bearer. Missing or invalid gives
  `401 INVALID_TOKEN`. A third-party token outside its allowed set gives
  `403 FORBIDDEN`.
- **Account-management routes** under `/v1/auth/` accept only account tokens,
  never `fd_` device tokens.
- **Admin routes** compare the bearer to the operator secret.

Some first-party routes also require that the caller has an *account*
(an email-verified identity) and not merely a device token. Those answer
`403 ACCOUNT_REQUIRED`; the sync journal is the main example.

The sign-in flows are described in full under
[Authentication and accounts](#authentication-and-accounts) and
[OAuth 2.0 / OpenID Connect provider](#oauth-20--openid-connect-provider).

### Third-party access

A token minted for a registered OAuth client is **default-denied**: it is
refused on every route not in this table, regardless of scope. The absence
of an entry is itself the policy.

| Method | Path | Scope required |
|---|---|---|
| `GET` | `/v1/sync/bootstrap` | `sync:read` |
| `GET` | `/v1/sync/changes` | `sync:read` |
| `GET` | `/v1/sync/key` | `sync:read` |
| `POST` | `/v1/sync/push` | `sync:write` |
| `POST` | `/v1/sync/snapshot` | `sync:write` |
| `POST` | `/v1/sync/snapshot/commit` | `sync:write` |
| `PUT` | `/v1/sync/key` | `sync:write` |
| `GET` | `/v1/oauth/userinfo` | `openid` |

The scopes a client may request, with the wording the user sees on the
consent screen:

| Scope | Consent text |
|---|---|
| `openid` | Confirm your Carrier Wave account |
| `profile` | See your callsign and public profile |
| `email` | See the email address on your account |
| `sync:read` | Download your encrypted log. The app still needs your sync passphrase to read it; this server cannot decrypt it and neither can anyone without that passphrase. |
| `sync:write` | Add and update QSOs in your log, and upload encrypted log data |

Unknown scope strings are dropped from the request rather than rejected.

## Rate limits, CORS and body size

| Scope | Limit |
|---|---|
| Whole server | 10 requests per second, burst 20 |
| `POST /v1/register` | 1 request per minute, burst 1 |
| `POST /v1/auth/verify/start` | 1 request per 20 seconds, burst 3 |
| `POST /v1/macros/:slug/run-event` | Per-account limiter (see Radio macros) |
| Event submissions | At most 10 pending per user |

When a limit trips the response is **not** the JSON error shape. It is
`429 Too Many Requests` with a plain-text body
`Too Many Requests! Wait for <n>s` and an `x-ratelimit-after: <n>` header.
No `X-RateLimit-Limit` or `X-RateLimit-Remaining` headers are sent. The limits
are enforced inside the application on the aggregate traffic that reaches
it, so treat them as a ceiling, not a per-client allowance, and back off on
`429`.

**CORS** allows the origins `https://carrierwave.app` and
`https://activities.carrierwave.app`, the methods
`GET POST PUT DELETE OPTIONS`, and the headers `Authorization` and
`Content-Type`. Browser-based third-party apps therefore cannot call the API
directly from another origin; use a backend. Native and CLI clients are
unaffected.

**Request bodies** are capped at 1 MiB. Upload endpoints that need more
(badge images, club logos, sync pushes and snapshots) say so in their notes.
Oversized bodies are rejected before the handler runs, as `400 VALIDATION_ERROR` on most endpoints.

## Error format

Application errors are JSON:

```json
{
  "error": {
    "code": "CHALLENGE_NOT_FOUND",
    "message": "Challenge not found",
    "details": { "challengeId": "7d6c…" }
  }
}
```

- `code` is a stable upper-snake identifier. Branch on it, never on `message`.
- `message` is human-readable and may change.
- `details` is omitted when there is nothing to add.

Unknown `/v1` paths return `404` with code `NOT_FOUND`. Malformed JSON, a
body that fails validation, or an unparseable path parameter is
`400 VALIDATION_ERROR` with the parser's explanation as the `message`. A few
older handlers answer those cases with a plain-text `400` or `422` instead.
`304 Not Modified` has no body.

The OAuth token, device-code and revoke endpoints use the RFC 6749 error shape
(`{"error": "invalid_grant", "error_description": "…"}`).

The complete list of application error codes is in
[Appendix: error codes](#appendix-error-codes).

## Endpoint index

Every route the server mounts. "Auth" is the gate the route sits behind;
individual handlers may add further checks such as ownership, account
required, or scope.

| Method | Path | Auth |
|---|---|---|
| `GET` | `/v1/challenges` | Public (optional bearer) |
| `GET` | `/v1/challenges/:id` | Public (optional bearer) |
| `POST` | `/v1/challenges/:id/join` | Public (optional bearer) |
| `GET` | `/v1/challenges/:id/leaderboard` | Public (optional bearer) |
| `GET` | `/v1/contests` | Public (optional bearer) |
| `GET` | `/v1/contests/:id` | Public (optional bearer) |
| `GET` | `/v1/badges/:id/image` | Public (optional bearer) |
| `GET` | `/v1/achievements` | Public (optional bearer) |
| `GET` | `/v1/users/:callsign/achievements` | Public (optional bearer) |
| `GET` | `/v1/programs` | Public (optional bearer) |
| `GET` | `/v1/programs/:slug` | Public (optional bearer) |
| `GET` | `/v1/spots` | Public (optional bearer) |
| `GET` | `/v1/callsign-enrichment/dataset` | Public (optional bearer) |
| `GET` | `/v1/callsign-enrichment/:callsign` | Public (optional bearer) |
| `GET` | `/v1/satellites/amsat-status` | Public (optional bearer) |
| `GET` | `/v1/health` | Public (optional bearer) |
| `GET` | `/v1/users/search` | Public (optional bearer) |
| `POST` | `/v1/register` | Public (optional bearer) |
| `GET` | `/v1/pota/stats/activator` | Public (optional bearer) |
| `GET` | `/v1/pota/stats/hunter` | Public (optional bearer) |
| `GET` | `/v1/pota/stats/state/:state` | Public (optional bearer) |
| `GET` | `/v1/pota/stats/park/:reference` | Public (optional bearer) |
| `GET` | `/v1/pota/stats/rankings/activators` | Public (optional bearer) |
| `GET` | `/v1/pota/stats/status` | Public (optional bearer) |
| `GET` | `/v1/parks/boundaries` | Public (optional bearer) |
| `GET` | `/v1/parks/boundaries/status` | Public (optional bearer) |
| `GET` | `/v1/parks/boundaries/:reference` | Public (optional bearer) |
| `GET` | `/v1/admin/boundaries` | Public (optional bearer) |
| `GET` | `/v1/trails` | Public (optional bearer) |
| `GET` | `/v1/trails/status` | Public (optional bearer) |
| `GET` | `/v1/trails/:reference` | Public (optional bearer) |
| `GET` | `/v1/clubs/:id/logo` | Public (optional bearer) |
| `GET` | `/v1/equipment/catalog` | Public (optional bearer) |
| `GET` | `/v1/equipment/search` | Public (optional bearer) |
| `POST` | `/v1/equipment/submissions` | Public (optional bearer) |
| `GET` | `/v1/events` | Public (optional bearer) |
| `GET` | `/v1/events/:id` | Public (optional bearer) |
| `GET` | `/v1/macros` | Public (optional bearer) |
| `GET` | `/v1/macros/versions` | Public (optional bearer) |
| `GET` | `/v1/macros/tombstones` | Public (optional bearer) |
| `GET` | `/v1/macros/:slug` | Public (optional bearer) |
| `GET` | `/v1/macros/:slug/versions` | Public (optional bearer) |
| `GET` | `/v1/rbn/spots` | Public (optional bearer) |
| `GET` | `/v1/rbn/stats` | Public (optional bearer) |
| `GET` | `/v1/rbn/skimmers` | Public (optional bearer) |
| `GET` | `/v1/websdr/directory` | Public (optional bearer) |
| `GET` | `/v1/websdr/status` | Public (optional bearer) |
| `GET` | `/v1/websdr/stream` | Public (optional bearer) |
| `POST` | `/v1/twilio/sms` | Public (optional bearer) |
| `POST` | `/v1/metrics` | Public (optional bearer) |
| `POST` | `/v1/diagnostics` | Public (optional bearer) |
| `POST` | `/v1/telemetry/equipment-usage` | Public (optional bearer) |
| `POST` | `/v1/challenges/:id/progress` | Bearer (first-party) |
| `GET` | `/v1/challenges/:id/progress` | Bearer (first-party) |
| `DELETE` | `/v1/challenges/:id/leave` | Bearer (first-party) |
| `GET` | `/v1/challenges/:id/participants/:callsign` | Bearer (first-party) |
| `GET` | `/v1/participants/:callsign/challenges` | Bearer (first-party) |
| `GET` | `/v1/friends/invite-link` | Bearer (first-party) |
| `POST` | `/v1/friends/requests` | Bearer (first-party) |
| `POST` | `/v1/friends/suggestions` | Bearer (first-party) |
| `GET` | `/v1/friends` | Bearer (first-party) |
| `GET` | `/v1/friends/requests/pending` | Bearer (first-party) |
| `POST` | `/v1/friends/requests/:id/accept` | Bearer (first-party) |
| `POST` | `/v1/friends/requests/:id/decline` | Bearer (first-party) |
| `DELETE` | `/v1/friends/:id` | Bearer (first-party) |
| `POST` | `/v1/activities` | Bearer (first-party) |
| `DELETE` | `/v1/activities/:id` | Bearer (first-party) |
| `POST` | `/v1/spots` | Bearer (first-party) |
| `DELETE` | `/v1/spots/:id` | Bearer (first-party) |
| `GET` | `/v1/feed` | Bearer (first-party) |
| `GET` | `/v1/clubs` | Bearer (first-party) |
| `GET` | `/v1/clubs/sync` | Bearer (first-party) |
| `GET` | `/v1/clubs/membership` | Bearer (first-party) |
| `GET` | `/v1/clubs/:id` | Bearer (first-party) |
| `GET` | `/v1/clubs/:id/activity` | Bearer (first-party) |
| `GET` | `/v1/clubs/:id/status` | Bearer (first-party) |
| `PUT` | `/v1/clubs/:id/notes` | Bearer (first-party) |
| `POST` | `/v1/events` | Bearer (first-party) |
| `GET` | `/v1/events/mine` | Bearer (first-party) |
| `PUT` | `/v1/events/:id` | Bearer (first-party) |
| `DELETE` | `/v1/events/:id` | Bearer (first-party) |
| `POST` | `/v1/telemetry/upload-errors` | Bearer (first-party) |
| `POST` | `/v1/spot-markers` | Bearer (first-party) |
| `POST` | `/v1/sota/zones` | Bearer (first-party) |
| `DELETE` | `/v1/account` | Bearer (first-party) |
| `POST` | `/v1/users/me/achievements/signal` | Bearer (first-party) |
| `PUT` | `/v1/account/callsign` | Bearer (first-party) |
| `POST` | `/v1/account/claim-previous` | Bearer (first-party) |
| `POST` | `/v1/macros/:slug/run-event` | Bearer (first-party) |
| `POST` | `/v1/sync/push` | Bearer (first-party) |
| `GET` | `/v1/sync/changes` | Bearer (first-party) |
| `POST` | `/v1/sync/snapshot` | Bearer (first-party) |
| `POST` | `/v1/sync/snapshot/commit` | Bearer (first-party) |
| `GET` | `/v1/sync/bootstrap` | Bearer (first-party) |
| `PUT` | `/v1/sync/key` | Bearer (first-party) |
| `GET` | `/v1/sync/key` | Bearer (first-party) |
| `POST` | `/v1/oauth/authorize/decision` | Bearer (first-party) |
| `POST` | `/v1/oauth/device/decision` | Bearer (first-party) |
| `GET` | `/v1/oauth/userinfo` | Bearer (first-party) |
| `GET` | `/v1/oauth/grants` | Bearer (first-party) |
| `DELETE` | `/v1/oauth/grants/:client_id` | Bearer (first-party) |
| `GET` | `/v1/admin/oauth/clients` | Admin token |
| `POST` | `/v1/admin/oauth/clients` | Admin token |
| `DELETE` | `/v1/admin/oauth/clients/:client_id` | Admin token |
| `GET` | `/v1/admin/sync/orphans` | Admin token |
| `POST` | `/v1/admin/sync/orphans/:participant_id/adopt` | Admin token |
| `POST` | `/v1/admin/challenges` | Admin token |
| `PUT` | `/v1/admin/challenges/:id` | Admin token |
| `DELETE` | `/v1/admin/challenges/:id` | Admin token |
| `POST` | `/v1/admin/contests` | Admin token |
| `DELETE` | `/v1/admin/contests/:id` | Admin token |
| `POST` | `/v1/admin/contests/validate` | Admin token |
| `POST` | `/v1/admin/challenges/:id/badges` | Admin token |
| `GET` | `/v1/admin/challenges/:id/badges` | Admin token |
| `DELETE` | `/v1/admin/badges/:id` | Admin token |
| `POST` | `/v1/admin/achievements/:id/award` | Admin token |
| `DELETE` | `/v1/admin/achievements/:id/award/:callsign` | Admin token |
| `POST` | `/v1/admin/achievements/:id/award/batch` | Admin token |
| `POST` | `/v1/admin/achievements/backfill` | Admin token |
| `POST` | `/v1/admin/challenges/:id/invites` | Admin token |
| `GET` | `/v1/admin/challenges/:id/invites` | Admin token |
| `DELETE` | `/v1/admin/invites/:token` | Admin token |
| `POST` | `/v1/admin/programs` | Admin token |
| `GET` | `/v1/admin/programs` | Admin token |
| `PUT` | `/v1/admin/programs/:slug` | Admin token |
| `GET` | `/v1/admin/programs/:slug` | Admin token |
| `DELETE` | `/v1/admin/programs/:slug` | Admin token |
| `POST` | `/v1/admin/clubs` | Admin token |
| `GET` | `/v1/admin/clubs` | Admin token |
| `PUT` | `/v1/admin/clubs/:id` | Admin token |
| `DELETE` | `/v1/admin/clubs/:id` | Admin token |
| `POST` | `/v1/admin/clubs/:id/members` | Admin token |
| `GET` | `/v1/admin/clubs/:id/members` | Admin token |
| `POST` | `/v1/admin/clubs/:id/import-notes` | Admin token |
| `PUT` | `/v1/admin/clubs/:id/logo` | Admin token |
| `DELETE` | `/v1/admin/clubs/:id/logo` | Admin token |
| `DELETE` | `/v1/admin/clubs/:id/members/:callsign` | Admin token |
| `PUT` | `/v1/admin/clubs/:id/members/:callsign` | Admin token |
| `POST` | `/v1/admin/equipment` | Admin token |
| `PUT` | `/v1/admin/equipment/:id` | Admin token |
| `DELETE` | `/v1/admin/equipment/:id` | Admin token |
| `GET` | `/v1/admin/equipment/submissions` | Admin token |
| `PUT` | `/v1/admin/equipment/submissions/:id/review` | Admin token |
| `GET` | `/v1/admin/events` | Admin token |
| `GET` | `/v1/admin/events/:id` | Admin token |
| `PUT` | `/v1/admin/events/:id` | Admin token |
| `DELETE` | `/v1/admin/events/:id` | Admin token |
| `PUT` | `/v1/admin/events/:id/review` | Admin token |
| `GET` | `/v1/admin/events/submitter/:callsign` | Admin token |
| `GET` | `/v1/admin/telemetry/upload-errors` | Admin token |
| `GET` | `/v1/admin/metrickit` | Admin token |
| `POST` | `/v1/admin/macros` | Admin token |
| `GET` | `/v1/admin/macros` | Admin token |
| `PUT` | `/v1/admin/macros/:slug` | Admin token |
| `PATCH` | `/v1/admin/macros/:slug` | Admin token |
| `DELETE` | `/v1/admin/macros/:slug` | Admin token |
| `DELETE` | `/v1/admin/spots/:id` | Admin token |
| `GET` | `/v1/admin/trails/status` | Admin token |
| `GET` | `/v1/admin/stats` | Admin token |
| `GET` | `/v1/admin/stats/users-by-hour` | Admin token |
| `POST` | `/v1/propagation/p2p` | None |
| `POST` | `/v1/propagation/wheel` | None |
| `POST` | `/v1/auth/verify/start` | Public |
| `GET` | `/v1/auth/verify/complete` | Public |
| `POST` | `/v1/auth/verify/poll` | Public |
| `POST` | `/v1/auth/token` | Public |
| `POST` | `/v1/auth/token/refresh` | Public |
| `POST` | `/v1/auth/logout` | Public |
| `POST` | `/v1/auth/logout/all` | JWT bearer (account) |
| `GET` | `/v1/auth/devices` | JWT bearer (account) |
| `DELETE` | `/v1/auth/devices/:id` | JWT bearer (account) |
| `POST` | `/v1/auth/callsigns/verify/start` | JWT bearer (account) |
| `GET` | `/v1/oauth/authorize` | Public / client credentials |
| `POST` | `/v1/oauth/token` | Public / client credentials |
| `GET` | `/v1/oauth/device` | Public / client credentials |
| `POST` | `/v1/oauth/device/code` | Public / client credentials |
| `POST` | `/v1/oauth/revoke` | Public / client credentials |
| `GET` | `/.well-known/jwks.json` | Public |
| `GET` | `/.well-known/openid-configuration` | Public |
| `GET` | `/.well-known/oauth-authorization-server` | Public |
| `GET` | `/invite/:token` | Public (HTML) |
| `GET` | `/link/qso/:token` | Public |
| `GET` | `/link/act/:token` | Public |
| `GET` | `/link/call/:callsign` | Public |
| `GET` | `/link/park/:reference` | Public |
| `GET` | `/link/sum/:reference` | Public |
| `GET` | `/link/static/link-card.js` | Public |
| `GET` | `/.well-known/apple-app-site-association` | Public |
| `GET` | `/metrics` | Public |

Routes marked *Admin token* are operated by Carrier Wave staff through the
admin console. They are listed for completeness and summarised briefly in
each section; their request and response shapes are not documented here.

## Authentication and accounts

All paths are under `/v1` unless noted. Carrier Wave uses two kinds of credential.

**Device tokens.** The original scheme. A device token is an opaque string with the `fd_` prefix, issued by `POST /v1/register` on the first registration of a callsign (and by challenge join). It carries no account identity and cannot be recovered if lost.

**Account tokens.** A Carrier Wave account owns one or more verified callsigns and issues two tokens per device:

- **Access tokens** are JWTs signed with EdDSA (Ed25519). They live for **15 minutes**; the server allows 60 seconds of clock skew. The header `kid` names the signing key published at `/.well-known/jwks.json`. Claims:
  - `iss`: always `https://activities.carrierwave.app`
  - `sub`: the account id (UUID)
  - `aud`: `cw-social` (accepted by this API) or `cw-sync` (accepted only by the sync service). A token minted for one audience is rejected by the other.
  - `scope`: space-delimited scopes from the set `sync:read sync:write social:read social:write account`. If you request no scopes or only unknown ones, you receive the full set.
  - `cs`: the account's primary callsign. Informational only; the server never uses it for authorization and re-resolves the acting callsign from the account.
  - `iat`, `exp`: unix seconds
  - `jti`: random UUID
  - `cid`: present only on tokens issued to third-party OAuth clients. Tokens issued by the endpoints in this section never carry it. Third-party tokens are refused (`403 FORBIDDEN`) by every endpoint in this section and treated as anonymous by the public ones.
- **Refresh tokens** are opaque strings with the `cwr_` prefix. Each has a sliding lifetime of **60 days**, and the family it belongs to has an absolute lifetime of **180 days**, after which you must verify by email again. Every refresh rotates the token. Re-presenting the previous token within a **60 second grace window** returns the current live pair; outside that window the server treats it as reuse and revokes the whole family. One refresh family corresponds to one device.

**Email verification flow.** Sign-in and onboarding use a magic link plus PKCE.

1. Generate a PKCE verifier and compute `pkceChallenge = hex(sha256(verifier))`, 64 hex characters (not base64url). Call `POST /v1/auth/verify/start` with the callsign and optionally a fallback `email`. If the amateur radio directory has an email for that exact callsign, the link goes there; otherwise it goes to the `email` you supplied. If the callsign already belongs to an account, the link goes only to that account's on-file address and your `email` is ignored. The response is always `202` with a `pollToken`, whether or not any mail could be sent.
2. The email contains a link to `GET /v1/auth/verify/complete?code=<code>`. Opening it marks the verification as clicked (single use) and shows a static page. The code alone is not a credential.
3. Finish one of two ways. If your app received the `code` (for example through a universal link), call `POST /v1/auth/token` with `code` and `pkceVerifier`. Otherwise poll `POST /v1/auth/verify/poll` with `pollToken` and `pkceVerifier`; `202` means not clicked yet, any other status is the same result `/auth/token` would return. Both paths consume the verification.
4. The outcome depends on what was started. **Onboarding** (unclaimed callsign): a new account, device and tokens, `201`. **Sign-in** (callsign already owned): a new device on that account, `201`. **Attach** (started from `/auth/callsigns/verify/start` by a signed-in account): the callsign is added to the account and no tokens are issued, `204`.

Verifications expire 15 minutes after they are started.

**Device management.** Every token issuance creates a device (`deviceName`, `platform`) with its own refresh family. `GET /auth/devices` lists devices, `DELETE /auth/devices/:id` revokes one, `POST /auth/logout` revokes the family of a given refresh token, and `POST /auth/logout/all` revokes everything.

**Revocation.** Access tokens are verified without a database lookup, so revocation has two strengths. `POST /auth/logout/all` and `PUT /account/callsign` invalidate every existing access token for the account immediately, including the one used to make the call. `POST /auth/logout` and `DELETE /auth/devices/:id` revoke only the refresh family: an access token already issued for that device stays valid until it expires, at most 15 minutes later.

**Which bearer an endpoint accepts.**

- *Public*: no credential needed. A bearer, if sent, is ignored.
- *Bearer (first-party)*: a device token or a first-party account access token. An account token acts as the account's primary callsign.
- *Account token*: an account access token only, with the `account` scope. A device token is rejected with `401 INVALID_TOKEN`; a token without the scope is rejected with `403 FORBIDDEN`.

**`ACCOUNT_REQUIRED`.** Some features outside this section (sync, OAuth user info and grants) need an account-backed session. When you call them with a device token you receive `403` with code `ACCOUNT_REQUIRED` and a message saying that a Carrier Wave account is required. Sign in with the email flow above to continue.

The `/v1/auth/*` and `/.well-known/*` endpoints exist only when account sign-in is enabled on the server; otherwise they return `404` and only device tokens are accepted.

### Sign-in and tokens

#### Start callsign verification
```
POST /v1/auth/verify/start
```
**Auth:** Public
**Rate limit:** 1 request per 20 s per IP, burst 3, in addition to the global limit.

**Request**
```json
{
  "callsign": "W6JY",
  "email": "me@example.com",
  "pkceChallenge": "3f1a…64 hex chars…"
}
```
| Field | Type | Required | Notes |
|---|---|---|---|
| `callsign` | string | yes | Trimmed; 1 to 16 characters. Stored upper-cased. |
| `email` | string | no | Fallback address, used only when the directory has no email for the callsign and the callsign is not already owned by an account. Must be non-empty, at most 254 characters, and contain `@`. Silently ignored if invalid. |
| `pkceChallenge` | string | yes | Exactly 64 hex characters: `hex(sha256(verifier))`. |

**Response** `202 Accepted`
```json
{ "pollToken": "cwp_<64 hex>" }
```
Always `202` with a fresh poll token, even if no email was sent (unknown callsign with no deliverable address, account with no stored email, delivery failure). You cannot tell from the response whether mail went out.

**Errors**
| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Empty or over-long callsign; `pkceChallenge` not 64 hex; malformed JSON |
| `INTERNAL_ERROR` | 500 | Server failure |
| (plain text) | 429 | Route or global rate limit |

**Notes**
- If the callsign already belongs to an account, the link goes to the directory email if one resolves, else the account's stored verified email. Your `email` is ignored.
- The emailed link is `https://activities.carrierwave.app/v1/auth/verify/complete?code=<32 hex>`.

#### Magic-link landing page
```
GET /v1/auth/verify/complete?code=<code>
```
**Auth:** Public

| Param | Type | Required | Description |
|---|---|---|---|
| `code` (query) | string | yes | The 32-hex code from the emailed link. |

**Response** `200 OK`, `Content-Type: text/html`. A self-contained Carrier Wave page saying either "Callsign verified" (return to the app to finish signing in) or "Link expired" (invalid or expired). Status is `200` in both cases. Headers: `referrer-policy: no-referrer`, `content-security-policy: default-src 'none'; style-src 'unsafe-inline'; img-src data:`, `cache-control: no-store`.

**Errors**
| Code | HTTP | When |
|---|---|---|
| (plain text) | 400 | `code` query parameter missing |

**Notes**
- Single use: a second visit shows the "expired" page.
- Opening the link does not issue tokens. The app must still present the PKCE verifier to `/auth/token` or `/auth/verify/poll`.

#### Poll for verification completion
```
POST /v1/auth/verify/poll
```
**Auth:** Public

**Request**
```json
{
  "pollToken": "cwp_<64 hex>",
  "pkceVerifier": "the-verifier-whose-sha256-hex-was-sent",
  "deviceName": "Jay's iPhone",
  "platform": "ios",
  "scopes": "sync:read sync:write social:read social:write account"
}
```
| Field | Type | Required | Notes |
|---|---|---|---|
| `pollToken` | string | yes | From `/auth/verify/start`. |
| `pkceVerifier` | string | yes | Must satisfy `hex(sha256(verifier)) == pkceChallenge`. |
| `deviceName` | string | no | Shown in `GET /auth/devices`. |
| `platform` | string | no | Free-form, shown in `GET /auth/devices`. |
| `scopes` | string | no | Space-separated. Unknown scopes are dropped; if nothing valid remains, all five scopes are granted. |

**Response**, one of:
- `202 Accepted`, empty body: link not yet clicked, poll token unknown, or verification expired. The server does not distinguish these, so stop polling after 15 minutes.
- `201 Created`, onboarding or new-device sign-in:
  ```json
  {
    "access": "<EdDSA JWT>",
    "refresh": "cwr_<64 hex>",
    "expiresIn": 900,
    "accountId": "4c4a1b3e-…"
  }
  ```
- `204 No Content`: the verification was an attach (started via `/auth/callsigns/verify/start`). The callsign is now on the account; no new tokens.

**Errors**
| Code | HTTP | When |
|---|---|---|
| `FORBIDDEN` | 403 | Link was clicked but `pkceVerifier` does not match the challenge. The verification is not consumed; retry with the right verifier. |
| `INVALID_TOKEN` | 401 | Sign-in path: the account the verification was bound to no longer exists. |
| `CALLSIGN_TAKEN` | 409 | Callsign became owned by another account between start and completion. `details.callsign`. |
| `VALIDATION_ERROR` | 400 | Malformed JSON or missing required fields |

**Notes**
- Tokens are identical to those from `/auth/token`. The access token audience is always `cw-social`.
- On `201` a new device and refresh family are created; on onboarding the account is created too.

#### Exchange a clicked verification code for tokens
```
POST /v1/auth/token
```
**Auth:** Public

**Request**
```json
{
  "code": "<32 hex from the emailed link>",
  "pkceVerifier": "…",
  "deviceName": "Jay's iPhone",
  "platform": "ios",
  "scopes": "sync:read sync:write"
}
```
`code` and `pkceVerifier` are required. The optional fields and their defaults are the same as `/auth/verify/poll`.

**Response:** `201 Created` with `access`, `refresh`, `expiresIn` (900) and `accountId`, or `204 No Content` for the attach case. Same semantics as `/auth/verify/poll`.

**Errors**
| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | No clicked, unexpired verification with that code (never clicked, expired, already exchanged, or unknown) |
| `FORBIDDEN` | 403 | PKCE verifier mismatch; the verification is not consumed |
| `CALLSIGN_TAKEN` | 409 | As above |
| `VALIDATION_ERROR` | 400 | Malformed JSON |

**Notes**
- The link must have been opened first. A successful exchange consumes the code.
- Not to be confused with `POST /v1/oauth/token`, the third-party OAuth token endpoint.

#### Refresh (rotate) tokens
```
POST /v1/auth/token/refresh
```
**Auth:** Public (the refresh token in the body is the credential)

**Request**
```json
{ "refresh": "cwr_<64 hex>", "aud": "cw-social" }
```
| Field | Type | Required | Notes |
|---|---|---|---|
| `refresh` | string | yes | Current live refresh token, or the one just rotated within the last 60 s. |
| `aud` | string | no | `"cw-social"` (default) or `"cw-sync"`. Anything else is a `400`. |

**Response** `200 OK`
```json
{ "access": "<JWT>", "refresh": "cwr_<new 64 hex>", "expiresIn": 900 }
```

**Errors**
| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Unknown `aud`; malformed JSON |
| `FORBIDDEN` | 403 | The refresh token belongs to a third-party OAuth grant (use `/v1/oauth/token`). Checked before rotation, so the token is not consumed. |
| `INVALID_TOKEN` | 401 | Unknown token; expired (60-day sliding); family older than 180 days (family revoked); reuse detected (replay outside the 60 s grace window, or a revoked token; the whole family is revoked); account missing. |

**Notes**
- Rotation is serialized per family. A concurrent or retried refresh with the previous token inside the grace window returns a fresh pair rather than revoking, so an app, widget and watch sharing one device do not lock each other out.
- Scopes carry over from the refresh token. `cs` is re-read from the account's primary callsign at mint time.

#### Log out this device
```
POST /v1/auth/logout
```
**Auth:** Public (refresh token in body)

**Request**
```json
{ "refresh": "cwr_<64 hex>" }
```

**Response:** `204 No Content`. Idempotent: an unknown token also returns `204`.

**Errors**
| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Malformed JSON |
| `INTERNAL_ERROR` | 500 | Server failure |

**Notes**
- Revokes every token in the refresh family. The device entry is not removed from `GET /auth/devices`, and an outstanding access token for the device remains valid until it expires (at most 15 minutes).
- Works with any token in the family, including an already-rotated one.

### Account management

These endpoints require an account access token with `aud` `cw-social`, a valid signature, unexpired, not revoked, and carrying the `account` scope. Checks run in that order: a missing, invalid, expired or revoked bearer is `401 INVALID_TOKEN`; a third-party token or a missing `account` scope is `403 FORBIDDEN`. A device token is rejected with `401 INVALID_TOKEN`.

#### Log out everywhere
```
POST /v1/auth/logout/all
```
**Auth:** Account token

No params, no body.

**Response:** `204 No Content`.

**Errors**
| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing, invalid or revoked bearer |
| `FORBIDDEN` | 403 | Missing `account` scope, or third-party token |

**Notes**
- Revokes every refresh token for the account and immediately invalidates every access token issued before the call, including the one used to make it. Device entries are not deleted, so a fresh session still sees them in `GET /auth/devices`.

#### List devices
```
GET /v1/auth/devices
```
**Auth:** Account token

**Response** `200 OK`
```json
{
  "data": [
    {
      "id": "0e7c…",
      "deviceName": "Jay's iPhone",
      "platform": "ios",
      "createdAt": "2026-10-01T18:04:11.120Z",
      "lastSeenAt": "2026-10-01T18:04:11.120Z"
    }
  ]
}
```
Ordered by `lastSeenAt` descending. `deviceName` and `platform` are `null` when not supplied at token issuance. At present `lastSeenAt` is set when the device is created and not updated afterwards, so it matches `createdAt`.

**Errors:** `401 INVALID_TOKEN`, `403 FORBIDDEN` as above.

**Notes:** Devices whose refresh family was revoked via `/auth/logout` or `/auth/logout/all` still appear. Only `DELETE /auth/devices/:id` removes an entry.

#### Revoke a device
```
DELETE /v1/auth/devices/:id
```
**Auth:** Account token

| Param | Type | Required | Description |
|---|---|---|---|
| `id` (path) | UUID | yes | Device id from `GET /auth/devices`. |

**Response:** `204 No Content`. Idempotent: `204` even if the device does not exist or belongs to another account.

**Errors**
| Code | HTTP | When |
|---|---|---|
| (plain text) | 400 | `id` is not a valid UUID |
| `INVALID_TOKEN` | 401 | Bearer problems |
| `FORBIDDEN` | 403 | Missing `account` scope, or third-party token |

**Notes:** Revokes that device's refresh tokens and removes the device entry. The device's current access token lives on until expiry.

#### Start verification of an additional callsign
```
POST /v1/auth/callsigns/verify/start
```
**Auth:** Account token
**Rate limit:** none route-specific (only the global limit), unlike the public `/auth/verify/start`.

**Request:** same body as `/auth/verify/start`: `callsign` (required), `email` (optional fallback), `pkceChallenge` (required, 64 hex).

**Response:** `202 Accepted` `{ "pollToken": "cwp_…" }`.

**Errors:** `VALIDATION_ERROR` 400, `INVALID_TOKEN` 401, `FORBIDDEN` 403 (scope), `INTERNAL_ERROR` 500.

**Notes**
- The verification is bound to your account. Ownership by another account is not checked at this stage; the directory-else-supplied email is used. On completion via `/auth/token` or `/auth/verify/poll`: if your account already owns the callsign, the completion behaves like a sign-in (new device and tokens, `201`); otherwise the callsign is attached and you receive `204`, or `409 CALLSIGN_TAKEN` if another account holds it.
- Attaching a callsign does not change the account's primary callsign. Use `PUT /account/callsign` for that.

### Key discovery

#### JSON Web Key Set
```
GET /.well-known/jwks.json
```
**Auth:** Public. Served at the domain root, not under `/v1`.

**Response** `200 OK`, headers `content-type: application/json`, `cache-control: public, max-age=3600`:
```json
{
  "keys": [
    { "kty": "OKP", "crv": "Ed25519", "use": "sig", "alg": "EdDSA", "kid": "v1", "x": "<base64url raw 32-byte public key>" }
  ]
}
```
The set contains exactly one key, the current signing key. After a key rotation, tokens signed with the previous key no longer verify.

**Errors:** none specific (`404` when account sign-in is disabled).

**Notes:** The same location also serves `/.well-known/openid-configuration` and `/.well-known/oauth-authorization-server` for the third-party OAuth provider, documented separately.

### Legacy registration and user search

Both endpoints are public. A bearer, if present and valid, is accepted but has no effect on the response; an invalid bearer is ignored, not rejected.

#### Register a callsign (legacy device token)
```
POST /v1/register
```
**Auth:** Public (optional bearer; no effect)
**Rate limit:** 1 request per 60 s per IP, burst 1.

**Request**
```json
{ "callsign": "w6jy ", "deviceName": "Jay's iPhone" }
```
| Field | Type | Required | Notes |
|---|---|---|---|
| `callsign` | string | yes | Trimmed and upper-cased before validation and storage; 1 to 16 characters. |
| `deviceName` | string | no | At most 128 characters. |

**Response** `201 Created`
```json
{ "data": { "userId": "b1a2…", "deviceToken": "fd_<32 alnum>" } }
```
`deviceToken` is omitted entirely when the callsign is already registered. Re-registering an existing callsign never yields a credential. `userId` (the friend-search identity) is returned in both cases. Status is `201` even when nothing new was created.

**Errors**
| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Empty callsign; callsign longer than 16 characters; `deviceName` longer than 128 characters; malformed JSON |
| (plain text) | 429 | Register or global rate limit |
| `INTERNAL_ERROR` | 500 | Server failure |

**Notes**
- Callsign ownership is not verified here; anyone can register any unclaimed callsign.
- A lost device token cannot be reissued. Recover access through the email verification flow.

#### Search users by callsign
```
GET /v1/users/search?q=<fragment>
```
**Auth:** Public (optional bearer; no effect)

| Param | Type | Required | Description |
|---|---|---|---|
| `q` (query) | string | yes | Case-insensitive substring match on callsign. Shorter than 2 bytes returns an empty result. |

**Response** `200 OK`
```json
{ "data": [ { "userId": "b1a2…", "callsign": "W6JY", "displayName": null } ] }
```
Up to 20 rows, ordered by callsign. `displayName` is currently always `null`.

**Errors**
| Code | HTTP | When |
|---|---|---|
| (plain text) | 400 | `q` missing |
| `INTERNAL_ERROR` | 500 | Server failure |

**Notes:** The length check on `q` counts bytes, not characters. `%` and `_` in `q` act as SQL wildcards.

### Account changes

These endpoints accept a device token or a first-party account access token. A missing or invalid bearer is `401 INVALID_TOKEN`; a third-party token is `403 FORBIDDEN`. An account token acts as the account's primary callsign.

#### Delete account
```
DELETE /v1/account
```
**Auth:** Bearer (first-party)

No params, no body.

**Response:** `204 No Content`.

**Errors**
| Code | HTTP | When |
|---|---|---|
| `USER_NOT_FOUND` | 404 | No profile exists for the acting callsign. Callsign-keyed data is still deleted before this is returned. |
| `INVALID_TOKEN` | 401 | Bearer problems |
| `FORBIDDEN` | 403 | Third-party token |

**Notes**
- Deletes the callsign's profile and everything keyed to it: challenge participation, progress, badges, friendships, friend requests, friend invites and activities. Any device tokens for the callsign stop working.
- For account-backed callers this does not delete the account, its verified callsigns, its devices or its tokens, and the session remains valid.

#### Change callsign
```
PUT /v1/account/callsign
```
**Auth:** Bearer (first-party)

**Request**
```json
{ "newCallsign": "W6JY" }
```
`newCallsign` is required; trimmed and upper-cased. No explicit length cap (unlike `/register`).

**Response** `200 OK`
```json
{ "data": { "callsign": "W6JY" } }
```

**Errors**
| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Empty `newCallsign`; equal to the current callsign; malformed JSON |
| `FORBIDDEN` | 403 | The current callsign is owned by an account and the caller is not that account. This includes device-token callers whose callsign has since been claimed by an account. Also third-party tokens. |
| `CALLSIGN_TAKEN` | 409 | Another profile already has `newCallsign`, or another account has verified it. `details.callsign`. |
| `USER_NOT_FOUND` | 404 | The caller's profile could not be found |
| `INVALID_TOKEN` | 401 | Bearer problems |

**Notes**
- Renames the callsign everywhere it appears (profile, challenges, progress, badges, activities, club membership, spots) and records the change in the callsign history.
- For account callers who own the current callsign, the account's verified callsign and primary callsign are rewritten and every existing access token is invalidated immediately, including the one used for this call. Call `/auth/token/refresh` to obtain a token whose `cs` reflects the new callsign. Refresh tokens are not revoked.

#### Claim a previous callsign's data
```
POST /v1/account/claim-previous
```
**Auth:** Bearer (first-party), effectively account tokens only. A device token authenticates but is refused with `403 FORBIDDEN` (not `ACCOUNT_REQUIRED`).

**Request**
```json
{ "previousCallsign": "KN6ABC" }
```
`previousCallsign` is required; trimmed and upper-cased.

**Response** `200 OK`
```json
{ "data": { "merged": true, "previousCallsign": "KN6ABC" } }
```

**Errors**
| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Empty; equal to the current callsign; malformed JSON |
| `FORBIDDEN` | 403 | Caller has no account (device token); the caller's account has not verified `previousCallsign`; or third-party token |
| `USER_NOT_FOUND` | 404 | No profile exists for `previousCallsign`, or none for the current callsign |
| `INVALID_TOKEN` | 401 | Bearer problems |

**Notes**
- Prerequisite: verify the old callsign on the same account first via `POST /auth/callsigns/verify/start`, the emailed link, then `/auth/token` or `/auth/verify/poll` (`204` attach).
- Merges the old callsign's friendships (both directions, skipping duplicates), friend requests and activities into the current callsign, and moves its challenge participation, progress, badges, club membership and spots. The old profile is then deleted, which invalidates any device tokens for the old callsign.
- The old callsign stays attached to the account.

## OAuth 2.0 / OpenID Connect provider

Carrier Wave is an OAuth 2.0 authorization server and an OpenID Connect provider. Your application can sign a Carrier Wave user in and, with the user's consent, read and write their encrypted log through the `/v1/sync/*` endpoints. The user signs in on Carrier Wave's own pages, so your app never handles their credentials. This is separate from the magic-link sign-in that Carrier Wave's own apps use.

All endpoints below are served from `https://activities.carrierwave.app`. The `/.well-known/*` documents live at the domain root; every other path is under `/v1`. On a server where OAuth is not enabled, the discovery documents and the public `/v1/oauth/*` endpoints return `404`.

### Registering a client

Client registration is curated. There is no self-serve portal and no dynamic client registration (RFC 7591). Email hello@carrierwave.app to register a client and include:

- The client id you would like (a short identifier such as `my-logger`) and the name users should see on the consent screen. A description and a homepage URL are optional; the homepage is shown on the consent screen as "Developer site".
- Your redirect URIs, if you use the authorization code flow. They are matched exactly: no wildcards, no prefixes, no normalization. Loopback URIs such as `http://127.0.0.1:<port>/callback` are fine for CLIs.
- The scopes you need. This becomes your client's ceiling; see Scopes and consent below.
- The grant types you need. Authorization code and refresh token are the default. Ask for `device_code` if you need the device flow.
- Whether the client is confidential (a server that can keep a secret) or public (native app, SPA, CLI).

A confidential client receives a secret of the form `cws_` followed by 40 alphanumeric characters. It is shown once and cannot be retrieved again. A public client has no secret, must not send one, and relies on PKCE instead.

Carrier Wave staff can suspend a client. A suspended client behaves exactly like an unknown one (`invalid_client`), so the two are indistinguishable to callers. There is no update endpoint; contact Carrier Wave to change redirect URIs or scopes.

### Grant types

| Grant | `grant_type` value | Notes |
|---|---|---|
| Authorization code | `authorization_code` | PKCE `S256` is mandatory for every client, confidential or public. `plain` is rejected. Codes live 60 seconds, are single use, and are bound to the client that requested them. |
| Refresh token | `refresh_token` | Rotating refresh tokens bound to the issuing client. A refresh never widens scope and honors revoked consent immediately. No `id_token` is returned on refresh. |
| Device authorization (RFC 8628) | `urn:ietf:params:oauth:grant-type:device_code` or the short form `device_code` | Device codes live 15 minutes. Poll every 5 seconds; `slow_down` is enforced. |

Not supported: implicit (`response_type=token`), client credentials, dynamic registration (RFC 7591), token introspection (RFC 7662). `response_types_supported` is `["code"]` only. Each client may use only the grant types it was registered with; any other grant returns `unsupported_grant_type`.

### Scopes and consent

These are the only scopes that exist. Any other scope string is silently dropped from a request, so an unknown scope can never become an authorization. The consent screen shows exactly this text next to each scope:

| Scope | Consent-screen description (verbatim) |
|---|---|
| `openid` | Confirm your Carrier Wave account |
| `profile` | See your callsign and public profile |
| `email` | See the email address on your account |
| `sync:read` | Download your encrypted log. The app still needs your sync passphrase to read it. This server cannot decrypt it and neither can anyone without that passphrase. |
| `sync:write` | Add and update QSOs in your log, and upload encrypted log data |

Scope rules:

- If a request omits `scope`, the server uses `openid`.
- Requested scopes are filtered to the known set, then clamped to your client's registered ceiling, preserving request order and dropping duplicates. You can always ask for less, never more.
- `openid` in the granted set turns the authorization into an OpenID Connect login and an `id_token` is minted. `email` additionally puts the verified email into the ID token and UserInfo.
- `profile` currently has no effect beyond appearing on the consent screen and in the token's `scope` claim. `callsign` and `preferred_username` are always returned by UserInfo.
- Whenever any `sync:*` scope is requested, the consent screen shows an explicit warning about the sync passphrase.

### What a third-party token may call

Access tokens issued to your client carry a `cid` claim (your client id). Every request made with such a token is checked against the table below. The route must be listed and the token must carry the exact scope shown (no prefix or wildcard matching; the HTTP method is part of the check). Anything else returns `403 FORBIDDEN`. Everything not listed, including clubs, friends, spots, events, contests, account management, the first-party `/v1/auth/*` routes and the OAuth flow routes themselves, is reserved for Carrier Wave's own apps.

| Method | Route (under `/v1`) | Required scope | What it moves |
|---|---|---|---|
| `GET` | `/sync/bootstrap` | `sync:read` | Live snapshot pointer plus post-snapshot journal entries (ciphertext and presigned download URLs) |
| `GET` | `/sync/changes?since=&limit=` | `sync:read` | Incremental journal entries with `seq > since` |
| `GET` | `/sync/key` | `sync:read` | The passphrase-wrapped key envelope (useless without the user's passphrase) |
| `POST` | `/sync/push` | `sync:write` | Reserve sequence numbers and get a presigned PUT URL per ciphertext entry |
| `POST` | `/sync/snapshot` | `sync:write` | Begin a snapshot (phase 1) |
| `POST` | `/sync/snapshot/commit` | `sync:write` | Confirm a snapshot (phase 2) |
| `PUT` | `/sync/key` | `sync:write` | Upload a new passphrase-wrapped key envelope |
| `GET` | `/oauth/userinfo` | `openid` | OpenID Connect UserInfo (documented below) |

The `/v1/sync/*` endpoints are documented separately. A refresh token issued by the OAuth provider cannot be used at the first-party `POST /v1/auth/token/refresh`; that returns `403 FORBIDDEN` without rotating the token. Use `POST /v1/oauth/token` with `grant_type=refresh_token`.

### Reading and writing the encrypted log

The log is an append-only journal of encrypted blobs. A token authorizes access to ciphertext, never decryption. The data key is derived on the user's device from their sync passphrase with Argon2id and never reaches the server.

1. `GET /v1/sync/key` (`sync:read`) returns the passphrase-wrapped data-key envelope. `404` means the user has not set up sync.
2. Ask the user for their sync passphrase in your own UI. Derive a key-encryption key with Argon2id and use it to unwrap the 32-byte data key.
3. `GET /v1/sync/bootstrap` for a first sync, or `GET /v1/sync/changes?since=<n>` for an incremental one. Each entry has a monotonic `seq` and a presigned download URL.
4. For each entry: download, decrypt with ChaCha20-Poly1305 using the data key, gunzip, and parse the journal payload JSON.
5. Fold payloads in `seq` order. Payloads are upserts and delete tombstones; the last write by `seq` wins. Persist the highest `seq` you have seen.
6. To write: build the QSO record or tombstone, wrap it in a journal payload, gzip it, seal it with the same key, call `POST /v1/sync/push` (`sync:write`) to get a presigned upload URL per entry, then `PUT` the ciphertext there. Push is idempotent on `client_entry_id`.

Wire details to watch: `frequency` is in MHz; field names are camelCase, with `rawADIF` and `isActivityLogQSO` as irregular spellings; entries are never modified in place.

### Error bodies

Two shapes appear in this family:

- RFC 6749 section 5.2 bodies on the OAuth protocol endpoints and the decision endpoints: `{"error": "<code>", "error_description": "<text>"}`, sent with `Cache-Control: no-store` and `Pragma: no-cache`. Status by code: `invalid_request` 400, `invalid_client` 401, `invalid_grant` 400, `unsupported_grant_type` 400, `invalid_scope` 400, `access_denied` 403, `authorization_pending` 400, `slow_down` 400, `expired_token` 400. The `401 invalid_client` response does not set a `WWW-Authenticate` header.
- The server envelope on UserInfo, connected-app routes, and for any bearer rejection: `{"error": {"code": "<CODE>", "message": "<text>"}}`, with an optional `details` field. Codes you may see: `INVALID_TOKEN` 401, `ACCOUNT_REQUIRED` 403, `FORBIDDEN` 403, `VALIDATION_ERROR` 400, `RATE_LIMITED` 429, `INTERNAL_ERROR` 500.

A request with the wrong content type, an unparseable body, or a missing required field such as `grant_type` is rejected before the OAuth handler runs and returns a plain-text error rather than an RFC 6749 body.

Every route is rate limited at roughly 10 requests per second with a burst of 20; beyond that you receive `429`. Request bodies are capped at 1 MiB.

### Walkthrough: authorization code flow (apps with a redirect)

1. Generate a random `code_verifier` (43 to 128 characters) and a random `state`. Compute `code_challenge = base64url_nopad(sha256(code_verifier))`. Optionally generate a `nonce`.
2. Send the user's browser to the consent page:

   ```
   GET /v1/oauth/authorize?client_id=my-logger
     &redirect_uri=https%3A%2F%2Fmylogger.example%2Foauth%2Fcallback
     &response_type=code
     &scope=openid%20sync%3Aread%20sync%3Awrite
     &state=5f1c…
     &code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM
     &code_challenge_method=S256
     &nonce=n-0S6_WzA2Mj
   ```

   The page is self-contained HTML. The user signs in on that page with a Carrier Wave magic link, so your app never sees their credentials, then clicks Allow or Deny. The page records the decision and sends the browser to your redirect URI.
3. The browser lands on your `redirect_uri`:
   - success: `?code=<48-character code>&state=5f1c…`
   - refusal: `?error=access_denied&state=5f1c…`
   - malformed request: `?error=unsupported_response_type|invalid_request|invalid_scope&state=…`

   Verify that `state` matches what you sent. An unknown `client_id` or an unregistered `redirect_uri` never redirects; the user sees a `400` HTML error page instead.
4. Within 60 seconds, exchange the code (form-encoded):

   ```
   POST /v1/oauth/token
   Content-Type: application/x-www-form-urlencoded

   grant_type=authorization_code&client_id=my-logger&code=<code>
   &redirect_uri=https%3A%2F%2Fmylogger.example%2Foauth%2Fcallback
   &code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
   ```

   A confidential client adds `Authorization: Basic base64(client_id:client_secret)` (or `client_secret=` in the form). A public client must not send a secret.
5. Receive `access_token`, `refresh_token`, `scope`, `expires_in: 900` and, with `openid`, `id_token`. Check that `id_token.nonce` equals the nonce you sent.
6. Call `/v1/sync/*` and `/v1/oauth/userinfo` with `Authorization: Bearer <access_token>`.
7. Before `expires_in` elapses, `POST /v1/oauth/token` with `grant_type=refresh_token&client_id=…&refresh_token=…`. Store the new `refresh_token` from every response.

### Walkthrough: device flow (CLIs and headless apps)

1. Start the authorization (form-encoded; client authentication as above):

   ```
   POST /v1/oauth/device/code
   Content-Type: application/x-www-form-urlencoded

   client_id=my-logger&scope=openid%20sync%3Aread
   ```

   The response carries `device_code`, `user_code` (for example `KRWG-ZPTL`), `verification_uri` (`https://activities.carrierwave.app/v1/oauth/device`), `verification_uri_complete` (`…/device?user_code=KRWG-ZPTL`), `expires_in: 900` and `interval: 5`.
2. Show the user `user_code` and `verification_uri`, or render `verification_uri_complete` as a QR code. On that page the user types the code, signs in with a magic link, and clicks Allow or Deny.
3. Poll no faster than every `interval` seconds:

   ```
   POST /v1/oauth/token
   Content-Type: application/x-www-form-urlencoded

   grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code
   &client_id=my-logger&device_code=<device_code>
   ```

   - `400 authorization_pending`: keep waiting.
   - `400 slow_down`: you polled too fast. The poll window resets even on a rejected poll, so back off by at least `interval`.
   - `403 access_denied`: the user declined. Stop.
   - `400 expired_token`: the device code is unknown, expired, or already consumed. Start over.
   - `200` with tokens: approved. The device code is consumed atomically.
4. Use and refresh tokens exactly as in the authorization code flow. The device flow never carries a `nonce`, so the `id_token` (with `openid`) has none.

### Discovery

Generic OpenID Connect and OAuth client libraries can configure themselves from the discovery document. A library that honors it will use PKCE `S256`, authenticate a confidential client with HTTP Basic (preferred) or form fields, and decline to attempt the implicit grant or `plain` PKCE.

#### Server metadata

```
GET /.well-known/openid-configuration
GET /.well-known/oauth-authorization-server
```

**Auth:** Public

Served at the domain root, not under `/v1`. Both paths (the OpenID Connect location and the RFC 8414 alias) return the same document.

No parameters.

**Request**

```
GET /.well-known/openid-configuration
```

**Response** `200 OK`, `application/json`.

```json
{
  "issuer": "https://activities.carrierwave.app",
  "authorization_endpoint": "https://activities.carrierwave.app/v1/oauth/authorize",
  "token_endpoint": "https://activities.carrierwave.app/v1/oauth/token",
  "userinfo_endpoint": "https://activities.carrierwave.app/v1/oauth/userinfo",
  "revocation_endpoint": "https://activities.carrierwave.app/v1/oauth/revoke",
  "device_authorization_endpoint": "https://activities.carrierwave.app/v1/oauth/device/code",
  "jwks_uri": "https://activities.carrierwave.app/.well-known/jwks.json",
  "scopes_supported": ["openid", "profile", "email", "sync:read", "sync:write"],
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token", "urn:ietf:params:oauth:grant-type:device_code"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["EdDSA"],
  "token_endpoint_auth_methods_supported": ["client_secret_basic", "client_secret_post", "none"],
  "code_challenge_methods_supported": ["S256"],
  "claims_supported": ["iss", "sub", "aud", "exp", "iat", "auth_time", "nonce", "at_hash",
                       "callsign", "preferred_username", "email", "email_verified"]
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| none | 404 | OAuth is not enabled on this server (the body is not JSON) |

**Notes**

- No cache headers are set on this document. The JWKS document is cacheable for an hour.
- `claims_supported` describes the ID token and UserInfo. Access tokens carry a different claim set (`scope`, `cs`, `jti`, `cid`); see Tokens.

#### Signing keys

```
GET /.well-known/jwks.json
```

**Auth:** Public

Served at the domain root with `Cache-Control: public, max-age=3600`. Use it to verify access tokens and ID tokens.

No parameters.

**Response** `200 OK`, `application/json`.

```json
{"keys":[{"kty":"OKP","crv":"Ed25519","use":"sig","alg":"EdDSA","kid":"v1","x":"…"}]}
```

### Authorization code flow

#### Consent screen

```
GET /v1/oauth/authorize
```

**Auth:** Public (browser page; the user signs in on the page)

Renders the HTML consent page. Every query parameter is optional at the HTTP level so that a malformed link renders a readable error page rather than a bare `400`; the page then enforces the required set itself.

| Param | Type | Required | Description |
|---|---|---|---|
| `client_id` | query string | yes | Registered client id. |
| `redirect_uri` | query string | yes | Must exactly equal one of the client's registered redirect URIs. |
| `response_type` | query string | no (defaults to `code`) | Only `code` is accepted; anything else is reported via redirect at decision time. |
| `scope` | query string | no (defaults to `openid`) | Space-delimited. Unknown scopes are dropped; the rest are clamped to the client's ceiling. |
| `state` | query string | no (strongly recommended) | Opaque CSRF binding; echoed verbatim on the redirect. |
| `code_challenge` | query string | yes | `base64url_nopad(sha256(code_verifier))`. |
| `code_challenge_method` | query string | no (defaults to `S256`) | Must be `S256`; `plain` is rejected at decision time. |
| `nonce` | query string | no | Echoed into the `id_token`. |

**Request**

```
GET /v1/oauth/authorize?client_id=my-logger&redirect_uri=https%3A%2F%2Fmylogger.example%2Foauth%2Fcallback&response_type=code&scope=openid%20sync%3Aread&state=abc123&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256
```

**Response** `200 OK`, `text/html; charset=utf-8`, `Cache-Control: no-store`, with `<meta name="robots" content="noindex, nofollow">`. The page shows the client name, the clamped scope list with the consent copy above, the client's homepage URL if any ("Developer site: …"), a passphrase warning whenever any `sync:*` scope is present, a callsign sign-in box, then Allow and Deny buttons. After the user signs in and decides, the page posts the decision to `POST /v1/oauth/authorize/decision` and sends the browser to the returned `redirectUrl`.

**Errors** All are `400 Bad Request` HTML pages, never a redirect:

| Page heading | HTTP | When |
|---|---|---|
| Invalid authorization request | 400 | `client_id`, `redirect_uri` or `code_challenge` missing |
| Unrecognized application | 400 | Unknown or suspended client, or `redirect_uri` not registered (RFC 6749 section 4.1.2.1: the server must not redirect) |
| Nothing to authorize | 400 | No scopes remain after filtering and clamping |
| none | 404 | OAuth is not enabled on this server |

**Notes**

- The page does not reject a bad `response_type` or `code_challenge_method`. Those are caught by the decision endpoint and reported to your app as `?error=…` on the redirect.
- Sign-in on the page waits for the magic link for up to 15 minutes.

#### Consent decision

```
POST /v1/oauth/authorize/decision
```

**Auth:** Bearer (first-party)

Called by the consent page's own JavaScript with the session the user just created on that page. Your application does not call this endpoint. It is documented so that the redirect you receive is fully explained. Every parameter is re-validated here; nothing from the rendered page is trusted.

**Request** `Content-Type: application/json`. The OAuth fields keep their snake_case wire names; only `approve` is camelCase.

| Param | Type | Required | Description |
|---|---|---|---|
| `client_id` | string | yes | As on the authorize request. |
| `redirect_uri` | string | yes | Must be registered for the client. |
| `response_type` | string | yes | Must be `code`. |
| `scope` | string | no | Space-delimited; filtered and clamped again. Omitted means `openid`. |
| `state` | string | no | Echoed on the redirect. |
| `code_challenge` | string | yes | Non-empty. |
| `code_challenge_method` | string | effectively yes | Must be exactly `S256`; missing or any other value produces an `invalid_request` redirect. |
| `nonce` | string | no | Stored with the code and echoed into the `id_token`. |
| `approve` | boolean | yes | `true` grants, `false` declines. |

```json
{
  "client_id": "my-logger",
  "redirect_uri": "https://mylogger.example/oauth/callback",
  "response_type": "code",
  "scope": "openid sync:read",
  "state": "abc123",
  "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
  "code_challenge_method": "S256",
  "nonce": null,
  "approve": true
}
```

**Response** `200 OK`, `application/json`. The URL is always a registered redirect URI. Query values are percent-encoded with an unreserved-only allowlist; if the redirect URI already has a query string the parameters are appended with `&`.

Approved:

```json
{ "redirectUrl": "https://mylogger.example/oauth/callback?code=Qm3k…48chars…&state=abc123" }
```

Declined (`approve: false`):

```json
{ "redirectUrl": "https://mylogger.example/oauth/callback?error=access_denied&state=abc123" }
```

Malformed but redirectable request (still `200` here; the error goes to your app):

```json
{ "redirectUrl": "https://mylogger.example/oauth/callback?error=invalid_request&state=abc123" }
```

Possible redirect `error` values: `unsupported_response_type` (`response_type` is not `code`), `invalid_request` (empty `code_challenge`, or `code_challenge_method` not `S256`), `invalid_scope` (nothing left after clamping), `access_denied` (the user declined).

On approval the server records the user's consent for your client with the clamped scopes (re-approving revives a previously disconnected app) and issues a single-use authorization code that lives 60 seconds and is bound to the client, the account, the `redirect_uri`, the scopes, the `code_challenge` and the `nonce`. Nothing is persisted on decline.

**Errors** RFC 6749 body, plus the server envelope for bearer rejections:

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` (envelope) | 401 | Missing or invalid bearer |
| `FORBIDDEN` (envelope) | 403 | Bearer is a third-party token |
| `access_denied` | 403 | The session is not backed by an account ("an account-backed session is required") |
| `invalid_client` | 401 | Unknown or suspended client |
| `invalid_request` | 400 | `redirect_uri` not registered; "client lookup failed"; "could not record consent"; "could not issue authorization code" |

**Notes**

- The scopes placed in the grant and the code are the server's clamped set, not the raw request.

### Device flow

#### Device verification page

```
GET /v1/oauth/device
```

**Auth:** Public (browser page; the user signs in on the page)

This is the `verification_uri` returned by `POST /v1/oauth/device/code`.

| Param | Type | Required | Description |
|---|---|---|---|
| `user_code` | query string | no | Pre-fills the code box. Normalized (uppercased, dash inserted, non-alphanumerics stripped) before rendering. |

**Request**

```
GET /v1/oauth/device?user_code=KRWG-ZPTL
```

**Response** `200 OK`, `text/html; charset=utf-8`, `Cache-Control: no-store`, `noindex`. Shows a code input (placeholder `XXXX-XXXX`), the callsign sign-in box, Allow and Deny buttons, and the notice "Only approve a code you started yourself, on a device you are holding." On decision the page posts to `POST /v1/oauth/device/decision` and then shows "<client name> is now connected" or "Request denied. Nothing was shared."

**Errors**

| Code | HTTP | When |
|---|---|---|
| none | 404 | OAuth is not enabled on this server |

**Notes**

- The page always renders `200`, whether or not `user_code` is valid. Validity is checked only at decision time.

#### Start a device authorization

```
POST /v1/oauth/device/code
```

**Auth:** Client credentials (same rules as the token endpoint: a confidential client must present its secret, a public client must not)

**Request** `Content-Type: application/x-www-form-urlencoded`

| Param | Type | Required | Description |
|---|---|---|---|
| `client_id` | string | yes unless sent via HTTP Basic | Client id. |
| `client_secret` | string | confidential clients only | Secret, if not sent via HTTP Basic. |
| `scope` | string | no (defaults to `openid`) | Space-delimited; filtered and clamped to the client's ceiling. |

```
POST /v1/oauth/device/code
Content-Type: application/x-www-form-urlencoded

client_id=my-cli&scope=openid%20sync%3Aread
```

**Response** `200 OK`, `application/json`, `Cache-Control: no-store`.

```json
{
  "device_code": "Xy7…48 alphanumerics…",
  "user_code": "KRWG-ZPTL",
  "verification_uri": "https://activities.carrierwave.app/v1/oauth/device",
  "verification_uri_complete": "https://activities.carrierwave.app/v1/oauth/device?user_code=KRWG-ZPTL",
  "expires_in": 900,
  "interval": 5
}
```

**Errors** RFC 6749 body:

| Code | HTTP | When |
|---|---|---|
| `invalid_client` | 401 | Missing, unknown or suspended client, or wrong secret handling (as on the token endpoint) |
| `unsupported_grant_type` | 400 | The client is not registered for the device flow |
| `invalid_scope` | 400 | No valid scopes after filtering and clamping ("no valid scopes requested") |
| `invalid_request` | 400 | The server could not start the authorization ("could not start device authorization") |

**Notes**

- `user_code` is `XXXX-XXXX` drawn from the 25-character ambiguity-free alphabet `ACDEFGHJKMNPQRTUVWXY34679`. Typed input is normalized (case, dash, spaces), so the user can enter `krwgzptl`.
- `interval` is enforced. A poll inside the window returns `slow_down` and resets the window.
- Scopes are clamped again at decision time, so a ceiling tightened between issue and approval is honored.

#### Device decision

```
POST /v1/oauth/device/decision
```

**Auth:** Bearer (first-party)

Called by the device verification page with the session the user created there. Your application does not call this endpoint.

**Request** `Content-Type: application/json`, camelCase.

| Param | Type | Required | Description |
|---|---|---|---|
| `userCode` | string | yes | The code the user typed; normalized server-side (`krwgzptl` becomes `KRWG-ZPTL`). |
| `approve` | boolean | yes | `true` to approve, `false` to deny. |

```json
{ "userCode": "KRWG-ZPTL", "approve": true }
```

**Response** `200 OK`, `application/json`.

```json
{ "approved": true, "clientName": "My CLI" }
```

On approval the server records the user's consent for the client with the re-clamped scopes and marks the device code approved; the polling client's next token request succeeds. A denial is terminal: the polling client receives `access_denied` and the code cannot be re-approved.

**Errors** RFC 6749 body, plus the server envelope for bearer rejections:

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` (envelope) | 401 | Missing or invalid bearer |
| `FORBIDDEN` (envelope) | 403 | Bearer is a third-party token |
| `access_denied` | 403 | The session is not backed by an account |
| `invalid_grant` | 400 | Unknown or expired user code, or the code was already approved or denied ("this code was already used") |
| `invalid_client` | 401 | The client behind the code is now unknown or suspended |
| `invalid_scope` | 400 | `approve: true` but no grantable scopes remain after re-clamping |
| `invalid_request` | 400 | The server could not record the decision ("could not record consent") |

### Tokens

| Artifact | Lifetime | Format |
|---|---|---|
| Authorization code | 60 seconds, single use | 48-character alphanumeric opaque string |
| Device code | 15 minutes (900 seconds) | 48-character opaque string |
| User code | same 15 minutes | `XXXX-XXXX` from the alphabet `ACDEFGHJKMNPQRTUVWXY34679` |
| Device poll interval | 5 seconds | Polling faster returns `slow_down` |
| Access token | 15 minutes (`expires_in: 900`) | EdDSA (Ed25519) JWT, `aud: "cw-social"` |
| ID token | 60 minutes | EdDSA JWT, `aud: <client_id>` |
| Refresh token | 60-day sliding window, 180-day absolute maximum per family | `cwr_` followed by 64 hex characters. Rotates on every use. Re-presenting the just-rotated token within 60 seconds returns its successor; reuse after that window revokes the whole family. |
| Client secret | until the client is suspended | `cws_` followed by 40 alphanumeric characters, shown once |

Access-token claims: `iss` (`https://activities.carrierwave.app`), `sub` (the account UUID), `aud` (`cw-social`), `scope` (space-delimited), `cs` (primary callsign, informational only), `iat`, `exp`, `jti`, `cid` (your client id). The JWT header carries `alg: EdDSA` and `kid`.

ID-token claims: `iss`, `sub`, `aud` (your `client_id`), `iat`, `exp`, `auth_time`, `nonce` (only when the authorization request carried one; the device flow never sets it), `at_hash` (base64url of the left 16 bytes of SHA-256 of the access token), `callsign`, `preferred_username` (mirrors `callsign`), and `email` with `email_verified: true` (only with the `email` scope and a verified address on file). `auth_time` is the moment of consent.

Verify both token types against `GET /.well-known/jwks.json`.

Revocation: disconnecting an app (`DELETE /v1/oauth/grants/:client_id`), client-side revocation (`POST /v1/oauth/revoke`) and client suspension all stop new tokens immediately, but access tokens already issued stay valid for up to 15 minutes because verification is stateless. Plan for that window.

#### Token endpoint

```
POST /v1/oauth/token
```

**Auth:** Client credentials. A confidential client must present its secret, either as `Authorization: Basic base64(client_id:client_secret)` or as `client_secret` in the form; HTTP Basic wins if both are present. A public client must not send a secret.

**Request** `Content-Type: application/x-www-form-urlencoded`

| Param | Type | Required | Description |
|---|---|---|---|
| `grant_type` | string | yes | `authorization_code`, `refresh_token`, `urn:ietf:params:oauth:grant-type:device_code`, or `device_code`. |
| `client_id` | string | yes unless sent via HTTP Basic | Client id. |
| `client_secret` | string | confidential clients only | Secret, if not sent via HTTP Basic. |
| `code` | string | `authorization_code` | The code from the redirect. |
| `redirect_uri` | string | `authorization_code` | Must equal the `redirect_uri` the code was issued for. |
| `code_verifier` | string | `authorization_code` | 43 to 128 characters; `base64url_nopad(sha256(code_verifier))` must equal the stored challenge. |
| `refresh_token` | string | `refresh_token` | A `cwr_…` token issued to this client. |
| `device_code` | string | device grant | From `POST /v1/oauth/device/code`. |

Authorization-code example:

```
POST /v1/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code&client_id=my-logger&code=Qm3k…&redirect_uri=https%3A%2F%2Fmylogger.example%2Foauth%2Fcallback&code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
```

Refresh example (confidential client, HTTP Basic):

```
POST /v1/oauth/token
Authorization: Basic bXktc2VydmVyOmN3c19…
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token&refresh_token=cwr_9f3a…64hex…
```

Device poll example:

```
POST /v1/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code&client_id=my-cli&device_code=Xy7…48chars…
```

**Response** `200 OK`, `application/json`, `Cache-Control: no-store`, `Pragma: no-cache`.

```json
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJFZERTQSIsImtpZCI6InYxIn0…",
  "token_type": "Bearer",
  "expires_in": 900,
  "refresh_token": "cwr_9f3a…",
  "scope": "openid sync:read",
  "id_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJFZERTQSIsImtpZCI6InYxIn0…"
}
```

`refresh_token` is always present. `id_token` is omitted (not `null`) when `openid` is not in the granted scopes, and is always omitted on `refresh_token` grants.

Per-grant behavior:

- `authorization_code`: consumes the code atomically (unknown, expired and already-used codes are indistinguishable), checks that the code was issued to this client, checks `redirect_uri` equality, verifies PKCE, then issues tokens.
- `refresh_token`: checks that the presented token belongs to this client before rotating it, rotates it (reuse outside the 60-second grace window revokes the family), requires the user's consent to still exist, and issues tokens whose scopes are the intersection of the token's scopes, the current consent and the client ceiling.
- device grant: returns the RFC 8628 section 3.5 errors until the user decides; on approval the device code is consumed and tokens are issued with the scopes recorded at decision time.

**Errors** RFC 6749 body, with `Cache-Control: no-store`:

| Code | HTTP | When |
|---|---|---|
| `invalid_client` | 401 | No `client_id` anywhere; unknown or suspended client; a public client sent a secret; a confidential client omitted its secret or it does not match |
| `unsupported_grant_type` | 400 | Unknown `grant_type`, or the client is not registered for that grant |
| `invalid_request` | 400 | Missing `code`, `code_verifier`, `refresh_token` or `device_code` for the chosen grant |
| `invalid_grant` | 400 | Code invalid, expired or used; code issued to another client; `redirect_uri` mismatch; PKCE failed; refresh token not issued to this client; refresh reuse detected, revoked or unknown; consent revoked ("this authorization has been revoked"); account no longer exists |
| `invalid_scope` | 400 | On refresh, no granted scopes remain for this client |
| `authorization_pending` | 400 | Device grant: the user has not decided yet |
| `slow_down` | 400 | Device grant: polled faster than `interval` |
| `access_denied` | 403 | Device grant: the user declined |
| `expired_token` | 400 | Device grant: unknown, expired, or already-consumed device code |
| `RATE_LIMITED` (envelope) | 429 | Per-IP rate limit |

**Notes**

- `invalid_grant` is one code, but `error_description` differs per cause (listed above), so you can tell a PKCE failure from a redirect mismatch by its text.
- Refresh tokens from Carrier Wave's own apps cannot be used here (`invalid_grant`), and refresh tokens issued here cannot be used at `/v1/auth/token/refresh` (`403 FORBIDDEN`).
- The user's consent is re-checked on every refresh, so a disconnect takes effect at the next refresh, not at the 60-day expiry.

#### Revoke a refresh token

```
POST /v1/oauth/revoke
```

**Auth:** Client credentials (same rules as the token endpoint)

RFC 7009 revocation for refresh tokens.

**Request** `Content-Type: application/x-www-form-urlencoded`

| Param | Type | Required | Description |
|---|---|---|---|
| `token` | string | yes | The refresh token (`cwr_…`) to revoke. Access tokens cannot be revoked here. |
| `client_id` | string | yes unless sent via HTTP Basic | Client id. |
| `client_secret` | string | confidential clients only | Secret, if not sent via HTTP Basic. |

`token_type_hint` is not read.

```
POST /v1/oauth/revoke
Content-Type: application/x-www-form-urlencoded

token=cwr_9f3a…&client_id=my-logger
```

**Response** `200 OK` with an empty body, whether or not the token existed or belonged to the caller (RFC 7009 section 2.2).

**Errors** RFC 6749 body:

| Code | HTTP | When |
|---|---|---|
| `invalid_client` | 401 | Client authentication failed (same cases as the token endpoint) |

**Notes**

- Revocation only happens if the token was issued to the calling client; otherwise the request is silently ignored.
- Revokes the whole rotation family, not just the presented token.
- Does not revoke the user's consent. The user stays connected to your app; you simply have no live refresh token until the user authorizes again. Access tokens already issued remain valid for up to 15 minutes.

### Identity and connected apps

#### UserInfo

```
GET /v1/oauth/userinfo
```

**Auth:** Bearer (third-party, scope `openid`). Carrier Wave's own apps may also call it. This is the only OAuth route reachable with a third-party token.

No parameters.

**Request**

```
GET /v1/oauth/userinfo
Authorization: Bearer eyJ0eXAiOiJKV1Qi…
```

**Response** `200 OK`, `application/json`. `email` and `email_verified` appear only when the token carries the `email` scope and a verified address exists; otherwise both keys are omitted.

```json
{
  "sub": "4c7a4c0e-7e0b-4f3a-9d8f-2a6e1b7a9c21",
  "callsign": "W6JY",
  "preferred_username": "W6JY",
  "email": "w6jy@example.com",
  "email_verified": true
}
```

**Errors** server envelope `{"error":{"code","message"}}`:

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing, malformed, expired or revoked bearer, or the account behind the token no longer exists |
| `FORBIDDEN` | 403 | Third-party token without the `openid` scope |
| `ACCOUNT_REQUIRED` | 403 | The session is not backed by an account |

**Notes**

- `sub` is the account UUID and matches `sub` in the access token and the ID token.
- `callsign` is resolved from the account at request time, not from the token's `cs` claim.
- `email` prefers the address the primary callsign was verified under.
- `profile` is not checked; `callsign` and `preferred_username` are always returned.

#### List connected applications

```
GET /v1/oauth/grants
```

**Auth:** Bearer (first-party)

Lists the apps the signed-in user has connected. Used by Carrier Wave's own apps; third-party tokens are denied.

No parameters.

**Request**

```
GET /v1/oauth/grants
Authorization: Bearer <first-party access token>
```

**Response** `200 OK`, `{ "data": [...] }`, newest first, disconnected apps excluded.

```json
{
  "data": [
    {
      "clientId": "my-logger",
      "clientName": "My Logger",
      "scopes": "openid sync:read sync:write",
      "grantedAt": "2026-10-09T18:22:41.120394Z"
    }
  ]
}
```

**Errors** server envelope:

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer |
| `FORBIDDEN` | 403 | Third-party bearer |
| `ACCOUNT_REQUIRED` | 403 | The session is not backed by an account |
| `INTERNAL_ERROR` | 500 | Server failure |

**Notes**

- `scopes` is the space-delimited string as last consented; re-consent overwrites it.
- `grantedAt` is RFC 3339 in UTC.

#### Disconnect an application

```
DELETE /v1/oauth/grants/:client_id
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `client_id` | path string | yes | The client to disconnect. |

**Request**

```
DELETE /v1/oauth/grants/my-logger
Authorization: Bearer <first-party access token>
```

**Response** `204 No Content`, empty body.

The user's consent is revoked and the client's refresh tokens for this account are removed. The client's next refresh fails with `invalid_grant`; access tokens it already holds remain valid for up to 15 minutes.

**Errors** server envelope:

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer |
| `FORBIDDEN` | 403 | Third-party bearer, or no active connection exists for this account and client (unknown client ids and already-disconnected apps both return `403`, not `404`) |
| `ACCOUNT_REQUIRED` | 403 | The session is not backed by an account |
| `INTERNAL_ERROR` | 500 | Server failure |

**Notes**

- A second `DELETE` for the same client returns `403`.
- Authorizing the app again later restores the connection.

### Operator endpoints

Clients are registered, listed and suspended by Carrier Wave staff; these endpoints are not available to third-party developers.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/admin/oauth/clients` | Register a client |
| `GET` | `/v1/admin/oauth/clients` | List registered clients |
| `DELETE` | `/v1/admin/oauth/clients/:client_id` | Suspend a client |

## Challenges, progress and leaderboards

A **challenge** is an operator-authored goal that participants join and report progress against: work all 50 US states, reach 1000 park contacts, take part in a time-boxed event. The server stores each challenge with a free-form `configuration` object. Your client evaluates QSOs locally against that configuration and sends the server a summary. The server turns the summary into a score, a tier, a percentage and a leaderboard rank.

These endpoints are first-party only. Third-party OAuth tokens receive `403 FORBIDDEN` on every route in this section. The public reads (list and get challenge, leaderboard, badge image) need no token at all.

**Conventions**

- All paths are under `/v1`. Responses are JSON unless noted. Success bodies are wrapped as `{"data": ...}`; errors as `{"error": {"code", "message", "details"?}}`.
- An invalid UUID in a path answers `400 VALIDATION_ERROR`. A missing or malformed JSON body (including a missing `Content-Type: application/json`) answers `400 VALIDATION_ERROR`. A query string that fails to parse (for example `active=maybe` or `limit=abc`) answers a plain-text 400 without the JSON envelope. An unknown `/v1/...` path answers `404 NOT_FOUND`.
- Request bodies are capped at 1 MiB on every route.
- Requests are rate limited per IP at 10 requests per second with a burst of 20. Excess requests receive 429. No rate-limit headers are returned.
- Cross-origin browser requests are accepted from `https://carrierwave.app` and `https://activities.carrierwave.app`.
- Callsigns are stored and compared upper-case.

**Auth levels used below**

- **Public (optional bearer).** A valid first-party bearer, if present, identifies the caller. A missing, invalid, expired or third-party token downgrades the request to anonymous. These routes never answer 401 or 403 for a bad optional token.
- **Bearer (first-party).** A device token (`fd_...`, issued by the join endpoint) or a first-party OAuth access token. Missing or invalid: `401 INVALID_TOKEN`. Third-party OAuth token: `403 FORBIDDEN`.
- **Operator.** An operator token. Any failure answers `401 INVALID_TOKEN`.

**Types and categories**

`type` and `category` are labels used for filtering and display.

| `type` | Meaning |
|---|---|
| `collection` | Work every item in a defined set (WAS, DXCC) |
| `cumulative` | Reach a numeric target (for example 1000 park contacts) |
| `timeBounded` | Fixed start and end window (13 Colonies) |

| `category` | Meaning |
|---|---|
| `award` | Official awards (DXCC, WAS, WAC) |
| `event` | Special events (13 Colonies, Field Day) |
| `club` | Club-specific challenges |
| `personal` | Individual goals |
| `other` | Everything else |

Progress maths use `configuration.goals.type` and `configuration.scoring.method`, not the `type` label. A challenge has ended when `isActive` is `false`. The server does not evaluate `timeConstraints` dates.

**How progress works**

1. The client evaluates QSOs locally against `configuration.qualificationCriteria`, `timeConstraints` and `historicalQsosAllowed`, then sends a summary (`completedGoals`, `currentValue`, `qualifyingQsoCount`, `lastQsoDate`) to `POST /v1/challenges/:id/progress`. The server stores the summary as sent. It does not see QSOs and does not check `completedGoals` against `goals.items`.
2. The server derives three values from the summary and the configuration:
   - **score**, from `scoring.method`. `count` (the default) is the number of `completedGoals`. `percentage` is `floor(completed / number of goals.items * 100)`, or 0 when there are no items. `points` is `currentValue`. Any other value, including `weighted`, behaves as `count`.
   - **currentTier**. The server walks `configuration.tiers` in array order and keeps the last tier whose integer `threshold` is less than or equal to the score. `tiers[].order` is not used, so list tiers in ascending `threshold` order. If `tiers` is absent, or any tier lacks a numeric `threshold`, `currentTier` is `null`.
   - **percentage**, from `goals.type`. `collection`: `completed / number of goals.items * 100`. `cumulative`: `currentValue / goals.targetValue * 100` (`targetValue` defaults to 100). Anything else: `0.0`. The value is not clamped to 100.
3. Each report replaces the previous one for that callsign and challenge and stamps the update time. The update time is the leaderboard tiebreaker: the earlier update wins.
4. **rank** orders all reported progress for the challenge by score descending, then earliest update. Ties share a rank and the following rank is skipped. `scoring.tiebreaker` is stored but not applied.
5. `newBadges` in the progress response is currently always empty. Badges are not awarded by the server.

**Tiers and badges**

Tiers are milestone thresholds inside `configuration.tiers`. Badges are images uploaded by an operator and optionally tagged with a `tierId`; the `tierId` is not validated against the configuration. Badge images are served publicly by id (`GET /v1/badges/:id/image`). There is no public badge listing, and the challenge object does not include a `badges` array; tiers in the configuration may carry a `badgeId`.

**Invite-only challenges**

A challenge requires an invite when `inviteConfig.requiresToken` is `true`. Nothing else in `inviteConfig` is read: `maxParticipants` and `expiresAt` are passed through and not enforced. Invite tokens have the form `inv_` followed by 24 characters from `[0-9a-z]`. Operators mint them with optional `maxUses` and `expiresAt`. A join validates the token first for a precise error, then redeems it atomically, so concurrent joins cannot exceed `maxUses`. A join that fails after redemption releases the use.

**Device token on join**

`POST /v1/challenges/:id/join` is how a device without an account obtains its `fd_` device token.

- If the callsign is new to the server, a participant record is created with a fresh token and the token is returned once in `deviceToken`.
- If the callsign already exists, the caller must already be authenticated as that exact callsign, otherwise the join answers `403 FORBIDDEN`. The token is never rotated or re-disclosed; `deviceToken` is omitted from the response. Recovering a lost token is handled by the magic-link sign-in flow, not this endpoint.
- A caller using a first-party OAuth token always takes the second branch: the participant record already exists for an OAuth caller, so an OAuth caller never receives a `deviceToken`.

**Challenge configuration schema**

Wire shape of `configuration` (camelCase). "Server reads" marks the keys the server inspects; everything else is stored and echoed verbatim for the client to interpret. "Required" marks keys the official clients expect to be present; the server does not validate the configuration.

| Field | Type | Required | Server reads | Description |
|---|---|---|---|---|
| `goals` | object | yes | yes | Goal definition |
| `goals.type` | `"collection"` \| `"cumulative"` | yes | yes (default `collection`) | Drives `percentage` |
| `goals.items` | `Goal[]` | collection | yes, length only | Items to collect. `Goal = {id: string, name: string, category?: string, metadata?: {[k]: string}}` |
| `goals.targetValue` | integer | cumulative | yes (default 100) | Target for cumulative goals |
| `goals.unit` | string | cumulative | no | Display unit, for example `"contacts"` |
| `goals.calculationRule` | string | no | no | Client-side aggregation rule, for example `"count"` |
| `tiers` | `Tier[]` | no | yes | Milestones. `Tier = {id: string, name: string, threshold: integer, order: integer, badgeId?: string}`. Only `id` and `threshold` are read; list tiers in ascending `threshold` order |
| `qualificationCriteria` | object | yes | no | Client-side QSO filter |
| `qualificationCriteria.bands` | `string[]` \| null | no | no | For example `["40m","20m"]`; null means any |
| `qualificationCriteria.modes` | `string[]` \| null | no | no | For example `["CW"]`; null means any |
| `qualificationCriteria.requiredFields` | array | no | no | Fields a QSO must carry; passed through to the client |
| `qualificationCriteria.dateRange` | `{start?: ISO8601, end?: ISO8601}` \| null | no | no | QSO date window |
| `qualificationCriteria.matchRules` | `MatchRule[]` | yes | no | `{qsoField: string, goalField: string, transformation?: "none"\|"uppercase"\|"lowercase", validationRegex?: string}` |
| `scoring` | object | yes | yes | Scoring config |
| `scoring.method` | `"count"` \| `"percentage"` \| `"points"` \| `"weighted"` | yes | yes (default `count`; `weighted` behaves as `count`) | See "How progress works" |
| `scoring.weights` | `{rule: string, weight: number}[]` | no | no | Client-side; not applied by the server |
| `scoring.tiebreaker` | `"earliestCompletion"` \| `"mostRecent"` \| `"alphabetical"` | no | no | Not applied; ranking always uses score descending, then earliest update |
| `scoring.displayFormat` | string | yes | no | For example `"{value}/50 states"` |
| `timeConstraints` | object | no | no | `{type: "calendar"\|"relative", startDate?: ISO8601, endDate?: ISO8601, duration?: string, timezone: string}`; client-side only |
| `historicalQsosAllowed` | boolean | yes | yes (default `true`) | Echoed as `historicalAllowed` in the join response |

`inviteConfig` (separate top-level field, nullable):

| Field | Type | Server reads | Description |
|---|---|---|---|
| `requiresToken` | boolean | yes | When `true`, joining requires a valid `inviteToken` |
| `maxParticipants`, `expiresAt` | integer, ISO8601 | no | Passed through; not enforced |

`hamalertConfig` (separate top-level field, nullable): `{enabled: boolean, alertType: string, spotSources: string[], autoManage: boolean}`. Passed through; the server does not read it.

### Browsing challenges

#### List challenges

```
GET /v1/challenges
```

**Auth:** Public (optional bearer; a bearer changes nothing in the response)

| Param | Type | Required | Description |
|---|---|---|---|
| `category` | string (query) | no | Exact match on `category` (`award`, `event`, `club`, `personal`, `other`). Not validated; an unknown value returns an empty list |
| `type` | string (query) | no | Exact match on `type` (`collection`, `cumulative`, `timeBounded`) |
| `active` | bool (query) | no | Filter on `isActive`. Omit for both |
| `limit` | int (query) | no | Default 50, maximum 100 (larger values are reduced to 100) |
| `offset` | int (query) | no | Default 0 |

**Request:** no body.

**Response:** `200 OK`

```json
{
  "data": {
    "challenges": [
      {
        "id": "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d",
        "name": "ARRL WAS 250",
        "description": "Work all 50 US states during 2026 ...",
        "category": "award",
        "type": "collection",
        "participantCount": 1234,
        "isActive": true
      }
    ],
    "total": 45,
    "limit": 50,
    "offset": 0
  }
}
```

`participantCount` counts participants with status `active`. Results are ordered newest first. `total` is the number of challenges matching the filters, ignoring paging. `limit` echoes the applied value.

**Errors**

| Code | HTTP | When |
|---|---|---|
| (plain text) | 400 | Query string fails to parse (no JSON envelope) |
| `INTERNAL_ERROR` | 500 | Server failure |

**Notes:** List items do not include `configuration`, `version`, `author` or timestamps. Fetch the challenge by id for those.

#### Get challenge

```
GET /v1/challenges/:id
```

**Auth:** Public (optional bearer; no effect on the response)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | UUID (path) | yes | Challenge id |

**Response:** `200 OK`

Response headers:

| Header | Value |
|---|---|
| `X-Challenge-Version` | Integer `version` |
| `ETag` | `"<version>:<updatedAt unix seconds>"`, quotes included. `If-None-Match` is not evaluated, so conditional requests always answer 200 |

```json
{
  "data": {
    "id": "b2c3d4e5-f6a7-5b6c-9d0e-1f2a3b4c5d6e",
    "version": 1,
    "name": "DXCC",
    "description": "Work 100 or more DXCC entities ...",
    "author": "ARRL",
    "category": "award",
    "type": "collection",
    "configuration": {
      "goals": {
        "type": "collection",
        "items": [
          { "id": "1", "name": "Canada", "category": "entity" }
        ]
      },
      "tiers": [
        { "id": "tier-50",  "name": "50 Entities", "threshold": 50,  "order": 1 },
        { "id": "tier-100", "name": "DXCC",        "threshold": 100, "order": 2 }
      ],
      "qualificationCriteria": {
        "bands": null,
        "modes": null,
        "requiredFields": [],
        "dateRange": null,
        "matchRules": [
          { "qsoField": "dxccEntity", "goalField": "id", "transformation": "none" }
        ]
      },
      "historicalQsosAllowed": true,
      "scoring": {
        "method": "count",
        "tiebreaker": "earliestCompletion",
        "displayFormat": "{value} entities"
      }
    },
    "inviteConfig": null,
    "hamalertConfig": null,
    "isActive": true,
    "createdAt": "2025-01-01T00:00:00Z",
    "updatedAt": "2025-01-01T00:00:00Z"
  }
}
```

Fields: `id`, `version`, `name`, `description`, `author` (nullable), `category`, `type`, `configuration`, `inviteConfig` (nullable), `hamalertConfig` (nullable), `isActive`, `createdAt`, `updatedAt`. There is no `badges` array.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `id` is not a UUID |
| `CHALLENGE_NOT_FOUND` | 404 | No such challenge; `details.challengeId` |

**Notes:** `inviteConfig` is returned verbatim, so a client can check `requiresToken` before attempting to join. Inactive challenges are still readable. `version` increments on every operator update, and `ETag` and `X-Challenge-Version` change with it.

### Participation and progress

#### Join a challenge

```
POST /v1/challenges/:id/join
```

**Auth:** Public (optional bearer). A bearer is required when the callsign is already known to the server: the request must then be authenticated as that same callsign or it answers `403 FORBIDDEN`. For a brand-new callsign no bearer is needed and this call issues the device token.

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | UUID (path) | yes | Challenge id |

**Request** (camelCase):

```json
{
  "callsign": "W1ABC",
  "deviceName": "iPhone",
  "inviteToken": "inv_k3j5h2g8f7d6s5a4p0o9i8u7"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `callsign` | string | yes | Upper-cased before storage |
| `deviceName` | string | no | Stored only when this call creates the participant |
| `inviteToken` | string | only when `inviteConfig.requiresToken` is `true` | Trimmed; an empty string is treated as absent. Not validated on challenges that do not require a token |

Processing order:

1. Challenge lookup; unknown id answers `404`.
2. `isActive` is `false`: `400 CHALLENGE_ENDED`. Only the flag is checked; `timeConstraints` dates are not evaluated.
3. If `requiresToken`: the token must be non-empty, exist, and belong to this challenge, otherwise `403 INVITE_REQUIRED`. Expired: `403 INVITE_EXPIRED`. `useCount >= maxUses`: `403 INVITE_EXHAUSTED`.
4. The participant record is found or created.
5. Existing participant and caller not authenticated as that callsign: `403 FORBIDDEN`.
6. Atomic invite redemption. If the token expired or ran out between steps 3 and 6, or the join lost a race: `403 INVITE_EXHAUSTED`.
7. Participation is recorded. If a participation already exists for this challenge and callsign: `409 ALREADY_JOINED`, and the invite use is released.

**Response:** `201 Created`

```json
{
  "data": {
    "participationId": "0f9c1c2e-6c1a-4d8e-9a7b-3c2d1e0f9a8b",
    "deviceToken": "fd_AbCdEfGhIjKlMnOpQrStUvWxYz012345",
    "joinedAt": "2025-01-15T12:00:00Z",
    "status": "active",
    "historicalAllowed": true
  }
}
```

`deviceToken` is present only when this call created the participant; for an existing callsign it is omitted entirely. `status` is always `"active"` on a fresh join. `historicalAllowed` echoes `configuration.historicalQsosAllowed` (default `true`).

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Bad UUID, or body missing, not JSON, or missing `callsign` |
| `CHALLENGE_ENDED` | 400 | `isActive` is `false` |
| `CHALLENGE_NOT_FOUND` | 404 | Unknown challenge |
| `INVITE_REQUIRED` | 403 | Gated challenge and token missing, blank, unknown, or issued for a different challenge |
| `INVITE_EXPIRED` | 403 | Token `expiresAt` is in the past |
| `INVITE_EXHAUSTED` | 403 | `useCount >= maxUses` at validation time, or the atomic redemption did not succeed |
| `FORBIDDEN` | 403 | Callsign already registered and the caller is not authenticated as that callsign (third-party OAuth tokens count as anonymous here) |
| `ALREADY_JOINED` | 409 | A participation already exists for this challenge and callsign, including one with status `left`. Leaving a challenge is permanent; re-joining answers 409 |

**Notes**

- The device token is shown once; the app must store it.
- Gated joins increment the invite's `useCount`.
- Joining does not create a progress record. The participant is absent from the leaderboard until the first progress report.

#### Report progress

```
POST /v1/challenges/:id/progress
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | UUID (path) | yes | Challenge id |

**Request:**

```json
{
  "completedGoals": ["CA", "NY", "TX"],
  "currentValue": 47,
  "qualifyingQsoCount": 52,
  "lastQsoDate": "2025-01-15T18:30:00Z"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `completedGoals` | string[] | yes | Goal ids the client considers complete. Stored as sent; not checked against `goals.items` and not de-duplicated |
| `currentValue` | int32 | yes | Current numeric value for cumulative goals, or the value to score under `points` |
| `qualifyingQsoCount` | int32 | yes | Accepted but not stored |
| `lastQsoDate` | ISO8601 datetime | no | Stored; not returned by any endpoint in this section |

**Response:** `200 OK` (not 201)

```json
{
  "data": {
    "accepted": true,
    "serverProgress": {
      "completedGoals": ["CA", "NY", "TX"],
      "currentValue": 47,
      "percentage": 6.0,
      "score": 3,
      "rank": 23,
      "currentTier": null
    },
    "newBadges": []
  }
}
```

- `accepted` is always `true`.
- `serverProgress.completedGoals` and `currentValue` echo the request.
- `percentage` (floating point, not capped at 100), `score` and `currentTier` are computed as described in "How progress works". `rank` is the rank after this report is applied.
- `newBadges` is an array of badge ids and is currently always empty.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer |
| `FORBIDDEN` | 403 | Third-party OAuth token |
| `VALIDATION_ERROR` | 400 | Bad UUID; body missing or invalid; missing `completedGoals`, `currentValue` or `qualifyingQsoCount` |
| `CHALLENGE_NOT_FOUND` | 404 | Unknown challenge |
| `NOT_PARTICIPATING` | 403 | The caller has never joined this challenge. A participation of any status satisfies the check, so a callsign that has left can still report and reappears on the leaderboard |

**Notes**

- Each report fully replaces the previous one and refreshes the update time, which moves the reporter later in tie ordering.
- Progress is accepted for inactive challenges; `isActive` is not checked here.

#### Get progress

```
GET /v1/challenges/:id/progress
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | UUID (path) | yes | Challenge id |

**Response:** `200 OK`

```json
{
  "data": {
    "completedGoals": ["CA", "NY", "TX"],
    "currentValue": 47,
    "percentage": 6.0,
    "score": 3,
    "rank": 23,
    "currentTier": null
  }
}
```

`score` and `currentTier` are the stored values from the last report. `percentage` is recomputed from the stored report and the current configuration. `rank` is live.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer |
| `FORBIDDEN` | 403 | Third-party OAuth token |
| `VALIDATION_ERROR` | 400 | Bad UUID |
| `CHALLENGE_NOT_FOUND` | 404 | Unknown challenge |
| `NOT_PARTICIPATING` | 403 | The caller has no stored progress for this challenge. A participant who has joined but never reported gets this code too |

#### Leave a challenge

```
DELETE /v1/challenges/:id/leave
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | UUID (path) | yes | Challenge id |

**Request:** no body.

**Response:** `204 No Content`, empty body.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer |
| `FORBIDDEN` | 403 | Third-party OAuth token |
| `VALIDATION_ERROR` | 400 | Bad UUID |
| `NOT_PARTICIPATING` | 403 | No participation with status `active` for the caller on this challenge. Also returned for an unknown challenge id; this endpoint never answers 404 |

**Notes**

- Leaving marks the participation `left` and deletes the caller's progress, in one transaction. A second leave call answers 403 and changes nothing.
- After leaving, the callsign no longer appears in `GET /v1/participants/:callsign/challenges` (active only) or on the leaderboard (progress deleted).
- Leaving a challenge is permanent. A later `POST /v1/challenges/:id/join` for the same callsign answers `409 ALREADY_JOINED`.
- Invite uses are not refunded.

#### Get participation status

```
GET /v1/challenges/:id/participants/:callsign
```

**Auth:** Bearer (first-party); the authenticated callsign must equal `:callsign` (case-insensitive)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | UUID (path) | yes | Challenge id |
| `callsign` | string (path) | yes | Must match the caller's own callsign |

**Response:** `200 OK`

```json
{
  "data": {
    "participationId": "0f9c1c2e-6c1a-4d8e-9a7b-3c2d1e0f9a8b",
    "challengeId": "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d",
    "joinedAt": "2025-01-15T12:00:00Z",
    "status": "active"
  }
}
```

`status` is one of `active`, `left`, `completed`. The server currently writes only `active` and `left`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer |
| `FORBIDDEN` | 403 | Third-party token, or `:callsign` is not the caller's callsign (checked before any lookup) |
| `VALIDATION_ERROR` | 400 | Bad UUID |
| `NOT_PARTICIPATING` | 403 | No participation at all. A `left` participation is returned normally with `status: "left"`. No 404 for an unknown challenge |

#### List a callsign's challenges

```
GET /v1/participants/:callsign/challenges
```

**Auth:** Bearer (first-party); `:callsign` must be the caller's own

| Param | Type | Required | Description |
|---|---|---|---|
| `callsign` | string (path) | yes | Must match the caller's callsign (case-insensitive) |

**Response:** `200 OK`. Note that `data` is a bare array.

```json
{
  "data": [
    {
      "participationId": "0f9c1c2e-6c1a-4d8e-9a7b-3c2d1e0f9a8b",
      "challengeId": "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d",
      "challengeName": "ARRL WAS 250",
      "joinedAt": "2025-01-15T12:00:00Z",
      "status": "active"
    }
  ]
}
```

Only participations with status `active` are returned, most recent join first. Inactive challenges are still listed.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer |
| `FORBIDDEN` | 403 | Third-party token, or callsign mismatch |

### Leaderboards

#### Get leaderboard

```
GET /v1/challenges/:id/leaderboard
```

**Auth:** Public (optional bearer; the bearer is ignored. `userPosition` comes from the `around` parameter, never from the caller's identity)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | UUID (path) | yes | Challenge id |
| `limit` | int (query) | no | Default 100, maximum 100. Ignored when `around` is set |
| `offset` | int (query) | no | Default 0. Ignored when `around` is set |
| `around` | string (query) | no | Callsign to centre on. Switches to the "around me" window |

**Response:** `200 OK`

```json
{
  "data": {
    "leaderboard": [
      {
        "rank": 1,
        "callsign": "K1ABC",
        "score": 50,
        "currentTier": "tier-50",
        "completedAt": "2025-01-10T00:00:00Z"
      },
      {
        "rank": 2,
        "callsign": "W1ABC",
        "score": 47,
        "currentTier": "tier-40",
        "completedAt": "2025-01-12T08:15:00Z"
      }
    ],
    "total": 1234,
    "userPosition": null,
    "lastUpdated": "2025-01-15T19:00:00Z"
  }
}
```

Entry fields: `rank` (integer), `callsign`, `score`, `currentTier` (nullable), `completedAt` (nullable). `userPosition` is either `null` or an object of the same shape.

**Ranking**

- Only participants who have reported progress at least once appear. `total` is the number of such participants, not the participant count.
- `rank` orders by score descending, then earliest update. Ties share a rank and the following rank is skipped (standard rank, not dense rank). `scoring.tiebreaker` is not applied.
- `completedAt` is not a completion timestamp. It is the time of the participant's latest report when `score > 0`, otherwise `null`. It moves on every report.
- `lastUpdated` is the server time when the response was built, not a data freshness marker.

**`around` behaviour**

- `around` returns a fixed window of five ranks either side of the named callsign (`rank` between target minus 5 and target plus 5, ordered by rank) and ignores `limit` and `offset`. With ties the window can hold more or fewer than 11 rows.
- If the callsign has no reported progress, `leaderboard` is `[]` and `userPosition` is `null`; `total` is still the full count.
- The callsign is upper-cased for the lookup, but `userPosition` is the entry whose `callsign` equals the `around` value exactly as supplied. Pass the callsign in upper case: `around=w1abc` returns the window but `userPosition: null`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `id` is not a UUID |
| (plain text) | 400 | Unparsable `limit` or `offset` |
| `CHALLENGE_NOT_FOUND` | 404 | Unknown challenge |

### Badges

#### Get badge image

```
GET /v1/badges/:id/image
```

**Auth:** Public (optional bearer; ignored)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | UUID (path) | yes | Badge id |

**Response:** `200 OK`, body is the raw image bytes.

| Header | Value |
|---|---|
| `Content-Type` | As uploaded: `image/png`, `image/jpeg` or `image/svg+xml` |
| `Cache-Control` | `public, max-age=86400` |

No `ETag` or `Last-Modified` is set.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `id` is not a UUID |
| `BADGE_NOT_FOUND` | 404 | Unknown badge; `details.badgeId` |
| `INTERNAL_ERROR` | 500 | Server failure |

**Notes:** Badges are deleted with their challenge, after which cached copies may outlive the badge for up to a day. Badge ids and the relative `imageUrl` (`/v1/badges/:id/image`) are issued to operators at upload time; prefix `imageUrl` with the API origin.

### Operator endpoints

All operator endpoints require an operator token in `Authorization: Bearer ...`; any failure answers `401 INVALID_TOKEN`. Request and response bodies are not documented here.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/admin/challenges` | Create a challenge. Answers 201 with the full challenge object at `version` 1. `isActive` defaults to `true`. `configuration` is stored without schema validation |
| `PUT` | `/v1/admin/challenges/:id` | Replace a challenge (full replacement, not a patch). Increments `version` and refreshes `updatedAt`, so the public `ETag` and `X-Challenge-Version` change. Stored scores and tiers are not recalculated until each participant reports again |
| `DELETE` | `/v1/admin/challenges/:id` | Delete a challenge and its participations, progress, badges and invites. Answers 204 |
| `POST` | `/v1/admin/challenges/:id/badges` | Upload a badge as `multipart/form-data` with parts `name` (required), `tierId` (optional, not validated against the configuration) and `image` (required; part `Content-Type` must be `image/png`, `image/jpeg` or `image/svg+xml`; at most 1,048,576 bytes). The whole request body is capped at 1 MiB, so the effective image maximum is a little under 1 MiB. Answers 201 with `id`, `name`, `tierId`, a relative `imageUrl`, `contentType` and `createdAt` |
| `GET` | `/v1/admin/challenges/:id/badges` | List a challenge's badges, oldest first, without image bytes. This is the only badge listing |
| `DELETE` | `/v1/admin/badges/:id` | Delete a badge. Answers 204. Public caches may keep serving the image for up to a day |
| `POST` | `/v1/admin/challenges/:id/invites` | Mint an invite token with optional `maxUses` (null means unlimited) and `expiresAt` (null means never). A JSON body is required; send `{}` for an unlimited, non-expiring token. Answers 201 with `token`, a relative `url`, `maxUses`, `useCount`, `expiresAt` and `createdAt`. Minting an invite does not gate the challenge; set `inviteConfig.requiresToken` for that |
| `GET` | `/v1/admin/challenges/:id/invites` | List a challenge's invites, newest first. Expired and exhausted tokens are included |
| `DELETE` | `/v1/admin/invites/:token` | Revoke an invite. Answers 204; unknown token answers `404 INVITE_NOT_FOUND`. Participants who already joined with the token are unaffected |

## Programs

A program is an entry in the on-the-air activity registry: Parks on the Air (POTA), Summits on the Air (SOTA), WWFF, IOTA, LOTA, Agents on Air, and the catch-all `casual`. Clients load the registry at startup and use it to drive reference entry, reference validation, feature switches, and ADIF export. The registry is read-only for third parties.

Every success body in this section is wrapped as `{"data": ...}`. Every error body is `{"error": {"code": "...", "message": "...", "details": {...}}}`, where `details` is optional. Field names are camelCase. Malformed JSON bodies and bad path parameters return `400 VALIDATION_ERROR`. Request bodies are capped at 1 MiB.

### Program record

| Group | Fields | Meaning |
|---|---|---|
| Identity | `slug`, `name`, `shortName`, `icon`, `iconUrl`, `website`, `serverBaseUrl` | How the program is named and linked. `slug` is the stable key (for example `pota`). `icon` is an SF Symbol name. `serverBaseUrl`, when present, is the program's own API base for spot and lookup features. |
| Reference format | `referenceLabel`, `referenceFormat`, `referenceExample`, `multiRefAllowed`, `activationThreshold`, `supportsRove` | How references such as `K-0001` or `W7W/LC-001` are labelled and validated. `referenceFormat` is a regular expression or `null`. `activationThreshold` is the number of QSOs needed for a valid activation (10 for POTA). `multiRefAllowed` and `supportsRove` say whether an operator can log several references at once or rove between them. |
| Capabilities | `capabilities` (string array) | Feature flags the client switches on. Known values: `referenceField`, `adifUpload`, `browseSpots`, `selfSpot`, `hunter`, `locationLookup`, `progressTracking`, `dataEntry`, `dataVerification`. The vocabulary is open; ignore values you do not recognise. |
| ADIF mapping | `adifFields` object: `mySig`, `mySigInfo`, `sigField`, `sigInfoField` | Which ADIF tags carry the operator's and the worked station's reference. For POTA: `MY_SIG=POTA`, `MY_SIG_INFO`, `SIG`, `SIG_INFO`. |
| Data entry | `dataEntry` object: `label`, `placeholder`, `format` | An extra free-text field shown when the `dataEntry` capability is set (for example the Agents on Air "Passkey"). |
| Status | `isActive` | Always `true` on public endpoints, which return only active programs. |

Field presence rules:

- `website`, `referenceFormat`, `referenceExample`, and `activationThreshold` are always present and may be `null`.
- `iconUrl`, `serverBaseUrl`, `adifFields`, and `dataEntry` are omitted when unset.
- `isActive` is always present.

### Versioning and caching

The list endpoint returns a numeric `version`: the Unix epoch seconds of the most recent update among active programs, or `0` when there are none. Any change to an active program moves it. No `ETag` or `Cache-Control` headers are emitted and conditional requests are not supported. Cache the list, store `version`, and re-fetch when it differs.

#### List programs

```
GET /v1/programs
```

**Auth:** Public (optional bearer; the response is identical with or without a token).

No parameters.

**Response:** `200 OK`

```json
{
  "data": {
    "programs": [
      {
        "slug": "pota",
        "name": "Parks on the Air",
        "shortName": "POTA",
        "icon": "tree",
        "website": "https://pota.app",
        "referenceLabel": "Park Reference",
        "referenceFormat": "^[A-Z]+-[0-9]{4,5}$",
        "referenceExample": "K-0001",
        "multiRefAllowed": true,
        "activationThreshold": 10,
        "supportsRove": true,
        "capabilities": ["referenceField", "adifUpload", "browseSpots", "selfSpot", "hunter", "locationLookup", "progressTracking"],
        "adifFields": {
          "mySig": "POTA",
          "mySigInfo": "MY_POTA_REF",
          "sigField": "SIG",
          "sigInfoField": "SIG_INFO"
        },
        "isActive": true
      },
      {
        "slug": "aoa",
        "name": "Agents on Air",
        "shortName": "AoA",
        "icon": "antenna.radiowaves.left.and.right",
        "website": null,
        "referenceLabel": "Mission Reference",
        "referenceFormat": "^M-[a-z0-9]{4}$",
        "referenceExample": "M-a01f",
        "multiRefAllowed": false,
        "activationThreshold": null,
        "supportsRove": false,
        "capabilities": ["referenceField", "hunter", "dataEntry", "dataVerification"],
        "dataEntry": {
          "label": "Passkey",
          "placeholder": "Enter code from other station",
          "format": null
        },
        "isActive": true
      }
    ],
    "version": 1737900000
  }
}
```

**Errors:**

| Code | HTTP | When |
|---|---|---|
| `INTERNAL_ERROR` | 500 | Server-side failure |

**Notes:**

- Only active programs are returned, in display order.
- No `ETag` is emitted; poll `version` instead.

#### Get a program

```
GET /v1/programs/:slug
```

**Auth:** Public (optional bearer; the response is identical with or without a token).

| Param | Type | Required | Description |
|---|---|---|---|
| `slug` | string (path) | yes | Program slug, for example `pota`. Case-sensitive exact match. |

**Response:** `200 OK` with `{"data": <Program>}`, the same shape as a list item above.

**Errors:**

| Code | HTTP | When |
|---|---|---|
| `PROGRAM_NOT_FOUND` | 404 | No program with that slug, or the program is inactive. `details`: `{"slug": "<slug>"}` |
| `INTERNAL_ERROR` | 500 | Server-side failure |

**Notes:** Inactive programs are not distinguishable from missing ones on this endpoint.

### Operator endpoints

These require an operator token and are not available to third-party integrations.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/admin/programs` | List all programs, including inactive ones |
| `GET` | `/v1/admin/programs/:slug` | Get any program, including inactive ones |
| `POST` | `/v1/admin/programs` | Create a program |
| `PUT` | `/v1/admin/programs/:slug` | Partially update a program (including `isActive`) |
| `DELETE` | `/v1/admin/programs/:slug` | Delete a program |

## Achievements

Achievements are shown to users as "Badges". There are two kinds of record:

- **Catalog entries** describe each badge: `id` (kebab-case string), `name`, `description`, `category` (`creator`, `community`, `activity`, `ecosystem`, `streak`, `quirky`), `tier` (`bronze`, `silver`, `gold`, or `null`), `iconName` (SF Symbol), `accentHex`, `awardMethod`, `secret`, `sortOrder`. The catalog is maintained by Carrier Wave; there is no API to add entries.
- **Awards** record that a callsign holds a badge: `id` (UUID), `callsign`, `achievementId`, `awardedAt`, `awardedBy`, `evidence` (arbitrary JSON or `null`). A callsign holds each badge at most once.

### Award methods

`awardMethod` on a catalog entry says who may grant the badge.

| `awardMethod` | Granted by | Examples |
|---|---|---|
| `manual` | Carrier Wave operators | `creator`, `beta-tester`, `founding-supporter`, `contributor`, `bug-hunter` |
| `signal` | A first-party client reporting a signal for the signed-in user | `sweep-user`, `watch-operator`, `home-screen`, `pebble-pioneer`, `swl`, `rbn-spotter` |
| `auto` | The server, from the user's logged activity | everything else |

**Signals.** A signal is a one-line claim from a signed-in first-party client, such as "this user paired with Sweep". The server accepts a signal only for catalog entries whose `awardMethod` is `signal`, so a client cannot claim manual or auto badges. The award is written with `awardedBy` set to `signal`. After a signal the server also checks for the `cross-platform` badge: it is granted when the callsign holds `sweep-user` and at least one of `watch-operator`, `home-screen`, or `pebble-pioneer`, both awarded within the last 7 days. That award has `awardedBy` set to `system` and `evidence` of `{"windowDays": 7}`.

**Auto badges.** Some auto badges are evaluated as soon as an activity is recorded: `first-qso`, `first-cw`, `first-ssb`, `first-ft8`, and `mode-polyglot` (five or more distinct modes), plus a small number of secret badges. Others are cumulative and are evaluated by a background evaluator that runs periodically over recently active callsigns: `qso-100`, `qso-1000`, `qso-10000` (total QSOs), `dxcc-10`, `dxcc-100` (distinct DXCC entities), `all-hf` (distinct bands), `streak-7`, `streak-30`, `streak-365` (longest daily streak), and `anniversary` (account at least one year old). Auto awards are idempotent; re-evaluation never duplicates an award.

### Refreshing on the client

- Fetch the catalog once and cache it. Entries change rarely.
- Fetch a callsign's awards when showing a profile, and again after the user logs activity or after sending a signal. Auto awards can appear minutes after the activity that earned them.
- Send each signal once. Re-sending is harmless but unnecessary.
- No `ETag` or `Cache-Control` headers are emitted on these endpoints.

#### List the achievement catalog

```
GET /v1/achievements
```

**Auth:** Public (optional bearer; the response is identical with or without a token).

No parameters.

**Response:** `200 OK`

```json
{
  "data": {
    "achievements": [
      {
        "id": "first-qso",
        "name": "First QSO",
        "description": "Logged your first contact",
        "category": "activity",
        "tier": null,
        "iconName": "antenna.radiowaves.left.and.right",
        "accentHex": "#4CAF50",
        "awardMethod": "auto",
        "secret": false,
        "sortOrder": 100
      },
      {
        "id": "qso-100",
        "name": "Centurion",
        "description": "Logged 100 contacts",
        "category": "activity",
        "tier": "bronze",
        "iconName": "antenna.radiowaves.left.and.right",
        "accentHex": "#CD7F32",
        "awardMethod": "auto",
        "secret": false,
        "sortOrder": 110
      }
    ]
  }
}
```

**Errors:**

| Code | HTTP | When |
|---|---|---|
| `INTERNAL_ERROR` | 500 | Server-side failure |

**Notes:**

- Secret achievements (`secret: true`) are excluded. Every entry returned has `secret: false`.
- Ordered by `sortOrder` ascending, then `id` ascending.

#### List a callsign's achievements

```
GET /v1/users/:callsign/achievements
```

**Auth:** Public (optional bearer; the response is identical with or without a token). Anyone can read anyone's awards.

| Param | Type | Required | Description |
|---|---|---|---|
| `callsign` | string (path) | yes | Upper-cased by the server before lookup. |

**Response:** `200 OK`

```json
{
  "data": {
    "callsign": "W6JY",
    "awards": [
      {
        "id": "3f2a9c1e-5b7d-4e8f-9a0b-1c2d3e4f5a6b",
        "callsign": "W6JY",
        "achievementId": "creator",
        "awardedAt": "2026-03-01T18:22:10.512345Z",
        "awardedBy": "system",
        "evidence": null
      }
    ]
  }
}
```

**Errors:**

| Code | HTTP | When |
|---|---|---|
| `INTERNAL_ERROR` | 500 | Server-side failure |

**Notes:**

- An unknown callsign returns `200` with an empty `awards` array. There is no 404.
- Awards of secret achievements are included even though the catalog omits them. A client that cannot match an `achievementId` to a catalog entry should skip it or render it generically.
- Ordered by `awardedAt` descending.
- `evidence` is whatever the awarding path recorded, for example `{"from": "sessionCompleted"}`, `{"total": 1234}`, or `{"windowDays": 7}`, or `null`.

#### Report an achievement signal

```
POST /v1/users/me/achievements/signal
```

**Auth:** Bearer (first-party). The award is always written for the token's own callsign; the body cannot name another user. Third-party OAuth tokens are refused.

No path or query parameters.

**Request:**

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | Catalog id. Its `awardMethod` must be `signal`. |
| `evidence` | any JSON | no | Stored verbatim on the award. |

```json
{ "id": "watch-operator" }
```

**Response:** `201 Created` with the award.

```json
{
  "data": {
    "id": "9d1b6e42-0c3a-4f5e-8b7d-2a1c3e5f7a9b",
    "callsign": "N0CALL",
    "achievementId": "watch-operator",
    "awardedAt": "2026-10-10T17:03:41.120934Z",
    "awardedBy": "signal",
    "evidence": null
  }
}
```

**Errors:**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing, invalid, or expired bearer token |
| `FORBIDDEN` | 403 | Third-party OAuth token |
| `VALIDATION_ERROR` | 400 | Unknown `id` (`"Unknown achievement: <id>"`), an `id` whose `awardMethod` is not `signal` (`"Achievement '<id>' is not signal-awardable"`), or malformed JSON |
| `INTERNAL_ERROR` | 500 | Server-side failure |

**Notes:**

- Idempotent. Re-sending the same signal returns `201` again with the original `awardedAt`. `awardedBy` is set to `signal` on every call. `evidence` is replaced only when the new request supplies a non-null value.
- Any `cross-platform` award triggered by the signal is not included in this response. Fetch the callsign's awards to see it.
- Accepted ids: `sweep-user`, `watch-operator`, `home-screen`, `pebble-pioneer`, `swl`, `rbn-spotter`.

### Operator endpoints

These require an operator token and are not available to third-party integrations.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/admin/achievements/:id/award` | Award a badge to one callsign |
| `DELETE` | `/v1/admin/achievements/:id/award/:callsign` | Revoke a badge from one callsign |
| `POST` | `/v1/admin/achievements/:id/award/batch` | Award a badge to many callsigns |
| `POST` | `/v1/admin/achievements/backfill` | Re-run the cumulative auto evaluators for every callsign |

## Contest definitions

A contest definition is a declarative JSON document describing one amateur-radio contest: schedule, exchange, dupe rules, scoring phases, operating constraints, Cabrillo header, and entry categories. The current format version is `0.3.0`. Definitions are published by Carrier Wave and are read-only for third parties.

**File vs. contest.** A *file* has a `version` and a `contests` array. Each *contest* in the file is stored and served individually, keyed by its `id`. The file-level `version` is served as `formatVersion` on each contest.

**Normalization.** The served `definition` is a normalized form of what was uploaded: absent optional fields are dropped, `experimental: false` and an empty `overlay_categories` are omitted, `required` is always present on exchange fields, fields with defaults (such as `zero_point_qsos_count_for_mults` and a rule's `conditions`) are always present, and unknown keys are discarded. The exception is `data_dependencies`, where unknown dependency types are kept.

**Case conventions.** The envelope and metadata fields (`id`, `name`, `shortName`, `sponsorName`, `sponsorUrl`, `formatVersion`, `isActive`, `createdAt`, `updatedAt`) are camelCase. The `definition` document itself is snake_case, because it is the stand-alone contest file format.

### Versioning

`version` is a semver string, currently `"0.3.0"`. Loaders should reject a file whose major version is higher than they support. Each contest carries `updatedAt`, which changes whenever its definition is republished. No `ETag` or `Cache-Control` headers are emitted; compare `updatedAt` per contest instead.

### Validation

Definitions are validated in two passes before they are published.

1. **Structural.** Required keys, types, and enum vocabularies (modes, bands, `schedule.type`, phase `type`, `op`, `scope`, and so on). A structural failure is a `400 VALIDATION_ERROR` whose `message` is the parser's text. It does not carry a problems list.
2. **Semantic.** Every rule runs and the full list of problems is returned. Errors block publication; warnings do not.

A validation problem has this shape:

```json
{
  "severity": "error",
  "contestId": "cwops-cwt",
  "path": "scoring.phases[2].operation.inputs[1].phase",
  "message": "..."
}
```

`severity` is `error` or `warning`. `contestId` is `null` only for file-level problems. `path` is a JSON path within the contest object.

Warnings are emitted for: `autofill` on a received exchange field; a `per_qso` phase whose last rule still has conditions; an unknown continent literal; and a scoring field with no `data_dependencies` entry that `provides` it. Everything else is an error, including duplicate contest, category, or phase ids, unknown modes, bands, or days, malformed `HH:MM` times, empty sessions, categories, or phases, forward phase references, unknown condition fields or dupe keys, and serial-number misuse.

A published definition that reaches you through the public endpoints has passed both passes.

### Refreshing on the client

Call the list endpoint to get summaries, then fetch each contest's full definition by id. Treat `definition` as an opaque document and keep it with its `updatedAt`. The first-party apps refresh at most once every 24 hours and on demand; a contest that disappears from the list has been withdrawn.

### File-level fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `$schema` | string | no | JSON Schema URL. Preserved. |
| `$id` | string | no | Schema id. Preserved. |
| `title` | string | no | Human title of the file. |
| `version` | string | yes | Format semver, currently `"0.3.0"`. Served as `formatVersion`. |
| `contests` | Contest[] | yes | One or more contests. |

### Contest fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Stable kebab-case id. Unique within the file. |
| `name` | string | yes | Full name. |
| `short_name` | string | no | For example `CWT`. |
| `sponsor` | `{name?, url?}` | no | Served as `sponsorName` and `sponsorUrl` in the metadata. |
| `modes` | string[] | yes | From `CW`, `SSB`, `DIGITAL`, `RTTY`, `BOTH`. |
| `bands` | string[] | yes | `2200m` through `1mm`. |
| `data_dependencies` | object | no | Keys `country_file`, `prefix_map`, `section_list`, `zone_map`, plus unknown keys, which are kept. Each is `{id, url?, file?, description?, update_frequency?, provides[], options?}`. |
| `schedule` | tagged object | yes | `type` is `recurring_weekly` (`sessions[{day, start_utc, duration_minutes}]`, `session_scoring` of `independent` or `cumulative`), `annual` (`rule`, `start_utc`, `start_day`, `duration_hours`), or `fixed_dates` (`occurrences[{start, duration_hours}]`). |
| `exchange` | `{sent[], received[]}` | yes | Each field: `name`, `type` (one of `text`, `signal_report`, `serial_number`, `cq_zone`, `itu_zone`, `grid_square`, `state_province`, `arrl_section`, `section_list`, `power`, `name`, `age`, `class`), `label`, `required` (default `true`), `autofill?`, `auto_increment?`, `list?`, `default?`, `pattern?`, `min?`, `max?`. |
| `dupe_rules` | object | yes | `scope` of `session` or `contest`; `key[]` from `callsign`, `band`, `mode`, `mode_group`; `zero_point_qsos_count_for_mults` (default `false`). |
| `scoring` | `{phases[]}` | yes | Phase `type` is `per_qso` (`rules[{description?, conditions[], value}]`, first match wins), `multiplier_count` (`source`, `scope` of `per_band` or `per_contest`, `include_zero_point_qsos`), or `aggregate` (`operation` tree of `{op: ref|literal|add|multiply|max}`). Conditions are `{field, op (eq|ne|in|not_in|gt|gte|lt|lte), value | ref}`. |
| `operating_constraints` | object | no | `off_time {minimum_off_minutes?, maximum_on_hours_by_category{}}`, `band_changes {applies_to[], min_minutes_on_band?, max_changes_per_clock_hour?}`. |
| `cabrillo` | object | no | `contest_name`, `version` (currently `"3.0"`), `qso_format?` (opaque). |
| `categories` | Category[] | yes | `{id, label, band?, power_classes[], assisted?, op_count? (single|multi|multi_two|multi_multi)}`. At least one; ids unique. |
| `overlay_categories` | Overlay[] | no | `{id, label, max_on_hours?, max_license_years?}`. Ids must not collide with `categories`. |
| `experimental` | bool | no | Default `false`. Omitted from the served document when `false`. |

#### List contest definitions

```
GET /v1/contests
```

**Auth:** Public (optional bearer; the response is identical with or without a token).

| Param | Type | Required | Description |
|---|---|---|---|
| `includeInactive` | bool (query) | no | Default `false`. When `true`, inactive contests are included. A non-boolean value returns a plain-text `400`, not the JSON error envelope. |

**Response:** `200 OK`. Summaries only; no `definition` body.

```json
{
  "data": {
    "contests": [
      {
        "id": "cwops-cwt",
        "name": "CWops Mini-CWT Test",
        "shortName": "CWT",
        "sponsorName": "CW Operators' Club",
        "formatVersion": "0.3.0",
        "isActive": true,
        "updatedAt": "2026-04-23T01:08:55.371358Z"
      },
      {
        "id": "k1usn-sst",
        "name": "K1USN Slow Speed Test",
        "shortName": "SST",
        "sponsorName": "K1USN Radio Club",
        "formatVersion": "0.3.0",
        "isActive": true,
        "updatedAt": "2026-04-23T01:08:55.371358Z"
      }
    ]
  }
}
```

**Errors:**

| Code | HTTP | When |
|---|---|---|
| `INTERNAL_ERROR` | 500 | Server-side failure |

**Notes:**

- Ordered by `name` ascending.
- `sponsorUrl` is not included in list items; fetch the contest to get it.
- No `ETag` is emitted; compare `updatedAt` per contest.

#### Get a contest definition

```
GET /v1/contests/:id
```

**Auth:** Public (optional bearer; the response is identical with or without a token).

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | string (path) | yes | The contest id, for example `cwops-cwt`. Exact match. |

**Response:** `200 OK`. Metadata plus the full contest object under `definition`. The envelope keys are camelCase; the `definition` document is snake_case.

```json
{
  "data": {
    "id": "a1club-awt",
    "name": "A1CLUB Weekly Test",
    "shortName": "AWT",
    "sponsorName": "A1CLUB",
    "sponsorUrl": "https://a1club.org/contest/awt/",
    "formatVersion": "0.3.0",
    "definition": {
      "id": "a1club-awt",
      "name": "A1CLUB Weekly Test",
      "short_name": "AWT",
      "sponsor": { "name": "A1CLUB", "url": "https://a1club.org/contest/awt/" },
      "modes": ["CW"],
      "bands": ["160m", "80m", "40m", "20m", "15m", "10m"],
      "schedule": {
        "type": "recurring_weekly",
        "sessions": [{ "day": "wednesday", "start_utc": "11:45", "duration_minutes": 75 }],
        "session_scoring": "independent"
      },
      "exchange": {
        "sent": [
          { "name": "rst", "type": "signal_report", "label": "RST", "required": true },
          { "name": "name", "type": "name", "label": "Name", "required": true }
        ],
        "received": [
          { "name": "rst", "type": "signal_report", "label": "RST", "required": true },
          { "name": "name", "type": "name", "label": "Name", "required": true }
        ]
      },
      "dupe_rules": { "scope": "session", "key": ["callsign", "band"], "zero_point_qsos_count_for_mults": false },
      "scoring": {
        "phases": [
          { "id": "qso_points", "type": "per_qso", "rules": [{ "conditions": [], "value": 1 }] },
          { "id": "mult_callsigns", "type": "multiplier_count", "description": "Unique callsigns worked across all bands", "source": "their_callsign", "scope": "per_contest", "include_zero_point_qsos": false },
          { "id": "total", "type": "aggregate", "operation": { "op": "multiply", "inputs": [ { "op": "ref", "phase": "qso_points" }, { "op": "ref", "phase": "mult_callsigns" } ] } }
        ]
      },
      "cabrillo": { "contest_name": "A1AWT", "version": "3.0" },
      "categories": [ { "id": "single_op", "label": "Single Operator", "power_classes": ["HP", "LP", "QRP"] } ],
      "experimental": true
    },
    "isActive": true,
    "createdAt": "2026-04-23T01:08:55.371358Z",
    "updatedAt": "2026-04-23T01:08:55.371358Z"
  }
}
```

**Errors:**

| Code | HTTP | When |
|---|---|---|
| `CONTEST_DEFINITION_NOT_FOUND` | 404 | No contest with that id. `details`: `{"contestId": "<id>"}` |
| `INTERNAL_ERROR` | 500 | Server-side failure |

**Notes:** Unlike the list, this endpoint does not filter on `isActive`. An inactive contest is still fetchable by id; check `isActive` in the response.

### Operator endpoints

These require an operator token and are not available to third-party integrations.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/admin/contests` | Publish or republish every contest in a definition file |
| `DELETE` | `/v1/admin/contests/:id` | Withdraw a contest definition |
| `POST` | `/v1/admin/contests/validate` | Validate a file or a single contest without publishing it |

## Social: friends, activity feed, clubs and share links

The social endpoints cover friends, the activity feed, clubs, and the public pages behind links shared from the app. JSON endpoints live under `/v1` on `https://activities.carrierwave.app`. The HTML landing pages and the universal-link association file are served from the domain root of the same host.

These endpoints are first-party only. They accept the bearer token issued to the Carrier Wave apps (a device token or a first-party OAuth access token). A missing, malformed, unknown, expired or revoked token returns `401 INVALID_TOKEN`. Third-party OAuth tokens are refused with `403 FORBIDDEN` regardless of their scopes. The invite and share-link landing pages, the club logo and the universal-link association file are public and need no token.

Conventions shared by every JSON endpoint in this section:

- Successful responses are wrapped as `{ "data": ... }`. Field names are camelCase.
- Errors are a top-level object `{ "code": "<CODE>", "message": "<text>", "details": { ... } }`. `details` is omitted when there is nothing to add. `304 Not Modified` has an empty body.
- A path id that is not a UUID, malformed JSON, a wrong content type, or a missing required field returns `400 VALIDATION_ERROR`.
- Request bodies are limited to 1 MiB.
- Requests are rate limited. Over the limit the server returns `429 RATE_LIMITED`.
- Timestamps are RFC 3339 strings in UTC.
- There is no separate registration step. The first friends or feed call for a callsign creates its user record.

### Friends

Friendships are symmetric and are keyed by user id, not by callsign. The lifecycle is:

1. **Invite link.** `GET /v1/friends/invite-link` returns a single-use token (`inv_` followed by 24 alphanumerics) and a URL of the form `https://activities.carrierwave.app/invite/<token>`. Tokens expire after 7 days. Each call returns a fresh token; earlier tokens stay valid until used or expired.
2. **Request.** `POST /v1/friends/requests` with either `inviteToken` or `toUserId` creates a request in status `pending`. A request between a pair that was previously declined or unfriended is revived rather than rejected.
3. **Accept or decline.** Only the addressee can act on a request. Accepting creates the friendship in both directions and is idempotent. Declining is not: a second decline returns 404.
4. **Remove.** `DELETE /v1/friends/:friendshipId` removes the friendship in both directions and clears the request history between the two users, so either can send a new request later.

Request status is one of `pending`, `accepted` or `declined`. `POST /v1/friends/suggestions` answers "which of these callsigns are Carrier Wave users I am not already friends or pending with" for up to 100 callsigns per call.

The public page `GET /invite/:token` shows the inviter's callsign while the invite is unused and unexpired, and offers a `carrierwave://invite/<token>` deep link. Viewing the page does not consume the invite.

#### Generate friend invite link

```
GET /v1/friends/invite-link
```

**Auth:** Bearer (first-party)

No parameters. No request body.

**Response:** `200 OK`

```json
{
  "data": {
    "token": "inv_k3J9xQpL2mN8vB4cD7fG1hRs",
    "url": "https://activities.carrierwave.app/invite/inv_k3J9xQpL2mN8vB4cD7fG1hRs",
    "expiresAt": "2026-10-17T18:04:11.123456Z"
  }
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FORBIDDEN` | 403 | Third-party OAuth token |
| `INTERNAL_ERROR` | 500 | Server failure |

**Notes**

- Every call creates a new token. Outstanding tokens are not reused.
- `expiresAt` is 7 days after creation.
- The token is single-use. It is consumed by the first `POST /v1/friends/requests` that presents it.

#### Create friend request

```
POST /v1/friends/requests
```

**Auth:** Bearer (first-party)

**Request.** Exactly one of the two fields must be present.

| Field | Type | Required | Description |
|---|---|---|---|
| `inviteToken` | string | one of | Token from an invite link (`inv_...`) |
| `toUserId` | uuid | one of | Target user id, for example from `/v1/friends/suggestions` |

```json
{ "inviteToken": "inv_k3J9xQpL2mN8vB4cD7fG1hRs" }
```

or

```json
{ "toUserId": "7d2c3d0a-6f6d-4b8e-9a7e-0b1f3d1a2c44" }
```

**Response:** `201 Created`

```json
{
  "data": {
    "id": "f0a2f8b4-1c1e-4f4e-9b0e-2b0c7f3c6d11",
    "fromUserId": "0a1b2c3d-...",
    "fromCallsign": "W6JY",
    "toUserId": "7d2c3d0a-...",
    "toCallsign": "K6ARK",
    "status": "pending",
    "requestedAt": "2026-10-10T18:04:11.123456Z"
  }
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Both or neither of `toUserId` and `inviteToken` given; malformed JSON |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `USER_NOT_FOUND` | 404 | `toUserId` does not exist (`details.userId`) |
| `FRIEND_INVITE_NOT_FOUND` | 404 | Token unknown, expired or already used (`details.token`) |
| `ALREADY_FRIENDS` | 409 | The two users are already friends |
| `FRIEND_REQUEST_EXISTS` | 409 | A `pending` request already exists in either direction |
| `CANNOT_FRIEND_SELF` | 422 | Target resolves to the caller |

**Notes**

- An invite token is consumed as soon as it is presented, even if the request is then rejected (for example with `ALREADY_FRIENDS` or `CANNOT_FRIEND_SELF`). The inviter must generate a new link in that case.
- An expired or used token returns `FRIEND_INVITE_NOT_FOUND`.
- If a request between the same pair was declined earlier, or left over from a removed friendship, it is revived as `pending` and its original `id` is returned.
- Lifecycle: `pending`, then `accepted` (via accept) or `declined` (via decline). Removing a friend deletes the request history between the pair.

#### Friend suggestions

```
POST /v1/friends/suggestions
```

**Auth:** Bearer (first-party)

**Request**

| Field | Type | Required | Description |
|---|---|---|---|
| `callsigns` | string[] | yes | Candidate callsigns, any case. Only the first 100 are considered. |

```json
{ "callsigns": ["k6ark", "W1AW", "N0CALL"] }
```

**Response:** `200 OK`

```json
{
  "data": [
    { "userId": "7d2c3d0a-...", "callsign": "K6ARK" },
    { "userId": "9e8f7a6b-...", "callsign": "W1AW" }
  ]
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Missing `callsigns`; malformed JSON |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |

**Notes**

- An empty `callsigns` array returns `[]`.
- Matching is case-insensitive. The result excludes the caller, existing friends, and users with a `pending` request in either direction. Callsigns that are not Carrier Wave users are simply absent.
- The returned `callsign` uses the casing stored for that user.

#### List friends

```
GET /v1/friends
```

**Auth:** Bearer (first-party)

No parameters.

**Response:** `200 OK`

```json
{
  "data": [
    {
      "friendshipId": "c1d2e3f4-...",
      "callsign": "K6ARK",
      "userId": "7d2c3d0a-...",
      "acceptedAt": "2026-09-30T02:15:00.000000Z"
    }
  ]
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |

**Notes**

- Ordered by friend callsign ascending.
- `friendshipId` is the id to pass to `DELETE /v1/friends/:id`. It identifies the caller's side of the friendship; the friend sees a different id for the same relationship.

#### List pending friend requests

```
GET /v1/friends/requests/pending
```

**Auth:** Bearer (first-party)

No parameters.

**Response:** `200 OK`

```json
{
  "data": {
    "incoming": [
      {
        "id": "f0a2f8b4-...",
        "fromUserId": "...", "fromCallsign": "N6XYZ",
        "toUserId": "...",   "toCallsign": "W6JY",
        "status": "pending",
        "requestedAt": "2026-10-10T17:00:00.000000Z"
      }
    ],
    "outgoing": []
  }
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |

**Notes**

- Only `pending` requests are returned. `incoming` holds requests addressed to the caller, `outgoing` the ones the caller sent. Both are newest first.

#### Accept friend request

```
POST /v1/friends/requests/:id/accept
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | uuid (path) | yes | Friend request id |

**Request:** no body.

**Response:** `200 OK` with the request, now `accepted`.

```json
{
  "data": {
    "id": "f0a2f8b4-...",
    "fromUserId": "...", "fromCallsign": "N6XYZ",
    "toUserId": "...",   "toCallsign": "W6JY",
    "status": "accepted",
    "requestedAt": "2026-10-10T17:00:00.000000Z"
  }
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `id` is not a UUID |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FORBIDDEN` | 403 | Caller is not the addressee (`toUserId`) |
| `FRIEND_REQUEST_NOT_FOUND` | 404 | No such request, or the request was declined |

**Notes**

- Idempotent: accepting an already accepted request returns the existing record with `200`, so a duplicate tap or a retry from a second device succeeds.
- The sender cannot accept their own outgoing request.

#### Decline friend request

```
POST /v1/friends/requests/:id/decline
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | uuid (path) | yes | Friend request id |

**Request:** no body.

**Response:** `204 No Content`

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `id` is not a UUID |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FORBIDDEN` | 403 | Caller is not the addressee |
| `FRIEND_REQUEST_NOT_FOUND` | 404 | No such request, or it is no longer `pending` |

**Notes**

- Not idempotent. A second decline returns 404.
- A later request between the same pair revives the declined request as `pending`.

#### Remove friend

```
DELETE /v1/friends/:id
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | uuid (path) | yes | `friendshipId` from `GET /v1/friends` |

**Response:** `204 No Content`

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `id` is not a UUID |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FRIENDSHIP_NOT_FOUND` | 404 | No friendship with this id belongs to the caller (`details.friendshipId`) |

**Notes**

- Removes the friendship for both users and clears the request history between them, so either can send a fresh request later.
- Only the caller's own `friendshipId` works. The id the other user sees for the same friendship returns 404.

### Activities and feed

An activity is a client-reported event with a `type` string, a `timestamp` (when it happened) and a free-form JSON `details` object. The server does not validate `type` or `details`. The Carrier Wave apps currently send these kinds:

`newDXCCEntity`, `newBand`, `newMode`, `dxContact`, `potaActivation`, `sotaActivation`, `dailyStreak`, `potaDailyStreak`, `personalBest`, `workedFriend`, `sessionCompleted`

Some kinds also feed achievement evaluation, which runs when the activity is posted: `newBand`, `sessionCompleted` and `newDXCCEntity` read `details.band`, `newMode` reads `details.mode`, and `workedFriend` reads `details.workedCallsign`. Achievement evaluation never fails the write.

Who sees an activity:

- `GET /v1/feed` returns activities of the caller's friends, newest first. The caller's own activities are not included.
- `GET /v1/clubs/:id/activity` returns activities of a club's members, including the caller's own, and is visible to any member of that club.

Both feeds are cursor-paginated on the server-side creation time, not on the client-supplied `timestamp`. A page returns `hasMore` and `nextCursor`; pass `nextCursor` back verbatim to get the next page. Items older than the cursor are returned (strictly before).

Activities persist until the owner deletes them.

#### Report activity

```
POST /v1/activities
```

**Auth:** Bearer (first-party)

**Request**

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | string | yes | Activity kind (free-form; see the kinds above) |
| `timestamp` | RFC 3339 datetime | yes | When the activity happened |
| `details` | JSON object | yes | Arbitrary payload, stored verbatim |

```json
{
  "type": "sessionCompleted",
  "timestamp": "2026-10-10T17:42:00Z",
  "details": { "qsoCount": 23, "band": "20m", "mode": "CW", "park": "US-1234" }
}
```

**Response:** `201 Created`

```json
{
  "data": {
    "id": "3f1c...",
    "callsign": "W6JY",
    "activityType": "sessionCompleted",
    "timestamp": "2026-10-10T17:42:00Z",
    "details": { "qsoCount": 23, "band": "20m", "mode": "CW", "park": "US-1234" }
  }
}
```

Note the field names differ: the request uses `type`, the response uses `activityType`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Missing `type`, `timestamp` or `details`; bad timestamp; malformed JSON |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `INTERNAL_ERROR` | 500 | Server failure |

**Notes**

- `callsign` is the caller's callsign at the time of the report.
- The activity appears in friends' `GET /v1/feed` and in `GET /v1/clubs/:id/activity` for every club the callsign belongs to.
- There is no deduplication. Posting the same activity twice creates two activities.

#### Delete activity

```
DELETE /v1/activities/:id
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | uuid (path) | yes | Activity id |

**Response:** `204 No Content`

**Errors**

| Code | HTTP | When |
|---|---|---|
| (400) | 400 | `id` is not a UUID |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `ACTIVITY_NOT_FOUND` | 404 | No activity with this id belongs to the caller (`details.activityId`) |

**Notes**

- Only the owner can delete an activity. Another user's activity returns 404, not 403.

#### Get activity feed

```
GET /v1/feed
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `limit` | integer (query) | no | Page size. Default 50, clamped to 1..100 |
| `before` | RFC 3339 string (query) | no | Cursor. Returns items created strictly before this instant. Unparseable values are ignored and the first page is returned |
| `filter` | string (query) | no | Accepted but currently has no effect |

**Response:** `200 OK`

```json
{
  "data": {
    "items": [
      {
        "id": "3f1c...",
        "callsign": "K6ARK",
        "userId": "7d2c3d0a-...",
        "displayName": null,
        "activityType": "potaActivation",
        "timestamp": "2026-10-10T16:00:00Z",
        "details": { "park": "US-0001" }
      }
    ],
    "pagination": {
      "hasMore": true,
      "nextCursor": "2026-10-10T16:00:03.512345+00:00"
    }
  }
}
```

`displayName` is currently always `null`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `limit` is not an integer |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |

**Notes**

- Scope: activities of the caller's friends. The caller's own activities are excluded.
- Ordering and the cursor use the server-side creation time, not the client-supplied `timestamp`. `nextCursor` is the creation time of the last item (RFC 3339 with a `+00:00` offset) and is `null` when `hasMore` is `false`. Pass it back verbatim as `before`.
- Items do not include their creation time. The cursor is the only place it appears.

### Clubs

Clubs are curated by Carrier Wave operators. A club has a `name`, an optional `callsign` and `description`, an optional notes link (`notesUrl` and `notesTitle`), and an optional logo. There is no self-join endpoint. Members are added by an operator or by roster sync.

**Membership and roles.** The roster is a list of callsigns (stored uppercase), each with a `role` of `admin` or `member`. Members are listed admins first, then by callsign, and carry `lastSeenAt` and `isCarrierWaveUser`. Club `admin` members can edit the club's notes link with `PUT /v1/clubs/:id/notes`. All members can read the club's details, activity and member status.

**Notes-URL roster sync.** A club whose `notesUrl` points at a callsign-notes text file (one callsign per line, first whitespace-separated token, `#` comments and blank lines ignored; the Ham2K PoLo format) has its roster reconciled against that file about every six hours. Callsigns new to the file are added as `member`. Members with the `member` role who are no longer in the file are removed. Members with the `admin` role are never touched by sync. If the file cannot be fetched, returns a non-2xx status, or yields zero callsigns, the roster is left unchanged. Operators can also run the same reconcile on demand.

**ETags.** `GET /v1/clubs/sync` and `GET /v1/clubs/membership` return an `ETag` that changes whenever any of the caller's clubs or their rosters change (add, remove, role change, roster sync, notes link, logo). Send it back as `If-None-Match` to get `304 Not Modified` with an empty body when nothing changed.

**Prior callsigns.** `GET /v1/clubs`, `GET /v1/clubs/sync` and `GET /v1/clubs/membership` accept `?callsigns=A,B` to include memberships held under the caller's earlier callsigns. Each extra callsign is honoured only if the caller is known to own it (current callsign, callsign history, or callsigns linked to the account). Anything else is silently dropped. The per-club routes (`/v1/clubs/:id/...`) check only the caller's current callsign.

**Member status.** `GET /v1/clubs/:id/status` classifies each member as `onAir` (an active spot for the callsign within the last 30 minutes), `recentlyActive` (seen in Carrier Wave within the last 15 minutes) or `inactive`.

**Logos.** `GET /v1/clubs/:id/logo` is public and cacheable. `hasLogo` on club responses says whether a logo exists.

Common query parameter for `GET /v1/clubs`, `GET /v1/clubs/sync` and `GET /v1/clubs/membership`:

| Param | Type | Required | Description |
|---|---|---|---|
| `callsigns` | string (query) | no | Comma-separated prior callsigns to include alongside the current one, for example `?callsigns=W6JSV,W6JNZ`. Trimmed, uppercased, deduplicated. Callsigns the caller does not own are dropped silently. |

#### List my clubs

```
GET /v1/clubs
```

**Auth:** Bearer (first-party)

Params: `callsigns` (see above).

**Response:** `200 OK`

```json
{
  "data": [
    {
      "id": "1b7e...",
      "name": "Brass Knuckle Gang",
      "callsign": "W6BKG",
      "description": "...",
      "notesUrl": "https://www.bkg.club/members.txt",
      "notesTitle": "BKG Callsign Notes",
      "hasLogo": true,
      "memberCount": 512
    }
  ]
}
```

`notesUrl` and `notesTitle` are omitted when unset. `callsign` and `description` are `null` when unset.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |

**Notes**

- Returns every club where any of the resolved callsigns is a member, ordered by name.

#### Sync clubs with full rosters

```
GET /v1/clubs/sync
```

**Auth:** Bearer (first-party)

Params: `callsigns` (see above). Optional request header `If-None-Match`.

**Response:** `200 OK` with header `ETag: "clubs-<epochSeconds>"`.

```json
{
  "data": [
    {
      "id": "1b7e...",
      "name": "Brass Knuckle Gang",
      "callsign": "W6BKG",
      "description": null,
      "notesUrl": "https://www.bkg.club/members.txt",
      "notesTitle": "BKG Callsign Notes",
      "hasLogo": true,
      "memberCount": 512,
      "members": [
        {
          "callsign": "W6JY",
          "role": "admin",
          "joinedAt": "2026-09-01T00:00:00Z",
          "lastSeenAt": "2026-10-10T17:55:00Z",
          "isCarrierWaveUser": true
        },
        {
          "callsign": "9A2NB",
          "role": "member",
          "joinedAt": "2026-09-26T15:40:00Z",
          "isCarrierWaveUser": false
        }
      ]
    }
  ]
}
```

`lastSeenAt` is omitted when unknown. A `lastGrid` field exists but is currently always null and therefore omitted.

`304 Not Modified` with an empty body when `If-None-Match` equals the current ETag byte for byte, including the quotes. The 304 response carries no `ETag` header.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |

**Notes**

- The ETag is derived from the most recent change across the caller's clubs and rosters. It is `"clubs-0"` when the caller has no clubs.
- Members are ordered by club, admins first, then by callsign.

#### Club membership map

```
GET /v1/clubs/membership
```

**Auth:** Bearer (first-party)

Params: `callsigns` (see above). Optional request header `If-None-Match`.

**Response:** `200 OK` with header `ETag: "membership-<epochSeconds>"`.

```json
{
  "data": [
    { "name": "Brass Knuckle Gang", "callsigns": ["9A2NB", "AA6XV", "W6JY"] }
  ]
}
```

`304 Not Modified` with an empty body on an ETag match.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |

**Notes**

- Same fingerprint as `GET /v1/clubs/sync` with a `membership-` prefix.
- Entries are grouped by club name. The order of clubs in the array is unspecified; callsigns within a club are sorted. Two clubs with the same name are merged into one entry.
- Intended as a lightweight callsign-to-club lookup.

#### Get club details

```
GET /v1/clubs/:id
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | uuid (path) | yes | Club id |

**Response:** `200 OK`

```json
{
  "data": {
    "id": "1b7e...",
    "name": "Brass Knuckle Gang",
    "callsign": "W6BKG",
    "description": null,
    "notesUrl": "https://www.bkg.club/members.txt",
    "notesTitle": "BKG Callsign Notes",
    "hasLogo": true,
    "members": [ { "callsign": "W6JY", "role": "admin", "joinedAt": "...", "lastSeenAt": "...", "isCarrierWaveUser": true } ]
  }
}
```

There is no `memberCount` on this response. Count the `members` array.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `id` is not a UUID |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FORBIDDEN` | 403 | Caller's callsign is not on the roster. An unknown club id also returns 403 |
| `CLUB_NOT_FOUND` | 404 | Club no longer exists |

**Notes**

- The membership check uses only the caller's current callsign. `?callsigns=` is not accepted here, so a membership held under a prior callsign returns 403 on the per-club routes.

#### Get club activity

```
GET /v1/clubs/:id/activity
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | uuid (path) | yes | Club id |
| `limit` | integer (query) | no | Page size. Default 20, clamped to 1..100 |
| `cursor` | RFC 3339 string (query) | no | Returns items created strictly before this instant. Unparseable values are ignored |

**Response:** `200 OK`

```json
{
  "data": {
    "items": [
      {
        "id": "3f1c...",
        "callsign": "9A2NB",
        "activityType": "newDXCCEntity",
        "timestamp": "2026-10-10T15:00:00Z",
        "details": { "entity": "Croatia", "band": "20m" },
        "createdAt": "2026-10-10T15:00:04.100000Z"
      }
    ],
    "pagination": { "hasMore": false, "nextCursor": null }
  }
}
```

Unlike `GET /v1/feed`, items include `createdAt` and omit `userId` and `displayName`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `id` is not a UUID |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FORBIDDEN` | 403 | Caller is not a member, or the club is unknown |

**Notes**

- Scope: all activities whose callsign is on this club's roster, including the caller's own and members who are not friends.
- Cursor semantics match `GET /v1/feed`: newest first by creation time, `nextCursor` is the `createdAt` of the last item. The query parameter is named `cursor` here and `before` on `/v1/feed`. The default `limit` is 20 here and 50 on `/v1/feed`.

#### Get club member status

```
GET /v1/clubs/:id/status
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | uuid (path) | yes | Club id |

**Response:** `200 OK`

```json
{
  "data": [
    {
      "callsign": "W6JY",
      "status": "onAir",
      "spotInfo": {
        "frequency": 14062.5,
        "mode": "CW",
        "source": "pota",
        "spottedAt": "2026-10-10T17:50:00Z"
      },
      "lastSeenAt": "2026-10-10T17:55:00Z"
    },
    { "callsign": "AA6XV", "status": "recentlyActive", "lastSeenAt": "2026-10-10T17:48:00Z" },
    { "callsign": "9A2NB", "status": "inactive" }
  ]
}
```

`status` is one of `onAir`, `recentlyActive` or `inactive`. `spotInfo` and `lastSeenAt` are omitted when not applicable.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `id` is not a UUID |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FORBIDDEN` | 403 | Caller is not a member, or the club is unknown |

**Notes**

- `onAir`: the most recent unexpired spot for the exact callsign, spotted within the last 30 minutes. `spotInfo.frequency` is in kHz. `source` is the lowercased spot network name, for example `pota`.
- `recentlyActive`: no qualifying spot, and the member was seen in Carrier Wave within the last 15 minutes.
- Otherwise `inactive`.

#### Update club notes link

```
PUT /v1/clubs/:id/notes
```

**Auth:** Bearer (first-party). The caller must be an `admin` member of the club.

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | uuid (path) | yes | Club id |

**Request.** This is a replace, not a patch. A missing or `null` field clears that value.

| Field | Type | Required | Description |
|---|---|---|---|
| `notesUrl` | string or null | no | Must start with `https://` when present |
| `notesTitle` | string or null | no | Display title |

```json
{ "notesUrl": "https://www.bkg.club/members.txt", "notesTitle": "BKG Callsign Notes" }
```

**Response:** `200 OK` with the club in the same shape as a `GET /v1/clubs` item.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `notesUrl` present but not `https://`; malformed JSON; `id` is not a UUID |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FORBIDDEN` | 403 | Caller is not a member, or is a member without the `admin` role |
| `CLUB_NOT_FOUND` | 404 | Club no longer exists |

**Notes**

- Setting a `notesUrl` enrols the club in roster sync (see above). Clearing it stops future reconciliation but does not remove members.
- Changes the club's ETag.

#### Get club logo

```
GET /v1/clubs/:id/logo
```

**Auth:** Public

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | uuid (path) | yes | Club id |

**Response:** `200 OK` with the raw image bytes. `Content-Type` is the uploaded type (`image/png`, `image/jpeg`, `image/svg+xml`, `image/gif` or `image/webp`). `Cache-Control: public, max-age=86400`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `id` is not a UUID |
| `CLUB_NOT_FOUND` | 404 | Club unknown, or it has no logo (`details.clubId`) |

**Notes**

- No membership check. Anyone with the club id can fetch the logo.
- Treat 404 as "no logo". `hasLogo: false` on club responses is the cheaper signal.

### Operator endpoints

Clubs are created and maintained by Carrier Wave operators through `/v1/admin/clubs*`. These routes require an operator token (`Authorization: Bearer <operator token>`); any other credential returns `401 INVALID_TOKEN`. They are listed here for completeness and are not available to app users.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/admin/clubs` | Create a club (`name`, optional `callsign` and `description`) |
| `GET` | `/v1/admin/clubs` | List all clubs with `memberCount`, `rosterSyncedAt` and `rosterSyncStatus` (`ok` or `error: ...`) |
| `PUT` | `/v1/admin/clubs/:id` | Update a club's name, callsign, description, `notesUrl` and `notesTitle` |
| `DELETE` | `/v1/admin/clubs/:id` | Delete a club and its roster. Activities are untouched |
| `GET` | `/v1/admin/clubs/:id/members` | List a club's members |
| `POST` | `/v1/admin/clubs/:id/members` | Add members (`callsign`, optional `role`, default `member`). Re-adding an existing member updates their role |
| `DELETE` | `/v1/admin/clubs/:id/members/:callsign` | Remove a member |
| `PUT` | `/v1/admin/clubs/:id/members/:callsign` | Change a member's role (`admin` or `member`) |
| `POST` | `/v1/admin/clubs/:id/import-notes` | Reconcile the roster from the club's `notesUrl` now. Returns `imported`, `skipped`, `removed`, `callsigns` and `removedCallsigns` |
| `PUT` | `/v1/admin/clubs/:id/logo` | Upload or replace the logo. Multipart with one `image` part (`image/png`, `image/jpeg`, `image/svg+xml`, `image/gif` or `image/webp`); logo uploads are limited to 1 MiB |
| `DELETE` | `/v1/admin/clubs/:id/logo` | Remove the logo |

Members added as `member` to a club with a `notesUrl` are removed by the next roster sync unless they are also in the notes file. Add them as `admin` to make them stick. Every roster or logo change moves the club's ETag.

### Share and invite pages

The pages below are served from the domain root of `https://activities.carrierwave.app`, not under `/v1`. They need no token.

#### Friend invite landing page

```
GET /invite/:token
```

**Auth:** Public

| Param | Type | Required | Description |
|---|---|---|---|
| `token` | string (path) | yes | Invite token from `GET /v1/friends/invite-link` |

**Response:** always `200 OK`, `Content-Type: text/html; charset=utf-8`, no cache headers. The page renders a single card:

- If the token exists, is unused and unexpired: `<title>` and `og:title` are `<CALLSIGN> wants to be friends on Carrier Wave`, `og:description` is `Open this link in Carrier Wave to add <CALLSIGN> as a friend.`, and the heading is `<CALLSIGN> wants to be friends!`.
- Otherwise (unknown, used or expired): the generic `Friend invite on Carrier Wave`, `You've been invited!` and `Open this link in Carrier Wave to accept this friend invite.`.
- An "Open in Carrier Wave" button linking to `carrierwave://invite/<token>` when the token matches `[A-Za-z0-9_]+`, otherwise to a bare `carrierwave://invite`.

The callsign and token are HTML-escaped. Viewing the page does not consume the invite; only `POST /v1/friends/requests` does.

**Errors:** none. Lookup failures fall back to the generic page.

**Notes**

- This page has no Open Graph image.
- `/invite/*` is not a universal link. The app is reached through the `carrierwave://` scheme only.

#### Share-link landing pages

```
GET /link/qso/:token
GET /link/act/:token
GET /link/call/:callsign
GET /link/park/:reference
GET /link/sum/:reference
```

**Auth:** Public

| Param | Type | Required | Description |
|---|---|---|---|
| `token`, `callsign` or `reference` | string (path) | yes | Identifier chosen by the sharing app. For `call` and `sum`, a `/` in the real identifier is written as `-` (for example `KD9LSV-P`, `W6-NC-123`); the page displays it uppercased with `-` turned back into `/`. For `qso` and `act` it is an opaque share token (for example `jZRcZAZMQI`). |

The server performs no lookup of the identifier. Every page is a static shell for the given kind.

**Response:** `200 OK`, `Content-Type: text/html; charset=utf-8`, `Cache-Control: public, max-age=3600, s-maxage=86400`. The HTML contains:

- `<title>` and `og:title`: `Carrier Wave QSO` (qso), `Carrier Wave Activation` (act), or `<IDENTIFIER> on Carrier Wave` (call, park, sum; identifier uppercased with `-` turned into `/`).
- `og:description` and `<meta name="description">`: a fixed sentence per kind, for example `A QSO shared from Carrier Wave. Open in the app for full details.`
- `og:type=website`, `og:site_name=Carrier Wave`, `og:url=https://carrierwave.app/link/<kind>/<identifier>`, `og:image=https://carrierwave.app/icon.png` (512 by 512), `twitter:card=summary_large_image`.
- A fallback card with the kind (QSO, Activation, Callsign, Park or Summit) and the normalised identifier, an "Open in Carrier Wave" link to the canonical path (which relies on universal links) and a "Get Carrier Wave" link to `https://carrierwave.app/`.
- `<script src="/link/static/link-card.js" defer>`.

**The `#d=` fragment convention.** The sharing app appends `#d=<base64url(JSON)>` to the URL. Browsers never send the fragment to the server, so the QSO or activation data is never received, logged or stored server-side. The page script reads `location.hash`, strips the optional `d=` prefix, base64url-decodes, parses the JSON and renders the card in the browser. The payload carries a version in `v` (currently 1; a greater value renders an "Update Carrier Wave" notice) and a kind in `k`:

| `k` | Fields rendered |
|---|---|
| `qso` | `c` their call, `me` my call, `rs`/`rr` RST sent/received, `mg`/`tg` my/their grid, `b` band, `md` mode, `f` frequency MHz, `p` park, `ts` unix seconds, `nt` notes |
| `call` | `c` call, `g` grid, `co` DXCC, `q` QTH, `wc` worked count, `lb`/`lm` last band/mode, `nm` name, `ph` footnote |
| `park` | `r` reference, `nm` name, `la`/`lo` latitude/longitude, `st` state, `co` country, `ua`/`uh` user activations/hunts, `an` active-now boolean |
| `sum` | `r` reference, `nm` name, `la`/`lo`, `am` altitude m, `pt` points, `rn` region, `as` association, `ac` activations, `ua`/`uc` my activations/chases |
| `act` | `p` park reference, `pn` park name, `me` operator, `qc` QSO count, `bs` bands[], `ms` modes[], `p2p`, `dx`, `st` start unix seconds, `nt` notes |

The script also calls the public callsign enrichment endpoint (`GET /v1/callsign-enrichment/<callsign>`) to draw club-membership chips for the callsigns in the payload. With no fragment, or an invalid one, the static fallback card stays in place.

**Errors:** none. Any path segment renders.

**Notes**

- Identifiers are HTML-escaped before rendering. The canonical URL keeps the identifier as given.
- Because `/link/*` is a universal link, iOS and macOS devices with the app installed open these URLs in the app, fragment included.

#### Link-card script

```
GET /link/static/link-card.js
```

**Auth:** Public

**Response:** `200 OK`, `Content-Type: application/javascript; charset=utf-8`, `Cache-Control: public, max-age=86400, s-maxage=604800`. The script that renders the share-link card from the `#d=` fragment.

#### Apple App Site Association

```
GET /.well-known/apple-app-site-association
```

**Auth:** Public

**Response:** `200 OK`, `Content-Type: application/json`, `Cache-Control: public, max-age=3600`.

```json
{
  "applinks": {
    "apps": [],
    "details": [
      { "appID": "7UE4RDLUSX.com.jsvana.FullDuplex", "paths": ["/link/*"] },
      { "appID": "7UE4RDLUSX.com.jsvana.CWSweep",    "paths": ["/link/*"] }
    ]
  }
}
```

**Notes**

- Only `/link/*` is claimed, for both the iOS and macOS apps. `/invite/*` is not.
- Served unsigned over HTTPS.

## Spots and reference data

This family covers the live "who is on the air" feed and the reference datasets that sit behind it: Reverse Beacon Network spots, KiwiSDR receiver proxies, POTA activation statistics, park and administrative boundaries, historic trails, satellite status, callsign enrichment and HF propagation predictions. Most of it is public. The few write endpoints need a first-party bearer token.

All paths are mounted under `/v1`. Successful JSON responses from the spots, POTA statistics and status endpoints are wrapped as `{"data": ...}`. GeoJSON endpoints and the RBN, WebSDR, satellite, callsign-enrichment and propagation endpoints return bare bodies. Each endpoint below states which. Errors use the envelope `{"error": {"code", "message", "details"?}}` unless noted.

Request validation behaves the same way across the family:

- Malformed query parameters (a non-numeric `limit`, an unknown `source`, a missing required `host`) answer with a plain-text `400`, not the JSON envelope.
- Malformed path parameters answer with `400 VALIDATION_ERROR` in the JSON envelope.
- Malformed JSON bodies on `POST /v1/spots` and `POST /v1/sota/zones` answer with `400 VALIDATION_ERROR`. The propagation endpoints answer malformed bodies with a plain-text `400`, `415` or `422`.
- A global rate limit applies to every endpoint: a burst of 20 requests, refilling at one request per 100 ms. Excess requests receive `429`. Request bodies are capped at 1 MiB.

Field names are camelCase except where a section says otherwise (the RBN, callsign-enrichment and propagation endpoints use snake_case).

| Dataset | Endpoint | Upstream source | Typical refresh |
|---|---|---|---|
| Spots (POTA, SOTA, self-spots) | `GET /v1/spots` | POTA activator spot feed, SOTAwatch spot feed, first-party clients | POTA polled every 60 s, SOTA every 90 s; expired spots purged every 2 minutes |
| RBN spots | `GET /v1/rbn/*` | `telnet.reversebeacon.net:7000` | Live; rolling 1-hour in-memory window |
| KiwiSDR directory | `GET /v1/websdr/directory` | `https://rx.skywavelinux.com/kiwisdr_com.js` | Cached in memory for 1 hour |
| POTA park catalog and activation stats | `GET /v1/pota/stats/*` | `https://pota.app/all_parks_ext.csv`, `https://api.pota.app` | Catalog resynced once per 24 h; per-park stats refreshed on a rolling 24 h cycle |
| Park boundaries (US, UK, IT, PL, selected US state parks) | `GET /v1/parks/boundaries*` | PAD-US, Natural England, WDPA feature services; state agencies for FL, OR, CA, TX; Polish GDOŚ WFS | 24 h cycle; a park's polygon is re-fetched after 90 days |
| US administrative boundaries (states, counties) | `GET /v1/admin/boundaries` | US Census cartographic boundary files (1:500k, 2023 vintage) | Loaded manually; refreshed rarely |
| National historic and scenic trails | `GET /v1/trails*` | USGS National Map transportation layer; NTIR per-trail feature services | Weekly cycle over a 19-trail catalog; a trail is re-fetched after 180 days |
| SOTA activation zones | `POST /v1/sota/zones` | Computed from Terrarium elevation tiles | On demand; cached permanently per summit code |
| AMSAT satellite status | `GET /v1/satellites/amsat-status` | `https://status.amsat.org/api/v1/` (CC BY 4.0 — attribute as "Satellite status data: AMSAT, https://status.amsat.org") | Every 30 minutes |
| Callsign enrichment (CWops) | `GET /v1/callsign-enrichment/*` | CWops membership roster | Every 24 h |
| HF propagation predictions | `POST /v1/propagation/*` | DVOACAP-based prediction service run alongside the API | Computed on demand; results cached for 24 h |

**Error codes used by this family**

| Code | HTTP | Raised by |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Bad JSON body or path parameter; WebSDR host checks; `bbox`, `refs` and `kind` validation; POTA `mode`; propagation inputs rejected by the prediction service |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer on authenticated routes |
| `PROGRAM_NOT_FOUND` | 404 | `POST /v1/spots` with an unknown program |
| `SPOT_NOT_FOUND` | 404 | `DELETE /v1/spots/:id` |
| `PARK_NOT_FOUND` | 404 | `GET /v1/pota/stats/park/:reference`, `GET /v1/parks/boundaries/:reference` |
| `TRAIL_NOT_FOUND` | 404 | `GET /v1/trails/:reference` |
| `NOT_FOUND` | 404 | Propagation endpoints when predictions are disabled |
| `SELF_SPOT_EXISTS` | 409 | `POST /v1/spots` |
| `CAPABILITY_NOT_SUPPORTED` | 422 | `POST /v1/spots` for a program without self-spotting |
| `RATE_LIMITED` | 429 | Global rate limit |
| `INTERNAL_ERROR` | 500 | Database errors, upstream fetch failures (WebSDR, propagation) |

### Spots

The spot feed is a short-lived merge of several sources. Each spot carries a `source` of `pota`, `rbn`, `sota`, `self` or `other`.

- **POTA** spots come from the POTA activator feed, polled every 60 s. Each spot expires when the upstream feed says it does, clamped to 24 hours, or after 30 minutes when upstream gives no expiry. They carry `programSlug: "pota"`, and a `locationDesc` such as `US-WY` is split into `countryCode` and `stateAbbr`.
- **SOTA** spots come from the SOTAwatch feed, polled every 90 s. They expire 30 minutes after `spottedAt`. `reference` is `ASSOCIATION/SUMMIT` (for example `W7W/KI-001`). Frequencies are converted to kHz.
- **Self-spots** are posted by first-party clients with `POST /v1/spots`. They expire after 30 minutes, and a participant can hold at most one unexpired self-spot per program.
- **SMS spots** are sent as a text message to the Carrier Wave number using a marker from `POST /v1/spot-markers`. The inbound webhook (`POST /v1/twilio/sms`) is called by the SMS provider, not by clients. POTA references are forwarded to the POTA spot API and re-enter the feed through the POTA poller. SOTA references by SMS are currently disabled and receive a "temporarily disabled" reply.

Expired spots are purged every 2 minutes and are never served in between. `latitude` and `longitude` on a spot are the coordinates of the referenced park or summit (the POTA park catalog centroid or the SOTA activation zone centroid), not of the spotter. They are present only when the park catalog has been synced (POTA) or an activation zone has been computed for that summit (SOTA).

#### List spots

```
GET /v1/spots
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `program` | string | no | | Exact match on `programSlug` (for example `pota`, `sota`). Case-sensitive. |
| `callsign` | string | no | | Exact match on `callsign`. Not upper-cased by the server. |
| `source` | enum | no | | One of `pota`, `rbn`, `sota`, `self`, `other`. Any other value answers with a plain-text 400. |
| `mode` | string | no | | Exact match on `mode` (for example `CW`, `SSB`). |
| `state` | string | no | | Exact match on `stateAbbr` (for example `WY`). |
| `maxAgeMinutes` | int | no | 30 | Only spots with `spottedAt` within the last N minutes. Clamped to 1 to 1440. |
| `limit` | int | no | 100 | Page size. Clamped to 1 to 250. |
| `cursor` | string | no | | RFC 3339 timestamp from a previous `pagination.nextCursor`. Returns spots with `spottedAt` strictly older. An unparsable cursor is ignored. |

**Response** `200 OK`, ordered by `spottedAt` descending. Only unexpired spots are returned.

```json
{
  "data": {
    "spots": [
      {
        "id": "7a0a9d0e-6e7d-4c2a-9a62-0c7f8e1a2b3c",
        "callsign": "W1AW",
        "programSlug": "pota",
        "source": "pota",
        "frequencyKhz": 14062.0,
        "mode": "CW",
        "reference": "US-1234",
        "referenceName": "Example State Park",
        "spotter": "K1ABC",
        "spotterGrid": "FN42",
        "locationDesc": "US-WY",
        "countryCode": "US",
        "stateAbbr": "WY",
        "comments": "QRP",
        "snr": 18,
        "wpm": 25,
        "latitude": 42.86,
        "longitude": -106.31,
        "spottedAt": "2026-10-10T14:02:11Z",
        "expiresAt": "2026-10-10T14:32:11Z"
      }
    ],
    "pagination": {
      "hasMore": true,
      "nextCursor": "2026-10-10T14:02:11+00:00"
    }
  }
}
```

Optional fields (`programSlug`, `reference`, `referenceName`, `spotter`, `spotterGrid`, `locationDesc`, `countryCode`, `stateAbbr`, `comments`, `snr`, `wpm`, `latitude`, `longitude`) are omitted when null. `frequencyKhz` is kHz, `snr` is dB, `wpm` is words per minute. `nextCursor` is the last returned `spottedAt`, formatted with a `+00:00` offset rather than `Z`. No caching headers are set.

**Errors**

| Code | HTTP | When |
|---|---|---|
| (plain text) | 400 | Malformed query value (`source` not in the enum, non-integer `limit` or `maxAgeMinutes`). |
| `INTERNAL_ERROR` | 500 | Database failure. |

#### Create a self-spot

```
POST /v1/spots
```

**Auth:** Bearer (first-party). The callsign and participant come from the token.

**Request**

```json
{
  "programSlug": "pota",
  "frequencyKhz": 14062.0,
  "mode": "CW",
  "reference": "US-1234",
  "comments": "QRP from the summit"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `programSlug` | string | yes | Must name an existing program that supports the `selfSpot` capability. |
| `frequencyKhz` | number | yes | Frequency in kHz. Not range-checked by the server. |
| `mode` | string | yes | Free text, stored as sent. |
| `reference` | string | no | Park or summit reference. Used to resolve coordinates in `GET /v1/spots`. |
| `comments` | string | no | Free text. |

**Response** `201 Created` with `{"data": <Spot>}` in the same shape as the list endpoint. `source` is `"self"`, `expiresAt` is 30 minutes after creation, and `spotter`, `snr`, `wpm`, `latitude` and `longitude` are absent. Coordinates appear once the spot is read back through `GET /v1/spots`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer. |
| `VALIDATION_ERROR` | 400 | Body is not valid JSON for the schema. |
| `PROGRAM_NOT_FOUND` | 404 | `programSlug` is unknown. `details: {"slug"}`. |
| `CAPABILITY_NOT_SUPPORTED` | 422 | The program does not support self-spotting. `details: {"capability": "selfSpot", "programSlug"}`. |
| `SELF_SPOT_EXISTS` | 409 | The caller already has an unexpired self-spot for this program. Delete it first or wait for it to expire. |

#### Delete your own self-spot

```
DELETE /v1/spots/:id
```

**Auth:** Bearer (first-party).

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | UUID | yes | Spot id. The spot must have been submitted by the caller. |

**Response** `204 No Content`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer. |
| `VALIDATION_ERROR` | 400 | `id` is not a UUID. |
| `SPOT_NOT_FOUND` | 404 | No spot with that id belongs to the caller. Also returned for other users' spots and for aggregated spots. `details: {"spotId"}`. |

#### Create a spot marker (SMS spotting)

```
POST /v1/spot-markers
```

**Auth:** Bearer (first-party). No request body.

Generates a 6-character marker from the alphabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no I, O, 0 or 1) bound to the caller's callsign. Each call replaces any existing marker for that callsign, so the previous marker stops working.

**Response** `201 Created`

```json
{
  "data": {
    "marker": "K7Q2ZX",
    "callsign": "W1AW",
    "createdAt": "2026-10-10T14:00:00Z"
  }
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer. |
| `INTERNAL_ERROR` | 500 | Database failure. |

**Notes:** The marker is the first token of the text message: `MARKER REFERENCE FREQUENCY MODE [COMMENTS]`, for example `K7Q2ZX US-1234 14.062 CW calling cq`.

### Reverse Beacon Network

The server keeps a live telnet session to `telnet.reversebeacon.net:7000` and holds the last hour of spots in memory. Only `CQ` and `DX` spot types are kept; beacon and NCDXF spots are dropped. Spots whose frequency falls outside the HF and 6 m amateur bands are dropped as well, so `band` is always one of `160m`, `80m`, `60m`, `40m`, `30m`, `20m`, `17m`, `15m`, `12m`, `10m` or `6m`. Nothing is persisted: the window is at most the last hour and is empty immediately after a server restart.

All three endpoints return bare JSON with snake_case field names and set no caching headers. When the RBN feed is disabled on the server they return empty results rather than an error.

#### RBN spots

```
GET /v1/rbn/spots
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `call` | string | no | | Spotted callsign, case-insensitive exact match. |
| `spotter` | string | no | | Skimmer callsign (for example `KM3T-#`), case-insensitive exact match. |
| `mode` | string | no | | Comma-separated list (`CW,RTTY`), case-insensitive. A spot matches if its mode is in the list. |
| `band` | string | no | | Band label, case-insensitive (`20m`). |
| `min_freq` | number | no | | Lower bound in kHz, inclusive. |
| `max_freq` | number | no | | Upper bound in kHz, inclusive. |
| `since` | RFC 3339 datetime | no | now minus 1 hour | Only spots with `timestamp >= since`. Cannot reach further back than the 1-hour window. |
| `limit` | int | no | 100 | Capped at 500. |

**Response** `200 OK`, newest first.

```json
{
  "total": 1342,
  "spots": [
    {
      "id": 48213,
      "callsign": "W1AW",
      "frequency": 14039.8,
      "mode": "CW",
      "snr": 18,
      "wpm": 25,
      "spotter": "KM3T-#",
      "band": "20m",
      "timestamp": "2026-10-10T14:02:11Z"
    }
  ]
}
```

`total` is the number of matching spots before `limit` is applied. `id` is a counter that resets when the server restarts. `frequency` is kHz. `snr` is dB and is `0` when the upstream line did not carry one. `wpm` is omitted when absent.

**Errors**

| Code | HTTP | When |
|---|---|---|
| (plain text) | 400 | Non-numeric `min_freq`, `max_freq` or `limit`, or unparsable `since`. |

#### RBN stats

```
GET /v1/rbn/stats
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `minutes` | int | no | 60 | Window ending now. Clamped to 1 to 60. |

**Response** `200 OK`

```json
{
  "minutes": 60,
  "total_spots": 5120,
  "spots_per_minute": 85.33,
  "bands": { "20m": 2100, "40m": 1600, "15m": 900 },
  "modes": { "CW": 4800, "RTTY": 220, "FT8": 100 }
}
```

`bands` and `modes` map a label to a count. Key order is unspecified.

#### RBN skimmers

```
GET /v1/rbn/skimmers
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `minutes` | int | no | 60 | Window ending now. Clamped to 1 to 60. |
| `limit` | int | no | 100 | Maximum skimmers returned. Capped at 500. |

**Response** `200 OK`, sorted by `spot_count` descending.

```json
{
  "minutes": 60,
  "count": 212,
  "skimmers": [
    {
      "callsign": "KM3T-#",
      "spot_count": 310,
      "last_spot": "2026-10-10T14:02:11Z",
      "bands": ["20m", "40m", "15m"]
    }
  ]
}
```

`count` is the number of distinct active skimmers before `limit`. `bands` lists bands in first-seen order.

### WebSDR proxies

These three endpoints exist so that a browser page served over HTTPS can load the KiwiSDR public directory, probe a receiver's status, and open a receiver's audio socket without running into cross-origin or mixed-content restrictions. Only hosts that resolve to public unicast addresses can be proxied; private, loopback, link-local, carrier-grade NAT and similar ranges are refused. Redirects from the target receiver are not followed by the status probe.

#### KiwiSDR directory

```
GET /v1/websdr/directory
```

**Auth:** Public (optional bearer; no behaviour change). No parameters.

**Response** `200 OK` with `Content-Type: application/javascript; charset=utf-8`. The body is the raw JavaScript of `https://rx.skywavelinux.com/kiwisdr_com.js` (about 1 MB). The server caches it in memory for 1 hour and collapses concurrent cache misses into a single upstream fetch. No `ETag` or `Cache-Control` headers are set. Clients parse the JavaScript themselves.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INTERNAL_ERROR` | 500 | The upstream fetch failed or returned a non-2xx status (`"websdr directory fetch failed: ..."`). A stale cached copy is not served on failure. |

#### Receiver status probe

```
GET /v1/websdr/status
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Description |
|---|---|---|---|
| `host` | string | yes | Hostname or IPv4 literal (IPv6 literals are rejected). 1 to 253 characters of `[A-Za-z0-9.-]`, not starting with `-` or `.`. |
| `port` | integer | yes | Must be 80, 443, or 1024 or above. |

**Response** `200 OK` with `Content-Type: text/plain; charset=utf-8`. The body is the receiver's `http://host:port/status` response verbatim (KiwiSDR `key=value` lines). The upstream request times out after 5 s. No caching headers are set.

**Errors**

| Code | HTTP | When |
|---|---|---|
| (plain text) | 400 | `host` or `port` missing, or `port` not a 16-bit integer. |
| `VALIDATION_ERROR` | 400 | `message` is one of `invalid host`, `invalid port`, `host must be a public address`, `host does not resolve`, `host resolves to a non-public address`. |
| `INTERNAL_ERROR` | 500 | Receiver unreachable, timed out, or returned a non-2xx status. |

#### Audio stream bridge (WebSocket)

```
GET /v1/websdr/stream
```

**Auth:** Public (optional bearer; no behaviour change). Browsers cannot send an `Authorization` header on a WebSocket handshake.

**Handshake:** a standard HTTP/1.1 WebSocket upgrade (`Upgrade: websocket`, `Sec-WebSocket-Key`, and so on) with query parameters:

| Param | Type | Required | Description |
|---|---|---|---|
| `host` | string | yes | Same rules as `/v1/websdr/status`. |
| `port` | integer | yes | Same rules as `/v1/websdr/status`. |

Host validation runs before the upgrade, so a rejected host answers with a normal `400 VALIDATION_ERROR` JSON response, not a WebSocket close. A request without upgrade headers answers with a plain-text 400.

**After the upgrade:**

1. The server warms up the receiver by fetching `/`, `/kiwisdr.min.js`, `/config/config.js` and `/status` from its own address, with a 4 s deadline. This raises the Kiwi's per-client page counter so the audio socket is not kicked with `MSG too_busy` after 10 s. Warm-up failures are ignored.
2. It connects upstream to `ws://host:port/ws/kiwi/<unix_ts>/SND` (current firmware). If that handshake is rejected it falls back to `ws://host:port/<unix_ts>/SND` (legacy firmware). Each attempt has a 10 s connect timeout and follows up to 3 HTTP redirects (the kiwisdr.com proxy answers with 307s), re-validating every redirect target against the public-address rule and preserving path case.
3. If the upstream connection fails the server sends one Text frame to the browser and then closes:
   - `MSG cw_proxy_error=connect_timeout`
   - `MSG cw_proxy_error=connect_failed` (handshake rejected, too many redirects, or an unparsable redirect)
   - `MSG cw_proxy_error=redirect_blocked` (a redirect pointed at a non-public target)
4. On success the socket is a transparent byte pipe. Text, Binary, Ping and Pong frames are forwarded unchanged in both directions, and a Close from either side closes the other. Nothing is interpreted: the browser speaks the KiwiSDR `SND` protocol end to end, and the server never sends `SET auth`, `SET mod`, keepalives or anything else on its own.

The error Text frame above is the only message the server originates.

**Errors**

| Code | HTTP | When |
|---|---|---|
| (plain text) | 400 | Missing or invalid `host` or `port`, or not a WebSocket request. |
| `VALIDATION_ERROR` | 400 | Host validation (see the status probe). |

**Notes:** The 1 MiB request body limit does not apply to WebSocket frames.

### POTA statistics

Activation and hunter statistics for Parks on the Air, built from the POTA park catalog (`https://pota.app/all_parks_ext.csv`) and the public POTA API. The catalog is resynced once every 24 hours and per-park statistics are refreshed on a rolling 24-hour cycle, so the dataset is usually a little behind POTA itself.

All responses are `{"data": ...}` wrapped with camelCase fields. Every response includes a `freshness` object describing how far the current collection cycle has progressed:

```json
"freshness": {
  "oldestFetch": "2026-10-09T02:00:00Z",
  "newestFetch": "2026-10-10T13:55:00Z",
  "parksPending": 120,
  "totalParks": 72000,
  "warning": "Data collection in progress (99% complete, 71880 of 72000 parks fetched). Stats may be incomplete."
}
```

`warning` is omitted when collection is complete. It reads `"Park catalog has not been synced yet. Stats are unavailable."` when `totalParks` is `0`. `oldestFetch` and `newestFetch` are `null` until any park has been fetched. When a query has a `state`, `freshness` is scoped to that state.

Callsigns, states and park references are upper-cased by the server before lookup. Unknown callsigns and states return zeros with HTTP 200. Only unknown park references answer 404.

#### Activator stats

```
GET /v1/pota/stats/activator
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Description |
|---|---|---|---|
| `callsign` | string | yes | Activator callsign. |
| `state` | string | no | Restrict ranking and totals to parks in this state (abbreviation such as `WY`). |
| `mode` | string | no | `cw`, `data` or `phone` (case-insensitive). Ranks by that mode's QSO count only. |

**Response** `200 OK`

```json
{
  "data": {
    "callsign": "W1AW",
    "activationCount": 42,
    "totalQsos": 1830,
    "qsosByMode": { "cw": 1200, "data": 300, "phone": 330 },
    "rank": 17,
    "totalRanked": 25000,
    "state": "WY",
    "modeFilter": "cw",
    "freshness": { ... }
  }
}
```

`state` and `modeFilter` are echoed only when supplied. When `mode` is given, `activationCount` is `0` and only the selected mode in `qsosByMode` is populated. `rank` and `totalRanked` are `0` for an unranked callsign.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `mode` is not `cw`, `data` or `phone` (`"Invalid mode 'x'. Must be cw, data, or phone."`). |
| (plain text) | 400 | `callsign` missing. |

#### Hunter stats

```
GET /v1/pota/stats/hunter
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Description |
|---|---|---|---|
| `callsign` | string | yes | Hunter callsign. |
| `state` | string | no | Restrict to parks in this state. |

**Response** `200 OK`

```json
{
  "data": {
    "callsign": "W1AW",
    "totalQsos": 980,
    "rank": 240,
    "totalRanked": 110000,
    "state": "WY",
    "freshness": { ... }
  }
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| (plain text) | 400 | `callsign` missing. |

#### State stats

```
GET /v1/pota/stats/state/:state
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Description |
|---|---|---|---|
| `state` | string | yes | State abbreviation. Upper-cased. |

**Response** `200 OK`. Top lists hold at most 10 entries.

```json
{
  "data": {
    "state": "WY",
    "totalActivations": 5400,
    "uniqueActivators": 610,
    "totalQsos": 260000,
    "topActivators": [ { "callsign": "W7XYZ", "count": 310 } ],
    "topHunters": [ { "callsign": "K0ABC", "count": 1200 } ],
    "freshness": { ... }
  }
}
```

`count` is activations for `topActivators` and QSOs for `topHunters`. An unknown state returns zeros and empty lists.

#### Park stats

```
GET /v1/pota/stats/park/:reference
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Description |
|---|---|---|---|
| `reference` | string | yes | POTA reference (for example `US-1234`, `K-1234`). Upper-cased. |

**Response** `200 OK`

```json
{
  "data": {
    "reference": "US-1234",
    "name": "Example State Park",
    "locationDesc": "US-WY",
    "state": "WY",
    "latitude": 42.86,
    "longitude": -106.31,
    "grid": "DN62",
    "active": true,
    "totalAttempts": 120,
    "totalActivations": 98,
    "totalQsos": 4300,
    "topActivators": [ { "callsign": "W7XYZ", "count": 12 } ],
    "topHunters": [ { "callsign": "K0ABC", "count": 40 } ],
    "freshness": { ... }
  }
}
```

`locationDesc`, `state`, `latitude`, `longitude` and `grid` are omitted when null.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `PARK_NOT_FOUND` | 404 | Reference is not in the synced catalog. `details: {"reference"}`. |

#### Activator rankings

```
GET /v1/pota/stats/rankings/activators
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `state` | string | no | | Restrict to parks in this state. |
| `limit` | int | no | 25 | Clamped to 1 to 100. |
| `offset` | int | no | 0 | Negative values become 0. |

**Response** `200 OK`

```json
{
  "data": {
    "rankings": [
      {
        "callsign": "W7XYZ",
        "activationCount": 310,
        "totalQsos": 14000,
        "qsosByMode": { "cw": 9000, "data": 2000, "phone": 3000 },
        "rank": 1
      }
    ],
    "totalRanked": 25000,
    "state": "WY",
    "freshness": { ... }
  }
}
```

#### POTA stats sync status

```
GET /v1/pota/stats/status
```

**Auth:** Public (optional bearer; no behaviour change). No parameters.

**Response** `200 OK`

```json
{
  "data": {
    "totalParks": 72000,
    "parksFetched": 71880,
    "parksPending": 120,
    "completionPercentage": 99,
    "oldestFetch": "2026-10-09T02:00:00Z",
    "newestFetch": "2026-10-10T13:55:00Z",
    "warning": "Data collection in progress (99% complete, 71880 of 72000 parks fetched). Stats may be incomplete."
  }
}
```

`oldestFetch`, `newestFetch` and `warning` are omitted when null. `completionPercentage` is an integer (rounded down).

### Park and administrative boundaries

Park polygons for POTA references, US state and county polygons, and SOTA activation-zone polygons. Boundary responses are bare GeoJSON with no `data` wrapper, camelCase property names and no caching headers. Responses can be large; use `simplify` for viewport queries.

**Park boundary feature shape**

```json
{
  "type": "Feature",
  "geometry": { "type": "MultiPolygon", "coordinates": [[[[-106.4, 42.8], [-106.3, 42.8], [-106.3, 42.9], [-106.4, 42.8]]]] },
  "properties": {
    "reference": "US-1234",
    "name": "Example State Park",
    "designation": "State Park",
    "manager": "Wyoming State Parks",
    "acreage": 1234.5,
    "matchQuality": "exact",
    "source": "padus"
  }
}
```

`designation`, `manager` and `acreage` are omitted when null. `matchQuality` is `exact`, `spatial` or `manual`; parks for which no polygon could be found are never returned. `source` tags the upstream dataset the polygon came from. Polygons come from PAD-US, Natural England and WDPA feature services, from state agencies for Florida, Oregon, California and Texas, and from the Polish GDOŚ WFS (national parks, landscape parks, reserves, protected landscape areas and Natura 2000 sites). Stored geometry is pre-simplified at a 0.001 degree tolerance. The collection runs on a 24-hour cycle and re-fetches a park's polygon after 90 days.

#### List park boundaries

```
GET /v1/parks/boundaries
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `refs` | string | one of `refs`, `bbox` | | Comma-separated POTA references, upper-cased, blanks dropped. Maximum 20. Takes priority over `bbox`; `limit` and `simplify` are ignored in refs mode. |
| `bbox` | string | one of `refs`, `bbox` | | `west,south,east,north` in decimal degrees (WGS 84 / EPSG:4326). Non-numeric parts are dropped; exactly 4 numbers must remain. Matches parks whose stored geometry's bounding box intersects the box. |
| `limit` | int | no | 50 | bbox mode only. Clamped to 1 to 100. Results are ordered by `reference`. |
| `simplify` | number | no | | bbox mode only. Douglas-Peucker tolerance in degrees, applied to the full-resolution geometry. Without it the stored pre-simplified geometry is returned. |

**Response** `200 OK`

```json
{
  "type": "FeatureCollection",
  "features": [ { "type": "Feature", "geometry": { ... }, "properties": { ... } } ],
  "meta": { "matched": 2, "unmatchedRefs": ["US-9999"] }
}
```

`meta.unmatchedRefs` lists requested references with no polygon, and is populated only in refs mode; it is `[]` in bbox mode. `meta.matched` equals `features.length`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Neither parameter (`"Either 'refs' or 'bbox' parameter is required"`), more than 20 refs (`"Maximum 20 refs per request"`), or bbox not 4 numbers (`"bbox must be 'west,south,east,north' (4 numbers)"`). |
| (plain text) | 400 | Non-numeric `limit` or `simplify`. |

#### Get one park boundary

```
GET /v1/parks/boundaries/:reference
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Description |
|---|---|---|---|
| `reference` | string | yes | POTA reference. Upper-cased. |

**Response** `200 OK`, a single Feature (shape above) with full-resolution geometry.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `PARK_NOT_FOUND` | 404 | No polygon is cached for the reference. `details: {"reference"}`. |

#### Park boundaries status

```
GET /v1/parks/boundaries/status
```

**Auth:** Public (optional bearer; no behaviour change). No parameters.

**Response** `200 OK`, `{"data": ...}` wrapped.

```json
{
  "data": {
    "totalParks": 80500,
    "totalCached": 61000,
    "unfetched": 9000,
    "completionPercentage": 88,
    "byCountry": {
      "us": { "totalParks": 72000 },
      "uk": { "totalParks": 2600 },
      "it": { "totalParks": 2400 },
      "pl": { "totalParks": 3500 }
    },
    "bySource": { "padus": 55000, "natural_england": 1200 },
    "exactMatches": 50000,
    "spatialMatches": 10000,
    "manualMatches": 1000,
    "noMatches": 10500,
    "oldestFetch": "2026-07-01T00:00:00+00:00",
    "newestFetch": "2026-10-10T13:00:00+00:00"
  }
}
```

`totalParks` is the sum of the US, UK, IT and PL catalog counts. `unfetched` is `totalParks - (totalCached + noMatches)`, and `completionPercentage` is `(totalCached + noMatches) * 100 / totalParks`. `oldestFetch` and `newestFetch` are RFC 3339 strings or `null` (not omitted). `bySource` keys are source tags; the values shown are illustrative.

#### List administrative boundaries

```
GET /v1/admin/boundaries
```

**Auth:** Public (optional bearer; no behaviour change). This path is public despite the `/admin/` prefix; no operator token is needed.

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `bbox` | string | yes | | `west,south,east,north` in decimal degrees (EPSG:4326). Matches boundaries whose stored geometry's bounding box intersects the box. |
| `kind` | string | no | | `state` or `county`. Omitted or empty returns both. |
| `limit` | int | no | 500 | Clamped to 1 to 4000. Results are ordered by `kind`, then `fips`. |
| `simplify` | number | no | | Extra Douglas-Peucker tolerance in degrees applied on top of the stored geometry, which is itself simplified at 0.002 degrees. |

**Response** `200 OK`, bare GeoJSON.

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "MultiPolygon", "coordinates": [ ... ] },
      "properties": {
        "id": "county-06037",
        "kind": "county",
        "name": "Los Angeles",
        "stateName": "California",
        "fips": "06037"
      }
    }
  ],
  "meta": { "matched": 1 }
}
```

`fips` is 2 digits for states and 5 for counties. `stateName` is omitted when null, which is the case for state features.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `bbox` missing (`"'bbox' parameter is required"`), not 4 numbers, or `kind` not `state` or `county` (`"kind must be 'state' or 'county'"`). |
| (plain text) | 400 | Non-numeric `limit` or `simplify`. |

**Notes:** The data is the US Census Bureau's 1:500,000 cartographic boundary set (2023 vintage, public domain). It is loaded manually rather than by a background refresh, and changes rarely. No caching headers are set.

#### SOTA activation zones

```
POST /v1/sota/zones
```

**Auth:** Bearer (first-party). Submissions are attributed to the account and rate limited per account. The zones feed the coordinates on `GET /v1/spots`, which remains public.

Returns cached activation-zone polygons for the requested summits and queues computation for summits that have not been seen before. Zones are computed from Terrarium elevation tiles and cached permanently per summit code.

**Request**

```json
{
  "summits": [
    { "code": "W7W/KI-001", "lat": 47.65, "lon": -121.85, "altitudeM": 1612.0 }
  ]
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `summits[].code` | string | yes | SOTA reference `PREFIX/REGION-NUMBER` (alphanumeric prefix and region, numeric suffix), at most 16 characters. Used as the cache key. |
| `summits[].lat` | number | yes | -90 to 90. |
| `summits[].lon` | number | yes | -180 to 180. |
| `summits[].altitudeM` | number | no | Summit altitude in metres. Stored with the zone. |

Entries that fail validation are dropped without error, and the list is truncated to the first 400 valid summits. At most 8 not-yet-seen codes per request are queued for computation in the background.

**Response** `200 OK`, bare GeoJSON.

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Polygon", "coordinates": [ [ [-121.86, 47.64], [-121.84, 47.64], [-121.84, 47.66], [-121.86, 47.64] ] ] },
      "properties": { "code": "W7W/KI-001", "altitudeM": 1612.0 }
    }
  ],
  "meta": { "matched": 1, "pending": ["W7W/KI-002"] }
}
```

`features` holds only zones whose computation has finished successfully. `meta.pending` lists codes queued by this request; re-request shortly to pick them up. Codes that computed to "no zone", or that are still pending from an earlier request, appear in neither list.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer. |
| `VALIDATION_ERROR` | 400 | Body is not valid JSON for the schema (for example missing `summits`). |
| `INTERNAL_ERROR` | 500 | Database failure while reading or queueing. |

**Notes:** When zone computation is disabled on the server, new codes are not queued but cached zones are still returned. A transient computation failure is retried on a later request; a "no zone" result is cached permanently. Cached zones are not recomputed. 400 summits fit comfortably within the 1 MiB body limit.

### Historic trails

National historic and scenic trails as GeoJSON `MultiLineString` features, with the same request contract as park boundaries. The catalog holds 19 trails sourced from the USGS National Map transportation layer and the NTIR per-trail feature services. Collection runs weekly and re-fetches a trail after 180 days. Stored geometry is simplified at a 0.005 degree tolerance. Responses are bare GeoJSON with no caching headers.

**Trail feature shape**

```json
{
  "type": "Feature",
  "geometry": { "type": "MultiLineString", "coordinates": [ ... ] },
  "properties": {
    "reference": "NHT-OREG",
    "name": "Oregon National Historic Trail",
    "designation": "National Historic Trail",
    "managingAgency": "National Park Service",
    "lengthMiles": 2170.0,
    "state": "MO,KS,NE,WY,ID,OR",
    "matchQuality": "exact",
    "source": "usgs_national_map"
  }
}
```

`designation`, `managingAgency`, `lengthMiles` and `state` are omitted when null. References follow the `NHT-XXXX` scheme. `source` tags the upstream dataset.

#### List trails

```
GET /v1/trails
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Default | Description |
|---|---|---|---|---|
| `refs` | string | one of `refs`, `bbox` | | Comma-separated trail references, upper-cased. Maximum 20. Takes priority over `bbox`; `limit` and `simplify` are ignored. |
| `bbox` | string | one of `refs`, `bbox` | | `west,south,east,north` in decimal degrees. Bounding-box intersection against the stored geometry. |
| `limit` | int | no | 50 | bbox mode only. Clamped to 1 to 100. Ordered by `reference`. |
| `simplify` | number | no | | bbox mode only. Tolerance in degrees, applied to the full-resolution geometry. |

**Response** `200 OK`: `{ "type": "FeatureCollection", "features": [...], "meta": { "matched": n, "unmatchedRefs": [...] } }`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Neither `refs` nor `bbox`; more than 20 refs; bbox not 4 numbers. |

#### Get one trail

```
GET /v1/trails/:reference
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Description |
|---|---|---|---|
| `reference` | string | yes | Trail reference. Upper-cased. |

**Response** `200 OK`, a single Feature with full-resolution geometry.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `TRAIL_NOT_FOUND` | 404 | No geometry is cached for the reference. `details: {"reference"}`. |

#### Trails status

```
GET /v1/trails/status
```

**Auth:** Public (optional bearer; no behaviour change). No parameters. The same data is also served at the operator-only `GET /v1/admin/trails/status`.

**Response** `200 OK`, `{"data": ...}` wrapped.

```json
{
  "data": {
    "totalCatalog": 19,
    "totalCached": 18,
    "unfetched": 1,
    "completionPercentage": 94,
    "exactMatches": 16,
    "spatialMatches": 1,
    "manualMatches": 1,
    "oldestFetch": "2026-09-01T00:00:00+00:00",
    "newestFetch": "2026-10-08T00:00:00+00:00"
  }
}
```

Unlike the park status there is no `noMatches` field; `unfetched` is `totalCatalog - totalCached`. Fetch timestamps are RFC 3339 strings or `null`.

### Satellites

#### AMSAT status

```
GET /v1/satellites/amsat-status
```

**Auth:** Public (optional bearer; no behaviour change). No parameters.

A mirror of the AMSAT status page (`https://status.amsat.org/`, read through its `/api/v1`), refreshed every 30 minutes, one row per transmitter name. The `*24h` counters cover reports in the last 24 hours, drawn from a 168-hour report window. The report data is AMSAT's (CC BY 4.0): display it with the attribution *Satellite status data: AMSAT, https://status.amsat.org*.

**Response** `200 OK`, bare object with camelCase fields.

```json
{
  "satellites": [
    {
      "name": "SO-50_[FM]",
      "noradId": 27607,
      "lastHeardAt": "2026-10-10T13:30:00Z",
      "lastReportedAt": "2026-10-10T14:30:00Z",
      "lastReport": "Heard",
      "lastCallsign": "ON7VQ",
      "lastGrid": "JO20gv",
      "heardReports24h": 7,
      "totalReports24h": 9
    }
  ],
  "updatedAt": "2026-10-10T15:00:12.412Z"
}
```

`noradId`, `lastHeardAt`, `lastReportedAt`, `lastReport`, `lastCallsign`, `lastGrid` and the top-level `updatedAt` are omitted when null. `updatedAt` is the time of the most recent update across all satellites. No caching headers are set.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INTERNAL_ERROR` | 500 | Database failure. |

### Callsign enrichment

Club membership lookups keyed by callsign. The only source today is the CWops membership roster, refreshed every 24 hours. Field names in this group are snake_case, and the bulk dataset uses single-character keys to keep it small.

#### Get the enrichment dataset

```
GET /v1/callsign-enrichment/dataset
```

**Auth:** Public (optional bearer; no behaviour change). No parameters.

**Caching:** the response carries `ETag: "cwe-<unix milliseconds of the most recent source fetch>"` and `Cache-Control: public, max-age=3600`. Send the ETag back in `If-None-Match` to receive `304 Not Modified` with an empty body and the same `ETag` header. The comparison is an exact string match: weak validators and comma-separated lists are not parsed. Until the first source sync has completed the ETag is derived from the current time and changes on every request.

**Response** `200 OK` with `Content-Type: application/json`.

```json
{
  "sources": [
    { "slug": "cwops", "name": "CWops", "emoji": "🎹", "last_fetched_at": "2026-10-10T12:00:00Z" }
  ],
  "callsigns": [
    { "c": "AA0FO", "m": [ { "s": "cwops", "n": "MARSHALL R", "#": "1532" } ] }
  ],
  "generated_at": "2026-10-10T12:00:00Z"
}
```

| Key | Meaning |
|---|---|
| `sources[].slug`, `name`, `emoji`, `last_fetched_at` | Per-source metadata. `emoji` and `last_fetched_at` are nullable and serialised as `null`. |
| `callsigns[].c` | Upper-case callsign. |
| `callsigns[].m[]` | Memberships: `s` source slug (always present), `n` name, `#` member number (digits), `e` per-row emoji override, `t` free-form note. `n`, `#`, `e` and `t` are omitted when null. |
| `generated_at` | The instant the ETag is derived from. |

**Errors**

| Code | HTTP | When |
|---|---|---|
| `INTERNAL_ERROR` | 500 | Database or serialisation failure. |

#### Look up one callsign

```
GET /v1/callsign-enrichment/:callsign
```

**Auth:** Public (optional bearer; no behaviour change).

| Param | Type | Required | Description |
|---|---|---|---|
| `callsign` | string | yes | Upper-cased before lookup. |

**Response** `200 OK`. Nullable fields are serialised as `null`, not omitted.

```json
{
  "callsign": "AA0FO",
  "memberships": [
    {
      "source_slug": "cwops",
      "source_name": "CWops",
      "emoji": "🎹",
      "name": "MARSHALL R",
      "member_number": "1532",
      "note": null
    }
  ]
}
```

`emoji` is the per-member override when present, otherwise the source's emoji. An unknown callsign returns `200` with `memberships: []`, never 404. No caching headers are set.

**Notes:** `dataset` is reserved and is never treated as a callsign.

### Propagation predictions

HF propagation predictions from a DVOACAP-based prediction service that runs alongside the API. These endpoints take no credentials: no bearer or operator token is read, and only the global rate limit applies. When predictions are disabled on the server the routes are not mounted and answer `404` with `{"error": {"code": "NOT_FOUND", "message": "Endpoint not found"}}`.

Both endpoints share the same proxy and cache behaviour:

1. The request is parsed, defaults are filled in, and the result is serialised to canonical JSON with sorted keys.
2. The canonical body is the cache key, so omitting `tx_power_w` and sending `100` hit the same cache entry.
3. A cached result younger than 24 hours is returned as-is.
4. Otherwise the request is forwarded to the prediction service with a 30 s timeout. A `422` from the prediction service becomes `400 VALIDATION_ERROR` whose `message` is the service's response text. Any other non-2xx status or transport error becomes `500 INTERNAL_ERROR`.
5. Successful results are cached for 24 hours.

Field names are snake_case. Malformed JSON bodies answer with a plain-text `400`, `415` or `422`.

#### Point-to-point prediction

```
POST /v1/propagation/p2p
```

**Auth:** None.

**Request**

```json
{
  "tx_lat": 42.0, "tx_lon": -71.0,
  "rx_lat": 51.5, "rx_lon": -0.1,
  "month": 4,
  "utc_hour": 14.0,
  "ssn": 120,
  "tx_power_w": 100,
  "frequencies_mhz": [3.5, 7.0, 14.1, 21.0, 28.0]
}
```

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `tx_lat`, `tx_lon`, `rx_lat`, `rx_lon` | number | yes | | Degrees. |
| `month` | integer | yes | | 1 to 12. |
| `utc_hour` | number | yes | | Hour of day UTC. Fractional values are allowed. |
| `ssn` | number | yes | | Smoothed sunspot number. |
| `tx_power_w` | number | no | `100.0` | Transmit power in watts. |
| `frequencies_mhz` | number[] | no | | Frequencies to evaluate in MHz. When omitted the prediction service uses its default band set. |

**Response** `200 OK`, bare object. Nullable fields are serialised as `null`.

```json
{
  "muf_mhz": 22.0,
  "path": { "distance_km": 5272.1, "bearing_deg": 49.3 },
  "bands": [
    {
      "freq_mhz": 14.1,
      "hop_count": 2,
      "tx_elevation_deg": 12.4,
      "total_loss_db": 132.7,
      "snr_db": 6.1,
      "reliability": 0.71,
      "service_prob": 0.68,
      "multipath_prob": 0.22
    }
  ]
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| (plain text) | 400 / 415 / 422 | Body missing, wrong content type, or not matching the schema. |
| `VALIDATION_ERROR` | 400 | The prediction service rejected the inputs. Its message is passed through as `message`. |
| `INTERNAL_ERROR` | 500 | Prediction service unreachable or timed out, a non-2xx status other than 422, or an undecodable response. |
| `NOT_FOUND` | 404 | Predictions are disabled on the server. |

#### Propagation wheel

```
POST /v1/propagation/wheel
```

**Auth:** None.

Predicts outward from a centre point along evenly spaced azimuths.

**Request**

```json
{
  "lat": 42.0, "lon": -71.0,
  "month": 4, "utc_hour": 14.0, "ssn": 120,
  "tx_power_w": 100,
  "radius_km": 5000,
  "azimuth_step_deg": 15,
  "frequencies_mhz": [7.0, 14.1, 21.0]
}
```

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `lat`, `lon` | number | yes | | Centre, in degrees. |
| `month`, `utc_hour`, `ssn` | as p2p | yes | | |
| `tx_power_w` | number | no | `100.0` | Transmit power in watts. |
| `radius_km` | number | no | `5000.0` | Distance of each spoke's receive point, in km. |
| `azimuth_step_deg` | number | no | `15.0` | Spacing between spokes in degrees. The default gives 24 spokes. |
| `frequencies_mhz` | number[] | no | | Frequencies to evaluate in MHz. |

**Response** `200 OK`

```json
{
  "centre_lat": 42.0,
  "centre_lon": -71.0,
  "radius_km": 5000.0,
  "spokes": [
    { "azimuth_deg": 0.0, "rx_lat": 86.9, "rx_lon": -71.0, "bands": [ /* same band objects as p2p */ ] }
  ]
}
```

**Errors:** identical to the point-to-point endpoint.

### Operator endpoints

These require an operator token and are not available to third-party clients.

| Method | Path | Purpose |
|---|---|---|
| `DELETE` | `/v1/admin/spots/:id` | Delete any spot regardless of source or owner. Aggregated POTA and SOTA spots reappear on the next poll if upstream still lists them. |
| `GET` | `/v1/admin/trails/status` | Same response as `GET /v1/trails/status`. |

## Events

Community-submitted on-air events: club meetings, hamfests, nets, field days and similar. Anyone can search approved events near a location. Signed-in users submit events, and an operator reviews each one before it appears publicly.

All event JSON uses camelCase, including query parameters.

### Review lifecycle

`status` is one of `pending`, `approved` or `rejected`.

- A new submission starts as `pending`.
- Only an operator moves an event to `approved` or `rejected`. Review is allowed from any status, so a rejected event can later be approved and an approved event can be rejected. On review the server sets `reviewedBy` to `"admin"` and `reviewedAt` to the current time. A rejection stores `rejectionReason`; an approval resets it to `null`.
- When the submitter edits an approved event and changes a key field (`name`, `description`, `address`, `venueName`, `latitude` or `longitude`), the event returns to `pending` and `reviewedBy` and `reviewedAt` are cleared. Sending a value identical to the stored one does not trigger re-review. Changing dates, `timezone`, `cost`, `url`, `city`, `state`, `country` or `eventType` keeps the current status.
- A user edit never clears `rejectionReason`, and a rejected event stays `rejected` after an edit. There is no resubmit action. Delete and recreate the event, or ask an operator to re-review it.
- Operator edits never change `status`.
- Events do not expire automatically.

### Shapes

List endpoints return a compact item:

`id`, `name`, `eventType`, `startDate`, `endDate`, `timezone`, `venueName`, `city`, `state`, `country`, `latitude`, `longitude`, `cost`, `submittedBy`, `status`, `createdAt`, `distanceMeters`

Single-event endpoints return the full event:

`id`, `name`, `description`, `eventType`, `startDate`, `endDate`, `timezone`, `venueName`, `address`, `city`, `state`, `country`, `latitude`, `longitude`, `cost`, `url`, `submittedBy`, `status`, `reviewedBy`, `reviewedAt`, `rejectionReason`, `createdAt`, `updatedAt`, plus `days`

`days` is omitted entirely when the event has no per-day schedule. When present it is ordered by `date` ascending.

`eventType` is one of `club_meeting`, `swap_meet`, `field_day`, `special_event`, `hamfest`, `net`, `other`.

#### List events near a location

```
GET /v1/events
```

**Auth:** Public (optional bearer)

| Param | Type | Required | Description |
|---|---|---|---|
| `lat` | float | yes | Latitude, -90 to 90 |
| `lon` | float | yes | Longitude, -180 to 180 |
| `radiusKm` | float | yes | Search radius in kilometres, 1 to 500 |
| `eventType` | string | no | Exact match on one of the event types above. Unknown values match nothing. |
| `fromDate` | RFC 3339 datetime | no | Only events with `startDate >= fromDate` |
| `toDate` | RFC 3339 datetime | no | Only events with `startDate <= toDate` |
| `includePast` | bool | no | Default `false`: only events whose `startDate` is now or later |
| `limit` | int | no | Default 50, maximum 100 |
| `offset` | int | no | Default 0 |

Only approved events are returned, ordered by `startDate` ascending. A bearer token does not change the result.

**Response** `200`:

```json
{
  "data": {
    "events": [
      {
        "id": "4b6a1c0e-…",
        "name": "Monthly Club Meeting",
        "eventType": "club_meeting",
        "startDate": "2026-11-01T19:00:00Z",
        "endDate": "2026-11-01T21:00:00Z",
        "timezone": "America/New_York",
        "venueName": "VFW Hall",
        "city": "Springfield",
        "state": "MA",
        "country": "US",
        "latitude": 42.1015,
        "longitude": -72.5898,
        "cost": "Free",
        "submittedBy": "W1ABC",
        "status": "approved",
        "createdAt": "2026-10-01T12:00:00Z",
        "distanceMeters": 1234.56
      }
    ],
    "total": 5,
    "limit": 50,
    "offset": 0
  }
}
```

`total` is the number of events matching the same filters, independent of `limit` and `offset`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `lat`, `lon` or `radiusKm` out of range |
| (plain text) | 400 | `lat`, `lon` or `radiusKm` missing or unparsable |

#### Get one approved event

```
GET /v1/events/:id
```

**Auth:** Public

| Param | Type | Required | Description |
|---|---|---|---|
| `id` | UUID (path) | yes | Event id. A non-UUID returns `400 VALIDATION_ERROR`. |

**Response** `200`:

```json
{
  "data": {
    "id": "4b6a1c0e-…",
    "name": "Monthly Club Meeting",
    "description": "Monthly meeting of the Springfield ARC",
    "eventType": "club_meeting",
    "startDate": "2026-11-01T19:00:00Z",
    "endDate": "2026-11-01T21:00:00Z",
    "timezone": "America/New_York",
    "venueName": "VFW Hall",
    "address": "123 Main St",
    "city": "Springfield",
    "state": "MA",
    "country": "US",
    "latitude": 42.1015,
    "longitude": -72.5898,
    "cost": "Free",
    "url": "https://example.com/meeting",
    "submittedBy": "W1ABC",
    "status": "approved",
    "reviewedBy": "admin",
    "reviewedAt": "2026-10-02T09:00:00Z",
    "rejectionReason": null,
    "createdAt": "2026-10-01T12:00:00Z",
    "updatedAt": "2026-10-02T09:00:00Z",
    "days": [
      { "id": "…", "date": "2026-11-01", "startTime": "2026-11-01T19:00:00Z", "endTime": "2026-11-01T21:00:00Z" }
    ]
  }
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `EVENT_NOT_FOUND` | 404 | No such id, or the event is not approved. `details.eventId` holds the id. |

#### Submit an event

```
POST /v1/events
```

**Auth:** Bearer (first-party)

**Request:**

```json
{
  "name": "Monthly Club Meeting",
  "description": "Monthly meeting of the Springfield ARC",
  "eventType": "club_meeting",
  "startDate": "2026-11-01T19:00:00Z",
  "endDate": "2026-11-01T21:00:00Z",
  "timezone": "America/New_York",
  "venueName": "VFW Hall",
  "address": "123 Main St",
  "city": "Springfield",
  "state": "MA",
  "country": "US",
  "latitude": 42.1015,
  "longitude": -72.5898,
  "cost": "Free",
  "url": "https://example.com/meeting",
  "days": [
    { "date": "2026-11-01", "startTime": "2026-11-01T19:00:00Z", "endTime": "2026-11-01T21:00:00Z" }
  ]
}
```

Required: `name`, `eventType`, `startDate`, `timezone`, `address`, `city`, `country`, `latitude`, `longitude`. Optional: `description`, `endDate`, `venueName`, `state`, `cost`, `url`, `days`. Each `days[]` item needs `date` (`YYYY-MM-DD`) and `startTime`; `endTime` is optional.

Validation: `eventType` must be one of the seven allowed values; coordinates must be in range; `endDate`, when given, must be strictly after `startDate`; the submitter must have fewer than 10 pending events. Length limits: `name` 200 characters, `description` 2000, `venueName` 200, `cost` 100. Exceeding a length limit returns `500 INTERNAL_ERROR` rather than `400`.

**Response** `201 Created` with the full event under `data`. `status` is `"pending"`, `submittedBy` is the callsign of the token's user, and `days` is included when supplied and non-empty.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Bad `eventType`, coordinates out of range, `endDate` not after `startDate`, malformed JSON |
| `MAX_PENDING_EVENTS` | 429 | The caller already has 10 or more pending events |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FORBIDDEN` | 403 | Third-party token |
| `INTERNAL_ERROR` | 500 | A text field exceeds its length limit |

#### Edit own event

```
PUT /v1/events/:id
```

**Auth:** Bearer (first-party)

**Request:** the same fields as submit, every one optional. Omitted fields are left unchanged, so you cannot clear `description`, `endDate`, `venueName`, `state`, `cost` or `url` through this endpoint. If `days` is present, even as `[]`, the existing schedule is deleted and replaced.

Validation: coordinates and `eventType` are checked when present. `endDate` is not checked against `startDate` on update.

**Response** `200` with the full event under `data`, including the current `days`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `EVENT_NOT_FOUND` | 404 | No such id |
| `EVENT_NOT_OWNED` | 403 | The caller is not the submitter |
| `VALIDATION_ERROR` | 400 | Bad coordinates, `eventType` or JSON |

**Notes.** The review lifecycle above applies: changing a key field of an approved event sends it back to `pending`.

#### Delete own event

```
DELETE /v1/events/:id
```

**Auth:** Bearer (first-party)

**Response** `204 No Content`. The event's day schedule is deleted with it.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `EVENT_NOT_FOUND` | 404 | No such id |
| `EVENT_NOT_OWNED` | 403 | The caller is not the submitter |

#### List my events

```
GET /v1/events/mine
```

**Auth:** Bearer (first-party)

| Param | Type | Required | Description |
|---|---|---|---|
| `limit` | int | no | Default 50, maximum 100 |
| `offset` | int | no | Default 0 |

Returns the caller's events in every status, newest first.

**Response** `200`:

```json
{ "data": { "events": [ { "…": "list item fields", "distanceMeters": null } ] } }
```

There is no `total`, `limit` or `offset` echo on this endpoint. List items do not include `rejectionReason`, and `GET /v1/events/:id` returns `404` for events that are not approved.

### Operator endpoints

These require the operator token and are not reachable with any OAuth token.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/admin/events` | List events in any status (`status`, `limit` max 100, `offset`; omitted `status` means all), oldest first |
| `GET` | `/v1/admin/events/:id` | Get any event regardless of status, with `rejectionReason` and `days` |
| `PUT` | `/v1/admin/events/:id` | Edit any event; never changes `status` or review fields |
| `PUT` | `/v1/admin/events/:id/review` | Approve (`{"action": "approve"}`) or reject (`{"action": "reject", "reason": "…"}`) from any status |
| `DELETE` | `/v1/admin/events/:id` | Permanently delete an event |
| `GET` | `/v1/admin/events/submitter/:callsign` | Submission counts for one callsign (`totalSubmitted`, `totalApproved`, `totalRejected`, `totalPending`) |

## Equipment catalog

A curated catalog of radios, antennas, keys, microphones and accessories that clients download and cache. Anyone can search it, fetch it in full or as a delta, and submit a new entry for operator review. Clients also report anonymous equipment-usage telemetry.

Equipment JSON uses snake_case (`max_power_watts`, `image_url`). `category` is one of `radio`, `antenna`, `key`, `microphone`, `accessory`. `portability` is one of `pocket`, `backpack`, `portable`, `mobile`, `base`.

### Entry shape

```json
{
  "id": "icom-ic-705",
  "name": "IC-705",
  "manufacturer": "Icom",
  "category": "radio",
  "bands": ["160m", "80m", "40m", "20m", "2m", "70cm"],
  "modes": ["CW", "SSB", "FM", "AM", "RTTY"],
  "max_power_watts": 10,
  "portability": "backpack",
  "weight_grams": 1100,
  "description": "…",
  "aliases": ["705"],
  "image_url": "https://…",
  "antenna_connector": "BNC",
  "power_connector": "DC barrel",
  "key_jack": "3.5mm",
  "mic_jack": "RJ45"
}
```

`max_power_watts`, `weight_grams`, `description`, `image_url`, `antenna_connector`, `power_connector`, `key_jack` and `mic_jack` are omitted when they have no value. `id` is a free-form string chosen by the operator when the entry is created.

### Submission review

A submission is `pending` until an operator reviews it, after which it is `approved` or `rejected`. Review can be repeated from any status. A review may link the submission to an existing catalog entry by `catalog_id`, but it does not create a catalog entry. Operators add entries separately.

#### Get the catalog, in full or as a delta

```
GET /v1/equipment/catalog
```

**Auth:** Public

| Param | Type | Required | Description |
|---|---|---|---|
| `since` | RFC 3339 datetime | no | Return only entries updated after this time |

**Caching.** The response carries `ETag: "equipment-<count>-<max_updated_at_ms>"` and `Cache-Control: public, max-age=86400`. If the request's `If-None-Match` header equals the ETag exactly (plain string comparison, no weak-match handling), the server answers `304` with an empty body. The ETag is computed from the whole catalog even when `since` is supplied, so a delta request can also receive `304`.

**Response** `200` (no `data` wrapper):

```json
{
  "version": 412,
  "updated_at": "2026-09-30T18:04:11Z",
  "entries": [ { "…": "entry" } ]
}
```

`version` is the number of entries in the full catalog. `updated_at` is the most recent entry update, or the current time for an empty catalog. Entries are ordered by `name` ascending. Deletions are not signalled in a delta: a client that only ever fetches with `since` never learns about removed ids. Refetch the full catalog to pick up removals.

**Errors:** none specific. `500 INTERNAL_ERROR` on a server failure.

#### Fuzzy search

```
GET /v1/equipment/search
```

**Auth:** Public

| Param | Type | Required | Description |
|---|---|---|---|
| `q` | string | yes | Non-blank search text. Fuzzy-matched against the name, the manufacturer and name together, and the aliases. Matches with similarity at or below 0.15 are excluded. |
| `category` | string | no | Exact match filter |
| `limit` | int | no | Default 5, clamped to 1 to 20 |

**Response** `200`:

```json
{
  "results": [
    { "entry": { "…": "entry" }, "confidence": 0.63, "matched_field": "name" }
  ]
}
```

`confidence` is the best similarity score rounded to two decimal places. `matched_field` is `"name"` or `"alias"`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `q` is blank |
| (plain text) | 400 | `q` is missing |

#### Submit equipment for review

```
POST /v1/equipment/submissions
```

**Auth:** Public

Submissions are anonymous. Nothing ties a submission to a user account. The server records the client's IP address and `User-Agent` header with the submission.

**Request:**

```json
{
  "name": "QMX+",
  "manufacturer": "QRP Labs",
  "category": "radio",
  "bands": ["80m", "40m", "20m"],
  "modes": ["CW", "FT8"],
  "max_power_watts": 5,
  "portability": "pocket",
  "weight_grams": 300
}
```

Required: `name`, `category`. Defaults: `manufacturer: ""`, `bands: []`, `modes: []`, `portability: "portable"`. `category` and `portability` must be from the lists above.

**Response** `201`:

```json
{ "id": "<uuid>", "status": "pending" }
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Bad `category` or `portability`, malformed JSON |

### Usage telemetry

#### Report equipment usage

```
POST /v1/telemetry/equipment-usage
```

**Auth:** Public

Intended for Carrier Wave's own apps. Reports are anonymous: no callsign or device identifier is sent or stored.

**Request:**

```json
{
  "metadata": { "app_version": "1.9.0", "os_version": "19.0" },
  "usage": [
    {
      "catalog_id": "icom-ic-705",
      "category": "radio",
      "is_custom": false,
      "custom_name": null,
      "custom_manufacturer": null,
      "custom_bands": [],
      "custom_modes": [],
      "custom_max_power_watts": null,
      "custom_portability": null,
      "session_mode": "CW",
      "session_band": "20m",
      "session_program": "pota",
      "paired_with": ["elecraft-ax1"]
    }
  ]
}
```

`metadata` (object) and `usage` (array) are required. Inside `metadata` both fields are optional; `os_version` is accepted but not stored. Per entry, `catalog_id` and `category` are required; `is_custom` defaults to `false` and `custom_bands`, `custom_modes` and `paired_with` default to `[]`. Field values are not validated. A batch of more than 50 entries is silently truncated to the first 50.

**Response** `201` with `{"accepted": <n>}`. An empty `usage` array returns `200` with `{"accepted": 0}`.

### Operator endpoints

These require the operator token and are not reachable with any OAuth token.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/admin/equipment` | Create a catalog entry (`id`, `name`, `manufacturer`, `category` required) |
| `PUT` | `/v1/admin/equipment/:id` | Partially update an entry; optional fields can be cleared by sending `null` |
| `DELETE` | `/v1/admin/equipment/:id` | Delete an entry |
| `GET` | `/v1/admin/equipment/submissions` | List submissions (`status`, `limit` max 200), newest first |
| `PUT` | `/v1/admin/equipment/submissions/:id/review` | Approve or reject a submission, optionally linking a `catalog_id` |

## Radio macros

A registry of `.cwmacro` documents: small, declarative scripts that configure a radio (set frequency, set mode, send CW, and so on). Clients list and download approved macros, check for newer versions in bulk, and learn which macros to remove through tombstones.

Public reads only ever see approved macros. Macro JSON uses snake_case (`applies_to`, `author_callsign`, `published_at`), except inside the `capabilities`, `args` and `steps` objects, which are camelCase.

Unknown or unapproved slugs return `400 VALIDATION_ERROR`, not `404`.

### Slugs, versions and tombstones

- A slug is lowercase ASCII letters, digits and hyphens, at most 64 characters, with no leading, trailing or doubled hyphen.
- Slugs are permanent. Every publish of a slug bumps its `version` and the full document for each version is kept.
- A macro's status is one of `approved`, `pending`, `withdrawn`, `tombstoned` or `author_deleted`. Only `approved` macros are visible to clients.
- When an operator sets a macro to `withdrawn`, `tombstoned` or `author_deleted`, the slug keeps its registry entry and a tombstone is published with reason `withdrawn`, `admin_removed` or `author_deleted` respectively. Clients poll the tombstone list to remove macros they have cached.
- A withdrawn slug can be republished as `approved`. The tombstone entry is not removed when that happens.
- A permanent delete removes the macro, its version history, its run telemetry and its tombstone, so a deleted slug never appears in the tombstone list. Operators are advised to withdraw rather than delete.

### Document format

A macro document has `name`, `icon`, `description`, `tags`, `applies_to` (radio model identifiers), `capabilities`, `args` and `steps`.

`capabilities` has the boolean fields `transmits`, `changesFrequency`, `changesMode`, `changesPower` and `usesRawBytes`.

Each `args[]` item has `name` and `type`, where `type` is one of `frequency`, `integer`, `string`, `bool`, `mode`. A `frequency` arg carries `min` and `max` in hertz, with `min < max`, within 100 kHz to 250 GHz.

Each `steps[]` item is tagged by `kind`:

| `kind` | Fields |
|---|---|
| `delay` | `durationMs` |
| `setFrequency` | `hz` |
| `setMode` | `mode` |
| `setPowerWatts` | `watts` |
| `setPTT` | `on` |
| `sendCW` | `text` |
| `vendorCommand` | `commandId`, optional `args` |
| `rawBytes` | `protocol`, `bytes` |
| `readField` | `field`, `into` |
| `waitUntil` | `expr`, `timeoutMs` |
| `assert` | `expr`, `message` |

`format` is the document format version. A client that understands format 2 can pass `max_format=2` to the list endpoint to hide newer documents.

Tags are at most 8 per macro, normalised to lowercase, 2 to 24 characters of `[a-z0-9-]`.

#### List approved macros

```
GET /v1/macros
```

**Auth:** Public

| Param | Type | Required | Description |
|---|---|---|---|
| `tag` | string | no | Exact match on one tag |
| `applies_to` | string | no | Exact match on one radio model identifier |
| `search` | string | no | Case-insensitive substring match over `name`, `slug` and `description` |
| `max_format` | int | no | Only macros with `format <= max_format` |
| `limit` | int | no | Default 50, clamped to 1 to 200 |
| `offset` | int | no | Default 0 |

Ordered by `published_at`, newest first.

**Response** `200`:

```json
{
  "entries": [
    {
      "slug": "kx2-cw-setup",
      "name": "KX2 CW setup",
      "icon": "waveform",
      "description": "…",
      "tags": ["cw", "kx2", "elecraft"],
      "applies_to": ["elecraft-kx2"],
      "capabilities": { "transmits": false, "changesFrequency": true, "changesMode": true, "changesPower": false, "usesRawBytes": false },
      "format": 2,
      "version": 3,
      "author_callsign": "W6JY",
      "published_at": "2026-09-01T00:00:00Z"
    }
  ]
}
```

#### Bulk version check

```
GET /v1/macros/versions
```

**Auth:** Public

| Param | Type | Required | Description |
|---|---|---|---|
| `slugs` | string | yes | Comma-separated slugs. Whitespace is trimmed and empty items dropped. More than 200 slugs returns `400`. |

**Response** `200`, an object keyed by slug. Only approved slugs appear; withdrawn and unknown slugs are simply absent:

```json
{ "kx2-cw-setup": { "version": 3, "format": 2 }, "k3-tuner-cycle": { "version": 1, "format": 2 } }
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | More than 200 slugs |

#### Tombstones

```
GET /v1/macros/tombstones
```

**Auth:** Public

| Param | Type | Required | Description |
|---|---|---|---|
| `since` | RFC 3339 datetime | no | Only tombstones created after this time. Omitted means all. |

**Response** `200`, ordered by `tombstoned_at` ascending:

```json
{ "entries": [ { "slug": "old-macro", "reason": "withdrawn", "tombstoned_at": "2026-08-10T12:00:00Z" } ] }
```

`reason` is `withdrawn`, `admin_removed` or `author_deleted`.

#### Get a macro document

```
GET /v1/macros/:slug
```

**Auth:** Public

**Response** `200`:

```json
{
  "slug": "kx2-cw-setup",
  "spec": {
    "name": "KX2 CW setup",
    "icon": "waveform",
    "description": "…",
    "tags": ["cw", "kx2"],
    "applies_to": ["elecraft-kx2"],
    "capabilities": { "transmits": false, "changesFrequency": true, "changesMode": true, "changesPower": false, "usesRawBytes": false },
    "args": [ { "name": "freq", "type": "frequency", "min": 14000000, "max": 14350000 } ],
    "steps": [ { "kind": "setFrequency", "hz": 14060000 }, { "kind": "setMode", "mode": "CW" } ]
  },
  "format": 2,
  "version": 3,
  "published_at": "2026-09-01T00:00:00Z",
  "updated_at": "2026-09-01T00:00:00Z",
  "author_callsign": "W6JY"
}
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Slug unknown or not approved. The message is `macro not found: <slug>`. |

#### Version history for one slug

```
GET /v1/macros/:slug/versions
```

**Auth:** Public

**Response** `200`, newest first:

```json
{ "versions": [ { "version": 3, "published_at": "…" }, { "version": 2, "published_at": "…" } ] }
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Slug is not currently approved |

#### Report a run event

```
POST /v1/macros/:slug/run-event
```

**Auth:** Bearer (first-party)

Intended for Carrier Wave's own apps.

**Request:**

```json
{ "success": false, "failed_step_index": 2, "error_code": "ptt-stuck-high", "occurred_at": "2026-10-10T14:00:00Z" }
```

`success` is required; the other three fields are optional. `occurred_at` is honoured only if it is within 48 hours of server time, otherwise the server substitutes the current time.

**Response** `204 No Content`.

**Rate limit.** 60 run events per minute per user. Excess requests receive `429 RATE_LIMITED`.

**Privacy.** The server does not store the user's identity with a run event. It stores a keyed hash of the user and slug that rotates daily, so events cannot be tied to a user across days or across macros.

**Retention.** Raw run events are folded into daily aggregates and deleted after 90 days.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `RATE_LIMITED` | 429 | More than 60 events per minute for this user |
| `VALIDATION_ERROR` | 400 | Slug not approved (`macro not found or not approved`), malformed JSON |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FORBIDDEN` | 403 | Third-party token |

### Operator endpoints

These require the operator token and are not reachable with any OAuth token.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/admin/macros` | Publish a macro or bump an existing slug (`201` when new, `200` when bumped); validates slug, tags, band plan and the step verifier |
| `GET` | `/v1/admin/macros` | List macros in every status (`status`, `limit` max 200, `offset`) |
| `PUT` | `/v1/admin/macros/:slug` | Replace a macro; body `slug` must equal the path slug; creates if absent |
| `PATCH` | `/v1/admin/macros/:slug` | Change `status` and optionally `moderator_notes`; writes a tombstone for `withdrawn`, `tombstoned` and `author_deleted` |
| `DELETE` | `/v1/admin/macros/:slug` | Permanently delete a macro, its history and its tombstone |

## Sync: the end-to-end encrypted journal

Carrier Wave Sync keeps a user's data in step across devices. Each device appends encrypted journal entries; other devices pull them, and periodically a device folds the journal into a single encrypted snapshot. The server is blind. It stores only metadata about each entry (its sequence number, entity type, operation, byte size, content hash and blob key) and hands out presigned URLs so clients move ciphertext directly to and from blob storage. The server never reads, parses or decrypts blob contents, and it cannot unwrap the user's data key.

This is the only data surface a third-party OAuth token can reach. All Sync JSON uses camelCase.

### Data model

- **Tenant.** The tenant is the account behind the bearer token, the unified account created by email sign-in. Clients never choose or see a tenant id beyond its appearance in blob keys. Legacy device tokens have no account and receive `403 ACCOUNT_REQUIRED` on every Sync route.
- **Sequence numbers.** Each tenant has its own 64-bit sequence. Sequence numbers are gap-free and strictly increasing. `highWater` is the highest sequence number assigned so far. A push reserves a contiguous block of sequence numbers atomically.
- **Entries.** One entry per journal payload, identified by its sequence number within the tenant. Each entry carries a `clientEntryId`, which is unique per tenant and acts as the idempotency key for pushes. The entry's ciphertext lives at blob key `<tenant>/entries/<seq>.bin`. `entityType` (for example `"qso"`) and `op` (for example `"upsert"` or `"delete"`) are free-form strings the server stores and returns but never interprets.
- **Cursor.** Per tenant, the server tracks `highWater` and the live snapshot pointer: `snapshotSeq` and the snapshot's blob key.
- **Snapshots.** A snapshot folds the journal up to a sequence number into one blob at `<tenant>/snapshots/<seq>-<snapshotId>.bin`. Snapshots are two-phase. Phase 1 registers a pending snapshot and returns a presigned upload URL. Phase 2 commits it: the server checks that the object was uploaded, moves the snapshot pointer forward (never backward), and then garbage-collects entries with `seq < snapshotSeq` together with the previous snapshot blob.
- **Key envelope.** The tenant's data key, wrapped with an AEAD under a passphrase-derived key, plus opaque Argon2id `kdfParams`. The server stores and returns the envelope but cannot unwrap it.
- **Bootstrap.** The live snapshot pointer plus the entries after it. A fresh device downloads one snapshot blob and a short tail of entries.
- **Blobs.** Every upload and download of ciphertext goes through a presigned URL returned by the API. Presigned URLs are valid for 15 minutes. A pending snapshot may be committed for 30 minutes after it is begun. The default page size is 500 entries.

### Authentication and scopes

All seven Sync routes require a bearer token. They are the only routes outside identity that a third-party OAuth token may call:

| Routes | Required scope |
|---|---|
| `GET /v1/sync/bootstrap`, `GET /v1/sync/changes`, `GET /v1/sync/key` | `sync:read` |
| `POST /v1/sync/push`, `POST /v1/sync/snapshot`, `POST /v1/sync/snapshot/commit`, `PUT /v1/sync/key` | `sync:write` |

A third-party token without the required scope receives `403 FORBIDDEN`. First-party tokens need no scope.

These errors can occur on any Sync route:

| Code | HTTP | When |
|---|---|---|
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `ACCOUNT_REQUIRED` | 403 | The token belongs to a legacy device identity with no account |
| `FORBIDDEN` | 403 | Third-party token lacking the required scope |
| `VALIDATION_ERROR` | 400 | Malformed JSON or a missing required field |
| `STORAGE_ERROR` | 500 | The server could not presign a URL or reach blob storage |

### Typical client flow

1. On a new device, `GET /v1/sync/key` and unwrap the data key with the passphrase-derived key. If the response is `404`, no envelope exists for this account yet; the client that creates one stores it with `PUT /v1/sync/key`.
2. `GET /v1/sync/bootstrap`. Download and decrypt the snapshot blob if `snapshotUrl` is set, then apply the returned entries. If 500 entries came back, continue with `GET /v1/sync/changes?since=<last seq>` until `entries` is empty or the last `seq` equals `highWater`.
3. To write, encrypt each payload, `POST /v1/sync/push` with its metadata, then `PUT` the ciphertext to each returned `uploadUrl` before the URL expires.
4. To read, poll `GET /v1/sync/changes?since=<last seq>` and download each `downloadUrl`.
5. Periodically, fold the journal into a snapshot: `POST /v1/sync/snapshot`, `PUT` the snapshot blob to `uploadUrl`, then `POST /v1/sync/snapshot/commit`.

#### Push entries

```
POST /v1/sync/push
```

**Auth:** Bearer (third-party allowed, scope `sync:write`)

**Request:**

```json
{
  "entries": [
    { "clientEntryId": "6f1c…", "entityType": "qso", "op": "upsert", "byteSize": 1832, "contentHash": "sha256-hex" }
  ]
}
```

All five fields are required on every entry. Values are not validated.

**Behaviour.** Entries whose `clientEntryId` already exists for this tenant are not assigned a new sequence number; they return their original `seq` and `blobKey`, so re-pushing after a failure is idempotent. Only new ids consume sequence numbers, as one contiguous block. If two devices push the same `clientEntryId` concurrently, both receive the same authoritative `seq`. An upload URL is presigned for every entry in the request, including already-stored ones, so a client can retry a blob upload that failed the first time.

**Response** `200`, entries in request order:

```json
{
  "entries": [
    { "clientEntryId": "6f1c…", "seq": 125, "blobKey": "<tenant>/entries/125.bin", "uploadUrl": "https://…" }
  ],
  "highWater": 125
}
```

The client must then `PUT` the ciphertext to each `uploadUrl` within 15 minutes. The server does not verify that entry blobs were uploaded; only snapshot uploads are checked, at commit.

**Errors:** the common Sync errors above.

#### Pull changes

```
GET /v1/sync/changes
```

**Auth:** Bearer (third-party allowed, scope `sync:read`)

| Param | Type | Required | Description |
|---|---|---|---|
| `since` | int64 | no | Return entries with `seq > since`. Default 0. |
| `limit` | int64 | no | Default 500, clamped to 1 to 1000 |

**Response** `200`:

```json
{
  "entries": [
    { "seq": 121, "entityType": "qso", "op": "upsert", "blobKey": "<tenant>/entries/121.bin", "byteSize": 1832, "contentHash": "sha256-hex", "downloadUrl": "https://…" }
  ],
  "snapshotSeq": 120,
  "snapshotUrl": "https://…",
  "highWater": 125
}
```

`snapshotSeq` and `snapshotUrl` are `null` when no snapshot has been committed. Entries below the live `snapshotSeq` may have been garbage-collected, so a client whose `since` is older than `snapshotSeq` should re-bootstrap. Paginate by passing the last `seq` as `since` until `entries` is empty or the last `seq` equals `highWater`.

**Errors:** the common Sync errors above.

#### Begin a snapshot (phase 1)

```
POST /v1/sync/snapshot
```

**Auth:** Bearer (third-party allowed, scope `sync:write`)

**Request:**

```json
{ "seq": 120, "byteSize": 48211, "contentHash": "sha256-hex" }
```

`seq` is required. `byteSize` and `contentHash` are optional; when given they are enforced at commit.

Validation: `seq` must be greater than the live `snapshotSeq` and at most `highWater`, otherwise `409 SYNC_SEQUENCE_CONFLICT`. `byteSize`, when present, must be greater than 0. Before validating, the server discards this tenant's pending snapshots that have expired or that target a sequence number at or below the live pointer, deleting any bytes uploaded for them.

**Response** `200`:

```json
{
  "snapshotId": "8b0a…",
  "seq": 120,
  "snapshotBlobKey": "<tenant>/snapshots/120-8b0a….bin",
  "uploadUrl": "https://…",
  "expiresAt": "2026-10-10T15:30:00Z"
}
```

Nothing is live yet. `bootstrap` and `changes` ignore pending snapshots. `PUT` the snapshot ciphertext to `uploadUrl` within 15 minutes, then commit before `expiresAt`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `SYNC_SEQUENCE_CONFLICT` | 409 | `seq` is at or below the live snapshot seq, or above `highWater` |
| `VALIDATION_ERROR` | 400 | `byteSize` is 0 or negative, malformed JSON |
| `ACCOUNT_REQUIRED` / `FORBIDDEN` | 403 | See the common Sync errors |

#### Commit a snapshot (phase 2)

```
POST /v1/sync/snapshot/commit
```

**Auth:** Bearer (third-party allowed, scope `sync:write`)

**Request:**

```json
{ "snapshotId": "8b0a…", "byteSize": 48211, "contentHash": "sha256-hex" }
```

`snapshotId` is required. `byteSize` and `contentHash` are optional, but if repeated they must equal the values declared in phase 1.

**Behaviour.** The server looks up the pending snapshot for this tenant and rejects it if it has expired (the pending record and any uploaded bytes are discarded). It compares the declared size and hash with those from phase 1. It then checks that the object exists in blob storage and that its stored size equals the declared `byteSize` (from the commit, or from phase 1 if the commit omitted it). If everything matches, it moves the snapshot pointer forward; the pointer never moves backward. Finally it garbage-collects on a best-effort basis: the pending record, entries with `seq < snapshotSeq` and their blobs, the previous snapshot blob, and any other pending snapshots at or below this sequence number. Garbage-collection failures are logged and do not fail the commit.

**Response** `200`:

```json
{ "snapshotSeq": 120, "snapshotBlobKey": "<tenant>/snapshots/120-8b0a….bin", "highWater": 124 }
```

**Errors.** The journal is untouched in every error case.

| Code | HTTP | When |
|---|---|---|
| `SYNC_SNAPSHOT_NOT_FOUND` | 404 | `snapshotId` is unknown for this tenant, already committed, expired (30 minutes), or discarded because a newer snapshot superseded it. `details.snapshotId` holds the id. |
| `SYNC_SNAPSHOT_NOT_UPLOADED` | 409 | No object exists at the snapshot's blob key. Finish the upload and retry; the pending snapshot survives until `expiresAt`. |
| `SYNC_SNAPSHOT_MISMATCH` | 409 | The committed size or hash differs from the declared values, or the stored object's size differs from the declared size. `details.reason` says which. |
| `SYNC_SEQUENCE_CONFLICT` | 409 | The live pointer is already at or beyond this sequence number (a newer snapshot won). The pending snapshot is discarded. |
| `STORAGE_ERROR` | 500 | Blob storage could not be queried for a reason other than not-found |

#### Bootstrap

```
GET /v1/sync/bootstrap
```

**Auth:** Bearer (third-party allowed, scope `sync:read`)

No parameters. Returns the live snapshot pointer plus up to 500 entries with `seq > snapshotSeq`, or from the start of the journal if no snapshot has been committed.

**Response** `200`:

```json
{
  "snapshotUrl": "https://…",
  "snapshotSeq": 120,
  "entries": [ { "…": "same shape as a changes entry" } ],
  "highWater": 125
}
```

`snapshotUrl` and `snapshotSeq` are `null` when no snapshot has been committed. If `entries` contains 500 items, continue with `GET /v1/sync/changes?since=<last seq>`.

**Errors:** the common Sync errors above.

#### Store the key envelope

```
PUT /v1/sync/key
```

**Auth:** Bearer (third-party allowed, scope `sync:write`)

**Request:**

```json
{ "wrappedKey": "<base64>", "kdfParams": { "…": "opaque Argon2id salt and cost parameters" } }
```

`wrappedKey` must be base64 in the standard alphabet with padding; it is decoded and stored as bytes. `kdfParams` may be any JSON value and is stored verbatim. This is an upsert: a new envelope overwrites the previous one with no versioning.

**Response** `204 No Content`.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | `wrappedKey` is not valid base64 (message `invalid base64 wrapped_key: …`) |

#### Fetch the key envelope

```
GET /v1/sync/key
```

**Auth:** Bearer (third-party allowed, scope `sync:read`)

**Response** `200`:

```json
{ "wrappedKey": "<base64>", "kdfParams": { "…": "…" } }
```

When no envelope is stored the server answers `404` with an empty body and no JSON error envelope.

### Operator endpoints

These require the operator token and are not reachable with any OAuth token.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/admin/sync/orphans` | List Sync datasets created under legacy device identities before Sync required an account, with the account that now owns the same callsign |
| `POST` | `/v1/admin/sync/orphans/:participant_id/adopt` | Move an orphaned dataset onto the account that owns its callsign; refused unless the account's Sync data is empty |

## Telemetry and ingestion

These endpoints exist for Carrier Wave's own apps. They are documented so the traffic is understandable, not as an integration surface for third parties. Third-party OAuth tokens cannot call the authenticated ones.

The ingestion request bodies use snake_case.

#### Ingest app metrics

```
POST /v1/metrics
```

**Auth:** Public

Intended for Carrier Wave's own apps. Accepts an Apple MetricKit metrics payload.

**Request:**

```json
{
  "metadata": { "app_version": "1.9.0", "build_number": "412", "device_model": "iPhone16,1", "os_version": "19.0", "locale": "en_US" },
  "payload": { "…": "raw MetricKit payload JSON" }
}
```

`metadata.app_version`, `build_number`, `device_model` and `os_version` are required; `locale` defaults to `"unknown"`. `payload` is any JSON value, stored verbatim. Length limits: `app_version`, `build_number`, `os_version` and `locale` 32 characters; `device_model` 64. The whole request body must be under 1 MiB.

**Response** `200`:

```json
{ "accepted": true }
```

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | A field exceeds its length limit, the body exceeds 1 MiB, or the JSON is malformed |

**Retention.** Stored payloads are not deleted automatically.

#### Ingest app diagnostics

```
POST /v1/diagnostics
```

**Auth:** Public

Intended for Carrier Wave's own apps. Identical to `POST /v1/metrics`, for MetricKit diagnostic payloads.

#### Inbound SMS webhook (SMS spotting)

```
POST /v1/twilio/sms
Content-Type: application/x-www-form-urlencoded
```

**Auth:** Webhook

Intended for Carrier Wave's own SMS spotting feature. The sender is identified by a marker code in the message body. Marker codes are minted by `POST /v1/spot-markers`, documented elsewhere.

**Request** form fields: `Body` (required), `From` (required, not used), `To` and `MessageSid` (optional, not used). A missing `Body` or `From`, or a wrong content type, yields a plain-text `4xx`.

`Body` grammar: `MARKER REFERENCE FREQUENCY MODE [COMMENTS]`, split on whitespace into at most five parts. Marker, reference and mode are upper-cased. A reference containing `/` is treated as a SOTA reference, otherwise as a POTA reference.

**Behaviour.** For a POTA reference, the server posts a spot to the POTA spotting service with the marker's callsign as both activator and spotter, the given frequency, reference, mode and comments, and the source `"Carrier Wave SMS"`. SOTA spotting is currently disabled: nothing is posted and the reply says so. Nothing is stored locally.

**Response** always `200` with `Content-Type: application/xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?><Response><Message>Spot posted! POTA K-1234 on 14.062 CW by W1ABC</Message></Response>
```

Any failure (bad format, unknown marker, upstream spotting error) is answered with the same `200` and the message `Error processing your spot. Check your message format: MARKER REFERENCE FREQ MODE [COMMENTS]`. The webhook never returns a non-200 status.

#### Report upload errors

```
POST /v1/telemetry/upload-errors
```

**Auth:** Bearer (first-party)

Intended for Carrier Wave's own apps. Reports failures when uploading QSOs to external logging services.

**Request:**

```json
{
  "errors": [
    { "service": "pota", "category": "authentication", "message_hash": "a1b2c3", "affected_count": 5, "is_transient": false, "app_version": "1.8.0", "os_version": "18.4" }
  ]
}
```

All seven fields are required on every entry. Validation: at most 50 entries; `service` is one of `pota`, `qrz`, `clublog`, `eqsl`, `lotw`, `hamqth`; `category` is one of `authentication`, `validation`, `rate_limited`, `maintenance`, `network_timeout`, `network_offline`, `server_error`, `rejected`, `subscription_required`; `affected_count` is 0 or more; `message_hash` is at most 64 characters; `app_version` and `os_version` are at most 32. Reports are stored with the caller's callsign.

**Response** `200` with `{"accepted": <n>}`. An empty `errors` array returns `{"accepted": 0}` without validation.

**Errors**

| Code | HTTP | When |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Too many entries, an unknown `service` or `category`, a field out of range, malformed JSON |
| `INVALID_TOKEN` | 401 | Missing or invalid bearer token |
| `FORBIDDEN` | 403 | Third-party token |

**Retention.** Stored reports are not deleted automatically.

### Operator endpoints

These require the operator token and are not reachable with any OAuth token.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/admin/telemetry/upload-errors` | Upload-error summary (`days` 1 to 90, default 7; `service`; `category`): totals, by service, by category, daily trend, 50 most recent |
| `GET` | `/v1/admin/metrickit` | MetricKit summary (`type` of `metrics` or `diagnostics`; `days` 1 to 90, default 7; `device_model`; `app_version`): totals, by type and device, daily trend, 50 most recent with full payloads |
| `GET` | `/v1/admin/stats` | User counts: `totalUsers`, `usersLast7Days`, `usersLast30Days` |
| `GET` | `/v1/admin/stats/users-by-hour` | Distinct active callsigns per hour (`days` 1 to 365, default 30); hours with no activity are absent |

## Operational endpoints

A health check for load balancers and monitoring, plus a note on how unknown routes behave.

#### Health check

```
GET /v1/health
```

**Auth:** Public

Checks that the database answers a trivial query within 2 seconds. The `rbn` block describes the Reverse Beacon Network ingester and is informational only; it never affects the status code.

**Response** `200` when the database answers (snake_case):

```json
{
  "status": "ok",
  "version": "0.4.59",
  "database": "ok",
  "rbn": { "connected": true, "spots_in_store": 1234, "oldest_spot": "2026-10-10T13:00:00Z", "spots_per_minute": 42.0 }
}
```

- `version` is the server build version.
- `rbn` is present only when the RBN ingester is connected or the spot store holds spots. `oldest_spot` is omitted when the store is empty. `spots_per_minute` is measured over the last minute.

**Response** `503 Service Unavailable` when the database check fails or times out:

```json
{ "status": "error", "version": "0.4.59", "database": "error", "error": "database check failed" }
```

`error` is `"database check failed"` or `"database check timed out"`. The underlying database error is never returned. `rbn` may still be present. The response carries no caching headers.

### Metrics and web surfaces

The server also exposes `GET /metrics` at the domain root (outside `/v1`) in Prometheus text format for operators; do not confuse it with `POST /v1/metrics`, the MetricKit ingestion endpoint. The same host serves the Carrier Wave web apps at `/`, `/contests` and `/logbook/`, and any unknown URL outside `/v1` returns the main web app's HTML page with `200`.

### Unknown `/v1` routes

A request to a `/v1` path with no matching route returns a JSON `404`:

```
HTTP/1.1 404 Not Found
Content-Type: application/json

{ "error": { "code": "NOT_FOUND", "message": "Endpoint not found" } }
```

There is no `details` key. This applies before authentication, so an unauthenticated request to an unknown `/v1/admin/...` path receives this `404` rather than a `401`.

### Cross-origin requests

Browser requests are accepted from `https://carrierwave.app` and `https://activities.carrierwave.app`, with methods `GET`, `POST`, `PUT`, `DELETE` and `OPTIONS` and the headers `Authorization` and `Content-Type`. `PATCH` is not in the allowed method list. Other origins must call the API from outside the browser.

## Appendix: error codes

Every application error code, its HTTP status, and the `details` object it
attaches. The OAuth endpoints' RFC 6749 errors are documented with those
endpoints.

| Code | HTTP | `details` | Meaning |
|---|---|---|---|
| `VALIDATION_ERROR` | 400 | | Request failed validation; `message` explains what. Also used for malformed JSON and bad path parameters. |
| `CHALLENGE_ENDED` | 400 | | Time-bounded challenge is over; cannot join or report. |
| `INVALID_CONTEST_DEFINITION` | 400 | `message`, `problems[]` | Contest definition failed schema/semantic validation. |
| `INVALID_EVENT_REVIEW` | 400 | | Review action/state transition not allowed. |
| `INVALID_TOKEN` | 401 | | Missing, invalid, expired or revoked bearer token on a route that requires one. |
| `FORBIDDEN` | 403 | | Caller authenticated but not allowed: wrong callsign, third-party token outside its scope map, bad admin token. |
| `ACCOUNT_REQUIRED` | 403 | | Route needs an email-verified account; a bare `fd_` device token is not enough. |
| `NOT_PARTICIPATING` | 403 | | Callsign has not joined this challenge. |
| `INVITE_REQUIRED` | 403 | | Challenge is invite-only and no `inviteToken` was supplied. |
| `INVITE_EXPIRED` | 403 | | Invite token past its expiry. |
| `INVITE_EXHAUSTED` | 403 | | Invite token reached `maxUses`. |
| `MAX_PARTICIPANTS` | 403 | | Challenge is full. |
| `EVENT_NOT_OWNED` | 403 | `eventId` | Attempt to edit or delete another user's event. |
| `NOT_FOUND` | 404 | | No route matched under `/v1`. |
| `CHALLENGE_NOT_FOUND` | 404 | `challengeId` | |
| `BADGE_NOT_FOUND` | 404 | `badgeId` | |
| `INVITE_NOT_FOUND` | 404 | `token` | |
| `USER_NOT_FOUND` | 404 | `userId` | |
| `FRIEND_INVITE_NOT_FOUND` | 404 | `token` | Friend invite link unknown or expired. |
| `FRIEND_REQUEST_NOT_FOUND` | 404 | `requestId` | |
| `FRIENDSHIP_NOT_FOUND` | 404 | `friendshipId` | |
| `ACTIVITY_NOT_FOUND` | 404 | `activityId` | |
| `PROGRAM_NOT_FOUND` | 404 | `slug` | |
| `SPOT_NOT_FOUND` | 404 | `spotId` | |
| `CLUB_NOT_FOUND` | 404 | `clubId` | |
| `CLUB_MEMBER_NOT_FOUND` | 404 | `clubId`, `callsign` | |
| `PARK_NOT_FOUND` | 404 | `reference` | |
| `TRAIL_NOT_FOUND` | 404 | `reference` | |
| `EQUIPMENT_NOT_FOUND` | 404 | `equipmentId` | |
| `CONTEST_DEFINITION_NOT_FOUND` | 404 | `contestId` | |
| `EVENT_NOT_FOUND` | 404 | `eventId` | |
| `SYNC_SNAPSHOT_NOT_FOUND` | 404 | `snapshotId` | Pending snapshot never started, expired, or superseded. |
| `ALREADY_JOINED` | 409 | | Callsign already in the challenge. |
| `ALREADY_FRIENDS` | 409 | | |
| `FRIEND_REQUEST_EXISTS` | 409 | | A pending request already exists between the two users. |
| `CALLSIGN_TAKEN` | 409 | `callsign` | Callsign belongs to another account. |
| `SELF_SPOT_EXISTS` | 409 | | An active self-spot already exists for this program. |
| `SYNC_SEQUENCE_CONFLICT` | 409 | | Push's `baseSeq` is behind the server; pull changes and retry. |
| `SYNC_SNAPSHOT_NOT_UPLOADED` | 409 | `snapshotId` | Commit called before the blob was PUT to `uploadUrl`. |
| `SYNC_SNAPSHOT_MISMATCH` | 409 | `reason` | Uploaded blob size/hash differs from what `begin` declared. |
| `SYNC_ADOPT_CONFLICT` | 409 | `entryCount`, `hasCursor`, `hasKeyBlob` | Target account already has sync data; merge manually. |
| `FRIEND_INVITE_USED` | 410 | `token` | Friend invite link already consumed. |
| `CANNOT_FRIEND_SELF` | 422 | | |
| `CAPABILITY_NOT_SUPPORTED` | 422 | `capability`, `programSlug` | Program lacks the capability (for example self-spotting). |
| `SYNC_ADOPT_NO_ACCOUNT` | 422 | `callsign` | Nobody has signed in with that callsign yet. |
| `MAX_PENDING_EVENTS` | 429 | | User already has 10 events awaiting review. |
| `RATE_LIMITED` | 429 | | Handler-level limiter tripped (macro run events). Note the global limiter returns plain text instead. |
| `INTERNAL_ERROR` | 500 | | Database or other internal failure. Check logs by `X-Request-Id`. |
| `STORAGE_ERROR` | 500 | | Blob store (S3) failure. |

`304 Not Modified` has no body.
