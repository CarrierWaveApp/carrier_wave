# Carrier Wave logbook MCP server

Exposes an operator's logbook to an MCP host (Claude Code, Claude Desktop) over
the third-party OAuth API.

It holds no privileged position: it authorizes through the same flow as anyone
else's application, carries a `cid`-stamped token, and is default-denied on
every route outside `sync:*` and `openid`. That makes it both a useful tool and
a working end-to-end exercise of the API.

## Tools

| Tool | Needs passphrase | Does |
|---|---|---|
| `whoami` | no | Account, callsign, and server — the quickest check that OAuth works |
| `search_qsos` | yes | Query contacts with the Carrier Wave query language |
| `log_summary` | yes | Totals by band, mode, year, park; most-worked callsigns |
| `add_qso` | yes | Append a contact (needs `sync:write`) |

`search_qsos` uses the real grammar (`band:20m mode:ft8`, `park:US-1044
after:2026-01-01`, `state:CA -confirmed`, `W1AW OR K1ABC`) because the query
engine is the same Rust the apps run, compiled to WebAssembly.

## Setup

```bash
npm install && npm run build

# One-time authorization. Opens a device-flow code to approve in a browser.
cd ../oauth-log-client && npm run build
CW_CLIENT_ID=my-logger node dist/cli.js login
```

Then register it with your MCP host:

```json
{
  "mcpServers": {
    "cw-logbook": {
      "command": "node",
      "args": ["/absolute/path/to/server/examples/cw-logbook-mcp/dist/index.js"],
      "env": {
        "CW_CLIENT_ID": "my-logger",
        "CW_BASE_URL": "https://activities.carrierwave.app",
        "CW_SYNC_PASSPHRASE": "…"
      }
    }
  }
}
```

| Variable | Default | Purpose |
|---|---|---|
| `CW_CLIENT_ID` | — | Registered OAuth `client_id` (required) |
| `CW_BASE_URL` | `https://activities.carrierwave.app` | Server; use `https://staging.carrierwave.app` to test |
| `CW_TOKEN_FILE` | `~/.cw-tokens.json` | Where `login` wrote the tokens |
| `CW_SYNC_PASSPHRASE` | — | Required by everything that reads QSOs |
| `CW_CACHE_TTL_SECONDS` | `300` | How long a decrypted log stays cached in memory |

## Testing without an MCP host

`scripts/drive.mjs` is a minimal host that speaks the same JSON-RPC over stdio:

```bash
DRIVE_CALLS='[["whoami",{}],["search_qsos",{"query":"band:20m","limit":5}]]' npm run drive
```

`whoami` needs no passphrase, so it verifies the whole OAuth path — token load,
refresh, `cid` claim, scope gate — on its own.

## About that passphrase

The log is end-to-end encrypted; the server cannot read it and neither can this
process without the passphrase. Putting it in an MCP host's config file means
writing it to disk in plaintext, in a file that is frequently synced, backed up,
and screen-shared.

Weigh that honestly. Anyone who reads that config can read the entire log, and
**there is no key rotation** — a passphrase that leaks cannot be changed. The
process drops it from its own environment once the key is derived, which limits
exposure to crash dumps and child processes but does nothing about the config
file itself.

`whoami` works without it, so OAuth can be verified before committing to this.

## Caching

The whole journal is downloaded and decrypted on first use and cached for
`CW_CACHE_TTL_SECONDS`. Pass `refresh: true` to any read tool to force a reload;
`add_qso` invalidates the cache itself.

For a large log this first load is slow — it is one HTTP request per journal
entry. A production client would persist `highWater` and pull
`/v1/sync/changes?since_seq=` instead. See `../oauth-log-client/README.md`.
