# Reference OAuth log client

A minimal, runnable Node client that authorizes against Carrier Wave, unlocks a
user's end-to-end-encrypted log, lists QSOs, and adds one.

It exists to be **read**, not depended on. Every non-obvious part of the
protocol is here in about 400 lines: the device grant, token refresh, Argon2id
escrow unwrap, blob decrypt, journal fold, and the push/upload two-step.

Full protocol spec: [`../../docs/features/oauth-api.md`](../../docs/features/oauth-api.md).

## Setup

```bash
npm install
npm run build
```

The crypto comes from `cw-web-crypto`, the same WebAssembly module the
`/logbook` viewer uses, compiled from the same Rust (`cw-crypto`) as the iOS and
Android apps. It is consumed here from the vendored copy in
`../../logbook-web/vendor/cw-web-crypto`.

## Use

```bash
export CW_CLIENT_ID=my-logger          # a registered client_id
export CW_BASE_URL=https://activities.carrierwave.app

node dist/cli.js login          # device flow; prints a code to enter in a browser
node dist/cli.js list           # prompts for the sync passphrase, prints QSOs
node dist/cli.js add W1ABC 20m FT8 --freq 14.074
```

`login` writes tokens to `.cw-tokens.json` in the working directory. That file
is a credential — it is not encrypted, and anyone holding it can act as the
user until the refresh token is revoked.

**The sync passphrase is never stored.** It is prompted for on each command,
used to derive the data key in memory, and discarded.

## What to copy, and what not to

Copy the protocol handling: the fold order, the snake_case `JournalPayload`
keys, the MHz frequency unit, the unknown-operation tolerance, and the
`clientEntryId` idempotency.

Do not copy the ergonomics. This client is deliberately naive:

- It re-downloads the entire journal on every `list`. A real client persists
  `highWater` and calls `/v1/sync/changes?since=` instead of bootstrapping.
- It holds all QSOs in memory.
- It has no retry/backoff. The server rate-limits per IP and you will need it.
- It writes tokens in plaintext. Use the OS keychain.
