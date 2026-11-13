# Satellite Workflows: Research + Opinionated Direction

Date: 2026-09-20. Status: assessment, not a committed plan.
Companion change shipped same day: pointing-mode boresight moved from the back
camera (−Z) to the boom axis (device +Y) — phone flat on the boom, screen up.

## How people actually work satellites (field research summary)

Sources: AMSAT (SO-50 guide, status API), K6LCS, VK3JED satiquette,
hamradiolaunchpad, mcbainsite, RadioReference operator threads, Look4Sat issue
tracker, HamSat App Store listing, hams.at, VoiceQSO, CardSat/FBSAT59 repos,
amsat.se 2025–26 full-duplex handheld reviews.

1. **Both hands are occupied during a pass** (boom + radio A/B toggle and PTT
   on half-duplex HTs). Nobody can type. Nobody can even hold the phone — it's
   strapped to the antenna (a whole cottage industry of 3D-printed Arrow-boom
   phone/HT mounts exists).
2. **Logging is deferred by design.** The dominant technique is: record audio
   of the whole pass, speak the metadata at AOS ("AO-91, 0140Z, grid CM97"),
   log after LOS from the recording. VoiceQSO now productizes exactly this
   (AI transcription tuned for callsigns/grids → QSOs).
3. **Exchanges are contest-style**: callsign + 4-char grid, 15–20 s per QSO,
   1–5 QSOs per pass. US satellite convention is 4-char grids (Europe: 6).
4. **Doppler practice is band-categorical**, not satellite-categorical: 2 m
   Doppler is ignored; 70 cm must be tracked. The operating rule everyone
   quotes is "hold your received downlink constant — tune until it sounds
   right," not "compute the offset." FM operators program 5-channel memory
   banks stepping the 70 cm side in 5 kHz increments.
5. **Pass selection is simple and shallow**: people work the next 2–3 passes,
   prefer ≥20–30° max elevation for handheld yagis, treat <15° as marginal,
   and love overhead passes. Multi-day pass tables are reference, not workflow.
6. **After the pass**: upload to LoTW with prop mode = SAT + satellite name
   (a distinct, easy-to-forget field — wrong = no credit), optionally report
   the bird as heard on the AMSAT status page. SatNOGS is a telemetry
   community, orthogonal to contact workflows.
7. **Rover/chaser culture runs on hams.at** (activation announcements, "what's
   visible from my grid"), mutual-window planning between two grids, and
   grid-award bookkeeping in ad hoc spreadsheets (KE4AL sheet, GridMaster).
8. **Competitive bar**: HamSat (iOS) already ships offline SGP4, per-second
   Doppler, a two-station sked planner, Apple Watch wrist-aim with haptics,
   Live Activities, and a "Rover Proof Photo." Look4Sat's open complaints:
   Doppler refresh too coarse, bad satellite naming, no list filtering.
   ISS Detector's: stale TLEs and a paid, poorly-maintained ham data add-on.

## Where Carrier Wave's satellite feature stands

What exists (alpha, hidden): azimuthal QTH-centered map, search, ±12 h time
scrubber, tilt-up sky dome with lock-on, info card with transmitters + AMSAT
workability, per-satellite and upcoming pass lists (10° workable filter),
mutual pass planner, antenna-mount pointing mode with Doppler-corrected
downlink/uplink + polarization roll.

What does not exist: **any connection to logging** (no SAT_NAME/PROP_MODE
fields on QSO, no way to log from the satellite tab), **any notifications**,
any watch surface, any hams.at awareness, any in-pass capture.

> **Status update (2026-09-20, same day):** P1 (SAT_NAME/PROP_MODE
> end-to-end + post-LOS quick log), P2 (favorites, pass alerts, Live
> Activity), and P3 (in-pass recording with tap marks) shipped on iOS.
> The whole suite then landed on **Android**, backed by a new shared Rust
> engine (`cw-domain/src/satellite/` + `SatelliteApi` in cw-ffi: SGP4,
> SatNOGS/AMSAT cache-through, pass prediction, alert planning) — chart,
> pass lists, exact-alarm alerts, quick log (born-completed session built
> Rust-side via `create_pass_session`), recording, sky dome, and pointing
> mode. **Phase D is done too**: iOS was swapped off SatelliteKit onto the
> shared engine — the Swift predictor/planner/workability/display-name/
> polarization/alert-planner/SatNOGS/AMSAT files are deleted, the tracker
> model and headless alert scheduler are thin clients of `SatelliteApi`,
> and the SatelliteKit SPM dependency is removed. Parity is anchored by
> the Rust fixture tests against SatelliteKit output (~0.006° az/el).
> P4 (watch) and P5 (FM channel-plan Doppler) remain open.

## The opinion

The feature today is a planetarium. It's a genuinely good planetarium — the
sky dome and pointing instruments are better than most of the market — but
research says the pass itself is the one moment users *cannot* interact with a
phone, and the moments they *can* interact (before: which pass? after: who did
I work?) are exactly where the app currently offers the least. Carrier Wave's
unfair advantage over HamSat/Look4Sat is that it IS the logbook. A tracker
bolted onto a logger that never logs is the wrong shape.

Organize everything around the **pass lifecycle**: plan → alert → aim →
capture → log → upload.

### P1 — Satellite logging (the differentiator, do first) — ✅ implemented 2026-09-20

Shipped as designed (schema v16 `sat_name`/`prop_mode`, quick-log via a
born-completed session through `SessionApi.logQso`). Cross-band cut:
FREQ/BAND = uplink (ADIF convention, your TX side); the store has no
`freq_rx`/`band_rx` columns yet — **FREQ_RX/BAND_RX is an explicit P1.5
follow-up** if satellite users ask. Old clients tolerate the new wire fields
but drop them on an edit round-trip (accepted — hidden alpha).
- First-class `satName` / `propMode` on QSO (ADIF SAT_NAME, PROP_MODE=SAT),
  flowing through ADIF export and QRZ/LoTW/sync paths. Forced, not optional,
  when a QSO originates from the satellite feature (research insight #6:
  forgetting prop mode = no LoTW credit).
- A **post-LOS quick-log flow** launched from the pointing screen / LOS:
  satellite, band, mode, frequency (from the worked transmitter), time, and
  my grid prefilled; the operator only enters callsign + 4-char grid per QSO
  (6-char accepted). One screen, N rows, done in a minute. This matches the
  real behavior (log after LOS from memory/scratch) instead of pretending
  live logging happens.

### P2 — Pass alerts — ✅ implemented 2026-09-20 (incl. Live Activity)

Shipped: favorites store (UserDefaults, first favorite auto-enables alerts),
`SatellitePassAlertPlanner` (pure, unit-tested) + scheduler headless of the
view-owned tracker model, `UNCalendarNotificationTrigger` alerts with a
24-of-64 pending budget, ≥20° default with the 10–20° "marginal" opt-in and
labels, 6 h BG refresh task, bell settings sheet, next-workable-passes strip,
and the AOS-countdown Live Activity (notification-tap start + foreground
imminence check; ActivityKit can't self-start from background without push).
- Local notifications for favorited birds: "SO-50 in 15 min, peaks 62° W→E."
- Default recommendation threshold ≥20° peak (research heuristic); keep the
  existing 10° filter as the floor and label 10–20° passes "marginal."
- Surface "next 2–3 workable passes" as the primary planning unit, not the
  full table. A Live Activity countdown → AOS is the natural iOS shape.

### P3 — In-pass capture (record now, structure later) — ✅ implemented 2026-09-20 (marks + scrub; no AI yet)

Shipped: REC PASS + giant MARK button on the pointing screen
(`SatellitePassRecorder`, AAC mono, foreground-only — no background-audio
mode), marks pre-seed quick-log rows at their tap times, inline playback with
per-mark chips that rewind 5 s (`SatellitePassPlaybackView`). Recordings are
backup-excluded and prune after 7 days. Transcription feed-in remains future
work as designed.
- One giant button on the pointing screen: record pass audio + tap-to-mark
  timestamps (each tap ≈ "I just worked someone"). Post-LOS, the quick-log
  flow plays back audio around each mark. This is the community's own coping
  mechanism, productized. Later: feed it the existing transcription muscle
  (VoiceQSO proves the category) — but marks + scrub is valuable with zero AI.

### P4 — Watch wrist-aim
- During the pass the phone is on the boom and the eyes are on the sky.
  Az/el error + haptic lock + Doppler-corrected downlink on the wrist.
  HamSat ships this; parity here plus P1's logging is a strictly better
  package. The boom-mounted phone (now correctly oriented) remains the
  "instrument panel" for the second operator / tripod case.

### P5 — Doppler presentation for FM birds
- Show the 70 cm side as a **5-step channel plan** (e.g. 436.795 → .790 →
  .785 → .780 → .775 with switch times), matching how HTs are actually
  programmed, and de-emphasize 2 m correction entirely. Keep the precise
  readout for the linear/CAT crowd. Frame guidance as "tune until it sounds
  right," which the current readout already supports.

### Later / explicitly not now
- **hams.at integration** in the mutual planner (rover announcements visible
  from your grid) — great fit, small audience; after the lifecycle works.
- **CAT-driven Doppler for linear birds** via the existing radio-control
  stack (IC-705 full duplex would be a real differentiator, and RadioIntent
  macros are the natural vehicle) — but it's a smaller, more technical
  subculture; FM easy-sats are the alpha audience.
- **Grid-award tracking** (VUCC-Sat, AMSAT Rover) — the spreadsheet gap is
  real, but only meaningful once satellite QSOs exist in the log.
- **More AR/sky-dome polish** — it's already the strongest part; further
  investment there is polishing the part of the workflow users look at least.

### Cuts/de-emphasis
- The ±12 h time scrubber is exploration candy; fine to keep, but it should
  never be more prominent than "next workable pass."
- The pointing screen's AR camera overlay is now (correctly) inconsistent
  with the flat-mount boresight; it earns its keep only for handheld visual
  acquisition. If it confuses users in testing, cut it before extending it.
