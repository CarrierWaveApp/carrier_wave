# Icom IC-9700 CI-V Reference (satellite, Main/Sub, scope, LAN)

**Date:** 2026-09-11
**Scope:** What CW Sweep needs to know about the IC-9700 beyond the generic CI-V in `CIVProtocol.swift`. Cross-checked against the Icom CI-V Reference Guide (A7508-3EX-3a), Basic Manual, Hamlib `rigs/icom/ic7300.c` + `icom.c`, and wfview `rigs/IC-9700.rig`.

Legend: **[V]** verified in a primary source or shipping code. **[C]** community-reported. **[U]** unverified; test on hardware. **[B]** observed on our bench, 2026-10-04 ([investigation](investigations/2026-10-04-ic9700-sat-civ-lan-bench.md)); a [B] note wins over an older tag where they disagree.

Byte conventions: controller `E0`, radio `A2`. Frequencies are 5-byte little-endian BCD (10Hz/1Hz, 1kHz/100Hz, 100kHz/10kHz, 10MHz/1MHz, 1GHz/100MHz). 145.900000 MHz = `00 00 90 45 01`; 435.850000 MHz = `00 00 85 35 04`.

## Summary

- Default CI-V address **`A2`**. Not in `RadioProfile.swift`'s catalog yet. Note the catalog lists IC-7300 as `0x94` and IC-705 as `0xA4` while `BridgeRigDetector.swift` has them swapped; the correct values are IC-7300 = `0x94`, IC-705 = `0xA4`. [V]
- Four independent CI-V endpoints: **REMOTE** jack (max 19200), **USB** CI-V (port A, max 115200), **DATA** jack when `DATA Function = CI-V`, and **LAN** (RS-BA1 UDP). With `CI-V USB Port = Unlink from [REMOTE]` (factory default) USB and REMOTE are electrically independent; LAN works regardless of that setting. [V]
- Scope waveform streaming (`27 11`) works over USB (only when Unlinked at 115200) and over LAN. It is **not available on REMOTE**. [V]
- Full duplex (RX on one band while TX on the other) exists only in **Satellite mode** (`16 5A 01`). Outside sat mode only Main can TX (except A/B split). [V]
- `25`/`26` are **not** Main/Sub. With satellite mode OFF they address the selected / unselected VFO (A/B) of one band and never return the other band's frequency [B]; they return NG in satellite mode [V]. There is no `0x29` on the 9700. Setting Sub means `07 D1` then `05`. [V]
- CI-V Transceive is one global setting. The CSN S.A.T. manual asks for OFF, but the S.A.T. tracked fine with it ON on the bench [B]. `00`/`01` transceive frames reach every port; scope waveform frames go only to the client that asked for them [B].
- The CSN S.A.T. does **not** use satellite mode. It runs dual-band VFO mode with Sub selected as the 2 m uplink and the other band as the 70 cm downlink, so the downlink is only visible to a read-only client through transceive broadcasts. [B]

## CI-V transport settings

| Setting (`1A 05 nnnn`) | Values | Notes |
|---|---|---|
| CI-V Address | default `A2` | |
| CI-V Baud Rate (REMOTE) | Auto / 4800..19200 | 19200 is the REMOTE cap [C] |
| CI-V Transceive `0127` | `00` OFF / `01` ON (default ON) | When ON the radio emits unsolicited `FE FE 00 A2 00 f×5 FD` (freq) and `01 mode filt` (mode) on changes, to all ports. Frames carry **no band tag**; assign them by frequency range [B] |
| CI-V USB/LAN→REMOTE Transceive Address `0128` | `00`..`DF` | Frames from USB/LAN aimed at this address are forwarded out REMOTE. Keep `00` |
| CI-V USB Port `0129` | `00` Link to REMOTE / `01` Unlink (default) | Unlink = independent ports |
| CI-V USB Baud Rate | Auto / up to 115200 | Auto: the port emits garbage (all `0x00` at 115200) until the host sends a command, then locks to the host's rate. Send first (e.g. `19 00`), trust reads after [B] |
| CI-V USB Echo Back `0130` | `00` OFF / `01` ON | Emulates shared-bus echo on USB |
| CI-V DATA Echo Back `0131` | | |
| USB (B) Function `0132` | OFF / RTTY Decode / DV Data | Port B is not CI-V |
| DATA Function `0133` | `04` = CI-V | Third serial CI-V port |
| Network Control `0145` | ON/OFF (valid after restart) | |
| Control / Serial / Audio UDP ports `0147/0148/0149` | 50001 / 50002 / 50003 | |

USB enumerates as two CP210x CDC ports plus a USB audio codec. Port A (first enumerated, "IC-9700 Serial Port A") is CI-V. [V]

Power-on (`18 01`) must be preceded by N×`FE` preamble bytes: 115200→119, 57600→59, 38400→40, 19200→20, 9600→9. [V]

## Main/Sub band and full duplex

Hardware model: two identical receivers, Main and Sub. "You can transmit on only the Main band (except in Split Frequency operation)." Split (`0F`) is VFO A/B split within the Main band, not Main/Sub. The same frequency cannot be set on both bands. [V]

| Action | Bytes (controller → radio) | Notes |
|---|---|---|
| Select Main band | `FE FE A2 E0 07 D0 FD` | |
| Select Sub band | `FE FE A2 E0 07 D1 FD` | |
| Read selected band | `FE FE A2 E0 07 D2 FD` → `… 07 D2 00\|01 FD` | 00 Main, 01 Sub |
| Exchange Main/Sub | `07 B0` | Hamlib avoids it (display flicker) |
| Select VFO A / B of selected band | `07 00` / `07 01` | `07 01` → NG in sat mode |
| Equalize A=B | `07 A0` | |
| Read freq (selected band) | `03` → `03 f×5` | |
| Set freq (selected band) | `05 f×5` | 145.900: `FE FE A2 E0 05 00 00 90 45 01 FD` |
| Read / set mode | `04` → `mode filt`; `06 mode [filt]` | 00 LSB 01 USB 02 AM 03 CW 04 RTTY 05 FM 07 CW-R 08 RTTY-R 17 DV 22 DD |
| Selected / unselected VFO freq (A/B of one band, **not Main/Sub**) | `25 00` / `25 01`; set `25 00 f×5` | NG in sat mode. Never returns the other band [B] |
| Selected / unselected VFO mode (A/B of one band, **not Main/Sub**) | `26 00\|01` → `26 <sel> <mode> <data> <filt>` | NG in sat mode [V]; reply format [B] |
| Read data mode | `1A 06` → `1A 06 <data> <filt>` | FM-D reads as `04` → `05 01` plus `1A 06` → `01 01` [B] |
| Dualwatch (Sub RX on/off) | `16 59 00\|01` | |
| Split on/off | `0F 00` / `0F 01` | Main A/B only |
| Duplex | `0F 10` simplex / `11` DUP- / `12` DUP+ | |
| PTT | `1C 00 00\|01` | already in `CIVProtocolHandler` |

Polling `03` while a tracker owns the radio is racy: the S.A.T. toggles `07 D2` between writes, so a `03` reply can belong to either band. [B]

Every Sub write moves the radio's "selected band" highlight and, by default, the scope (see below). Hamlib and wfview both do `07 D1` → `05` → (optionally) `07 D0`. [V]

Hamlib `icom_set_split_vfo()` turns satellite mode ON when asked for a Main/Sub split and OFF for an A/B split; `icom_get_split_vfo()` returns `rx=MAIN, tx=SUB` in sat mode. `icom_satmode_fix()` clears targetable VFO caps while sat mode is on because `25/26` fail. [V]

`Sub Band Mute (TX)` for Speaker / USB / LAN (`1A 05 0033/0034/0035`) mutes Sub audio during TX (default OFF). Relevant for hearing your own downlink. [V]

## Satellite mode

| Action | Bytes | Notes |
|---|---|---|
| Satellite mode on/off | `16 5A 01` / `16 5A 00`; read `16 5A` | Hamlib `RIG_FUNC_SATMODE` |
| Select satellite memory (in sat mode) | `08 00 01` .. `08 00 99` | |
| Read satellite memory | `1A 07 00 nn` (nn = 01..99 BCD) | record layout below |
| Write satellite memory | `1A 07` + full record | |
| Memory write / copy to VFO / clear | `09` / `0A` / `0B` | |

`1A 07` record: bytes 1–2 channel; 3–7 downlink freq; 8–9 mode+filter; 10 data mode; 11 tone type; 12 digital squelch; 13–15 repeater tone; 16–18 TSQL; 19–21 DTCS; 22 DV code; 23–30 UR call; 31–38 R1; 39–46 R2; then the same block for the uplink; 16-char name at the end. NOR/REV tracking is not stored. wfview's `SatFormat` string in `IC-9700.rig` is a working parser. [V]

Behaviour in sat mode: Main = **downlink/RX**, Sub = **uplink/TX**. NOR: both move together with MAIN DIAL; REV: uplink moves opposite. RIT tunes the downlink ±9.99 kHz. `07 00` "selects the VFO mode"; `07 01`, `25`, `26` → NG; `08` works. [V]

Unknowns: whether a CI-V `05` on Main drags Sub in sat mode (SatPC32 sets both independently every second, which implies not) [U]. There is **no CI-V command for NOR/REV** [V]/[C].

## Spectrum scope / waterfall

Preconditions: for `27 11` over USB set `CI-V USB Port = Unlink` and `CI-V USB Baud Rate = 115200`. LAN works regardless. REMOTE cannot stream. Waveform output resets to OFF at power-off. wfview also requires `CI-V Transceive = ON` for the radio to push `27 00` frames. [V] Waveform output is per client: frames requested by the LAN session never appeared on the Unlinked USB port. [B]

A client that changes `27 10` / `27 11` must read them first and restore them on disconnect. wfview 2.22 turned the scope on at connect and left `27 10` = `01` after disconnect (baseline not read, so it may already have been on). [B]

### Control sub-commands (`FE FE A2 E0 27 xx … FD`; MS = `00` Main / `01` Sub)

| Sub-cmd | Data | Meaning |
|---|---|---|
| `27 10` | `00\|01` | Scope on/off |
| `27 11` | `00\|01` | Waveform data output to controller on/off |
| `27 12` | `00\|01` | **Which band's scope is active/streamed** |
| `27 14` | `MS mode` | `00` Center, `01` Fixed, `02` Scroll-C, `03` Scroll-F |
| `27 15` | `MS f×5` | Span (Center/Scroll-C): 2.5k `00 25 00 00 00`, 5k `00 50 00 00 00`, 10k `00 00 01 00 00`, 25k `00 50 02 00 00`, 50k `00 00 05 00 00`, 100k `00 00 10 00 00`, 250k `00 00 25 00 00`, 500k `00 00 50 00 00` |
| `27 16` | `MS 01–04` | Fixed / Scroll-F edge number |
| `27 17` | `MS 00\|01` | Hold |
| `27 19` | `MS dB1 dB2 sign` | Ref level −20.0..+20.0 dB in 0.5 steps; sign `00` + / `01` −. e.g. −10.5 dB: `27 19 00 10 50 01`. Common to both scopes |
| `27 1A` | `MS 00\|01\|02` | Sweep speed FAST/MID/SLOW |
| `27 1B` | `00\|01` | Scope during TX |
| `27 1C` | `00\|01\|02` | Center type |
| `27 1D` | `MS 00\|01` | VBW Narrow/Wide |
| `27 1E` | `MS range edge lo×5 hi×5` | Fixed edges; range `01` 144–148, `02` 430–450, `03` 1240–1300 MHz |
| `27 20` | `00\|01` | Marker position |

No `27 13` (dual scope) on the 9700. One stream at a time; `27 12` picks the band. wfview reports the scope follows the *selected* band, so tuning Sub via `07 D1` flips the stream to Sub unless re-pinned with `27 12`. [V]/[C]

### `27 00` waveform frame (radio → controller)

`FE FE E0 A2 27 00 [MS] [div] [max] [mode] [f×5] [f×5] [oor] [data…] FD`

| Payload index (after `27 00`) | Content | Values |
|---|---|---|
| 0 | Main/Sub | `00` Main, `01` Sub (fixed `00` on 7300/705) |
| 1 | Division order | BCD `01`–`11` |
| 2 | Division max | `11` over USB, `01` over LAN |
| 3 | Scope mode (div 1 only) | `00` Center, `01` Fixed, `02` Scroll-C, `03` Scroll-F |
| 4–8 | Center freq (Center) or lower edge (Fixed/Scroll) | BCD |
| 9–13 | Span (Center; half-width, wfview doubles it) or upper edge | BCD |
| 14 | Out of range (div 1 only) | `00` in range, `01` out (no waveform) |
| 15… | Waveform | `0x00`–`0xA0` (0–160) |

USB: division 1 is header only (18-byte frame); divisions 2–10 carry 50 pixels each; division 11 carries 25 → **475 bins**. LAN: a single frame with `div=01 max=01` carrying header + all 475 bytes (wfview detects payload length 490). Hamlib caps: `spectrum_line_length = 475`, `single_frame_data_length = 50`, level 0..160. [V]

Parsers to mirror: Hamlib `icom_parse_spectrum_frame()` (`icom.c`), wfview `parseSpectrum()` (`icomcommander.cpp`) which keeps separate Main/Sub accumulators keyed by byte 0.

Other scope settings via `1A 05`: `0187` scope during TX, `0188` max hold, `0189` center type, `0191` VBW, `0192` averaging, `0197` waterfall display, `0198` waterfall speed, `0202–0210` + `0348–0350` fixed edges. [V]

## LAN (RS-BA1 UDP)

Same protocol as IC-705 / IC-7610 already implemented in `IcomWiFiTransport` + `RSBA1Protocol.swift` (`docs/features/icom-wifi-protocol.md`): control 50001, serial/CI-V 50002, audio 50003, login/token/conninfo/capabilities handshake. wfview has no 9700-specific branch in its UDP handler except the LAN scope datagram size table (`490` = IC-705/9700/7300-LAN/905). Scope waveform data flows in the CI-V stream on 50002 as the single 490-byte-payload frame. [V]

- Network User1 / User2 are credentials, not concurrent slots. The built-in server serves **one client session**; a second client sees "Busy". [V] (Second concurrent LAN client not yet tested on our bench.)
- Bring-up: after the Ethernet cable went in the radio needed a restart before it answered ping/ARP. Network Control ON (valid after restart) and a configured User1 are required. Discovery packet type `0x03` → "I am here" type `0x04` works. [B]
- wfview 2.22 logged in over LAN while the S.A.T. drove REMOTE and a client polled USB, with no effect on control, USB audio, or an ISS recording. [B]
- RS-BA1 (Icom's client) resets **Sub band OFF, Satellite mode OFF, DR OFF, CI-V Transceive ON** on connect. wfview does not. Our transport must not either. [V]
- LAN RX audio: 1-ch (Main only) or 2-ch LPCM (Main = L, Sub = R). Sub audio only arrives with a 2-ch codec. [V]

## Multi-controller coexistence

- REMOTE, USB (Unlinked), DATA, and LAN are independent CI-V paths. A user runs Win4Icom over LAN, SatPC32 over USB, and a third controller on REMOTE simultaneously. Conflicts are logical (two writers fighting over VFOs), not electrical. [V]/[C]
- `CI-V Transceive` is global: unsolicited `00`/`01` frames go to every port. `27 00` scope frames go only to the client that enabled output [B]. Trackers' manuals want Transceive OFF; the S.A.T. tracked fine with it ON [B].
- USB and REMOTE are separate buses when Unlinked: >1100 read polls on USB, 0 NG, nothing reached the S.A.T. [B]
- Band selection (`07 D0/D1`) and scope band (`27 12`) are shared state. A second controller must not select Sub while a tracker owns tuning. Read `07 D2` before acting, or keep all traffic read-only / Main-only. [V]/[U]

## Doppler practice (how existing trackers drive the 9700)

| Tracker | Port | Sat mode? | Method / rate | Gotchas |
|---|---|---|---|---|
| SatPC32 | REMOTE 19200 or USB 57600–115200 with USB Echo Back ON; Transceive OFF | Yes (`16 5A 01`) | 1 Hz, tunes uplink and downlink independently; "transparent tuning" reads the dial back | Cannot set NOR/REV; scope edition needs USB dedicated to scope with CAT elsewhere |
| MacDoppler | USB preferred; Transceive OFF | Yes | Configurable updates/s; infers dial vs Doppler by rate | AFC off in FM; in-band Doppler fails during PTT |
| CSN S.A.T. | **REMOTE** 19200; manual says Transceive OFF, works with ON [B] | **No** ("Do not enable Satellite Mode"); `16 5A` read `00` for ISS FM and RS-44 [B]. Observed: Sub selected (`07 D2` = `01`, briefly toggled to Main), selected band = 2 m uplink, other band = 70 cm downlink [B] | `05` every UPDATE INTERVAL ms (500 recommended, 200 used) when change > MIN FREQ CHANGE; LOCK VFO keeps uplink in step with dial changes. Bench: ~0.57 s per band on a duplex bird, ~1.9 frames/s on one band; RS-44 uplink +0.65 Hz/s, downlink −1.95 Hz/s in 1–2 Hz steps; no tone commands [B] | Pauses writes when ENABLE is off; "do not simultaneously track with a PC program" |
| Gpredict + Hamlib (`-m 3081`) | USB, Unlink, Echo OFF, Transceive ON | Effectively yes (Hamlib enables it for Main/Sub split) | 1000 ms; alternates `07 D0/D1` + `05` | Main/Sub flicker; TX VFO stops updating during PTT (gpredict #181, #287) |

## Hamlib cross-check (`ic9700_caps`, rigctl model 3081)

Address `0xA2`; `serial_USB_echo_check = 1`; `spectrum_scope_caps {475, 50, 0, 160}`; edge ranges 144–148 / 430–450 / 1240–1300 MHz; `x25x26_always = 1`; VFOs `A|B|MAIN|SUB|MEM|MAIN_A|MAIN_B|SUB_A|SUB_B`; functions include `SATMODE (16 5A)`, `DUAL_WATCH (16 59)`, `SCOPE`, `SPECTRUM*`, `AFC`, `TRANSCEIVE`. `icom_defs.h`: `S_MAIN 0xD0`, `S_SUB 0xD1`, `S_BAND_SEL 0xD2`, `S_XCHNG 0xB0`, `S_FUNC_SATM 0x5A`, `C_SEND_SEL_FREQ 0x25`, `C_SEND_SEL_MODE 0x26`, `C_CTL_SCP 0x27`.

wfview `rigs/IC-9700.rig`: `CIVAddress=162`, `NumberOfReceivers=2`, `HasCommand29=false`, `SpectrumSeqMax=11`, `SpectrumAmpMax=160`, `SpectrumLenMax=475`, `HasLAN=true`.

## Sources

- IC-9700 CI-V Reference Guide 3a: https://www.pestingers.net/pages-images/ham-stuff/icom/ic9700/IC-9700_ENG_CI-V_3a.pdf (Icom Japan: https://www.icomjapan.com/support/manual/2161/)
- IC-9700 Basic Manual: https://rwb.co.nz/wp-content/uploads/2021/09/IC-9700_ENG_Basic_3.pdf
- IC-9700 Advanced Manual: https://icomuk.co.uk/files/icom/PDF/advancedManuals/IC-9700_AdvancedManual_ENG_1.pdf
- RS-BA1 v2 manual: https://www.icomeurope.com/wp-content/uploads/2022/12/RS-BA1_Ver2_ENG_IM_4.pdf
- Icom UK RS-BA1 + IC-9700 tips: https://icomuk.co.uk/Tips_When_Using_the_RS-BA1_IP_Remote_Control_Software_with_the_IC-9700/4056/1904/
- Hamlib: https://github.com/Hamlib/Hamlib (`rigs/icom/ic7300.c`, `icom.c`, `icom_defs.h`)
- wfview: https://gitlab.com/eliggett/wfview (`rigs/IC-9700.rig`, `src/radio/icomcommander.cpp`, `icomudphandler.cpp`, `icomudpcivdata.cpp`)
- gpredict IC-9700 notes: https://raw.githubusercontent.com/csete/gpredict/master/doc/notes/ic-9700.txt
- DK1TB SatPC32 settings: http://www.dk1tb.de/IC9700_settings.htm ; WA2FZW: https://github.com/WA2FZW/SatPC32-and-the-IC-9700 ; WB4SON: https://wb4son.com/wpblog/?p=4036 ; AMSAT: https://www.amsat.org/wordpress/wp-content/uploads/2020/01/SatPC32-IC9700-Setup-1.pdf
- MacDoppler manual: https://www.dogparksoftware.com/MacDopplerManual.pdf
- ON4ABS IC-9700 notes: https://sites.google.com/myuba.be/on4abstools/home/satellite-tracking/transcievers/ic-9700
- gpredict issues: https://github.com/csete/gpredict/issues/181 , https://github.com/csete/gpredict/issues/287
- wfview forum: https://forum.wfview.org/t/satellite-operation-with-9700/2887 , https://forum.wfview.org/t/ic-9700-and-sat-mode/999 , https://forum.wfview.org/t/ic-9700-no-spectrum-waterfall/2681 , https://forum.wfview.org/t/ic-9700-sub-band-audio-over-network-connection/4640
- Klop.solutions three-CI-V-interfaces note: https://klop.solutions/the-one-cable-solution/
