---
title: "Contest Support"
description: "WA7BNM contest calendar, contest templates, and Cabrillo export"
weight: 9
showToc: true
---

Carrier Wave provides contest support through server-published contest definitions, a contest browser, a phase-based scoring engine, and Cabrillo log export for submission to contest sponsors.

## Overview

Contest support in Carrier Wave covers:

- **Contest intent on the Sessions tab** for picking a contest and starting a scored session in one flow
- **Server-published contest definitions** (format v0.3) with 24-hour refresh
- **Phase-based scoring engine** with per-QSO, multiplier, and aggregate phases
- **Cabrillo export** for log submission
- **Contest-specific exchange logging** with validation
- **Operating constraints** (off-time, band-change limits)

## Contests Browser

### Accessing the Browser

Open the **Sessions** tab and tap the **Contest** intent in the 2×2 grid (Activate / Hunt / Casual / Contest). The contest picker opens automatically the first time and lets you browse the full calendar/catalog — Live-now contests at the top, schedule captions for the rest, with month/week/day calendar modes. Selecting a contest starts a scored `LoggingSession` with the contest id, category, and power populated from the definition's defaults.

Returning contesters see one-tap entry: the last-picked contest is remembered and the Contest intent jumps straight to session start.

Contests still appear at-a-glance on the dashboard `On Air` sheet under the Contests section, but the dedicated "Contests" row under Activity → Community has been retired as of 1.93.0 — Sessions is now the only entry point for starting contest operating.

### Contest Listing

The browser groups contests into sections:

- **Live now** — Contests currently in progress, with time remaining ("Live — ends in 45m")
- **All contests** — Full catalog with relative next-session times ("Next in 3h")

Each row shows:

- Contest name
- Mode, bands, and duration as colored chips
- Live countdown or next-session time
- Progress bar for active contests
- Popularity tier indicator

### Contest Detail

Tap a contest to view full details:

- **Schedule** — Start/end times, duration (UTC)
- **Rules summary** — Modes, bands, dupe scope and key, minimum off-time
- **Categories** and overlay categories
- **Sent/received exchange** format
- **Friend participation** — Friends who have logged a session for this contest, with QSO count and category

### Contest Calendar

Tap **See full calendar** from the section header to open `ContestCalendarView` — a month-grid and agenda browser with per-day contest markers and drill-through to contest detail sheets.

### Contest Detail Actions

From a contest detail sheet:

- **Log Now** — Start a logging session pre-configured for this contest
- **Remind me 30 min before** — Schedules a local notification
- **Add to Calendar** — Creates a calendar event
- **Open Rules** — Opens the sponsor's rules page

## Contest Definitions

### Server-Published Definitions

Contest definitions are fetched from the Carrier Wave server (`GET /v1/contests`) and cached locally with a 24-hour refresh cycle. Each definition includes:

- Schedule (recurring weekly, annual, or fixed dates)
- Scoring rules (per-QSO points, multiplier definitions, aggregate formulas)
- Exchange format (sent and received fields)
- Dupe rules (scope and composite key)
- Operating constraints (off-time, band-change limits)
- Categories and overlay categories
- Cabrillo export format

### On-Demand Loading

If a contest row's full definition hasn't been cached yet, tapping it triggers an on-demand fetch from the server. A per-row spinner appears while loading, and errors are surfaced as a modal.

### WA7BNM Calendar Integration

The WA7BNM contest calendar is still polled for discovery. Contest rows in the On Air sheet parse the WA7BNM description for mode, bands, exchange, duration, and category, and match known-major events against the server definitions.

### Browsing from Session Start

From the session start wizard, tap **Contest** to browse:

- **Active now** — Contests currently in progress
- **Upcoming** — Contests starting within the next 7 days
- **Recent** — Contests that ended within the last 48 hours (for late log submission)

## Contest Templates

### Starting a Contest Session

When you select a contest from the calendar:

1. Carrier Wave creates a session pre-configured with:
   - **Mode** matching the contest (CW, SSB, or the contest's primary mode)
   - **Exchange fields** appropriate for the contest type
   - **Contest identifier** stored in session metadata
2. The session title is set to the contest name
3. Contest-specific exchange fields appear in the QSO entry form

### Exchange Fields

Contest sessions add exchange-specific fields to the Logger:

| Exchange Type | Field | Example |
|---------------|-------|---------|
| **Serial number** | Auto-incrementing counter | 001, 002, 003... |
| **State/Province** | US state or Canadian province | CA, ON |
| **Grid square** | 4-character Maidenhead | CM87 |
| **CQ Zone** | CQ zone number | 3 |
| **ITU Zone** | ITU zone number | 6 |
| **Name** | Operator name | JOHN |
| **Custom** | Contest-specific exchange | ARRL section, power category, etc. |

### Serial Number Management

For contests requiring serial numbers:

- Serial numbers auto-increment starting from 001
- The next serial number is displayed before you log the QSO
- If you delete a QSO, the serial number is **not** reused (gaps are acceptable per contest rules)
- Serial numbers are per-session

### Scoring Engine

Carrier Wave uses a phase-based scoring engine that evaluates contest definitions:

1. **Per-QSO phase** — Assigns point values per contact based on conditions (e.g., `their_country`, `my_cq_zone`, `received.<field>`)
2. **Multiplier phase** — Counts unique multipliers (new DXCC entities, zones, states) with configurable scope
3. **Aggregate phase** — Computes the final score from per-phase results

The live Logger shows per-phase score breakdown, off-time remaining badges, and band-change violation counts.

### CWT Strike Card and Auto-Fill

For CWT (CW Open Test) sessions, Carrier Wave consolidates the callsign card, exchange row, and score footer into a single dense **strike card** that fits above the keyboard fold:

- Callsign + membership chips (e.g. `🎹 #3573`) + dupe / NEW MULT badge in the header
- Status line summarising name · state · grid · distance · bearing · prior-contact-count
- Two big monospaced exchange inputs (NAME and `# OR S/P/C`, 50pt tall) sized for thumb targeting at 100 QSOs/hour
- Tertiary `47Q · 47P · 12M · 564` score footer

When the operator's callsign hits the local member-list cache, **CWT auto-fill** prefills both fields:

- **CWops members** — name + member number from the cache
- **W/VE non-members** — first name from QRZ + state/province (e.g. `MD`, `ON`)
- **DX non-members** — first name + DXCC primary prefix derived from the callsign (e.g. `DL`, `JA`, `VK`)

QRZ nicknames win over registered first names (so K5OHY auto-fills as `TIM` not `TIMOTHY`). The auto-fill is re-runnable: a richer source arriving later overwrites the earlier prefill while preserving anything you typed by hand. Toggle in **Settings → Logger → Contests → Auto-fill exchange from member lists**.

### Duplicate Checking

Contest duplicate checking uses the definition's `dupe_rules`:

- **Composite keys** — e.g., callsign + band + mode_group
- **Configurable scope** — Per-band, per-mode, or custom combinations
- **`include_zero_point_qsos`** — Some contests count zero-point dupes toward multipliers
- **Duplicate warning** shows which band/mode combination already has a QSO with this station
- Duplicates are **not blocked** (some contests allow duplicate QSOs for band-change logging)

## Cabrillo Export

### Generating a Cabrillo File

From a contest session's detail view:

1. Tap the **Export** button
2. Select **Cabrillo (.cbr)**
3. Review the header fields
4. Share or save the file

### Header Fields

Carrier Wave auto-populates the Cabrillo header:

```
START-OF-LOG: 3.0
CONTEST: CQ-WW-CW
CALLSIGN: W6JSV
CATEGORY-OPERATOR: SINGLE-OP
CATEGORY-BAND: ALL
CATEGORY-POWER: LOW
CATEGORY-MODE: CW
CLAIMED-SCORE: 12345
CLUB:
LOCATION: CA
NAME: Your Name
ADDRESS: ...
SOAPBOX: Logged with Carrier Wave
END-OF-HEADER:
```

### Editing Header Fields

Before exporting, you can edit any header field:

- **Category fields** - Tap to select from contest-valid options
- **Claimed score** - Auto-calculated from QSO data and contest scoring
- **Soapbox** - Free-text notes about your operation
- **Club affiliation** - For club competition scoring

### QSO Records

Each QSO is formatted according to the Cabrillo specification:

```
QSO: 14000 CW 2025-11-29 1423 W6JSV 599 CA K1ABC 599 CT
```

Fields include: frequency (kHz), mode, date, time, your call, sent exchange, their call, received exchange.

### Validation

Before export, Carrier Wave validates:

- All required exchange fields are populated
- Frequency data is present for each QSO
- Time stamps are within the contest window
- **Warnings** appear for QSOs outside the contest period (they're included but flagged)

## Tips for Contest Logging

### Speed

- Use **Quick Entry** mode for fastest logging
- **Command row** buttons for frequent operations (CQ, QSY, band change)
- **Auto-incrementing serial numbers** eliminate manual tracking

### Accuracy

- Review exchange fields before logging
- Use QRZ lookup to verify callsigns
- Check the duplicate indicator before calling a station

### Submission

- Export Cabrillo **promptly** after the contest ends
- Most contests have a 5-7 day submission deadline
- Verify the Cabrillo file before uploading to the sponsor's submission page

## See Also

- [Logger](/reference/logger/) - Session management and QSO entry
- [Export & Sharing](/reference/export/) - Cabrillo and ADIF export
- [Logs & Search](/reference/logs-search/) - Browse contest QSOs with `contest:*` query
