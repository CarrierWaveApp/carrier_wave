# FT8: Firmware ↔ App comparison and app-side suggestions

**Date:** 2026-06-03
**Branch analyzed:** `s3-devkit-n16r8` (firmware + iOS app, version-consistent)
**Scope:** All bridge subsystems (FT8, CW keyer, CAT). FT8 measured against the
WSJT-X FT8 protocol papers (QEX 2020 "FT4 and FT8 Communication Protocols",
Franke/Somerville/Taylor; WSJT-X `lib/ft8/`; cross-checked vs kgoba/ft8_lib).
**Status:** SUGGESTIONS ONLY — no source was modified. Directive: changes land
**app-side** unless no app-side path exists.

> Decision driving this report: the app should **adopt the firmware's bridge
> FT8 path** (drive the verified on-bridge codec over BLE) and retire its
> parallel local-audio FT8 synth/decode.

---

## 1. The central finding

The firmware **fully implements** FT8 over the bridge and advertises it; the app
**implements none of it** and runs an entirely separate local-audio FT8 stack.

**Firmware (ready):**
- Encode/synth/TX, capture, decode all present and wired to the protocol.
  `Ft8Send` handler synthesizes and keys the mic jack (`firmware/src/main.rs:1143-1180`);
  `Ft8CaptureStart/Stop` run a continuous decoder (`firmware/src/main.rs:1193-1280`);
  decode loop emits `Ft8Decode` (`firmware/src/main.rs:1299-1334`).
- Encodes the full FT8 message set: `encode_ft8_decode`, `encode_ft8_status`,
  `encode_ft8_encode_rsp_*`, `encode_jack_status`, `encode_battery_status`
  (`firmware/src/protocol.rs:130-202`).
- Advertises **`CAP_FT8_CODEC = 1 << 4`**, always set in the handshake
  (`firmware/src/protocol.rs:21,37-41`).
- Uses the **same CFT8 C library** as the app, so encode/decode bits are
  identical and WSJT-X-faithful (`firmware/src/ft8.rs:1-186`).

**App (absent):**
- Sends/handles **zero** FT8 cwbp messages. The inbound router
  `BridgeFrame.event(from:)` ends in `default: return nil` with no FT8 / JackStatus /
  BatteryStatus cases (`swift/ios/CarrierWave/Services/Radio/BridgeFrame.swift:282-324`).
  No `buildFt8*` frame builders exist.
- The `Capabilities` OptionSet has no FT8 bit (`…/BridgeFrame.swift:12-19`).
- FT8 today is local-audio only — `FT8SessionManager` drives `FT8AudioEngine`
  (device mic/speaker via AVAudioEngine) + local `FT8Encoder`/`FT8Decoder`, with
  no connection to `BridgeProtocol`.

**Implication for the prior (2026-06-03) local-audio FT8 audit:** adopting the
bridge path makes most of those findings **moot** because the local synth/decode
is retired — except the two that are really about *timing ownership* (slot offset,
turnaround), which carry over because the app still owns the wall clock.

---

## 2. Paper requirements × where each must change

The CFT8 bit-level requirements (Costas, Gray, CRC-14 0x6757, LDPC(174,91),
6.25 Hz spacing, 12 kHz, 1920 samp/symbol, 79 symbols) are satisfied on **both**
sides via CFT8 — no change. The requirements that are *not* automatically
satisfied:

| Paper requirement | Firmware today | App today | Where the fix must land |
|---|---|---|---|
| TX = continuous-phase **GFSK, BT=2.0** + envelope ramp | continuous-phase **8-FSK**, no Gaussian, no ramp (`ft8.rs:191-215`) | same (local synth) — *retired* | **FIRMWARE-ONLY** (see §4). In the bridge path the app never synthesizes audio, so there is no app-side path. |
| TX keyed at **slot_start + 0.5 s** (UTC) | keys **immediately** on `Ft8Send`, no slot wait, no lead (`main.rs:1143-1180`) | n/a | **APP** — time the `Ft8Send` send-moment (§3.1) |
| RX 15 s window **UTC-aligned**, use `dt` for fine align | capture free-running / audio-onset-gated, **not** UTC-aligned; emits `delta_time_s` (`main.rs:1299-1334`, `firmware/CLAUDE.md:202`) | n/a | **APP** — own the UTC clock, bucket decodes by `dt` (§3.2) |
| Message construction via CFT8 packers | `ftx_message_encode` from text | builds text + packs locally | **APP** — send **text**, let firmware pack (§3.3) |
| Decode fields: `dt` seconds, freq **audio** Hz, snr **uncalibrated** | emits exactly that in `Ft8Decode` | local equivalent | **APP** — map `Ft8Decode` → existing `FT8DecodeResult` (§3.4) |

---

## 3. App-side suggestions (priority order)

These are the changes to *adopt the bridge path*. None modify firmware.

### 3.0 Wire FT8 into the existing bridge transport (foundation)
The transport is clean and the insertion points are obvious:
- **Add frame builders** in `BridgeFrame` next to the CW builders
  (`…/BridgeFrame.swift:156-208`): `buildFt8Send(text, baseFreqHz=1500)`,
  `buildFt8CaptureStart(minFreqHz=100, maxFreqHz=3000)`, `buildFt8CaptureStop()`,
  optionally `buildFt8EncodeReq(...)` for preview.
- **Add `BridgeEvent` cases** (`…/BridgeFrame.swift:222-270`): `ft8Decode(text, snrDb, freqHz, dt)`,
  `ft8Status(state, detail)`, and while here `jackStatus(...)`, `batteryStatus(...)`.
- **Add router cases** in `event(from:)` before the `default` (`…/BridgeFrame.swift:282-324`)
  for `.ft8Decode`, `.ft8Status`, `.jackStatus`, `.batteryStatus`.
- **Add async senders** on `BridgeProtocol` mirroring the CW methods.
- **Add the capability bit**: `static let ft8Codec = Capabilities(rawValue: 1 << 4)`
  (`…/BridgeFrame.swift:12-19`) and gate the bridge-FT8 path on
  `caps.contains(.ft8Codec)`; fall back to local audio (or disable) if absent.

### 3.1 Own the TX timing — send `Ft8Send` to hit slot_start + 0.5 s
The firmware keys **immediately** on receipt and adds **no lead** (tones start at
sample 0; it first builds the whole 151 680-sample buffer, then streams it). So
the app must fire `Ft8Send` *early enough* that the first tone reaches the air at
**slot_start + 0.5 s**, compensating for **BLE latency + firmware synth time**.
- Reuse the UTC slot clock already in `FT8SessionManager.startCycleTimer`
  (`swift/ios/CarrierWave/Services/FT8SessionManager.swift:280-324`), but trigger
  a BLE `Ft8Send` instead of local playback.
- Send at `target = slotStart + 0.5 − (bleLatency + synthLead)`; start with a
  measured constant (e.g. 150–250 ms) and refine against the decode-timing log.
- Tighten the slot timer `tolerance` (currently `1.5 s`, `…/FT8SessionManager.swift:310`)
  to ≤ 50 ms on the FT8 path — at 1.5 s the OS can smear the send moment across
  most of the on-air window.

### 3.2 Own the RX slot clock; bucket decodes by `dt`
Firmware capture is **free-running** (ADC) or **audio-onset-gated** (USB), and
its internal 15 s window is **not** UTC-aligned (`firmware/CLAUDE.md:202`). The
app must:
- Start `Ft8CaptureStart` once and keep it running; keep its **own** UTC 15 s
  slot clock for labeling.
- Use `Ft8Decode.delta_time_s` to assign each decode to the correct UTC slot and
  display DT, exactly as WSJT-X does — **do not** assume the firmware's decode
  cadence equals a UTC slot. Decodes arrive as async BLE events mid-slot.

### 3.3 Send message **text**, drop local packing/synth
Keep `FT8QSOStateMachine`'s WSJT-X text builder (CQ / grid / `-NN` / `R-NN` /
RRR / RR73 / 73). Pass that text in `Ft8Send.text`; the firmware's CFT8 packs the
77 bits. Retire `FT8Encoder.synthesizeTones` and the local `FT8AudioEngine`
TX/RX paths for the bridge path. (This also deletes the prior audit's local-synth
findings: CPFSK, missing 0.5 s lead in the buffer, 44.1 kHz route-change
decimation bug — all gone with the local audio engine.)

### 3.4 Map `Ft8Decode` → existing `FT8DecodeResult`
The bridge `Ft8Decode` carries the same semantics the app already consumes
(`text`, `snr_db` uncalibrated, `frequency_hz` audio-Hz, `delta_time_s` seconds).
Adapt it into the existing `FT8DecodeResult` so `FT8DecodeEnricher`, the QSO
state machine, and all FT8 views work unchanged.

### 3.5 Preserve the QSO turnaround budget
The reply for slot N+1 must be on air at `+15.5 s`. Firmware decode is
~1.4 s (`MAX_CANDIDATES = 64`, tuned explicitly to fit the reply budget —
`ft8.rs:282-291`); add BLE delivery + the app's reply decision + the §3.1 send
lead. Drive the sequencer so the reply is computed from the **latest processed**
`Ft8Decode` events for the just-ended slot, then `Ft8Send` is scheduled on the
slot timer (this is the bridge-path version of the prior audit's stale-state
turnaround risk — keep decode-processing ordered before the next send).

### 3.6 Handle FT8 status, errors, and jack/source state
- Handle `Ft8Status` (IDLE/TRANSMITTING/CAPTURING/ERROR) and surface `ERROR`
  detail (busy, encode fail, PSRAM alloc fail, no audio device).
- Handle `JackStatus`: the firmware does **not** gate TX/RX on jack presence, so
  the app should warn/disable FT8 TX when `mic_plugged == false` and RX when
  `phone_plugged == false` (TRS path only).
- The firmware silently prefers radio **USB audio** over the TRS phone jack when
  the radio exposes a UAC device, and exposes **no flag** saying which source is
  live. The app can only infer it from the detected radio. (Optional firmware
  improvement noted in §4.)
- While here, handle `BatteryStatus` (already emitted, `protocol.rs:193-202`) to
  show bridge battery; it's currently dropped by the app.

---

## 4. The few changes with **no app-side path** (firmware-side, justified)

1. **GFSK BT=2.0 + amplitude envelope (paper-mandated modulation).** In the
   adopted architecture the app never synthesizes FT8 audio, so this can only be
   fixed where the audio is generated: `firmware/src/ft8.rs:191-215`
   (`synthesize_tones`), which is continuous-phase 8-FSK with hard frequency
   steps and no start/stop ramp. Add a Gaussian pulse (BT=2.0) over symbol
   transitions and a raised-cosine ramp on the first/last symbol to match WSJT-X
   and stop adjacent-channel splatter. *Interop impact is low (it still decodes);
   this is spectral-cleanliness / good-citizen compliance.* The same routine
   feeds the loopback self-test (`ft8.rs:408`), so verify the self-test still
   decodes after shaping.

2. **(Optional) Report the active FT8 audio source / granular capability.**
   Today `CAP_FT8_CODEC` is a single bit and `Ft8Decode` carries no source tag,
   so the app can't tell TRS-jack from USB-audio capture, nor TX-capable from
   RX-only. A small firmware addition (a field on `Ft8Status`, or capability
   sub-bits) would let the app drive accurate UI/gating. Not paper-mandated —
   logged as a design-consistency nicety.

---

## 5. CW keyer & CAT (design-consistency, not paper-driven)

Both subsystems are already well-aligned app↔firmware; only minor notes:

**CW keyer**
- App expands templates/prosigns locally and sends pre-expanded `CwSend`, and uses
  `CwSlotPlay`+context for firmware-side expansion — matches the firmware contract
  (`firmware/src/keyer.rs` template expansion; app `CWKeyerService`). Prosign tables
  are duplicated on both sides; keep them in sync (or, longer term, single-source).
- **Yaesu KY6 cannot be stopped via CAT** — the firmware `CwStop` is a no-op on
  Yaesu. The app UI should not promise a working stop on Yaesu rigs.
- **CI-V `CwProgress.buf_depth` is an estimate** (no `TB;` poll); the app should
  trust only the `complete` flag for CI-V/QMX, and may treat Kenwood/QCX
  `buf_depth` as authoritative.

**CAT**
- The wire `RadioInfo` carries only `protocol` / `baud_rate` / `id_string`
  (`firmware/src/protocol.rs:69-78`) — it does **not** send `freq_digits` or the
  QCX/QMX variant. The firmware applies those CAT-encoding quirks internally
  (`verify.rs`), so the app correctly need not replicate encoding; if the app
  wants to *display* "9-digit Yaesu / QCX / QMX" it must re-derive from
  `id_string` via `RigProtocolDetector`. This split is fine — just don't assume
  those fields arrive over the wire.
- **CI-V RIT/XIT has no firmware emulation** (only Kenwood emulates). The app
  should handle `SetResult.UNSUPPORTED` gracefully (disable the control or
  emulate app-side) for CI-V rigs.
- `UniversalMode.from` already maps `"FT8"` → `.data` (`…/BridgeFrame.swift:86-90`),
  so CAT mode-setting for FT8 operation is consistent.

---

## 6. Reconciliation with the prior local-audio FT8 audit

| Prior finding (local-audio) | Under bridge-path adoption |
|---|---|
| CPFSK not GFSK (app `FT8Encoder`) | Moves to firmware `ft8.rs` (still to fix) — §4.1 |
| TX not offset +0.5 s | Becomes "time the `Ft8Send`" — §3.1 |
| 1.5 s slot-timer tolerance | Still relevant (app owns the clock) — §3.1 |
| Stale-state auto-reply turnaround | Still relevant (app sequencer) — §3.5 |
| 44.1 kHz route-change decimation bug | **Moot** — local audio engine retired |

---

## 7. Open item

Pending **decode-timing log** to calibrate the §3.1 send-lead constant
(BLE + synth latency) so transmitted tones land at slot_start + 0.5 s on air.
