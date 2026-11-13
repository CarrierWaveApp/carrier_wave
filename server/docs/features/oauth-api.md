# Third-party OAuth 2.0 / OpenID Connect API

Lets someone else's application read, update, and add QSOs in a Carrier Wave
user's log, with the user's consent.

Two things must be true before an application can read a single QSO:

1. **The user authorizes it** — an OAuth flow on `carrierwave.app` grants the
   application scoped access to their account.
2. **The user gives it the sync passphrase** — the log is end-to-end encrypted
   and the server cannot decrypt it. The application derives the data key
   locally from a passphrase the user types into *it*.

Neither substitutes for the other. A token with `sync:read` downloads
ciphertext; without the passphrase that ciphertext is noise.

> **Security note, stated plainly.** Asking users to type their sync passphrase
> into third-party software is the credential-phishing shape OAuth normally
> exists to prevent, and there is **no key-rotation path today** — a passphrase
> that leaks cannot be changed, and it decrypts the entire log forever. This is
> why client registration is curated: every `client_id` is approved by hand.
> Only ask for the passphrase if you genuinely need to read log contents, keep
> it in memory, and never transmit or persist it.

---

## Contents

- [Registering a client](#registering-a-client)
- [Discovery](#discovery)
- [Scopes](#scopes)
- [Authorization code flow (apps)](#authorization-code-flow-apps)
- [Device flow (CLIs, headless)](#device-flow-clis-headless)
- [Refreshing and revoking](#refreshing-and-revoking)
- [Reading the log](#reading-the-log)
- [Writing to the log](#writing-to-the-log)
- [Errors](#errors)
- [What a token cannot do](#what-a-token-cannot-do)

---

## Registering a client

There is no self-serve portal and no dynamic registration (RFC 7591). Ask the
maintainers to register your application; an admin runs:

```bash
curl -X POST https://activities.carrierwave.app/v1/admin/oauth/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "clientId": "my-logger",
        "name": "My Logger",
        "description": "Syncs QSOs with My Logger",
        "homepageUrl": "https://mylogger.example",
        "redirectUris": ["https://mylogger.example/oauth/callback"],
        "scopes": "openid profile sync:read sync:write",
        "grantTypes": "authorization_code refresh_token device_code",
        "confidential": false
      }'
```

`confidential: true` returns a `clientSecret` **once** — only its hash is
stored. Use it only for server-side applications that can keep a secret. Native
apps, single-page apps, and CLIs must register as public clients
(`confidential: false`) and rely on PKCE.

`name` is what the user sees on the consent screen, and is the main thing
standing between them and a lookalike application. It is reviewed by hand.

Suspend a client with `DELETE /v1/admin/oauth/clients/:client_id`. Suspension
takes effect immediately for new tokens; existing access tokens expire within
15 minutes.

## Discovery

```
GET /.well-known/openid-configuration
GET /.well-known/oauth-authorization-server   # RFC 8414 alias
GET /.well-known/jwks.json
```

Most OAuth libraries configure themselves from the first of these. Tokens are
EdDSA (Ed25519); verify them against the JWKS by `kid`.

> **Known wrinkle:** `issuer` is always `https://activities.carrierwave.app`,
> because that is what tokens carry in `iss`. On staging, whose host differs, a
> strict OIDC client that requires issuer/host agreement will complain. Use
> production for conformance testing.

## Scopes

| Scope | Grants |
|---|---|
| `openid` | Confirms the account; enables `id_token` and `/v1/oauth/userinfo` |
| `profile` | Callsign and public profile |
| `email` | The verified email address on the account |
| `sync:read` | Download the encrypted log (`/v1/sync/bootstrap`, `/changes`, `/key`) |
| `sync:write` | Upload encrypted log entries (`/v1/sync/push`, `/snapshot`, `/snapshot/commit`) |

**Everything else on the API is closed to third-party tokens.** This is
default-deny: a route not explicitly listed in `src/auth/scope_map.rs` returns
`403` for any token carrying a `cid` claim, no matter what scopes it holds.
Clubs, friends, spots, events, contests, and account management are all
first-party-only today. Ask if you need one — widening is a deliberate,
per-route decision, not an oversight.

## Authorization code flow (apps)

PKCE with `S256` is **required** for every client, public or confidential.
`plain` is rejected.

Note this is the standard RFC 7636 encoding —
`base64url_nopad(sha256(verifier))`. (Carrier Wave's own first-party
magic-link flow uses a hex variant; that is a different flow and does not apply
to you.)

**1. Send the user to the consent screen:**

```
GET /v1/oauth/authorize
  ?client_id=my-logger
  &redirect_uri=https://mylogger.example/oauth/callback
  &response_type=code
  &scope=openid%20sync:read%20sync:write
  &state=<random, checked on return>
  &code_challenge=<base64url_nopad(sha256(verifier))>
  &code_challenge_method=S256
  &nonce=<random, optional; echoed into the id_token>
```

`redirect_uri` must **exactly** match a registered URI — no prefixes, no extra
query parameters. An unknown client or unregistered redirect renders an error
page and does *not* redirect, so a bad `redirect_uri` never receives a code.

CLIs should use a loopback redirect (`http://127.0.0.1:<port>/callback`) and
register it, or use the device flow below.

**2. The user returns to your `redirect_uri`:**

```
https://mylogger.example/oauth/callback?code=<code>&state=<your state>
```

Verify `state` matches what you sent. On refusal you get
`?error=access_denied&state=…` instead.

**3. Exchange the code within 60 seconds:**

```bash
curl -X POST https://activities.carrierwave.app/v1/oauth/token \
  -d grant_type=authorization_code \
  -d client_id=my-logger \
  -d code=<code> \
  -d redirect_uri=https://mylogger.example/oauth/callback \
  -d code_verifier=<verifier>
```

```json
{
  "access_token": "eyJ0eXAiOiJKV1Qi…",
  "token_type": "Bearer",
  "expires_in": 900,
  "refresh_token": "cwr_…",
  "scope": "openid sync:read sync:write",
  "id_token": "eyJ0eXAiOiJKV1Qi…"
}
```

Codes are single-use and client-bound. A confidential client authenticates with
HTTP Basic or `client_id`/`client_secret` form fields.

## Device flow (CLIs, headless)

For anything that cannot host a redirect listener.

```bash
curl -X POST https://activities.carrierwave.app/v1/oauth/device/code \
  -d client_id=my-logger -d "scope=openid sync:read"
```

```json
{
  "device_code": "…",
  "user_code": "KRWG-ZPTL",
  "verification_uri": "https://activities.carrierwave.app/v1/oauth/device",
  "verification_uri_complete": "https://activities.carrierwave.app/v1/oauth/device?user_code=KRWG-ZPTL",
  "expires_in": 900,
  "interval": 5
}
```

Show the user `user_code` and `verification_uri`, then poll:

```bash
curl -X POST https://activities.carrierwave.app/v1/oauth/token \
  -d grant_type=urn:ietf:params:oauth:grant-type:device_code \
  -d client_id=my-logger \
  -d device_code=<device_code>
```

Poll no faster than `interval`. Responses follow RFC 8628 §3.5:

| Response | Meaning |
|---|---|
| `authorization_pending` | Keep waiting |
| `slow_down` | You polled too fast; increase the interval |
| `access_denied` | The user declined; stop |
| `expired_token` | Start over |
| tokens | Approved |

## Refreshing and revoking

Access tokens last 15 minutes. Refresh tokens rotate on every use and are bound
to the client that received them:

```bash
curl -X POST https://activities.carrierwave.app/v1/oauth/token \
  -d grant_type=refresh_token -d client_id=my-logger -d refresh_token=<token>
```

Store the new `refresh_token` from every response — the old one is dead.
Presenting a rotated token twice is treated as theft and revokes the entire
token family, forcing re-authorization. Refreshing never widens scope, and a
user who has revoked consent causes the refresh to fail immediately rather than
at token expiry.

Revoke your own token (RFC 7009):

```bash
curl -X POST https://activities.carrierwave.app/v1/oauth/revoke \
  -d token=<refresh_token> -d client_id=my-logger
```

Users manage connected applications themselves via `GET /v1/oauth/grants` and
`DELETE /v1/oauth/grants/:client_id`.

## Reading the log

This is where the encryption shows up. The log is an **append-only journal** of
encrypted blobs; you reconstruct the current QSO set by replaying it.

**1. Get the key envelope** (`sync:read`):

```
GET /v1/sync/key   ->  { the passphrase-wrapped data key }
```

`404` means the user has not set up sync yet — there is nothing to read.

**2. Ask the user for their sync passphrase**, and unwrap the envelope locally:

- Argon2id derives a key-encryption key from the passphrase.
- That KEK unwraps the 32-byte data key.

**3. List journal entries** (`sync:read`):

```
GET /v1/sync/bootstrap        # everything (first sync)
GET /v1/sync/changes?since_seq=<n>   # incremental
```

Each entry has a monotonic `seq` and a presigned download URL.

**4. For each entry:** download the blob, then

- ChaCha20-Poly1305 decrypt with the data key,
- gunzip,
- parse the `JournalPayload` JSON.

**5. Fold the payloads in `seq` order**, applying upserts and deletes, to get
the current set of QSOs. Persist the highest `seq` you have seen and pass it as
`since_seq` next time.

### QSO field notes that will bite you

- **`frequency` is in MHz on the wire**, not kHz. (ADIF `FREQ` is also MHz, so
  pass it through unchanged.) A shipped bug once divided by 1000 twice and
  displayed `0.014` for 14.074 MHz.
- Field names are camelCase, with `rawADIF` and `isActivityLogQSO` as
  irregular spellings.
- Entries are never mutated in place. An edit is a new entry with the same QSO
  id and a later `seq`; a delete is a tombstone. Last write wins by `seq`.

## Writing to the log

Adding and updating are the same operation: append a journal entry.

1. Build the QSO record (or a delete tombstone).
2. Wrap it in a `JournalPayload`.
3. gzip, then ChaCha20-Poly1305 seal with the same data key.
4. `POST /v1/sync/push` (`sync:write`) with entry metadata — the response
   returns a presigned upload URL per entry.
5. `PUT` the ciphertext to that URL.

Push is idempotent on `client_entry_id`, so retrying a timed-out push is safe.
Retry `429` and `5xx` with backoff; the server applies a per-IP rate limit.

**Do not push plaintext.** The server does not inspect blobs, so it cannot stop
you, but every other client will fail to decrypt what you wrote and the user's
log will be corrupted from their perspective.

## Errors

OAuth endpoints return RFC 6749 §5.2 errors:

```json
{ "error": "invalid_grant", "error_description": "…" }
```

`invalid_grant` is deliberately undifferentiated across expired, unknown,
replayed, and mismatched grants — distinguishing them would be an oracle.

The rest of the API uses this server's usual envelope:

```json
{ "error": { "code": "FORBIDDEN", "message": "Forbidden" } }
```

| Status | Meaning for a third-party token |
|---|---|
| `401` | Missing, expired, or invalid access token — refresh |
| `403 FORBIDDEN` | Route not permitted for third parties, or missing scope |
| `403 ACCOUNT_REQUIRED` | The token has no account tenant |
| `429` | Rate limited — back off |

## What a token cannot do

- **Decrypt anything.** The server never sees the passphrase or the data key.
- **Reach un-scoped routes.** Default-deny; unlisted means `403`.
- **Widen its own scope.** Not at refresh, not ever.
- **Outlive revoked consent** by more than one access-token lifetime (15 min).
- **Use another client's tokens.** Codes and refresh tokens are client-bound.

---

## Implementation notes

| Concern | Location |
|---|---|
| Endpoints | `src/handlers/oauth.rs` |
| Consent + device screens | `src/handlers/oauth_pages.rs` |
| Persistence | `src/db/oauth.rs` |
| Schema | `migrations/047_oauth_provider.sql` |
| **Default-deny scope map** | `src/auth/scope_map.rs` |
| Token claims (`cid`, id_token) | `src/auth/jwt.rs` |
| Gate enforcement | `src/auth/middleware.rs` |

Adding a route to `main.rs` without classifying it in `scope_map.rs` fails the
`scope_map_covers_every_route` test. That is intentional: it forces a decision
about third-party exposure at the moment the route is added.
