---
title: "Tiles on the Air (TOTA)"
description: "TOTA activations, scoring, tile detection, T3 contacts, and Personal Effort Factor"
weight: 5
showToc: true
---

Carrier Wave is a Tiles on the Air-aware logger. Tag a session as TOTA at start
and Carrier Wave handles tile detection, scoring, and ADIF upload — and shows
you a four-tier score breakdown after every activation.

For the program rules and rankings, see [tilesontheair.com](https://tilesontheair.com/).

## Setting Up

1. Go to **Settings → Sync Services → Tiles on the Air**.
2. Generate an API key from your tilesontheair.com profile, paste it, and tap
   **Save and Test**. Carrier Wave makes a small spots-fetch call to confirm
   the key works.
3. Optional: opt in to **Personal Effort Factor (PEF)** in the same screen.
   Pick a value from 1–10 — this scales the distance term of your score on the
   PEF leaderboard. Standard leaderboard ranking is unaffected.

## Starting a TOTA Session

In the start sheet, tick the **TOTA** program chip. The TOTA section then
appears with:

- **Activation site** — lat/lon (use **Detect** to pull from GPS) plus a small
  map preview. The 6-character Maidenhead tile is derived automatically.
- **Category** — Standard (full formula) or Mobile (separate leaderboard,
  simpler formula). Picking Mobile hides the percentage-bonus inputs.
- **Record GPS track** — when on, the app samples your route and uses the
  total distance + elevation gain for scoring.
- **Winter activation** — auto-checked when the date and your latitude fall
  in your hemisphere's winter window. Override it if needed.
- **Bonus toggles** — pets, kids, ruck weight, Winlink/APRS/VarAC sent over RF.
- **Personal Effort Factor** — copied from your profile setting; editable here
  and frozen onto this session at start (per the rules).

QRP is detected from your wattage field — set ≤10 W and the session
automatically scores at the 2× multiplier.

## During the Session

Log QSOs as usual. The score is computed at session end (live scoring would
hit the spots feed too aggressively and add main-thread work to the logger).
If you change frequency or category mid-session, update via the session edit
sheet.

## After the Session: The Score Ledger

The TOTA section in the session detail view shows a **four-tier ledger**:

| Tier | What's in it |
| --- | --- |
| **Confirmed** | Base × distance × QSOs, QRP ×2, winter, ruck, elev, pets, kids, Winlink/APRS/VarAC flats |
| **Estimated** | Tile-to-Tile (T3) boost from spot correlation — chasers spotted as tile activators within a 6-hour window before the QSO |
| **Asserted** | First-activation-of-tile-ever bonus, if you tick the box |
| **Pending** | First-activation-of-grid-this-quarter — only the server can confirm; shown as eligibility until upload |

The headline pre-upload total sums **Confirmed + Estimated + Asserted**. Once
you upload to TOTA, the official points value replaces it and the diff line
shows what bonuses credited.

The section also includes:

- **Path map** — your track polyline, start/end markers, and 6-char tile
  boundary overlay. Tap **Share GPX** to export the recorded track.
- **Bonus chips** — quick visual of which bonuses fired (winter, ruck, pets,
  etc.).
- **T3 candidates** — list of QSOs we matched against TOTA spots, with each
  chaser's tile.
- **Refresh spots** — re-runs the correlation when the snapshot is older than
  5 minutes. Useful when you logged QSOs before activators self-spotted.

## Multi-Tile Outings

If your track crosses tile boundaries and you log QSOs from each, the summary
log shows a single row listing every tile activated. The upload layer splits
into one TOTA submission per tile (each tile is its own row on the
leaderboard).

Tiles the track passed through but where you didn't log get listed as
**candidates** with a "tap to add" affordance — you decide whether to claim
them.

## Uploading

The current path is **Settings → Tiles on the Air → Upload ADIF File…** —
pick an ADIF and Carrier Wave POSTs it to the TOTA API. The server parses
ADIF 3.x and computes the official score; the response is written back to
the session as `totaOfficialPoints` and the brag-sheet activity is updated
so clubmates see the official number.

## Brag-Sheet Visibility

When the activity feed is shared with your clubs, your TOTA session card
includes the activated tile(s), category, total score with confidence
("estimated" pre-upload, "official" after), distance, elevation, bonus
flags, and PEF. The full track and raw T3 list stay on your device.

## Edit Semantics After Session End

| Field | Editable until |
| --- | --- |
| Personal Effort Factor | Frozen at session end (rules requirement) |
| Category (Standard/Mobile) | Pre-upload only |
| Winter override | Pre-upload only |
| First-activation-of-tile-ever | Pre-upload only |
| Activated/candidate tiles | Pre-upload only |
| T3 candidate snapshot | Always refreshable |

After upload, all inputs lock and a "Locked: submitted to TOTA" note appears.

## What Carrier Wave Doesn't Enforce

- **Repeater contact cap** (rules limit FM repeater QSOs to 2 per activation,
  on different repeaters). Carrier Wave doesn't track which QSOs were via a
  repeater — it counts FM QSOs as 1 each and the server enforces the cap on
  upload.
- **First-activation-of-grid-in-quarter** — this requires the global TOTA
  history. Shown as a Pending tier; the server credits up to +10 per tile if
  it qualifies.
