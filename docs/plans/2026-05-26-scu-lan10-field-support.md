# SCU-LAN10 Support on Field (iOS)

**Date:** 2026-05-26
**Branch:** `claude/scu-lan10-field-support-0VXd4`
**Status:** Phases 1a–4 landed (CAT control shippable). Phases 5–6 (waterfall, audio) deferred — see below.
**Goal:** Let Carrier Wave: Field (iOS) connect **directly** to a Yaesu SCU-LAN10 over the LAN/Internet — CAT control, waterfall, and (later) RX audio — instead of only viewing a SCU-LAN10 relayed through a Mac running CW Sweep.

## Background

SCU-LAN10 is fully implemented on **macOS (CW Sweep)**. The protocol is reverse-engineered and documented in [`docs/scu-lan10-protocol.md`](../scu-lan10-protocol.md). Today on iOS the only way to see a SCU-LAN10 is the **RemoteSweep relay**: the Mac connects to the hardware and rebroadcasts the waterfall/CAT over the LAN (`swift/ios/CarrierWave/Views/Remote/RemoteSweepWaterfallView.swift` — *"Connect a SCU-LAN10 or SmartSDR radio there"*). There is no native, direct connection from Field to the box.

### What exists where

| Concern | Location | Shared? |
|---------|----------|---------|
| `RadioSession`, `RadioTransport`, `RadioProtocolHandler`, `FrameAssembler` | `CarrierWaveData/Radio/` | ✅ shared |
| `FlexRadioTransport`, `IcomWiFiTransport`, `UDPChannel`, `CIVProtocolHandler`, `KenwoodProtocolHandler` | `CarrierWaveData/Radio/` | ✅ shared |
| `YaesuProtocol` / `YaesuMode` (CAT vocabulary) | `CarrierWaveCore/YaesuProtocol.swift` | ✅ shared |
| `SCULAN10Crypto` (framing, XOR crypto, channel/msg enums, errors) | was macOS → **now `CarrierWaveData/Radio/`** | ✅ (Phase 1a) |
| `YaesuProtocolHandler` (CAT handler) | was macOS → **now `CarrierWaveData/Radio/`** | ✅ (Phase 1a) |
| `SCULAN10Transport` (4-UDP-port actor), `PortChannel` (raw Darwin sockets), diagnostics, `SCULAN10DebugStats` | `swift/macos/CWSweep/Services/Radio/` | ❌ macOS-only |
| `SCULAN10WaterfallData` (scope → renderable) | macOS — couples to `WaterfallStore` | ❌ macOS-only |
| `SCULAN10AudioPlayer` (AVFoundation) | macOS — couples to `RadioAudioBroadcaster` | ❌ macOS-only |
| iOS radio stack `RadioService` (transports: `.ble`, `.wifi`, `.flex`/SmartLink) | `swift/ios/CarrierWave/Services/Radio/` | iOS-only; **no `.scuLan10` case** |

**Portability finding:** none of the SCU-LAN10 core files import AppKit — only `Foundation`/`Network`/`Darwin`/`AVFoundation`/`OSLog`, all available on iOS. This is a *lift-and-share*, not a rewrite.

## Phasing

| Phase | Scope | Status |
|-------|-------|--------|
| **1a** | Move `SCULAN10Crypto` + `YaesuProtocolHandler` into `CarrierWaveData` (public). | ✅ done |
| **1b** | Move `SCULAN10Transport`, `PortChannel`, `SCULAN10TransportDiagnostic`, `SCULAN10DebugStats` into `CarrierWaveData` (public). Share `RadioCommandDirection`. | ✅ done |
| 2 | Add `.scuLan10` to `RadioTransportKind` + iOS `RadioService.TransportType`; host/port via UserDefaults, credentials via Keychain. | ✅ done |
| 3 | `RadioService.connectSCULAN10()` (in `RadioService+SCULAN10`) mirroring `connectWiFi()`/`connectFlex()`; `SCULAN10Transport` + `YaesuProtocolHandler`, `.kenwood` framing; poll/state via the shared `RadioSession`. | ✅ done |
| 4 | Connection UI: global `RadioSettingsView+SCULAN10` section (host / port / user / password + Connect) and per-item `RadioConnectionSheet` detail fields. | ✅ done |
| 5 | Native scope/waterfall. | ⏸ deferred |
| 6 | RX audio. | ⏸ deferred |

Phases 1a–4 are the minimum shippable feature ("Field can CAT-control a SCU-LAN10") and are complete. The transport exposes frequency/mode/PTT through the shared `RadioSession`, polled at 200 ms like the other network transports.

### Phases 5–6 deferral

Both are device-validated features and are **not** safe to land blind from the cloud environment (no Xcode/simulator to render the waterfall or play audio). Importantly, the data is already available: `SCULAN10Transport` exposes public `scopeData` and `audioData` `AsyncStream`s, so these phases need **no further package changes** — they are pure iOS-view work.

**Phase 5 (waterfall) remaining work:**
1. `SCULAN10WaterfallData` couples to the macOS `WaterfallStore` (and its `WaterfallSource` enum + geometry provider). To share it, introduce a `WaterfallSink` protocol in `CarrierWaveData` that `WaterfallStore` conforms to, and make `SCULAN10WaterfallData` generic over the sink; **or** write a small iOS-local `@Observable` waterfall store that consumes `transport.scopeData` directly.
2. Build/adapt a SwiftUI `Canvas` scope view (the FT8 waterfall and `RemoteSweepScopeView+Rendering` are references) and place it in `RadioPanel`, shown only when the active transport is `.scuLan10`.

**Phase 6 (audio) remaining work:**
1. Share `SCULAN10AudioPlayer` (AVFoundation, currently coupled to the macOS `RadioAudioBroadcaster`) or write an iOS-local player that consumes `transport.audioData` (Int16 LE 16 kHz mono).
2. Add a small RX-audio toggle to `RadioPanel`; manage the `AVAudioSession` lifecycle for background/interruptions.

## iOS-specific blockers (not present on macOS)

1. **Local Network privacy permission.** iOS requires `NSLocalNetworkUsageDescription` + the user prompt to reach a LAN device. Without it, UDP to `192.168.x.x` silently fails. Must be added to the iOS target Info.plist and the connect path must handle the "denied" state gracefully.
2. **Background suspension.** SCU-LAN10 drops the session without ~1 Hz keepalives on all 4 ports; iOS suspends sockets when backgrounded/locked, so the session dies when the user leaves the app. Need reconnect-on-foreground; true background operation isn't realistic without audio-session tricks.
3. **Raw `Darwin` sockets.** `PortChannel` uses POSIX sockets. Works on iOS but interacts badly with the background limits — consider rewriting on `NWConnection` / the existing shared `UDPChannel` for proper iOS lifecycle behaviour. Decide in Phase 1b.
4. **Exclusive session.** The box allows one client. Field-direct and Mac-relay are mutually exclusive — surface this in the UI so users don't fight a connected Sweep.
5. **Feature gating.** Ships under the existing `.radioControl` (Alpha) experiment; update the iOS experiments table + What's New when it lands.

## Files touched (rough)

Shared (`CarrierWaveData/Radio/`): `SCULAN10Crypto.swift` (new), `YaesuProtocolHandler.swift` (new), then `SCULAN10Transport.swift`, `SCULAN10PortChannel.swift`, `SCULAN10TransportDiagnostic.swift`, `SCULAN10DebugStats.swift` (Phase 1b), `RadioConnectionProfile.swift` (Phase 2). `RadioCommandDirection` promoted from macOS `RadioCommandLog.swift`.

iOS: `RadioService.swift` (+`TransportType.scuLan10`), `RadioService+Connection.swift` (`connectSCULAN10`), `RadioConnectionSheet.swift`, `RadioSettingsView*.swift`, `RadioPanel.swift`, Info.plist.

macOS: delete moved files; `RadioManager+Transport.swift` keeps consuming the now-shared types unchanged.

## Verification

No Xcode in the cloud environment — compilation is verified by Xcode Cloud on merge. Each phase must land green there. Unit-testable now: `SCULAN10Crypto` (gTable, packet build/decrypt, auth packet) — add `CarrierWaveDataTests` once the macOS test (if any) is mirrored.

## Open questions

1. **`PortChannel` vs `UDPChannel`.** Reuse the shared `UDPChannel`/`NWConnection` for iOS, or port the Darwin `PortChannel`? Leaning `NWConnection` for iOS background behaviour.
2. **Credentials storage.** Per-radio Keychain entry keyed by host (follow the SmartLink/wifi pattern).
3. **Waterfall sharing.** `SCULAN10WaterfallData` → a transport-agnostic scope model both apps share, or an iOS-local consumer of the `scopeData` stream?
