# Another Morse Trainer (AMT) stats API

Contract Carrier Wave builds against for the AMT integration (streak + practice
days). The AMT server repo is private; this file is the reference. Handoff from
the AMT maintainer (N9HO), 2026-10-06. Questions: N9HO on Discord.

Implementation: `rust/cw-core/cw-net/src/amt.rs` (`AmtClient`) and
`rust/cw-core/cw-ffi/src/amt_api.rs` (`AmtApi`, shared by Swift and Kotlin);
Swift facade `CarrierWaveData/Services/AMT/AMTService.swift`; Android
`ui/settings/AmtViewModel.kt` + `HomeViewModel`.

## Basics

- Base URL: `https://amt-accounts.n9ho-amt.workers.dev`. Contract is stable
  under `/v1`: fields may be added, none removed/renamed/retyped without `/v2`.
  Ignore unknown fields.
- Client id: `client: "carrier-wave-ios"` for every platform (the user sees it
  in the email, the confirm page and their devices list); `platform` carries
  the real platform.
- Scope: `stats:read` only. We can read `/v1/me`, `/v1/me/stats`,
  `/v1/me/sessions` and sign ourselves out. We cannot see the email, write
  anything, read other users, or manage devices/profile.
- Numbers are self-reported by the AMT apps, not attested — never a public
  leaderboard. Stats are all zeros until the AMT apps start syncing (coming).
- Replies are `Cache-Control: private, no-store`.

## Sign-in (emailed link + PKCE)

1. `verifier` = 32 random bytes, base64url no padding (43 chars);
   `challenge` = base64url(SHA-256(verifier)) (RFC 7636 S256).
2. `POST /v1/auth/verify/start` `{ email, pkceChallenge, client, deviceName?,
   platform?, scopes: "stats:read" }` → always `202 { pollToken }` (never
   reveals whether the email has an account).
3. User opens the emailed link (valid 15 min) and presses **Confirm** — opening
   alone does nothing (email scanners follow links).
4. `POST /v1/auth/verify/poll` `{ pollToken, pkceVerifier }` every 2 s:
   `202` empty = pending · `201` `{ access, refresh, expiresIn, account { id,
   callsign, displayName } }` = signed in · `410` = link expired/used (offer a
   new link) · `400 invalid_verifier` = our bug · `429` = wait `Retry-After`.
5. Keep the refresh token in the Keychain / EncryptedSharedPreferences; the
   access token (JWT, EdDSA, 15 min) in memory only.
6. `Authorization: Bearer <access>` on the `/v1/me*` routes.
7. `POST /v1/auth/token/refresh` `{ refresh }` → `200 { access, refresh,
   expiresIn }` or `401` (session dead). Every refresh **rotates**; save the new
   refresh token before using the new access token; a reuse/race signs the
   device out. Refresh from one place (single-flight).
8. `POST /v1/auth/logout` with the bearer → `204`; then delete both tokens.

The user can remove Carrier Wave from their AMT devices at any time; tokens then
return `401` immediately. Treat a `401` after a failed refresh as signed out.

## Routes

| Method & path | Auth | Notes |
|---|---|---|
| `POST /v1/auth/verify/start` | none | `202 { pollToken }` |
| `POST /v1/auth/verify/poll` | none | `202` · `201` tokens · `410` · `400` · `429` |
| `POST /v1/auth/token/refresh` | none | `200` tokens · `401` |
| `POST /v1/auth/logout` | Bearer | `204` |
| `GET /v1/me` | Bearer | `{ id, callsign, displayName, createdAt }` |
| `GET /v1/me/stats?today=yyyy-mm-dd` | Bearer | stats object below |
| `GET /v1/me/sessions?since=0&limit=100&detail=1` | Bearer | `{ sessions, nextSince, hasMore }` (not used yet) |
| `GET /.well-known/jwks.json` | none | Ed25519 key for optional offline JWT checks |

Pass `today` as the user's **local** calendar date so the current streak is
exact; without it the server uses its UTC date (can be a day generous).

## Stats object

Times are epoch ms unless the name ends in `Seconds`/`expiresIn`; ratios are
0–1 or `null` when nothing was answered.

- `totals.{sessions, answered, correct, accuracy, practiceSeconds}` — passive
  modes (`listen`, `story`, `cw77Listen`) never count toward accuracy.
- `bestTtrMs` — fastest single recognition.
- `personalBests { mode: int }` — 0 is a real best.
- `streak.{current, longest, lastPractisedDay}` — consecutive practice days
  ending today or yesterday; longest within the last 400 days; `yyyy-mm-dd`.
- `perMode[mode].{sessions, answered, correct, accuracy, medianTtrMs, lastDate}`
- `perCharacter[char].{attempts, correct, accuracy, medianTtrMs}` (newest 20
  scored sessions)
- `activity.days { "yyyy-mm-dd": seconds }` (local days, summed across the
  user's devices, last 400 days), `activity.level { day: 0–4 }` (a recorded day
  is never below 1), `activity.levelThresholds` `[1, 300, 900, 1800]`.
- `updatedAt`.

Mode ids (new ones may appear; show unknown ids as-is): journey, characters,
words, cw77, cw77Listen, abbreviations, qCodes, prosigns, headCopy, typed,
sending, confusion, listen, qso (Pileup Runner), contest, story, exam, qrq,
rapidFire, invaders, galaga, defender, dungeon, frogger, asteroids.

## Errors and limits

`{ "error": "<code>", "message": "<text>" }`. Retry only `401` (refresh once)
and `429` (wait `Retry-After`). `400` invalid_request / invalid_scope /
invalid_verifier; `403` insufficient_scope; `404`; `410` expired; `500`
internal (retry later).

Rate limits: sign-in start 5/email/hour and 20/IP/hour; poll once per 2 s per
sign-in; refresh 30/device/hour.

## Open with AMT

- Which fields Carrier Wave shows first (streak + activity today); new fields
  can be added without breaking anything.
- Test data: AMT can load a sample history into a test account on request.
