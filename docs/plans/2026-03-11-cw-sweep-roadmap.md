# CW Sweep Feature Roadmap

**Date:** 2026-03-11
**Status:** Phase A complete, Phase B complete, Phase C implemented

## Context

CW Sweep is a macOS companion app for Carrier Wave with substantial existing functionality: QuickEntry logging, multi-protocol radio control (CI-V, Kenwood, Elecraft, Yaesu, FlexRadio), spot aggregation (RBN, POTA, SOTA, WWFF, DX Cluster), band map, contest engine, WebSDR/KiwiSDR integration, WinKeyer CW keying, N1MM+ broadcast, WSJT-X listener, iCloud sync, role-based layouts, and FT8 codec in CarrierWaveCore.

This roadmap identifies what's missing to make CW Sweep a credible standalone desktop logger and ultimately the best ham radio app on any platform.

## Competitive Landscape

### macOS Direct Competitors

| App | Price | Strengths | Weaknesses |
|-----|-------|-----------|------------|
| **MacLoggerDX** | $60 | Most complete macOS logger, DXCC, DX cluster, LoTW, rotator | Dated AppKit UI, no POTA/SOTA, no contest support |
| **RUMlogNG** | Free | Good basic logger, LoTW/eQSL, DX cluster, DXCC | Spartan UI, limited contests, slow development |
| **Aether** | $30 | Beautiful modern SwiftUI, iCloud sync | Very basic — no radio control, no cluster, no awards |
| **QLog** | Free/OSS | Cross-platform, LoTW/eQSL/Club Log, DXCC/WAS/WAZ, hamlib | Qt UI looks foreign on macOS, limited contests |

### Windows Heavyweights (the bar to clear)

| App | Price | Key Advantages |
|-----|-------|----------------|
| **N1MM+** | Free | Gold standard contest logger. SO2R, ESM, every contest template, deep macro system |
| **Ham Radio Deluxe** | $100 | All-in-one: logger + CAT + rotator + DM780 digital + satellite tracking |
| **Log4OM v2** | Free | Full award tracking (DXCC/WAS/WAZ/VUCC/IOTA), LoTW/eQSL/Club Log, cluster, propagation |
| **DXLab Suite** | Free | Modular suite: DXKeeper + Commander + SpotCollector + WinWarbler + Pathfinder + DXView |
| **Logger32** | Free | Mature logger, deep DX cluster, LoTW, DXCC tracking, rotator |
| **N3FJP** | $50-100 | Simple and approachable, strong casual/field day following, per-contest editions |

### Web-Based / Cross-Platform

| App | Key Advantages |
|-----|----------------|
| **Wavelog** (self-hosted) | Modern web UI, LoTW/eQSL/QRZ/Club Log, DXCC/WAS/WAZ/IOTA, ADIF, POTA integration |
| **CloudLog** | Predecessor to Wavelog, large user base, similar feature set |

### CW Sweep's Current Position

Already ahead of Aether and RUMlogNG on raw capability. The POTA/SOTA-first design, WebSDR integration, and role-based layouts are genuinely unique. But critical table-stakes features (ADIF, LoTW, award tracking) are missing, which prevents adoption by the broader ham community.

## What Hams Want (Forum Consensus)

Sourced from r/amateurradio, QRZ forums, eham.net reviews, and contest reflectors:

1. **"One app, not five"** — Juggling WSJT-X + logger + cluster + CAT controller is the #1 pain
2. **"macOS is second-class"** — Most serious tools are Windows-only; Mac users feel abandoned
3. **"LoTW sync is always broken"** — QSL syncing is fragile across all loggers
4. **"Show me what I need"** — Instant feedback on whether a spot is a new DXCC/band/mode
5. **"Contest logging shouldn't require a PhD"** — N1MM+ is powerful but intimidating
6. **"POTA/SOTA is an afterthought"** — Most loggers were built for DX/contest; parks came later
7. **"The UI looks like 2005"** — Modern design is essentially nonexistent in this space

CW Sweep already addresses points 2, 5, 6, and 7. The roadmap below addresses the rest.

---

## Phase A — Foundation ✅ Complete

*Goal: Make CW Sweep a credible standalone logger that people can migrate to.*

**Completed 2026-03-11.** All five foundation features shipped as CW Sweep 1.0.

### A1. ADIF Import/Export

**Priority:** Critical
**Effort:** Medium
**Dependencies:** `ADIFParser` already exists in CarrierWaveCore

The universal ham radio interchange format. Without this, users can't migrate in and their data can't get out.

- **Import:** File picker, field mapping preview, conflict resolution (skip/overwrite/merge), progress indicator, import report (added/skipped/errors)
- **Export:** Full log, filtered by date/session/contest, ADIF 3.1.4 compliant
- **Session export:** Export a single logging session as ADIF
- **Drag-and-drop:** Accept .adi/.adif files dropped onto the app window

### A2. DXCC Entity Database

**Priority:** Critical
**Effort:** Medium
**Dependencies:** `CTYParser` exists in CarrierWaveCore, CTY.dat bundled or downloadable

This is the foundation for award tracking, spot prioritization, and "new one" detection. Every callsign should instantly resolve to a DXCC entity with metadata.

- Auto-derive DXCC entity, CQ zone, ITU zone, continent from every callsign
- Store derived fields on QSO records (entity code, zone, continent)
- Backfill existing QSOs on first run
- Bundle CTY.dat with periodic updates (AD1C publishes monthly)
- Show entity info in: QSO entry field summary, spot list, inspector panel, band map tooltips
- Country flag display

### A3. LoTW Integration

**Priority:** Critical
**Effort:** High
**Dependencies:** TQSL for signing, or direct LoTW API

The #1 most-requested integration across all ham forums. ~90% of active contesters and DXers use LoTW.

- **Upload:** Sign and upload QSOs via TQSL CLI or LoTW direct API
- **Download:** Fetch confirmations, match to local QSOs by callsign+band+mode+date
- **Status tracking:** Per-QSO confirmation status (unconfirmed/confirmed, with date)
- **Visual indicators:** Confirmed badge in QSO log table, confirmation percentage in dashboard
- **Auto-sync:** Periodic background check for new confirmations
- **Batch upload:** Upload all unsynced QSOs, or per-session

### A4. Award Tracking — DXCC

**Priority:** Critical
**Effort:** High
**Dependencies:** A2 (DXCC entity database)

The primary motivation for logging for a huge segment of hams. DXCC is the most important award by far.

- **Band/mode matrix:** Grid of entities × bands/modes showing worked (W) and confirmed (C) status
- **Progress summary:** Total entities worked/confirmed, per-band and per-mode breakdowns
- **Challenge tracking:** DXCC Challenge (sum of band-entities confirmed on 160–6m)
- **Needed list:** Entities still needed overall and per-band/mode, sortable by most-likely-to-appear
- **Historical tracking:** Date of first QSO per entity/band/mode

### A5. "Needed" Indicators on Spots

**Priority:** Critical
**Effort:** Medium
**Dependencies:** A2 + A4

This is the single feature that creates the "I can't live without this app" moment. Every spot, every decode, every callsign entry instantly tells you what's new.

- **Spot list coloring:** Highlight spots that are new DXCC entity, new band-entity, or new mode-entity
- **Band map markers:** Distinct visual treatment for "needed" spots vs already-worked
- **Entry field feedback:** When typing a callsign, show "NEW ON 20M CW!" or "WORKED — confirmed on 40m SSB"
- **Priority scoring:** Rank spots by award value (new entity > new band-slot > new mode-slot > already worked)
- **Configurable:** Let users choose which awards drive the needed indicators (DXCC, WAS, etc.)

---

## Phase B — Competitive Parity

*Goal: Match the feature depth of Windows heavyweights (HRD, Log4OM, DXLab) — but on macOS with a modern UI.*

### B1. Additional QSL Services

**Priority:** High
**Effort:** Medium per service
**Dependencies:** A3 (LoTW pattern established)

- **eQSL:** Upload/download, confirmation matching
- **QRZ Logbook:** Upload (you already sync QSOs to QRZ from iOS — bring to CW Sweep)
- **Club Log:** Upload for DXpedition credit and DXCC tracking
- **Unified QSL status:** Single view showing confirmation status across all services per QSO
- **QSL card tracking:** Sent/received, via bureau/direct/LoTW/eQSL, date tracking

### B2. Additional Award Programs

**Priority:** High
**Effort:** Medium per award
**Dependencies:** A2, A4

- **WAS (Worked All States):** 50-state matrix per band/mode, state derivation from callsign
- **WAZ (Worked All Zones):** 40-zone matrix, CQ zone from CTY.dat
- **VUCC:** Grid square tracking for VHF/UHF
- **IOTA:** Island reference tracking (requires IOTA reference database)
- **WPX:** Prefix tracking
- **Unified awards dashboard:** Summary of progress across all award programs

### B3. CW/SSB Macro System

**Priority:** High
**Effort:** Medium
**Dependencies:** WinKeyer support exists; need voice keyer (B4)

Essential for contest and activation efficiency. N1MM+'s F-key macros are the gold standard.

- **F1–F12 programmable messages** for CW (sent via WinKeyer/Elecraft CWX)
- **Variable substitution:** `{CALL}`, `{RST}`, `{SERIAL}`, `{MYCALL}`, `{PARK}`, `{FREQ}`, `{NAME}`
- **Per-mode macro sets:** Different macros for CW, SSB, RTTY, FT8
- **Per-contest templates:** Load macro sets with contest definitions
- **ESM (Enter Sends Message):** Automatic message sequencing — Enter key sends the contextually appropriate message based on QSO state
- **Speed adjustment:** WPM +/- buttons, speed pot passthrough
- **Macro editor:** Visual editor with variable picker, test/preview

### B4. Voice Keyer

**Priority:** High
**Effort:** Medium
**Dependencies:** Audio output routing

Contest SSB operators need this alongside CW keying.

- **Record messages:** Record CQ, exchange, sign-off, etc. from microphone
- **F-key playback:** Same F1–F12 mapping as CW macros, mode-switched
- **Audio routing:** Play through radio's audio input (requires audio interface or VOX)
- **Variable insertion:** TTS for `{CALL}` and `{SERIAL}` spliced into recorded audio, or manual pause points
- **DVK mode:** Continuous CQ loop with configurable pause

### B5. Propagation Display

**Priority:** Medium
**Effort:** Medium

- **Solar indices:** SFI, A-index, K-index, Bz — already in menu bar extra, expand to dashboard widget
- **Band condition indicators:** Open/marginal/closed per band based on solar data and time of day
- **Gray line map:** Day/night terminator on world map, highlight gray line path
- **MUF estimation:** Maximum usable frequency for paths to specific DXCC entities
- **VOACAP integration:** Point-to-point propagation prediction (could use web API)
- **Band activity heatmap:** Show where spots are concentrated by band and time

### B6. Rotator Control

**Priority:** Medium
**Effort:** Medium

Every serious desktop logger supports this.

- **Protocol support:** hamlib `rotctld` network protocol (covers GS-232, Hy-Gain, Green Heron, etc.)
- **Bearing calculation:** Auto-calculate bearing from grid square to target callsign/entity
- **One-click aim:** Click a spot or QSO → point rotator at bearing
- **Azimuthal map integration:** Show current rotator position on the azimuthal map
- **Short path / long path toggle**
- **Preset positions:** Save named bearings for common directions

### B7. Bidirectional WSJT-X Integration

**Priority:** Medium
**Effort:** Medium
**Dependencies:** WSJT-X listener exists (UDP receive); need UDP send

Current WSJT-X support is receive-only. Full integration means:

- **Send logged QSO data** back to WSJT-X for its log
- **Highlight decodes** in WSJT-X decode list with worked-before / needed status
- **Auto-log:** When WSJT-X completes a QSO, automatically create the QSO in CW Sweep
- **Frequency/mode sync:** CW Sweep and WSJT-X stay in lockstep on radio state
- **Decode panel:** Show WSJT-X decodes in a CW Sweep panel with DXCC/needed coloring

### B8. Print & PDF Export

**Priority:** Medium
**Effort:** Low–Medium

- **QSL labels:** Avery label format printing for paper QSL cards
- **Log printouts:** Per-session, per-contest, date range, filtered
- **Award application forms:** DXCC application printout
- **PDF export:** Statistics summaries, session logs, contest results
- **Cabrillo preview:** Already have Cabrillo export; add preview before submission

---

## Phase C — Category-Defining

*Goal: Features that make CW Sweep the reason to buy a Mac for ham radio.*

### C1. Native FT8/FT4 Decode & Transmit

**Priority:** High (game-changer)
**Effort:** Very High
**Dependencies:** FT8 codec in CarrierWaveCore (exists), audio I/O, radio PTT control

No desktop logger on any platform has native FT8 built in. Everyone depends on WSJT-X as a separate app. This alone would be category-defining.

- **Waterfall display:** Integrated spectrogram with decode markers, frequency cursor
- **Decode list:** Real-time decode table with DXCC entity, distance, worked-before, needed-for-award coloring
- **One-click QSO:** Click a CQ decode → auto-fill entry → initiate FT8 exchange sequence
- **Auto-sequencing:** FT8 QSO state machine (exists in `FT8QSOStateMachine`) drives automatic message progression
- **Auto-logging:** QSO automatically logged on RR73/73 exchange
- **Multi-decode:** Decode all signals in the passband simultaneously
- **TX frequency management:** Auto-select clear TX frequency, respect sub-band boundaries
- **Integration with spot/award system:** Decodes feed into the same needed-indicator pipeline as spots

### C2. FlexRadio Panadapter Integration

**Priority:** Medium
**Effort:** High
**Dependencies:** SmartSDR TCP connection exists

FlexRadio users already use SmartSDR, but integrating the panadapter into CW Sweep creates a unified experience.

- **Wideband waterfall:** Display FlexRadio panadapter data in a CW Sweep panel
- **Spot overlay:** Plot spots on the waterfall at their frequencies
- **Click-to-tune:** Click on a signal in the waterfall to tune the radio
- **Slice management:** Create/move/remove receiver slices from CW Sweep
- **Band scope:** Narrowband scope around current frequency

### C3. iOS ↔ macOS Seamless Handoff

**Priority:** High
**Effort:** Medium
**Dependencies:** iCloud sync exists

Leverage the unique advantage of having both an iOS and macOS app.

- **Session continuity:** Start a POTA activation on iPhone (in the field), continue logging on Mac (at home/car)
- **Handoff protocol:** Use Apple Handoff to transfer active session state
- **Shared spot list:** Spots discovered on one device appear on the other
- **Unified dashboard:** See combined statistics across both devices
- **Remote radio control:** Use iPhone as a wireless radio control head for the Mac-connected rig

### C4. AI-Assisted Features

**Priority:** Low–Medium (differentiator, not urgent)
**Effort:** Medium per feature

Nobody in ham logging does this yet.

- **Smart callsign completion:** Beyond SCP — learn from your QSO patterns, recent spot activity, and band openings
- **Propagation prediction from QSO history:** "Based on your log, 20m to JA opens at 2300Z this time of year"
- **Anomaly detection:** Flag suspicious QSOs (e.g., claimed grid doesn't match callsign region)
- **Contest strategy suggestions:** "Switch to 15m — multiplier rate is higher there right now"
- **Natural language log search:** "Show me all my JA contacts on 40m CW from last winter"

### C5. Multi-Operator / Networked Logging

**Priority:** Low (Field Day / contest teams)
**Effort:** High

- **Shared log over LAN:** Multiple CW Sweep instances share one log via Bonjour discovery
- **Real-time dupe sync:** Instant dupe checking across all stations
- **Multiplier notifications:** "Station 2 just worked a new mult on 15m!"
- **Band locking:** Prevent two stations from transmitting on the same band (multi-single rules)
- **Unified score display:** Aggregate score across all stations

### C6. SDR Receiver Integration

**Priority:** Low
**Effort:** Very High

- **RTL-SDR / SDRplay / Airspy support** via rtl_tcp or SoapySDR
- **Integrated wideband waterfall** as a second receiver / skimmer
- **CW Skimmer equivalent:** Decode CW signals across the band, feed into spot system
- **Band monitoring:** Watch a band for activity while operating on another

---

## Implementation Sequencing

```
Quarter 1 (Foundation): ✅ COMPLETE
  A1. ADIF Import/Export ──────────┐
  A2. DXCC Entity Database ────────┤
  A3. LoTW Integration ────────────┤── Shipped as "CW Sweep 1.0"
  A4. Award Tracking (DXCC) ───────┤
  A5. Needed Indicators on Spots ──┘

Quarter 2 (Depth):
  B1. QSL Services (eQSL, Club Log, QRZ) ──┐
  B2. Additional Awards (WAS, WAZ) ─────────┤
  B3. CW/SSB Macro System ─────────────────┤── Ship as "CW Sweep 1.1"
  B4. Voice Keyer ──────────────────────────┘

Quarter 3 (Polish):
  B5. Propagation Display ──────────────────┐
  B6. Rotator Control ─────────────────────┤
  B7. Bidirectional WSJT-X ────────────────┤── Ship as "CW Sweep 1.2"
  B8. Print & PDF Export ───────────────────┘

Quarter 4+ (Leapfrog):
  C1. Native FT8 ──────────────────────────── The headline feature
  C3. iOS ↔ macOS Handoff ─────────────────── Unique ecosystem play
  C2. FlexRadio Panadapter ────────────────── Power user draw
  C4–C6. AI, Multi-Op, SDR ────────────────── Future differentiators
```

## Success Criteria

CW Sweep becomes a "true player" when a ham operator can:

1. **Migrate in:** Import their existing log from any other logger via ADIF
2. **Log effectively:** Enter QSOs with full radio integration, spots, and contest support
3. **Track progress:** See DXCC/WAS/WAZ progress and know what they still need
4. **Confirm QSOs:** Upload to LoTW/eQSL/Club Log and track confirmation status
5. **Act on spots:** Instantly see whether a spot is needed for any award program
6. **Export data:** Get their data out via ADIF, Cabrillo, print, or PDF
7. **Never open another app:** Radio control, digital modes, keying, cluster — all in one window

The single most impactful deliverable is **A2 + A4 + A5 together** — DXCC entity lookup + award tracking + needed indicators on spots. This creates the "I can't live without this" feedback loop where every spot and every QSO has immediate meaning in the context of the operator's award goals.
