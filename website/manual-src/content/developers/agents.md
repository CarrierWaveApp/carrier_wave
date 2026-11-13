---
title: "Using the API from agents and tools"
description: "The short, copy-pastable version of the activities server API for coding agents, scripts and CLIs: where the raw docs are, how to authenticate without a browser, and the requests you will make most"
weight: 2
showToc: true
outputs: ["html", "markdown"]
---

This page is for software that reads documentation and makes HTTP requests on
its own: coding agents, scripts, CLIs, notebooks. It is deliberately short.
The full reference is [Activities Server API Reference](/developers/api/).

## Machine-readable documentation

| What | URL |
|---|---|
| Index of everything machine-readable on this site | `https://carrierwave.app/llms.txt` |
| Full API reference as plain Markdown | `https://carrierwave.app/manual/developers/api/index.md` |
| This page as plain Markdown | `https://carrierwave.app/manual/developers/agents/index.md` |
| OAuth / OpenID Connect discovery document | `https://activities.carrierwave.app/.well-known/openid-configuration` |
| Token verification keys (JWKS) | `https://activities.carrierwave.app/.well-known/jwks.json` |

The Markdown files are the same source as the HTML pages and are rebuilt on
every deploy. Fetch them with a plain `GET`; no authentication, no JavaScript.
There is no OpenAPI document yet. The Markdown reference lists every route
with its exact field names, so generate clients from that.

## Ground truth in five lines

- Base URL `https://activities.carrierwave.app`. JSON API under `/v1`.
- Field names are `camelCase`, timestamps are RFC 3339 UTC, ids are UUIDs.
- Errors are `{"error": {"code": "UPPER_SNAKE", "message": "…"}}`. Branch on
  `code`. A `429` is plain text, not JSON, with an `x-ratelimit-after` header.
- Public data needs no token. Acting for a user needs an OAuth token from the
  device flow or the authorization-code flow. The only user data a third-party
  token can reach is the encrypted sync journal and OIDC userinfo.
- Send a descriptive `User-Agent`, honour `ETag`, and stay well under 10
  requests per second.

## Public data without authentication

These answer to anyone. Add `-H 'If-None-Match: <etag>'` on repeat calls to
the reference-data endpoints that return an `ETag`; a `304` has no body.

```sh
BASE=https://activities.carrierwave.app

# Liveness and component status
curl -s $BASE/v1/health

# Current spots. Optional filters: program, callsign, source, mode, state,
# maxAgeMinutes (default 30, max 1440).
curl -s "$BASE/v1/spots?program=pota&maxAgeMinutes=15"

# Reverse Beacon Network spots relayed from the telnet feed
curl -s "$BASE/v1/rbn/spots"

# POTA statistics for one park
curl -s "$BASE/v1/pota/stats/park/US-0348"

# Registry of activity programs (POTA, SOTA, …) and their capabilities
curl -s "$BASE/v1/programs"

# Contest definitions, radio macros, achievements catalog
curl -s "$BASE/v1/contests"
curl -s "$BASE/v1/macros"
curl -s "$BASE/v1/achievements"

# Satellite status, callsign enrichment (club memberships such as CWops)
curl -s "$BASE/v1/satellites/amsat-status"
curl -s "$BASE/v1/callsign-enrichment/W1AW"
```

Query parameters, limits, units and response shapes for each of these are in
the [Spots and reference data](/developers/api/#spots-and-reference-data),
[Programs](/developers/api/#programs), [Contest definitions](/developers/api/#contest-definitions)
and [Radio macros](/developers/api/#radio-macros) sections of the reference.

## Authenticating without a browser: the device flow

Agents and CLIs should use the OAuth 2.0 device authorization grant
(RFC 8628). You need a registered client id; email hello@carrierwave.app to
get one and ask for the `device_code` grant. Registration is curated, there
is no self-service endpoint.

1. Request a device code (form-encoded, not JSON):

   ```sh
   curl -s -X POST $BASE/v1/oauth/device/code \
     -d client_id=my-cli -d 'scope=openid sync:read'
   ```

   ```json
   {
     "device_code": "Xy7…",
     "user_code": "KRWG-ZPTL",
     "verification_uri": "https://activities.carrierwave.app/v1/oauth/device",
     "verification_uri_complete": "https://activities.carrierwave.app/v1/oauth/device?user_code=KRWG-ZPTL",
     "expires_in": 900,
     "interval": 5
   }
   ```

2. Show the user `verification_uri_complete` (or the URI plus the code). They
   open it, sign in to Carrier Wave, and approve the scopes.

3. Poll the token endpoint every `interval` seconds until it stops answering
   `authorization_pending`:

   ```sh
   curl -s -X POST $BASE/v1/oauth/token \
     -d grant_type=urn:ietf:params:oauth:grant-type:device_code \
     -d client_id=my-cli -d device_code=Xy7…
   ```

   Pending looks like `{"error": "authorization_pending"}`. Polling faster
   than `interval` returns `slow_down`. After `expires_in` seconds you get
   `expired_token` and must start over. Success returns `access_token`,
   `token_type`, `expires_in`, `scope`, `refresh_token` and, with the `openid`
   scope, `id_token`.

4. Use the access token as `Authorization: Bearer <access_token>`. It expires
   after 15 minutes; refresh with `grant_type=refresh_token` and the
   `refresh_token`, which rotates on every use.

Apps with a redirect URI should use the authorization-code flow with PKCE
instead. Both flows, every parameter and every error are in the
[OAuth 2.0 / OpenID Connect provider](/developers/api/#oauth-20--openid-connect-provider)
section.

## Scopes a third-party token can use

| Scope | Lets you call |
|---|---|
| `openid` | `GET /v1/oauth/userinfo` |
| `profile`, `email` | Extra claims in the ID token and userinfo |
| `sync:read` | `GET /v1/sync/bootstrap`, `GET /v1/sync/changes`, `GET /v1/sync/key` |
| `sync:write` | `POST /v1/sync/push`, `POST /v1/sync/snapshot`, `POST /v1/sync/snapshot/commit`, `PUT /v1/sync/key` |

Every other route answers `403 FORBIDDEN` to a third-party token, by design,
even with every scope. Challenges, friends, clubs, events and the feed are
reserved for Carrier Wave's own apps.

## Reading a user's log

The log is end-to-end encrypted. The server stores and serves ciphertext;
decryption needs the user's sync passphrase, which never reaches the server
and which your tool must ask the user for.

```sh
TOKEN=…   # access token with sync:read

# The passphrase-wrapped data key envelope (404 if the user has not set up sync)
curl -s -H "Authorization: Bearer $TOKEN" $BASE/v1/sync/key

# First sync: snapshot pointer plus the journal entries after it
curl -s -H "Authorization: Bearer $TOKEN" $BASE/v1/sync/bootstrap

# Incremental sync: entries with seq greater than the last one you applied
curl -s -H "Authorization: Bearer $TOKEN" "$BASE/v1/sync/changes?since=1234"
```

Each entry carries a monotonic `seq` and a time-limited download URL. Download,
decrypt with ChaCha20-Poly1305 using the unwrapped data key, gunzip, parse the
JSON payload, and fold entries in `seq` order (last write wins; deletes are
tombstones). The full data model, the two-phase snapshot, and every error code
are in the
[Sync](/developers/api/#sync-the-end-to-end-encrypted-journal) section.

## Error handling cheat sheet

| You get | It means | Do |
|---|---|---|
| `401 INVALID_TOKEN` | Missing, expired or revoked bearer on a route that needs one | Refresh the token, or re-run the device flow |
| `403 FORBIDDEN` | Third-party token outside its allowed routes or scopes | Stop; the route is first-party only |
| `403 ACCOUNT_REQUIRED` | Route needs an account-backed session, not a device token | Sign the user in through OAuth |
| `400 VALIDATION_ERROR` | Bad JSON, bad path parameter, or a failed check named in `message` | Fix the request |
| `404 NOT_FOUND` | No such route under `/v1` | Check the path; OAuth routes are `404` when OAuth is disabled on a host |
| `409 SYNC_SEQUENCE_CONFLICT` | Your push is behind the server | Pull `changes`, then retry |
| `429` (plain text) | Rate limited | Wait `x-ratelimit-after` seconds |
| `304` (empty) | Nothing changed since your `If-None-Match` | Keep your cached copy |

## Etiquette

- Identify your tool in `User-Agent` so we can contact you if something
  misbehaves.
- Cache. The reference datasets change on a cadence of minutes to days and
  most of them emit an `ETag`.
- Do not poll the social endpoints or scrape user data; they are closed to
  third parties.
- Questions, client registration, or a dataset you wish existed:
  hello@carrierwave.app.
