# Investigation: KiwiSDR Connection Failure

**Date:** 2026-02-13
**Status:** Resolved
**Outcome:** Multiple protocol bugs in KiwiSDRClient prevented successful connection

## Problem Statement

WebSDR connection to KiwiSDR receivers was not working. Connections would fail during the handshake phase.

## Root Cause

Compared the implementation against the [kiwiclient](https://github.com/jks-prv/kiwiclient) canonical Python reference and found **6 protocol bugs**:

### Bug 1: Wrong WebSocket URL path (CRITICAL)

The connection URL included an incorrect `/kiwi/` prefix:
```
BROKEN:  ws://host:8073/kiwi/1707350400000/SND
CORRECT: ws://host:8073/1707350400/SND
```

The KiwiSDR server expects `/<timestamp>/<stream_type>` directly with no path prefix.

### Bug 2: Timestamp in milliseconds instead of seconds

Used `Date().timeIntervalSince1970 * 1000` (milliseconds) but protocol expects seconds.

### Bug 3: Invalid identity command

Sent `SERVER DE CLIENT CarrierWave SND` which is not a recognized KiwiSDR protocol command. The correct command is `SET ident_user=CarrierWave`.

### Bug 4: Missing compression command

Never sent `SET compression=<0|1>`. Without this, the server defaults may not match what the client's audio decoder expects. Now sends `SET compression=1` for IMA ADPCM.

### Bug 5: No server error detection during handshake

The `waitForSampleRate` loop only looked for `sample_rate=` messages. If the server sent `badp` (bad password), `too_busy`, or `down` messages, they were silently ignored and the client would time out after 20 iterations.

### Bug 6: Reconnect used hardcoded frequency/mode

After connection loss, reconnect always used `14.060 MHz / CW` regardless of the user's actual frequency and mode.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `CarrierWave/Services/WebSDR/KiwiSDRClient.swift` | Main client | All 6 bugs |
| `CarrierWave/Services/WebSDR/WebSDRSession.swift` | Session coordinator | Bug 6, hardcoded sample rate |
| `CarrierWave/Services/WebSDR/KiwiSDRADPCM.swift` | ADPCM decoder | Correct, no issues |
| kiwiclient `kiwi/client.py` | Reference impl | Protocol spec |
| kiwiclient `kiwi/wsclient.py` | Reference WS | URL format spec |

## Resolution

1. Fixed URL: `ws://host:port/<seconds>/SND` (no `/kiwi/` prefix, seconds not ms)
2. Fixed identity: `SET ident_user=CarrierWave`
3. Added `SET compression=1` to handshake
4. Added server error detection (`badp`, `too_busy`, `down`, `redirect`)
5. Added new error types: `authenticationFailed`, `tooBusy`, `serverDown`, `serverRedirect`
6. Fixed reconnect to use stored `lastFrequencyMHz` / `lastMode`
7. Used negotiated sample rate from server instead of hardcoded 12000
8. Added `audio_adpcm_state` parsing for ADPCM decoder state resets
9. Created protocol reference document at `docs/kiwisdr-protocol.md`

## Lessons Learned

- The `/kiwi/` prefix was likely guessed or copied from the KiwiSDR web UI URL. The WebSocket endpoint path is different from the HTTP UI path.
- Always verify protocol implementation against the canonical reference client.
