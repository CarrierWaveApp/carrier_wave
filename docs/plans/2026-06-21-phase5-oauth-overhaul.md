# Phase 5 — OAuth2 auth overhaul (design)

**Date:** 2026-06-21
**Status:** design — security-hardened 2026-06-21 after adversarial review (see §1, §15)
**Phase:** 5 (gates the `cw-sync` server transport)
**Companions:**
[migration plan §10](2026-06-13-rust-core-migration.md) ·
[rustification finish handoff §Phase 5](2026-06-18-rustification-finish-handoff.md) ·
[phase 4 cutover status](2026-06-20-phase4-cutover-status.md) ·
[server auth (current)](../../server/docs/features/auth.md)

This is the **gating** half of Phase 5. The other half — porting
`CloudSyncJournalEngine` to a `cw-sync` HTTPS transport against new `/sync`
endpoints — depends on the access-token carrier defined here and is specced
separately. Nothing here ships to users until the server side is deployed and
the client wiring lands.

---

## 1. Decisions (locked 2026-06-21)

| # | Question | Decision |
|---|----------|----------|
| D1 | First deliverable | **This design doc**, reviewed before any code. |
| D2 | Identity scope | **Add callsign-ownership verification** — not just token hardening. |
| D3 | Verification mechanism | **Email magic-link** (primary): callsign → registered email → one-time link. |
| D4 | Access-token format | **JWT access** (short TTL) **+ opaque rotating refresh** (hashed at rest). |
| D5 | Existing `fd_` device tokens | **Forced re-auth** — retire all `fd_` tokens; every device re-establishes identity. |
| D6 | Legacy data reattachment (was O1) | **Directory-email only.** Inheriting existing callsign-keyed data (challenges/progress/badges) requires `directory_email` proof. `user_email` accounts start clean-slate / lower-tier — **resolved by security review F1/F2.** |
| D7 | JWT algorithm (was O3) | **EdDSA (Ed25519), single hardcoded alg.** Multi-service JWKS verification is a goal; accepting >1 alg family is an algorithm-confusion vuln — **resolved by security review F5.** |
| D8 | Callsign scope (was O2) | **Multi-callsign from day one.** An account may hold N verified callsigns (vanity/club/portable); each verified independently. Schema was already N-ready. |
| D9 | Email provider (was O5) | **Resend** — HTTP API over existing `reqwest`; send from `noreply@carrierwave.app`; new DKIM/SPF/DMARC records on `carrierwave.app` (Porkbun/Terraform); API key in ansible vault. |
| D10 | Deployment topology (was O8) | **Plan for multi-instance now** — shared-nothing horizontal pool; revocation propagation via **Postgres `LISTEN/NOTIFY`** (no in-process-only cache). Designed + tested for N instances even though v1 deploys 1. |

These supersede the three "still to settle" items in
[migration plan §10](2026-06-13-rust-core-migration.md): D3 settles verification,
D4 settles refresh-rotation/revocation, D5 settles the device-token migration UX.
(SQLCipher key recovery is a `cw-store` concern, out of scope here.)

> **Security hardening (2026-06-21).** An adversarial design review (§15) found two
> Critical identity-takeover paths (F1, F2) and several High issues (F3–F6). Their
> mitigations are folded inline below; D6 and D7 close the two open questions the
> review escalated. The full findings list with severities is §15.

## 2. Goals / non-goals

**Goals**
- A single unified identity (`account`, keyed by verified callsign) shared by the
  social/challenges API **and** the forthcoming sync API.
- OAuth2-style token lifecycle: short-lived JWT access tokens, long-lived opaque
  refresh tokens with **rotation** (refresh is single-use; reuse ⇒ family revoke).
- **Server-side revocation**: per-refresh, per-device, and per-account "log out
  everywhere."
- **Scopes** so a sync access token and a social access token are distinguishable
  and least-privilege.
- Real **callsign-ownership proof** via email magic-link before an account is
  issued tokens.
- A clean forced-cutover from `fd_` device tokens.

**Non-goals (this doc)**
- The `cw-sync` HTTPS transport, `/sync` endpoints, Postgres sync tables, change
  feed — separate spec; this only defines the *token they carry*.
- LoTW/QRZ credential proof (D3 chose email magic-link; LoTW is a possible future
  "verified+" tier, noted in §11).
- SQLCipher local-store key handling.
- Third-party / delegated OAuth (we are the issuer, not a relying party). "OAuth2-
  style" = we mint and rotate our own tokens; there is no external IdP.

## 3. Two infrastructure gaps to close first (flagged)

The chosen design needs two capabilities the server **does not have today**:

1. **Outbound email.** No `lettre`/SMTP/transactional-email integration exists
   (`Cargo.toml` has `reqwest` but no mailer). Magic-link **requires** sending
   mail. **Resolved (D9): Resend** via the existing `reqwest` client (HTTPS POST to
   the Resend API) — no SMTP on the Hetzner box, deliverability/DKIM owned by the
   provider. New env: `RESEND_API_KEY`, `EMAIL_FROM=noreply@carrierwave.app` (key in
   ansible vault). **New DNS (Porkbun/Terraform `dns.tf`): DKIM, SPF, and DMARC
   records for `carrierwave.app`** — a prerequisite for deliverability, must land
   before cutover. A `Mailer` trait abstracts it; `NullMailer` (logs the link,
   **env-guarded off in prod**, F15) backs local dev + tests.

2. **Callsign → email resolution.** QRZ/ULS lookup is **iOS-only** today
   (`qrz-callsign-lookup` skill); the server has no resolver. Magic-link must map
   a claimed callsign to a deliverable address. **Two sub-paths, support both:**
   - **Directory resolve** — server queries QRZ XML (`<email>`) and/or FCC ULS
     for the callsign's on-file address, sends there. *Risk:* QRZ `<email>` is
     frequently private/absent and ULS email is increasingly redacted, so this
     fails for many ops. Needs a QRZ XML subscriber credential in server env.
   - **User-supplied + record** — user types their email; we send the link there
     and **store which email verified which callsign**. Weaker as ownership proof
     (proves email control, not callsign control) but always works.

   **Resolved (D6, security review F1/F2):** the two methods are **different trust
   tiers with different rights**, not just an audit flag:
   - `directory_email` (address came from the directory **for that exact callsign**,
     never an attacker-supplied "match") — the only tier permitted to **reattach
     pre-existing callsign-keyed data** (challenges/progress/badges/leaderboard) and
     to mint leaderboard-affecting `social:write` for that callsign.
   - `user_email` (user typed an address) — proves email control, **not** callsign
     ownership. Such an account is **clean-slate**: it may use the app but may
     **not** inherit existing callsign history and is flagged unverified-ownership
     in any public/competitive surface. It can later upgrade to `directory_email`.

   Without this split, user-supplied email launders an unverified claim into a
   "verified" account and lets anyone inherit any callsign's data (F1) and
   land-grab callsigns during cutover (F2). Every consumer of identity must branch
   on `verification_method` — enforced centrally, not per-handler (see §9).

## 4. Identity model

```
account (1) ───< account_callsign (N)        -- an account may hold multiple callsigns
   │                                             (vanity/club/portable); each verified
   │                                             independently
   ├──< device (N)                            -- a registered client install
   │       └──< refresh_token (N, 1 live)     -- rotating; family chain per device
   └──< (access tokens are stateless JWTs, not stored)
```

- **Primary key of identity = `account.id` (UUID).** Callsign is an *attribute*
  (verified per-callsign), not the PK — this fixes today's bug where identity ==
  a mutable claimed string and lets W6JSV→W6JY-style callsign changes (see
  user memory) keep one account.
- **Multi-callsign from day one (D8).** An account holds N verified callsigns;
  adding one is an authed flow (§8 `verify/start` with a bearer token attaches to
  the existing account instead of creating one). Each callsign carries its own
  `verification_method` tier (D6), so a `directory_email`-verified call can inherit
  data while a `user_email` one on the same account cannot. `primary_callsign` is
  the JWT's `cs` convenience claim (non-authoritative). Authorization always checks
  the *set* via `assert_account_owns_callsign` (F6), never the single `cs` claim.

## 5. Token model

### Access token — JWT, stateless
- **Alg:** **EdDSA (Ed25519) only** (D7) via `jsonwebtoken`. Asymmetric so the sync
  service (and any future service) verifies with the public key without sharing a
  secret; the public JWKS is published. **No HS256 fallback** — a verifier that
  accepts both alg families is the classic asymmetric-vs-symmetric confusion attack
  (sign with the public key as an HS256 secret). One alg, hardcoded.
- **TTL:** 15 min.
- **Claims:** `iss` (server URL), `sub` = `account.id`, `aud` (`cw-sync` /
  `cw-social`), `scope` (space-delimited), `cs` = primary callsign (convenience,
  **non-authoritative — never authorize on `cs`**, always resolve via
  `account_callsigns`), `iat`, `exp`, `jti`. `kid` in header for rotation.
- **Verification policy (mandatory, F5):** `Validation::new(Algorithm::EdDSA)` and
  reject every other `alg`; **require and validate `aud`** against the *specific*
  verifying service (a `cw-social` token must be rejected by the `cw-sync`
  verifier — so `verify_access` takes the expected `aud` as a parameter); require
  and validate `iss`; explicit clock-skew leeway (~30–60 s); reject unknown/missing
  `kid` and resolve `kid` only against the bounded local key set (never a
  `kid`-as-path/URL); JWKS endpoint cache-controlled and bounded.
- **Revocation:** by short TTL. No per-request DB hit on the hot path — the JWT
  verifies cryptographically. For emergency pre-expiry kill, use a cheap
  `tokens_valid_after` epoch (per-account, optionally global) compared against
  `iat`, **not** an unbounded `jti` denylist scan; the `revoked_jti` table is a
  targeted backstop, prune-by-`expires_at`, and its multi-instance propagation is
  specified in §9 (F3).

### Refresh token — opaque, rotating, hashed at rest
- **Format:** `cwr_` + 32 bytes base64url from a CSPRNG (~256 bits). The `cwr_`
  prefix replaces `fd_` and makes secret-scanners/log filters trivial.
- **Storage:** only the **SHA-256 hash** is stored (`refresh_token.token_hash`);
  the plaintext is returned once. `sha2` is already a dep; refresh tokens are
  high-entropy so a fast hash is correct (argon2 is for low-entropy passwords —
  not needed, not added).
- **TTL:** 60 days sliding (each rotation re-bases expiry).
- **Rotation:** every `/token/refresh` issues a **new** refresh + access pair and
  marks the presented refresh `rotated`. Tokens form a **family** (`family_id`,
  per device).
- **Idempotent rotation + reuse detection (F4 — avoids self-DoS).** A sync product
  shares Keychain across processes (app + widget + watch), so concurrent/retried
  refresh is *normal*, not an attack. Rules:
  - Rotation runs in a transaction with `SELECT … FOR UPDATE` on the family row to
    serialize concurrent refreshes.
  - The parent row records its successor (`replaced_by`). Re-presenting a token
    that was **rotated within a short grace window** (e.g. 60 s) returns the
    **already-issued successor pair** (idempotent replay), it does **not** revoke.
  - Re-presenting a token rotated **outside** the grace window, or one already
    `revoked`, is true reuse ⇒ **revoke the whole family** and force re-auth on
    that device. On family-revoke, signal *all* the account's devices so the
    legitimate user learns of the theft instead of being silently displaced (F11).
- **Absolute lifetime (F12):** in addition to the 60-day sliding window, a family
  has a hard maximum age (e.g. force full re-auth + re-verification every ~6 mo),
  so a warm-kept compromised token can't persist indefinitely.
- **Scopes:** stored on the refresh row; access tokens minted from it inherit
  (or down-scope) them.

## 6. Scopes (v1)

| Scope | Grants |
|-------|--------|
| `sync:read` | Pull journal payloads from `/sync`. |
| `sync:write` | Push journal payloads to `/sync`. |
| `social:read` | Challenges/leaderboards/feed reads that need identity. |
| `social:write` | Join/progress/leave, club actions, spot posts. |
| `account` | Manage own devices/sessions, read own profile. |

A normal app install requests all five. The set is small and additive; the point
is least-privilege per `aud` and a forward hook for future service tokens.

## 7. Server-side schema (new migrations)

New migration(s) after `025_*` (next free number). DDL sketch:

```sql
-- accounts: the unified identity
CREATE TABLE accounts (
    id            UUID PRIMARY KEY,
    primary_callsign TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    status        TEXT NOT NULL DEFAULT 'active',  -- active | suspended
    -- emergency/global kill: access JWTs with iat < this are rejected (F3).
    tokens_valid_after TIMESTAMPTZ,
    -- primary_callsign must be a callsign this account actually verified (F10):
    FOREIGN KEY (id, primary_callsign)
        REFERENCES account_callsigns(account_id, callsign) DEFERRABLE INITIALLY DEFERRED
);

-- verified callsigns held by an account
CREATE TABLE account_callsigns (
    account_id    UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    callsign      TEXT NOT NULL,
    verified_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    verification_method TEXT NOT NULL,            -- directory_email | user_email
    verified_email TEXT,                          -- audit/PII: where the link went (see retention §7)
    PRIMARY KEY (account_id, callsign),
    UNIQUE (account_id, callsign)                 -- target of accounts' composite FK
);
-- One account per callsign, case-insensitive. NOTE (F10): this makes a claim
-- exclusive + permanent, which (a) feeds the cutover land-grab — mitigated by
-- D6 (directory-email required to inherit data) — and (b) has no story for an
-- FCC-reassigned/lapsed callsign going to a new licensee. Reassignment is an
-- admin transfer/release flow (release the row, audit-logged), NOT a silent
-- re-point. Tracked as O7.
CREATE UNIQUE INDEX uq_account_callsigns_callsign ON account_callsigns(upper(callsign));

-- magic-link verification challenges
CREATE TABLE email_verifications (
    id            UUID PRIMARY KEY,
    callsign      TEXT NOT NULL,
    email         TEXT NOT NULL,
    code_hash     BYTEA NOT NULL,                 -- sha256 of the one-time code
    method        TEXT NOT NULL,                  -- directory_email | user_email
    account_id    UUID REFERENCES accounts(id),   -- non-null = attach to existing account (D8); null = onboarding
    expires_at    TIMESTAMPTZ NOT NULL,           -- now() + 15 min
    consumed_at   TIMESTAMPTZ,
    attempts      INT NOT NULL DEFAULT 0,          -- code-check attempts; locked at MAX (e.g. 5)
    pkce_challenge TEXT NOT NULL,                  -- S256 of the app's verifier (F8 device binding)
    request_ip    INET,                            -- abuse forensics
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_email_verifications_callsign ON email_verifications(callsign);
-- RETENTION (F10/PII): purge consumed + expired rows on a schedule (e.g. daily,
-- older than 7 days). Do not retain verification emails indefinitely.

-- a registered client install
CREATE TABLE devices (
    id            UUID PRIMARY KEY,
    account_id    UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    device_name   TEXT,
    platform      TEXT,                           -- ios | macos | android
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Per-account device cap enforced in app logic (e.g. 20); prune LRU to bound
-- refresh-family growth + "log out everywhere" cost (F10).

-- rotating refresh tokens (one live per family/device)
CREATE TABLE refresh_tokens (
    id            UUID PRIMARY KEY,
    device_id     UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    account_id    UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    family_id     UUID NOT NULL,                  -- rotation chain
    token_hash    BYTEA NOT NULL UNIQUE,          -- sha256(plaintext)
    scopes        TEXT NOT NULL,                  -- space-delimited
    replaced_by   UUID REFERENCES refresh_tokens(id), -- successor (idempotent replay, F4)
    issued_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL,           -- sliding (60d); family also has an absolute cap (F12)
    family_started_at TIMESTAMPTZ NOT NULL DEFAULT now(), -- absolute-lifetime anchor (F12)
    rotated_at    TIMESTAMPTZ,                    -- set when superseded
    revoked_at    TIMESTAMPTZ,                    -- set on explicit/forced revoke
    revoked_reason TEXT,                          -- logout | reuse_detected | admin | cutover
    last_used_ip  INET                            -- reuse forensics (F10/F11)
);
CREATE INDEX idx_refresh_tokens_family ON refresh_tokens(family_id);
-- "One live token per family" as a DB invariant (F10), not just convention:
CREATE UNIQUE INDEX uq_refresh_live_per_family ON refresh_tokens(family_id)
    WHERE rotated_at IS NULL AND revoked_at IS NULL;

-- emergency access-token denylist (NOT the hot path; checked only when populated)
CREATE TABLE revoked_jti (
    jti           TEXT PRIMARY KEY,
    expires_at    TIMESTAMPTZ NOT NULL            -- prune past exp
);
```

**`participants` (existing):** keep the table — challenges/progress/badges FK on
`callsign`, not on `participants.id`, so they're unaffected by retiring tokens.
Add a nullable `account_id UUID REFERENCES accounts(id)` to `participants` to
link legacy rows to the new identity as accounts are created. **D5 forced re-auth:**
in the cutover migration, **drop the `device_token` uniqueness/usefulness** — set
all `participants.device_token` to a sentinel or add a `tokens_revoked_at` so
`validate_token` (legacy path) rejects every `fd_` token after the flag date.

## 8. Endpoints

All under `/v1/auth/*`, public (no bearer) except where noted.

| Method | Path | Body / notes |
|--------|------|--------------|
| `POST` | `/v1/auth/verify/start` | `{ callsign, email?, pkce_challenge }`. **Optional bearer** (`account` scope): if present, this verification *attaches* the callsign to the existing account (D8 multi-callsign add); if absent, it's onboarding a new account. Resolves address (directory, else supplied), records the method tier (D6), stores the app's PKCE S256 challenge, creates `email_verifications`, sends magic-link. **Always 202** (no account/callsign enumeration). Rate-limited per §12-O6. |
| `GET`  | `/v1/auth/verify/complete` | `?code=...` (the link target). Validates code (single-use, attempt-capped), marks consumed, renders a minimal **static** success page ("return to the app") — **no user-controlled content, `Referrer-Policy: no-referrer`, strict CSP**. The code is *not* yet a credential: the app must still present the PKCE verifier to `/token`. |
| `POST` | `/v1/auth/token` | `{ code, pkce_verifier, device_name, platform, scopes }` → server checks `S256(pkce_verifier) == pkce_challenge` (binds redemption to the device that started verify, F8), enforces D6 tier on any data reattachment. If the verification row's `account_id` is set (D8 attach), adds the callsign to that account and returns 204; otherwise creates account + device + refresh family and returns `{ access, refresh, expires_in, account_id }`. |
| `POST` | `/v1/auth/token/refresh` | `{ refresh }` → rotates; returns new `{ access, refresh, expires_in }`. Reuse ⇒ 401 + family revoke. |
| `POST` | `/v1/auth/logout` | bearer or `{ refresh }` → revoke this device's family. |
| `POST` | `/v1/auth/logout/all` | bearer (`account` scope) → revoke every family for the account. |
| `GET`  | `/v1/auth/devices` | bearer → list account devices/sessions. |
| `DELETE` | `/v1/auth/devices/{id}` | bearer → revoke a specific device. |
| `GET`  | `/.well-known/jwks.json` | public key set (EdDSA path only). |

**Magic-link UX:** the email link points at `verify/complete`; opening it marks the
code consumed and returns a static "return to the app" page. The app — which holds
the PKCE verifier from its own `verify/start` call — then redeems `code +
pkce_verifier` at `/token`. Because redemption requires the verifier, a leaked link
alone (logs, screenshot, click-tracking) **cannot mint tokens** (F8). The app
learns the code is ready by polling `verify/complete` status **or** via a hardcoded
universal link back into the app (no `?next=`/redirect param — open-redirect/XSS
surface, F9); universal link is the nicer path — **O4**. The `?code=` query string
must be excluded from nginx access logs and the email provider's click-tracking
must be disabled (else it pre-consumes the single-use code).

## 9. Middleware changes (`server/src/auth/`)

- **New `jwt.rs`:** key load (env `JWT_ED25519_PRIVATE_KEY` / public),
  `mint_access(account_id, aud, scopes)`, `verify_access(token, expected_aud) ->
  Claims` enforcing the full policy in §5 (alg-locked, `aud`/`iss` validated,
  leeway, `kid`). Compares `iat` against the account's `tokens_valid_after` epoch.
- **New `tokens.rs`:** refresh generation (`cwr_…`), hashing (`sha2`), idempotent
  rotation (FOR UPDATE + grace-window replay → successor), family-revoke, reuse
  detection. Reuse `subtle::ConstantTimeEq` for hash compare.
- **New `authz.rs`:** **`assert_account_owns_callsign(account_id, callsign)`**
  (F6) — backed by `account_callsigns`, case-insensitive. **Mandatory on every
  callsign-scoped mutation.** The old model coupled token↔callsign in one row; the
  new model decouples them, so any handler that takes a callsign from the request
  body/path could otherwise let account A write B's data (IDOR). Also exposes the
  D6 tier so callsign-keyed *reattachment* checks `verification_method ==
  directory_email`.
- **Rewrite `middleware.rs`:**
  - `require_auth` → verify JWT (no per-request DB hit on the steady-state path),
    build `AuthContext { account_id, callsign, scopes }`.
  - **Emergency revocation (F3, D10 multi-instance):** the steady-state fast path
    stays DB-free via an in-process cache of `tokens_valid_after` epochs + the
    `revoked_jti` set; the cache is invalidated across all instances via **Postgres
    `LISTEN/NOTIFY`** (channel e.g. `auth_revocation`, payload = account id / jti).
    No in-process-only path (that would be unsound the moment a second instance
    exists). Worst-case revocation latency = NOTIFY round-trip (sub-second);
    document it. On startup each instance `LISTEN`s and warms the cache; the
    `revoked_jti` table is pruned by `expires_at`.
  - Add `require_scope(scope)` layer/extractor for per-route least-privilege.
  - `optional_auth` (F14): distinguish **no token** (proceed anonymous) from
    **present-but-invalid/expired token** (reject with 401) — do *not* silently
    downgrade a client that believes it's authenticated into an anonymous action.
  - `require_admin` unchanged (static admin token stays).
- **`AuthContext`** gains `account_id: Uuid` and `scopes: Vec<String>`;
  `participant_id` removed (resolve via `account_id`/callsign where still needed).
  This is the main downstream churn — **enumerate (grep) every `participant_id`
  read AND every request-supplied `callsign`** before cutover (the review flags
  this as more than "a handful"); each callsign-scoped mutation must route through
  `assert_account_owns_callsign` (F6).
- **Retire `token.rs`** (`generate_device_token`/`is_valid_token_format`) after
  the legacy validate path is removed post-cutover.
- **State:** extend router state from bare `PgPool` to an `AppState { pool,
  jwt_keys, mailer, config }` (use `axum`'s `FromRef`); `with_state(pool)` at
  `main.rs:611` becomes `with_state(app_state)`.

## 10. Client changes (out of scope to *build* here; enumerated for the doc)

- **Swift (`CarrierWaveData`/networking):** store refresh in Keychain (not
  `UserDefaults`); an actor that holds the in-memory access token, refreshes on
  401/expiry with single-flight (no thundering herd), and surfaces a
  re-auth-required state when refresh fails. Replaces wherever the `fd_` token is
  read today.
- **`cw-net`/`cw-sync` (Rust):** the HTTPS `SyncTransport` impl (future spec)
  takes an access-token provider closure; `transport.rs`'s doc comment already
  anticipates "carrying an OAuth access token." cw-core stays stateless about
  identity — the platform supplies tokens over FFI.
- **Onboarding UI:** callsign + (maybe email) entry → "check your email" → return.
  Forced re-auth means existing users hit this once on first launch after the
  update.
- **macOS Sweep:** lockstep (decision #5), same `CarrierWaveData` shim.

## 11. Forced re-auth cutover (D5)

1. Ship server with **both** paths live for a short window? — **No.** D5 chose a
   clean cutover. Plan:
   - Deploy server with new `/v1/auth/*` + new middleware; legacy `validate_token`
     rejects all `fd_` tokens (flag/sentinel from the migration).
   - Ship the app update that knows the new flow on the same date.
   - On first launch post-update, the client finds no valid refresh → routes to
     onboarding/verify. Challenges/progress are keyed on callsign, so **no user
     data is lost** — they re-verify the same callsign and reattach.
   - **Land-grab defense (F2 — Critical).** The `upper(callsign)` unique index makes
     claiming first-come-first-served *and* permanent; without guards, an attacker
     who knows a victim hasn't re-verified can claim their callsign during the
     window and inherit their history. Defenses (all required):
     - **Reattachment of legacy callsign-keyed data requires `directory_email`**
       (D6). A `user_email` claim cannot inherit an established callsign's data, so
       grabbing the *string* yields nothing of value.
     - At migration, **seed `account_callsigns` for known-active participants bound
       to no account** (claim-reserved), so the legacy owner's callsign can only be
       claimed via directory-resolve, not user-supplied.
     - **Rate-limit + alert on bulk verification** during the cutover window; cap
       directory-resolved sends per callsign/day (ties to O6).
     - Ship an **admin dispute/transfer/recovery flow before cutover**, not after
       (also covers FCC callsign reassignment, O7).
2. Comms: What's New entry + a one-line in-app explainer ("sign-in changed; verify
   your callsign once"). Per CLAUDE.md, add a `WhatsNewEntry` when this ships.
3. Rollback: if the new auth is broken, the app is unusable for authed features —
   so gate behind a server feature flag + keep the deploy reversible; do **not**
   delete `participants.device_token` data in the cutover migration (sentinel/flag
   only) so a rollback can restore validation.

## 12. Open questions

- ~~**O1.** user-supplied email fallback acceptable?~~ **RESOLVED → D6:**
  user-supplied allowed for app *use* but **never** for inheriting callsign-keyed
  data; directory-email required for that. (§3)
- ~~**O2.** one vs multi-callsign for v1?~~ **RESOLVED → D8: multi-callsign from
  day one** (authed attach flow, §8). (§4)
- ~~**O3.** EdDSA vs HS256?~~ **RESOLVED → D7: EdDSA only**, single hardcoded alg,
  JWKS published. (§5)
- ~~**O4.** Magic-link return: universal link vs app-polls-for-completion?~~
  **RESOLVED 2026-06-21 → build both.** Polling (`verify/start`→`pollToken`,
  `verify/poll`) is live and the default; the universal-link/`carrierwave://auth`
  handler is built but the https half is inert until the `associated-domains`
  entitlement + AASA land (infra #5). Return target hardcoded, no redirect param
  (F9). (§8, §16)
- ~~**O5.** email provider + sending domain/DKIM?~~ **RESOLVED → D9: Resend**, send
  from `noreply@carrierwave.app`; DKIM/SPF/DMARC to be added to `dns.tf` before
  cutover. (§3)
- **O6.** Anti-abuse budget for `verify/start` (email-bombing a callsign's on-file
  address is a concrete harm — F7). **Now a requirement, not a suggestion;** numbers
  to confirm: per-callsign cap (≤3 unconsumed, ≤N/day), per-IP + global rate limit,
  dedupe identical (callsign,email) in-window, hard daily cap on directory-resolved
  sends per callsign regardless of IP, exponential backoff; CAPTCHA/PoW if abuse
  appears; `email_verifications.attempts` lockout ≤5. (§3)
- **O7.** (new) Admin **callsign transfer/release** policy — FCC reassignment of a
  lapsed callsign to a new licensee; needed before cutover (also disarms F2). (§7)
- ~~**O8.** (new) deployment topology?~~ **RESOLVED → D10: plan for multi-instance
  now** — shared-nothing, Postgres `LISTEN/NOTIFY` revocation propagation,
  sub-second worst-case latency. v1 still deploys 1 instance. (§9)

## 13. Implementation phasing (once design approved)

> **Status (2026-06-21): server-side steps 1–6 + step-7 dual-auth IMPLEMENTED, additive + tested.**
> Migration `044`, `auth/{jwt,tokens,mailer,jwt_middleware,revocation}.rs`,
> `db/auth.rs`, and `handlers/auth.rs` (`/v1/auth/*`, incl. authed
> logout-all/devices/multi-callsign-attach) are landed and green: 180 server tests
> (unit + DB-gated integration + HTTP onboarding→token→refresh→logout + dual-auth +
> revocation), clippy-clean, full `cargo build`.
>
> **Step 7 first half done (dual-auth):** the legacy `require_auth`/`optional_auth`
> now accept a JWT access token OR an `fd_` token — a JWT request resolves a
> `participants` bridge row so all existing handlers work unchanged, and
> `AuthContext` carries an optional `account_id`. Revocation propagates via a
> shared cache + Postgres `LISTEN/NOTIFY` (D10/F3). Multi-callsign attach is wired
> over HTTP (`/v1/auth/callsigns/verify/start`, D8).
>
> **Directory-email tier done:** `auth/directory.rs` resolves callsign→on-file
> email via QRZ XML (Null when creds unset, fail-closed to `user_email`). When the
> directory resolves, the link is sent to the on-file address and recorded as
> `directory_email` (the inheritance-eligible tier); an attacker-supplied email
> can't redirect a directory-resolvable callsign (F1, tested). Needs `QRZ_USERNAME`/
> `QRZ_PASSWORD` in prod.
>
> **Step 8 client core started (iOS):** `OAuthClient` actor (PKCE verify→exchange,
> single-flight refresh, logout; Keychain refresh token, in-memory access token).
> `ActivitiesClient.ensureAuthToken()` prefers OAuth, falls back to `fd_` (dual).
> Remaining client: onboarding/verify UI + magic-link return path (O4) to deliver
> the `code` to `exchange`, and migrating direct `getAuthToken()` call sites.
> (App-target compile verified by Xcode Cloud; SwiftFormat/SwiftLint clean.)
>
> **Not yet done:** legacy `fd_` *rejection* (the final hard cutover — step 7
> second half), the rest of step 8 (client UI), step 9 (cutover). Note: actual
> data-reattachment *logic* on directory_email accounts (vs. just recording the
> tier) lands with the handler migration in the cutover.

Server-first, each independently testable with `cargo test`:

1. **Schema + models** — migrations (§7), sqlx models, no behavior change.
2. **JWT core** — `jwt.rs` mint/verify + key loading + unit tests; `jsonwebtoken`
   dep. No routes yet.
3. **Refresh core** — `tokens.rs` generate/hash/**idempotent rotation (FOR UPDATE
   + grace-window successor replay, F4)**/family-revoke + reuse detection + tests
   incl. a concurrent-refresh test asserting *no* false-positive family revoke.
4. **Mailer + resolver** — `Mailer` trait + `NullMailer` (dev/test, env-guarded so
   it can never run in prod, F15) + **Resend** impl (D9, `reqwest` POST,
   `RESEND_API_KEY`); callsign→email resolver (directory **vs** user-supplied →
   `verification_method` tier per D6); `verify/*` rate-limits + attempt lockout (O6).
5. **`authz.rs`** — `assert_account_owns_callsign` + D6 reattachment-tier gate (F6);
   unit tests for the IDOR and `user_email`-cannot-inherit cases.
6. **Endpoints** — `/v1/auth/*` handlers (PKCE bind, F8) wired to the above;
   integration tests with `NullMailer` driving the full
   verify→token→refresh→logout loop **plus** the negative paths: leaked-code-only
   redemption fails, cross-callsign write fails, reuse-revoke fires, concurrent
   refresh succeeds.
7. **Middleware swap** — JWT `require_auth(expected_aud)`/`require_scope`;
   `optional_auth` reject-on-invalid (F14); `tokens_valid_after` epoch check +
   `LISTEN/NOTIFY` revocation propagation (D10); migrate handlers off
   `participant_id` → `account_id` routing all callsign mutations through
   `assert_account_owns_callsign`; legacy `fd_` rejection.
8. **Client wiring** (separate session) — Swift Keychain + single-flight refresh
   actor; PKCE verifier on the device; multi-callsign add UI (D8); cw-net token
   provider; onboarding UI; Sweep lockstep.
9. **Cutover** — DKIM/SPF/DMARC DNS for `carrierwave.app` (D9) + Resend domain
   verified, admin transfer/dispute flow (O7) + claim-reserved seeding live
   *first*, then deploy + app release + What's New, per §11.

Gate (server): `cargo build` + `cargo test` + `cargo clippy -- -D warnings`.

## 14. Security notes

- Access tokens never stored server-side; refresh tokens stored **hashed** only.
- Refresh **rotation + family-revoke** gives stolen-token reuse detection.
- Magic-link codes: high-entropy, hashed at rest, 15-min expiry, single-use,
  attempt-capped, `verify/start` always 202 (no account/callsign enumeration).
- Constant-time compares (`subtle`) for any secret/hash comparison.
- Scopes enforce least privilege per `aud`; sync tokens can't drive social writes.
- Admin token path unchanged (already constant-time, CAR-144).
- TLS-only (already the case behind nginx); refresh only over HTTPS.
- **Ownership ≠ email control:** `directory_email` is the only tier that inherits
  callsign data or affects competitive surfaces (D6/F1).
- **JWT policy is pinned** (alg-locked, `aud`/`iss` validated, leeway, `kid`); never
  authorize on the `cs` claim (F5).
- **Idempotent refresh rotation** prevents legitimate concurrent refresh from
  self-DoSing the user (F4).
- **PKCE-bound magic links:** a leaked link/code alone can't mint tokens (F8); no
  redirect param on the success page (F9); `?code=` stripped from logs/click-tracking.
- **PII:** `email_verifications` purged on a schedule; `verified_email` deletable on
  account-deletion request (F10).
- Single factor (email) is an accepted risk for v1; no MFA (F13). Revisit with a
  LoTW "verified+" tier (§11-future).

## 15. Security review findings (2026-06-21)

Adversarial design review by a security subagent. **All Critical/High mitigations
are folded into §1–§14 above**; this section is the audit trail. Severities are the
reviewer's.

| # | Sev | Issue | Where mitigated |
|---|-----|-------|-----------------|
| F1 | **Critical** | user-supplied email → claim any callsign + inherit its data (identity laundering) | D6, §3 tiers, §9 `authz.rs` |
| F2 | **Critical** | cutover land-grab via the exclusive `upper(callsign)` index | §11 land-grab defense, D6, O7 |
| F3 | High | `revoked_jti` skip-if-empty unsound multi-instance; stale cache honors revoked tokens | §5/§9 `tokens_valid_after` epoch + LISTEN/NOTIFY (O8) |
| F4 | High | concurrent/retried refresh → false-positive family revoke (self-DoS) | §5 idempotent rotation + grace window + FOR UPDATE |
| F5 | High | JWT verification under-specified (alg confusion, missing `aud`/`iss`, skew, `kid`) | §5 verification policy (mandatory), D7 |
| F6 | High | IDOR during `participant_id`→`account_id`: request-supplied callsign authorizes writes | §9 `assert_account_owns_callsign` (mandatory) |
| F7 | Medium | email-bombing real hams via unauthenticated `verify/start` | O6 now a requirement |
| F8 | Medium | magic-link `?code=` leaks (logs/referrer/click-tracking); ticket not device-bound | §8 PKCE binding + log/referrer hardening |
| F9 | Medium | open-redirect / reflected-XSS on the browser return path | §8 hardcoded return, static page, CSP (O4) |
| F10 | Medium | schema gaps: `primary_callsign` drift, no callsign-reassignment, PII retention, "one live/family" not a DB invariant, no device cap | §7 composite FK, partial unique index, retention note, O7, device cap |
| F11 | Medium | refresh theft fully portable; victim triggers the revoke, not the thief | §5 notify-all-devices on family-revoke; F13 future PoP/DPoP |
| F12 | Medium | 60-day sliding expiry never forces re-verification | §5 absolute family lifetime |
| F13 | Low/Med | no MFA; email is the sole factor | §14 accepted risk; LoTW tier future |
| F14 | Low | `optional_auth` may silently downgrade present-but-invalid token | §9 reject-on-invalid |
| F15 | Low | new secret-leak surfaces (`NullMailer` link, `reqwest` debug bodies) | §13 env-guard + log discipline |

**Confirmed sound (don't second-guess):** JWT-access + opaque-rotating-refresh
shape; SHA-256-without-salt for high-entropy tokens (argon2 unneeded); always-202
enumeration defense; UUID-not-callsign identity; `cwr_` prefix; constant-time
compares.

**Must-fix before implementation (review shortlist, all now reflected above):**
F1/F2 (D6 + land-grab defense + O7), F5 (JWT policy + D7), F4 (idempotent rotation),
F3 (revocation topology, O8), F6 (`assert_account_owns_callsign`), F7/O6 (hard rate
limits), F8 (PKCE-bound links).

## 16. Continuation handoff (2026-06-21)

**Where the work lives.** Branch `server/phase5-oauth-foundation`, checked out in
a worktree at `.claude/worktrees/phase5-oauth-foundation`. Nothing pushed. The
branch also carries one **unrelated, interleaved commit** — `3a2df4a7 cw-store:
port POTAAwards` (authored by Jay, landed here during a concurrent session); it's
reachable only from this branch, not `main`. Left as-is by choice; it rides along
on merge.

**Commits so far (newest first):**
- `f396c280` ios: fix OAuthClient actor isolation (verified by full app build)
- `8b0413e3` ios: OAuth client core + dual-token wiring (step 8 start)
- `69c3c86a` server: directory-email verification tier (D6/F1)
- `951e19eb` server: dual-auth on legacy routes (step 7, first half)
- `dcb2ef11` server: JWT middleware + revocation + authed endpoints
- `77d7ca5d` server: OAuth2 auth foundation (schema + jwt + tokens + endpoints)

### Done (server — all tested, additive, not yet live)
Steps 1–6 + step-7 dual-auth + directory tier. `cargo build` + 188 tests +
clippy-clean. Files: migration `044_oauth_accounts.sql`; `auth/{jwt, tokens,
mailer, jwt_middleware, revocation, directory}.rs`; `db/auth.rs`;
`handlers/auth.rs`; dual-auth in `auth/middleware.rs`; wiring in `main.rs`. The
`/v1/auth/*` routes only mount when `JWT_ED25519_PRIVATE_PEM`/`_PUBLIC_PEM` are
set; otherwise legacy `fd_` only.

### Done (server — O4 polling return path, 2026-06-21)
The polling half of O4 needed a server endpoint: the app never sees the emailed
link, and the server stores only `code_hash` (never the plaintext code), so it
**can't** "return the code." Instead `verify/start` now hands the app an opaque
`poll_token` and `verify/poll` mints tokens directly once the link is clicked.
- Migration `045_oauth_verify_poll.sql`: `poll_token_hash BYTEA` (+ index) on
  `email_verifications` (hashed at rest like the code/refresh token).
- `tokens.rs`: `generate_poll_token()` (`cwp_` prefix, 256-bit).
- `db/auth.rs`: `create_email_verification` stores the poll-token hash;
  `poll_verification()` → `PollResult::{Pending, Claim}` (consumes on success,
  PKCE-checked, `Forbidden` on verifier mismatch).
- `handlers/auth.rs`: `verify/start` (+ `callsigns/verify/start`) returns
  `{ pollToken }`; new `verify_poll` handler; shared `issue_from_claim` so
  `/token` (universal-link) and `/verify/poll` (polling) mint identically.
- `main.rs`: mounts `POST /v1/auth/verify/poll` (public).
- **F7 anti-enumeration:** `verify/start` *always* returns a poll token (even
  when nothing was deliverable) and `verify/poll` returns `202 Pending` for any
  unknown/unclicked/expired token — only `201`/`204` on real success, so every
  poll looks identical until issuance; the client times out on its own.
- `cargo build` + clippy-clean (auth files) + tests green: 31 lib + 6 HTTP incl.
  new `poll_flow_pending_until_clicked_then_claims` (db) and
  `poll_returns_pending_then_issues_tokens` (HTTP). Run with
  `TEST_DATABASE_URL=postgres://localhost/cw_oauth_test` (migration 045 applied).

### Done (server — JWKS endpoint, 2026-06-21)
`GET /.well-known/jwks.json` is now mounted (was missing). Publishes the EdDSA
signing key as an OKP/Ed25519 JWK (`kid`, base64url `x`) so the future `cw-sync`
verifier can validate access tokens by `kid` without a shared secret (§5/§14).
- `JwtKeys` keeps the raw 32-byte public key (parsed from the SPKI PEM) and
  exposes `jwks()`; `handlers::auth::jwks` serves it (content-type json,
  `cache-control: public, max-age=3600`); mounted at the domain root in
  `main.rs` only when OAuth keys are configured. New dep `base64` (already in
  the tree via `jsonwebtoken`).
- Verified live: served `x` decodes to the exact signing key; JWK `kid` matches
  the access-token header `kid`. Unit test `jwks_exposes_ed25519_public_key`.

### Done (iOS — verified compiling in the full app)
`OAuthClient` actor (`swift/ios/CarrierWave/Services/OAuthClient.swift`): PKCE
verify→exchange, single-flight refresh, logout; Keychain refresh token, in-memory
access token. `ActivitiesClient.ensureAuthToken()` prefers OAuth, falls back to
`fd_`. Keychain keys added in `CarrierWaveData`.

### Done (iOS — onboarding/verify UI + O4 "build both", 2026-06-21)
The end-to-end verify flow that makes OAuth usable. **O4 decision: build both** —
polling (works today) + universal-link handler (works once infra lands). Surfaced
as an **opt-in Settings entry** (forced cutover still deferred). `xcodebuild` of
the full app in the worktree: **BUILD SUCCEEDED**; SwiftFormat/SwiftLint clean.
- `OAuthClient`: `startVerification` now persists the in-flight `{verifier,
  pollToken, callsign}` to the Keychain (survives relaunch — the link can return
  via a fresh launch); `pollForCompletion()` (loops `verify/poll`, 201→persist /
  204→done / 202→retry, honours cancellation, ~3 min timeout); `completeWithCode()`
  (universal-link path → `exchange`); `hasPendingVerification()`,
  `pendingCallsign()`, `cancelPendingVerification()`; `sendForStatus` returns the
  HTTP status so poll can read 202 vs 201/204. New `OAuthError.{noPendingVerification,
  timedOut}`.
- `KeychainHelper.Keys`: `activitiesOAuthPending{Verifier,PollToken,Callsign}`.
- `OAuthVerifyView.swift` (new): callsign + optional email → "check your email"
  (auto-finishing poll) → success; cancel/retry/timeout states. Listens for
  `.didCompleteOAuthVerification` so the universal-link return also finishes it.
- `ActivitiesSettingsView`: "Callsign Verification" section (gated on community
  features) — Verify Callsign link / Verified + Sign Out; refreshes on appear +
  on `.didCompleteOAuthVerification`.
- Universal-link routing (`CarrierWaveApp+URLHandling`): `isOAuthReturnURL` +
  `handleOAuthReturnURL` handle **`carrierwave://auth?code=`** (custom scheme —
  works now, no entitlement) **and** `https://*.carrierwave.app/link/auth?code=`
  (universal link — once the `associated-domains` entitlement + AASA land). The
  app currently has **no `associated-domains` entitlement**, so the https half is
  inert until infra step #5; the custom-scheme half is live. New notifications
  `.didCompleteOAuthVerification` / `.didFailOAuthVerification`.

### How to verify (this worktree)
- **Server:** `TEST_DATABASE_URL=postgres://localhost/cw_oauth_test cargo test
  --manifest-path <worktree>/server/Cargo.toml` (the `cw_oauth_test` DB has
  migrations applied; PostGIS migrations are skipped locally — irrelevant to auth).
  Gate: `cargo build` + `cargo test` + `cargo clippy --all-targets`.
- **iOS:** the app builds in the worktree ONLY after staging the gitignored
  `CwFfi.xcframework`: copy it from the main repo into
  `<worktree>/swift/packages/CarrierWaveCore/Vendored/CwFfi.xcframework`, then
  `xcodebuild build -project <worktree>/swift/ios/CarrierWave.xcodeproj -scheme
  CarrierWave -destination 'generic/platform=iOS Simulator' -derivedDataPath
  /tmp/cw-oauth-dd CODE_SIGNING_ALLOWED=NO`. This catches isolation bugs that
  SourceKit/SwiftLint miss (it found two).

### Remaining — ordered
1. ~~**iOS onboarding/verify UI + magic-link return path (O4).**~~ **DONE
   2026-06-21** (build both: polling + universal-link; opt-in Settings entry).
   See "Done (iOS — onboarding/verify UI…)" and "Done (server — O4 polling…)"
   above. End-to-end usable via the polling path today. Residual: the
   universal-link half is built but inert until the `associated-domains`
   entitlement + AASA land (infra step #5); the email's `verify/complete` page
   still needs a server-side button/redirect to the `carrierwave://auth?code=`
   (live now) / `/link/auth?code=` (post-infra) return link — fold into infra #5.
2. **Migrate remaining iOS call sites** off direct `getAuthToken()` (e.g.
   `deleteAccount`, spots/telemetry) to `ensureAuthToken()` so they ride OAuth too.
3. **Directory resolver in prod** — set `QRZ_USERNAME`/`QRZ_PASSWORD`; until then
   every verification is `user_email` tier (no legacy-data inheritance, fail-closed).
4. **Server cutover (step 7 second half + step 9):** reject legacy `fd_` tokens,
   add the `directory_email` data-reattachment logic, migrate the few
   `participant_id`-keyed handlers to `account_id`. **Do this only after the iOS
   OAuth flow ships** so it's flag-day-safe. Needs the O7 callsign transfer flow
   and claim-reserved seeding first (§11).
5. **Infra:** DKIM/SPF/DMARC for `carrierwave.app` in `dns.tf`; `RESEND_API_KEY`,
   `EMAIL_FROM`, JWT Ed25519 keys, QRZ creds into the ansible vault (§3, §13).
6. **macOS Sweep** lockstep (same `CarrierWaveData`/client seams).

### Still-open questions (non-blocking for #2–#3)
O5 (confirm Resend + own a DKIM domain), O7 (callsign transfer policy — needed
before #4), O2-residual (multi-callsign UI surface). O4 resolved (build both, §16).
