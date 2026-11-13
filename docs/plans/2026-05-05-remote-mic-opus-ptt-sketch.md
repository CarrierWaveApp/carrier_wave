# Remote Mic + Opus + PTT — Design Sketch

**Date:** 2026-05-05
**Status:** Pre-implementation sketch. No Linear issue yet. Sibling to [`2026-05-02-cw-field-remote-mode-design.md`](2026-05-02-cw-field-remote-mode-design.md).

Adds **voice TX from iOS Field through CW Sweep to the radio**, plus an Opus codec swap for the existing RX audio path so we don't double our cellular budget. The CW straight-key tap pad is the model for the user-facing surface; mic is the harder cousin.

This doc is the surface to react to before we open issues.

---

## Goals (v1)

- Field's mic captures voice → Sweep keys SSB / FM / AM TX → release returns to RX.
- Opus codec replaces raw PCM16 on `radio.audio` (RX) and on the new `radio.audio.tx` (TX). Cellular uplink is the budget we're protecting.
- PTT state machine on Sweep mediates radio-side keying so RX is muted before TX starts and isn't unmuted until TX has fully drained.
- Mouth-to-air latency target **< 300 ms** end-to-end on LAN, **< 600 ms** on cell. Bigger numbers feel awful.

## Non-goals (v1)

- Full-duplex VOX. Push-and-hold only — explicit operator action.
- Voice keyer recording on Field. Text → TTS → TX is a separate feature.
- DV (D-STAR / DMR / Fusion). SSB / FM / AM only — analog gateway from radio's perspective.

---

## Wire format

### Codec negotiation

`AudioCodec` already reserves an Opus slot — wire it up:

```swift
public enum AudioCodec: String, Codable, Sendable {
    case pcmS16LE = "pcm_s16le"
    case opus = "opus"
}
```

`AudioFormatEvent` carries `codec`, `sampleRate`, `channels`, `bitsPerSample`. For Opus, `bitsPerSample` is meaningless — leave it 0. Add `framesPerPacket: Int` (samples per Opus frame, typically 960 = 20 ms at 48 kHz). The decoder needs this; `pcm_s16le` ignores it.

Both directions speak the same `AudioFrameEvent`. New cases:

```swift
case eventAudioTXFormat(AudioFormatEvent)   // Sweep ← Field, on subscribe
case commandAudioTXFrame(AudioFrameEvent)   // Sweep ← Field, per-packet
case commandPTT(PTTCommand)                 // Sweep ← Field, state edges
case eventTXState(TXStateEvent)             // Sweep → Field, mirror
```

**Why TX frames are commands, not events**: they target Sweep specifically; events implicitly broadcast. The existing `commandSendCW` is the precedent.

### PTT command

```swift
public struct PTTCommand: Codable, Sendable {
    public let requestID: UUID
    public let radioID: String?
    public let edge: PTTEdge   // .keyDown / .keyUp / .panic
}
```

`.panic` is "drop TX no matter what" — a recovery path for stuck PTT.

### TX state event

```swift
public struct TXStateEvent: Codable, Sendable {
    public let radioID: String
    public let phase: TXPhase  // .idle, .pttHeld, .draining, .keying
    public let bufferedMs: Int
    public let underrunCount: Int
    public let timestamp: Date
}
```

Field uses this to drive the on-screen TX indicator and to surface "you're cutting out" warnings.

---

## Encoder / decoder placement

### Direction matrix

| Path        | Producer        | Encode where         | Decode where                | Codec |
|-------------|-----------------|----------------------|-----------------------------|-------|
| RX (today)  | radio          | nowhere (raw PCM)     | iOS player (passthrough)    | pcm16 |
| RX (target) | radio          | Sweep `RadioAudioBroadcaster` | iOS player (Opus)   | opus  |
| TX (new)    | iOS mic        | iOS capture node      | Sweep mic relay → radio     | opus  |

Sweep gains an `OpusEncoder` (RX side) and `OpusDecoder` (TX side). Field gains the mirror pair.

### Library

- macOS / iOS both ship Opus via SwiftPM through [opus-swift-spm](https://github.com/Vyolet/opus-swift) or vendored libopus. Same build artifact across platforms — there's no Apple-blessed one.
- 48 kHz / mono / VOIP application / 24 kbps target / 20 ms frames. Roughly 60 bytes per packet on the wire — 30 KB/s before TCP framing, comfortably inside an LTE uplink.

### Sample-rate plumbing

The radio supplies whatever it supplies (16 kHz on SCU-LAN10, 48 kHz on Flex). Opus wants 8/12/16/24/48 kHz. Resample to **48 kHz** on the encoder side before handing to Opus; the decoder upconverts as a side-effect of frame sizing, so the consumer just needs to set its `AVAudioFormat` to 48 kHz mono. AVFoundation's `AVAudioConverter` is fine for both directions.

---

## PTT state machine (Sweep)

```
  ┌──── idle ────┐
  │              │
  │  PTT.down    │
  ▼              │
  pttHeld        │ PTT.up
  │              │
  │  drain TX    │
  ▼              │
  draining ──────┘
  │
  │  panic / drained
  ▼
  idle
```

States and transitions:

| State        | Behavior                                                                    |
|--------------|-----------------------------------------------------------------------------|
| `idle`       | RX audio flowing. No TX queue. Reject `audio.tx` frames (drop + log).        |
| `pttHeld`    | Radio keyed (PTT line + audio mute on RX broadcaster). Accept TX frames into ring buffer. Push to radio's audio input.   |
| `draining`   | PTT released; flush remaining buffered audio (≤ 200 ms cap) before unkeying. |

**RX mute** is half-duplex enforcement: while in `pttHeld` / `draining`, `RadioAudioBroadcaster` stops emitting frames so iOS doesn't get an echo of its own voice as side-tone. Sweep's local Mac speaker also mutes — operator was already hearing the sidetone direct from the radio. The TX-state-event tells Field to dim the RX volume slider.

`panic` short-circuits to `idle` even mid-drain, used when Field disconnects unexpectedly. A 5-second hard timeout in `pttHeld` catches stuck-mic scenarios from the operator's side too.

---

## Half-duplex management on Field

Three things happen on PTT-down:

1. Capture node starts. AVAudioSession switches to `.playAndRecord` with `.voiceChat` mode (echo cancellation, no AGC fight with the radio's mic gain).
2. RX player ducks to silence (don't tear down — re-priming on PTT-up adds 100 ms+).
3. Visual: pad turns red, TX indicator goes solid, RX volume slider greys out.

PTT-up reverses 1 + 2 + 3 in that order. Don't unduck RX until Sweep reports `phase: .idle` — otherwise Field unducks while Sweep is still draining and you hear your own tail.

---

## Bandwidth math (recap)

| Stream             | PCM16 16k | Opus voip 24 kbps |
|--------------------|-----------|-------------------|
| RX (Sweep → Field) | 256 kbps  | 24 kbps           |
| TX (Field → Sweep) | 256 kbps  | 24 kbps           |
| **Both directions**| 512 kbps  | **48 kbps**       |

Cell uplink on weak LTE can dip below 100 kbps. Raw PCM round-trip would not survive that; Opus does, with margin.

---

## Latency budget (LAN)

| Stage                                  | Budget |
|----------------------------------------|--------|
| iOS mic → AVAudioEngine input tap      | ~10 ms |
| Resample 16/48 kHz                     | ~5 ms  |
| Opus encode (20 ms frame)              | ~20 ms |
| iOS → Sweep TCP                        | ~5–15 ms |
| Opus decode + resample                 | ~5 ms  |
| Sweep → radio audio interface (USB / SCU-LAN10 UDP) | ~10–20 ms |
| Radio TX onset                         | ~10 ms |
| **Total**                              | **~70–90 ms** |

Cell adds 50–150 ms RTT. Worst-case ~250 ms still fits under the 300 ms LAN target with margin.

---

## What this commits us to

- New shared module: `OpusCodec` package wrapping libopus, with platform-specific `AVAudioFormat` glue.
- New TX-side broadcaster on Sweep (`RadioAudioInputForwarder`?) that pushes decoded PCM to the radio's mic line. Per-radio strategy:
  - **SCU-LAN10**: send to UDP port 50001 (mic uplink) framed in their inner header — needs a packet-format reverse. Spec already has the structure.
  - **USB CAT radios**: most don't support audio over USB; fall back to a virtual audio cable user-configured. Acceptable v1 limitation.
  - **Flex SmartSDR**: TCP DAX-style audio — separate channel.
- PTT line control via existing `RadioSession.setPTT` for non-bridge radios; CW Bridge gets a new "voice TX" frame.
- Field UI: PTT pad similar to the straight-key pad in placement, but press-and-hold (release ends TX). Mic-permission prompt the first time.
- Settings: per-radio "Remote Mic enabled" toggle in Sweep so users can opt out for radios that lack a clean mic-in path.

Total effort: roughly two weeks once the Opus library is integrated. Three if SCU-LAN10 packet-format reverse engineering is hostile (which it could be — the inner-header discovery for RX took a long capture session).

---

## Open questions

1. **Opus library choice.** Vendor libopus or pull a SwiftPM mirror? Vendoring gives us guaranteed reproducibility; mirror gives us less code to own.
2. **Echo cancellation.** AVAudioSession `.voiceChat` mode helps but assumes a phone-call-like loop. With a desk speaker pair playing radio audio at the same time the mic is hot, the cancellation may overcorrect. Test with `.measurement` mode as a fallback.
3. **DTX / silence suppression.** Opus can drop frames during silence. Saves ~30 % of the uplink but introduces a sidetone gap on the radio side. Probably leave off for v1.
4. **Audio routing on Field.** What if a Bluetooth headset is paired? Default behavior is "follow system route", but for amateur operations the operator might want explicit pinning. Out of scope for v1; document the tradeoff.
5. **TX while Sweep is offline.** No fallback. PTT pad disabled when not connected.
6. **Audio buffer sizing.** Smaller buffer = lower latency, more jitter risk. Start with 60 ms (3 × 20 ms Opus frames) and instrument.

---

## Next step (if approved)

Open Linear issues:

- `CAR-???` — Opus codec wrapper package + AVFoundation glue (CarrierWaveCore)
- `CAR-???` — Migrate `radio.audio` (RX) from PCM16 to Opus, with codec negotiation
- `CAR-???` — `audio.tx` topic + `commandPTT` + TX state event in RemoteOp protocol
- `CAR-???` — Sweep PTT state machine + `RadioAudioInputForwarder` for SCU-LAN10
- `CAR-???` — iOS Field PTT pad + mic capture pipeline + half-duplex RX duck
- `CAR-???` — Per-radio "Remote Mic enabled" Settings toggle in Sweep

Each is a vertical slice. Codec migration ships first so we don't have to hold both PCM16 and Opus paths live.
