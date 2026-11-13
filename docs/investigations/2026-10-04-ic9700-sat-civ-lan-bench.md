# Investigation: IC-9700 + CSN S.A.T. CI-V / LAN bench

**Date:** 2026-10-04
**Status:** Resolved (bench phase); a real above-horizon duplex pass is still open
**Outcome:** USB (Unlinked), REMOTE (S.A.T.) and LAN coexist. The S.A.T. runs dual-band VFO mode, never satellite mode, so `25`/`26` can't see the downlink band; transceive broadcasts (assigned by frequency range) are the only read-only view of both bands. Sweep must restore the scope state it changes.

## Problem Statement

Phase 0 of [docs/plans/2026-09-11-satellite-ops-design.md](../plans/2026-09-11-satellite-ops-design.md) listed hardware unknowns that change the design: whether CI-V Transceive can be ON while the S.A.T. tracks, whether the ports are really independent, and what the S.A.T. actually sends. This bench session answered most of them with the S.A.T. tracking real birds below the horizon.

## Setup

- IC-9700, CI-V address `A2`.
- Mac mini (N9HO station) over USB: CP2102N port A = CI-V; USB audio codec L = MAIN, R = SUB. Also LAN at 192.168.68.54.
- CSN S.A.T. drives Doppler and the rotator through the CI-V REMOTE jack.
- Radio menu: CI-V USB Port = Unlink from [REMOTE], CI-V Transceive ON, CI-V USB Baud Rate Auto, CI-V USB Echo Back OFF, Network Control ON (took effect only after a restart), UDP ports 50001 / 50002 / 50003.
- Clients: a polling script on USB, wfview 2.22 on LAN.

## Hypotheses

### Hypothesis 1: USB and REMOTE are separate buses when Unlinked
- **Evidence for:** Icom reference guide, community reports (see the protocol doc).
- **Tested:** Yes
- **Result:** Confirmed. Nothing sent on USB reached the S.A.T.; 0 NG (`FA`) in more than 1100 read polls while the S.A.T. was writing.

### Hypothesis 2: The S.A.T. tolerates CI-V Transceive ON (design spec test #1)
- **Tested:** Yes (below the horizon only)
- **Result:** Yes. Transceive was ON for the whole session and the S.A.T. kept tracking. Unsolicited frames (`to=00 from=A2`) arrive on USB continuously while it tracks, even with the bird below the horizon. Scope waveform frames do **not** follow the same "every port" rule (see finding 9).

### Hypothesis 3: The S.A.T. uses the 9700's satellite mode
- **Tested:** Yes, ISS FM SSTV and RS-44 (linear, inverted)
- **Result:** No. `16 5A` read `00` throughout. The S.A.T. runs dual-band VFO mode.

### Hypothesis 4: `25`/`26` read Main vs Sub
- **Tested:** Yes
- **Result:** No. With satellite mode OFF they address the selected / unselected VFO (A/B) of one band. They never return the other band's frequency.

### Hypothesis 5: The LAN client coexists with the S.A.T. and USB (design spec test #3)
- **Tested:** Yes, with wfview 2.22 as the LAN client
- **Result:** Yes. wfview logged in over LAN at the same time as the S.A.T. on REMOTE and the USB link, with no effect on control, USB audio, or an ISS recording in progress. Sweep's own LAN client was not used.

## Findings

1. **USB and REMOTE are separate buses when Unlinked.** Nothing sent on USB reaches the S.A.T. 0 NG in >1100 read polls.
2. **Auto-baud locks on the first host command.** With CI-V USB Baud Rate = Auto the USB port outputs garbage (all `0x00` at 115200) until the host sends something. After `19 00` it locked at 115200. A client must send a command before it trusts anything it reads.
3. **Transceive broadcasts arrive all the time while the S.A.T. tracks**, even below the horizon:
   - one band (FM SSTV): about 1.9 frames/s;
   - duplex bird: pairs of `01 <mode>` + `00 <freq>`, alternating per band, about 0.57 s per band.
   - The frames carry **no band tag**. Assign them to a band by frequency range (144–148 / 430–450 / 1240–1300 MHz).
4. **The S.A.T. never uses satellite mode** (`16 5A` = `00`), for either ISS FM SSTV or RS-44 (linear, inverted). It runs dual-band: Sub selected (`07 D2` = `01`, briefly toggled to Main), the selected band = 2 m uplink, the other band = 70 cm downlink.
5. **With satellite mode OFF, `25 00/01` and `26 00/01` address the selected / unselected VFO of the same band, not Main vs Sub.** The downlink band is only visible through the transceive broadcasts. Polling `03` is racy because the S.A.T. toggles `07 D2`, so a `03` reply can belong to either band.
6. **RS-44 below the horizon:** uplink 145.9637 MHz LSB drifting +0.65 Hz/s; downlink 435.6438 MHz USB drifting −1.95 Hz/s (inverted, ratio ≈ 3), in 1–2 Hz steps. Only freq / mode frames; no tone commands seen.
7. **Reply formats:** `26 <sel> <mode> <data> <filter>`; `1A 06 <data> <filter>`. FM-D shows up as `04` reply = `05 01` and `1A 06` = `01 01`.
8. **LAN bring-up:** the radio needed a restart after the Ethernet cable went in before it answered ping/ARP. Network Control ON and a configured User1 are required. Discovery (type `0x03`) → "I am here" (type `0x04`) works. wfview 2.22 logged in over LAN alongside the S.A.T. and the USB link with no effect on control, USB audio, or an ISS recording.
9. **Scope frames go to the requesting client only.** Scope output started from the LAN session never appeared on the Unlinked USB port.
10. **wfview turned the scope on at connect and didn't restore it on disconnect** (`27 10` = `01` afterwards). Caveat: `27 10` wasn't read in the baseline, so it may already have been ON. wfview's waterfall was blank at first, which points to scope output (`27 11`) being off.
11. **Not tested:** CW Sweep itself against the radio; the LAN client slot limit (second concurrent LAN client); Main/Sub scope buffer separation against real frames; whether the S.A.T.'s band selection flips the LAN scope stream (spec test #2); a real above-horizon pass with duplex and PTT; spec tests #4 (`/track` casing) and #5 (MacLogger UDP push).

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `swift/macos/CWSweep/Services/Radio/RadioManager+Transport.swift` | Scope enable/disable on connect | Sent `27 11 01` / `27 11 00` blind; never read or restored `27 10` / `27 11`. Fixed: reads both on connect, restores on disconnect |
| `swift/macos/CWSweep/Services/Serial/SerialRadioTransport.swift` | USB CI-V path | Poll loop sends `03` right after open; RX chunks were all logged, including the transceive stream |
| `swift/macos/CWSweep/Services/Radio/RadioAutoDetect+Probes.swift` | USB auto-detect | Sends `19 00` first and skips `to=00` frames: correct for auto-baud |
| `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Radio/CIVProtocolHandler.swift` | CI-V decode | Decodes only `03`/`05` and `04`/`06`; ignores `to`; transceive `00`/`01` frames are not used for state |
| `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Radio/IcomWiFiTransport.swift` | LAN demux | Scope frames split out; CI-V payloads are not written to the command log |

## Root Cause

Not a bug hunt; design inputs. The one code defect found: Sweep changed the radio's scope state without restoring it, the same thing wfview was seen doing (finding 10).

## Resolution

- Protocol doc and design spec updated where they disagreed with the bench (see those files).
- Sweep now reads `27 10` / `27 11` on Icom LAN connect and puts them back on disconnect (`CIVScopeRestorePlan`, unit-tested).
- Serial CI-V RX chunks made only of transceive broadcasts are kept out of the command log.

## Lessons Learned

- Don't assume Main = downlink. Read what the tracker actually does: here the selected band is Sub = 2 m uplink.
- Any client that flips a radio-global setting must read it first and put it back.
- On the 9700, "unsolicited goes to every port" is true for `00`/`01` transceive frames, not for scope waveform output.
