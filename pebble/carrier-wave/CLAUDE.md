# Carrier Wave for Pebble

Pebble watchapp companion to Carrier Wave: Field. Targets Pebble Time 2,
Round 2, and original basalt/chalk/diorite hardware via the rePebble SDK.

## Architecture

Three layers:

1. **Watchapp (C, `src/c/`)** — runs on the Pebble. One window per screen
   (Solar, Spots, UTC, Session) plus a root menu. Windows register an
   AppMessage inbox handler on load via `cw_comm_set_inbox_handler` and
   clear it on unload — only one handler is active at a time.

2. **PebbleKit JS (`src/pkjs/index.js`)** — runs inside the Pebble phone
   app on iOS. Receives `ACTION` codes from the watch and either:
   - hits public APIs (HamQSL solar XML, POTA spot JSON), or
   - hits the Field bridge at `http://127.0.0.1:47373/v1/...`.

3. **iOS bridge** — `swift/ios/CarrierWave/Services/PebbleBridgeService.*`.
   Localhost-only HTTP listener that exposes app-group session/solar/spot
   snapshots and posts `didReceivePebbleLogQSO` for the LoggerView to
   handle.

## Conventions

- C source files use the `cw_` prefix for public symbols (`cw_solar_window_push`).
- One window per file pair `*_window.{c,h}`. Each owns its TextLayer/MenuLayer
  state as file-scope statics — Pebble apps are inherently single-instance.
- Keep buffers short (`char buf[24]` etc.) — the original basalt platform
  has 32 KB app RAM. PT2 has more headroom but design for the lower bound.
- `messageKeys` are declared in `package.json` and consumed in C via
  `MESSAGE_KEY_<NAME>` and in JS via `payload.NAME` / `Pebble.sendAppMessage({ NAME: ... })`.
- AppMessage inbox is 1024 bytes — send spots one at a time with `SPOT_INDEX`
  and a leading `SPOT_COUNT` reset. The C side accumulates into `s_rows`.
- Hardware buttons only — Pebble Time 2 touchscreen is not yet enabled in
  PebbleOS firmware as of April 2026. Don't design around tap targets.

## When the bridge is offline

PebbleKit JS treats bridge timeouts/failures as `STATUS_BRIDGE_ERROR` and
falls back to public APIs where possible (solar/spots). The Session screen
will simply show "Bridge offline" when Field is suspended. Returning to
Field's foreground re-arms the listener via `scenePhase == .active`.

## Building

Requires the rePebble SDK + `pebble` CLI. From this directory:

```bash
pebble build      # produces build/carrier-wave.pbw
pebble install    # sideload to watch (paired phone in dev mode)
pebble logs       # tail watchapp logs over BT
```

The `wscript` is standard waf — it picks up `src/c/**/*.c` automatically,
so adding a new window means: write `foo_window.{c,h}`, push it from the
menu, and rebuild. No manifest edits beyond `messageKeys`.

## Roadmap

- **Phase 1 (done):** Solar / Spots / UTC standalone via PebbleKit JS.
- **Phase 2 (done):** Session mirror via Field bridge.
- **Phase 3 (done):** Remote-log a QSO with SELECT.
- **Phase 4 (deferred):** Heart-rate-on-QSO, speaker CW sidetone, haptic
  notifications on new park spots — all dependent on PebbleOS firmware
  enabling those subsystems on PT2.
- **Phase 5 (deferred):** Migrate `src/c/` to Alloy (JS-on-watch) once
  Alloy's API surface covers MenuLayer + buttons.
