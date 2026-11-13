# Pebble (rePebble)

Two Pebble apps targeting **rePebble** — the community-rebooted Pebble platform shipped alongside the new Pebble Time 2 / Round 2 (mass production 2026). The original 2016 Pebble iOS app is irrelevant; the iOS companion is now the **rePebble** app installed from <https://repebble.com/app>.

## Components

| Path | Type | iOS bridge? |
|---|---|---|
| `carrier-wave/` | Watchapp (companion) | yes — hits localhost `127.0.0.1:47373` (`PebbleBridgeService`) for session/solar/spots/QSO log |
| `carrier-wave-face/` | Watchface | no — JS XHR direct to HamQSL solar XML |

The iOS bridge implementation lives in `swift/ios/CarrierWave/Services/PebbleBridgeService*.swift`. See repo root `CLAUDE.md` and the auto-memory `project_pebble_companion.md` for architecture notes.

## SDK + Tooling

- `pebble` CLI: `~/.local/bin/pebble` (Pebble SDK 4.9.x). Default install via `pebble` from rePebble docs.
- Build: `pebble build` from inside `carrier-wave/` or `carrier-wave-face/` (waf-based, see `wscript`)
- Resulting `.pbw` lands in `build/`
- `targetPlatforms` in `package.json` covers basalt/chalk/diorite/emery — Time 2 ships as `emery`

## Developer Connection — Cloud relay (default modern path)

The rePebble default flow tunnels through `wss://cloudpebble-proxy.repebble.com/tool-v2`. Mac and phone do **not** need to be on the same network. Authentication is via a Rebble/GitHub account that both sides share.

1. rePebble iOS app → **Devices** → `⋯` → **Enable Dev Connect** → sign in with GitHub
2. On this Mac, sign in once with the same GitHub account:
   ```bash
   pebble login
   ```
3. From the watchapp/face directory, omit `--phone <ip>` to use the relay:
   ```bash
   pebble ping --phone
   pebble logs --phone
   pebble install --phone build/<name>.pbw
   ```
   Equivalent forms: `--cloudpebble`, or `export PEBBLE_PHONE=` (no value) plus the bare command.

## Developer Connection — LAN (verified working 2026-07-18)

The current iOS companion is the **Core Devices "Pebble" app** (Kotlin Multiplatform, source at <https://github.com/coredevices/mobileapp>), whose UI differs from older rePebble docs. Its LAN dev server is a WebSocket on the **phone** at **port 9000** (hardcoded in `DevConnectionLANServer.kt`; port 5002 seen in old forum posts does not exist in this app). No `pebble login` needed for the LAN path.

Setup (both required):

1. Pebble app → **Settings** tab → Connectivity → check **Use LAN developer connection**
2. **Devices** tab → your watch → `⋯` menu → enable **Dev Connection** — the popup shows the phone's IPv4/IPv6
3. iOS Local Network permission must be granted (iOS Settings → Pebble → Local Network)

Then from the watchapp/face directory:

```bash
pebble install --phone <phone-ip> build/<name>.pbw
```

### LAN path fails with "connection refused" on port 9000

**Most common cause: stale Dev Connection toggle.** The toggle can show "on" while the port-9000 listener isn't actually running (server-lifecycle quirk acknowledged in the app source). Fix: toggle Dev Connection **off and back on** (force-quit + relaunch the app if that doesn't work). This was the entire root cause of a long debugging session — every setting was already correct.

Debug workflow:

- Verify the listener before installing: `nc -z -G 1 <phone-ip> 9000`
- Use the IP shown in the Dev Connection popup; confirm it's really the phone with `arp -a` (hostname `theseus`). Don't port-scan for 9000 — other LAN devices (e.g. the Vizio TV) also listen on 9000 and will accept-then-hang.
- Mac and phone must be on the same LAN (no AP isolation / guest network).
- If "Use LAN developer connection" is unchecked, the Dev Connection toggle instead tunnels to `wss://cloudpebble-proxy.repebble.com/device-v2` and the CLI side needs `pebble login` (interactive browser sign-in).

## Watchface JS — known limitations

`carrier-wave-face/src/pkjs/index.js` fetches `https://www.hamqsl.com/solarxml.php` and replies with `K_INDEX/A_INDEX/SOLAR_FLUX/PROPAGATION` strings. PebbleKit JS runs inside the rePebble iOS app process, so any failure mode of that app (suspension, network entitlement, killed JS context) shows up as the watch face stuck on `--`.

Missing tags fall back to the `'--'` no-data sentinel (leading `'-'` is what the C side checks for) — keep that invariant when touching the JS layer. The JS also fetches current temperature from Open-Meteo via phone geolocation (`location` capability in `package.json`).

## Conventions

- Watchapp UUID: see `carrier-wave/package.json`
- Watchface UUID: `b7e41c8a-3f19-4d6e-a152-8c0e7a5d9b31` — do not regenerate; sideload over the same UUID to upgrade in place
- `messageKeys` in `package.json` declares the AppMessage dictionary for both directions; keep C macro names (`MESSAGE_KEY_*`) and JS payload keys identical
- `enableMultiJS: true` is required for the multi-file JS layout

## References

- Developer Connection guide: <https://developer.repebble.com/guides/tools-and-resources/developer-connection/>
- Debugging with App Logs: <https://developer.repebble.com/guides/debugging/debugging-with-app-logs/>
- SDK install: <https://developer.repebble.com/sdk/>
