---
title: "Logs & Search"
description: "Query language, filters, QSO detail, and session browsing"
weight: 3
showToc: true
---

The Logbook tab provides powerful search and filtering capabilities for exploring your QSO history, with full {{< term "ADIF" >}} metadata display and sync status tracking.

## Log List

The default view shows your most recent contacts in reverse chronological order. Each entry displays:

- **Callsign** (with nickname if available from callsign notes, and emoji if configured)
- **Contact count badge** (bronze at 10 QSOs, silver at 25, gold at 50)
- **Date and time** (UTC)
- **Frequency** (if logged)
- **Band and mode**
- **RST exchanged**
- **Park references** (POTA, with park names when available)
- **SOTA reference** (if applicable)
- **WWFF reference** (if applicable)
- **Sync status indicators** (one badge per service)

Tap any entry to view the full QSO detail.

## Search

The search bar supports two modes: simple callsign search and structured query language.

### Simple Search (Implicit Callsign Search)

When you enter plain text without field qualifiers, Carrier Wave treats it as a callsign prefix search:

```
W1AW
K6TEST
VE3
```

- Text is automatically uppercased
- Acts as `callsign:<text>*` wildcard search
- Searches across their call, your call, and operator call fields
- An info note appears when using implicit callsign search

### Query Language

For precise searches, use field-specific queries.

#### Field Queries

| Query | Meaning |
|-------|---------|
| `call:K6TEST` | Exact callsign match |
| `call:K6*` | Wildcard callsign (prefix) |
| `band:20m` | Contacts on 20 meters |
| `mode:cw` | CW mode contacts |
| `mode:ssb` | SSB mode contacts |
| `mode:ft8` | FT8 mode contacts |
| `state:CA` | California stations |
| `grid:CM87` | Grid square (4 or 6 char) |
| `park:US-0001` | Specific POTA park |
| `park:K-*` | Any US POTA park (wildcard) |
| `theirpark:US-0001` | Their POTA park reference |
| `sota:W7W/KG-001` | SOTA summit reference |
| `wwff:KFF-1234` | WWFF reference |
| `freq:14.074` | Specific frequency |
| `freq:>14.0` | Above 14 MHz |
| `power:>100` | Over 100W |
| `rig:IC-705` | Radio/rig name (partial match) |
| `antenna:EFHW` | Antenna description (partial match) |
| `notes:*portable*` | Notes field search |
| `country:Japan` | DXCC entity name |
| `dxcc:339` | DXCC entity number |
| `contest:*` | QSOs logged during a contest |

#### Source Filters

Filter by import or sync source:

| Query | Meaning |
|-------|---------|
| `source:clublog` | Imported from Club Log |
| `source:qrz` | Imported from QRZ |
| `source:pota` | Downloaded from POTA |
| `source:lofi` | Synced from Ham2K LoFi |
| `source:lotw` | Downloaded from LoTW |
| `source:eqsl` | Imported from eQSL |
| `source:logger` | Logged in Carrier Wave |

#### Date Queries

| Query | Meaning |
|-------|---------|
| `date:today` | Today's contacts (UTC) |
| `date:yesterday` | Yesterday's contacts |
| `after:7d` | Last 7 days |
| `after:30d` | Last 30 days |
| `after:2024-01-01` | Since January 1, 2024 |
| `before:2024-06-01` | Before June 1, 2024 |
| `date:2024-01` | Specific month (January 2024) |
| `date:2024` | Specific year |

#### Status Queries

| Query | Meaning |
|-------|---------|
| `confirmed` | Confirmed via LoTW |
| `confirmed:lotw` | LoTW confirmed |
| `confirmed:qrz` | QRZ QSL confirmed |
| `confirmed:eqsl` | eQSL confirmed |
| `synced:pota` | Uploaded to POTA |
| `synced:qrz` | Uploaded to QRZ |
| `synced:clublog` | Uploaded to Club Log |
| `synced:eqsl` | Uploaded to eQSL |
| `pending` | Awaiting sync to any service |
| `pending:yes` | Same as `pending` |

#### Combining Queries

Use **spaces** for **AND** (all conditions must match):

```
band:20m mode:cw after:30d
```

Finds CW contacts on 20 meters in the last 30 days.

Use **`|`** for **OR** (any condition matches):

```
call:W1AW | call:K1ABC
```

Finds contacts with either W1AW or K1ABC.

Use **`-`** for **NOT** (exclude matches):

```
-mode:ft8
```

Excludes FT8 contacts.

```
band:20m -state:CA
```

20 meter contacts excluding California.

#### Examples

**W1AW on 40 meters:**

```
call:W1AW band:40m
```

**SSB contacts with Colorado stations this year:**

```
state:CO mode:ssb after:2024-01-01
```

**All POTA contacts in the last week:**

```
park:* after:7d
```

**Park-to-park (P2P) contacts:**

```
park:* theirpark:*
```

**Confirmed but not yet uploaded to QRZ:**

```
confirmed:lotw -synced:qrz
```

**All contacts using a specific radio:**

```
rig:IC-705 after:30d
```

**SOTA contacts:**

```
sota:*
```

### Quick Filters

The filter menu (three horizontal lines icon) provides common search presets:

- Last 7 days
- Last 30 days
- This year
- CW contacts
- FT8 contacts
- SSB contacts
- POTA activations
- LoTW confirmed
- Pending upload

Tap a quick filter to populate the search bar.

### Performance Warnings

Carrier Wave analyzes your query and warns about potentially slow searches. Warnings appear when:

- Searching a large log (>5,000 QSOs) without indexed field filters
- Using only non-indexed fields (e.g., notes, grid)
- Full-table scans are required

When warned:

- Click **Search Anyway** to proceed
- Click **Add Date Filter** to add `after:30d` and narrow results
- Add field-specific filters (callsign, band, mode, date) for better performance

**Performance note:** Field-specific queries use database predicates for efficient full-table search. Simple callsign searches and indexed field queries execute quickly even on large logs.

### Help Sheet

Tap the filter menu and select **Search Help** to view the syntax reference in-app.

## QSO Detail View

Tap any contact to view the full QSO record. The detail view uses a visual-hierarchy layout designed for quick scanning.

### Hero Card
- **Callsign** (large, monospaced)
- **Name** (if available)
- **Location** (QTH, state, country)
- **License class and contest badges** (if applicable)

### Contact Panel
- **Band, mode, and frequency** as colored pills
- **RST** displayed as "sent ↔ received" exchange with large digits
- **Stats strip** — Distance (km + mi), bearing with compass point, watts-per-km / watts-per-mi efficiency

### Station Context

Two side-by-side cards show **THEY** vs **ME**:

- Grid square, location, DXCC entity
- POTA park reference, rig, power
- Antenna, key, mic (from matching Station Profile)

### Activity References
- **POTA, SOTA, WWFF, AoA** references as colored chips (shown only when populated)
- **Club affiliations** as flowing chip rows

### My Station Section
- **My callsign, station callsign, rig, station profile** (shown only when populated)

### Contest Section
- **Contest name, serial sent/received, exchange sent/received** (shown only when populated)

### Notes Section
- **Notes** rendered as an italic quote card with accent bar

### Sync Status Section

Shows per-service sync indicators:

- **Service badges** (colored pills showing status)
- **Status text** (Present, Submitted, Rejected, Pending Upload)
- **Last confirmed date** (if available)
- **Confirmation stars** (LoTW, QRZ QSL, eQSL)

**Badge colors:**

- **Green:** Present/synced
- **Blue:** Submitted, awaiting confirmation
- **Orange:** Pending upload (service configured)
- **Gray:** Pending upload (service not configured)

### Source Section
- **Import/source metadata** collapsed into a single disclosure
- **Other ADIF Fields** — Expandable disclosure that parses `rawADIF` and surfaces any ADIF spec fields not already mapped to a dedicated row, so imported logs don't silently drop unfamiliar tags

### Actions

From the QSO detail view, you can:

- **Edit** — Modify any field (changes saved locally and re-queued for sync)
- **Delete** — Soft delete (hides QSO, prevents future sync)
- **Share** — Send an enriched share link via iMessage, Mail, or Notes

## Editing QSOs

Tap **Edit** from the detail view. The Edit sheet is organized into collapsible sections with explicit tap targets:

### Sections

- **Contact** (expanded by default) — Callsign, date/time, band, mode, frequency, RST
- **My Station** — My callsign, station callsign (club/alternate call), rig, station profile
- **Signal** — Power, RST adjustments
- **Their Location** — Grid, state/province, DXCC entity, country
- **Activity References** — POTA park (theirs and mine), SOTA summit, WWFF reference, AoA code
- **Contest** — Contest name, serial sent/received, exchange sent/received
- **Notes** — Free-form text

### Rich Pickers

Fields use the same rich pickers as the Logger:

- **Rig** — `InventoryPickerSheet` with equipment catalog
- **Park** — `ParkPickerSheet` with nearby suggestions and search
- **SOTA** — `SummitPickerSheet` with searchable catalog
- **WWFF** — `WWFFReferencePickerSheet`
- **Contest** — `ContestPickerView`
- **DXCC** — `DXCCPickerSheet` backed by entity database
- **Mode** — `ModePickerSheet` (55 modes grouped by Phone/CW/Digital/Image)
- **Band** — `BandPickerSheet` (30 bands from 2190m to 1mm)
- **State** — `StatePickerSheet` (USA + Canada with full names)

Every picker includes a **Custom** entry row for values outside the bundled catalog.

### Saving Changes

Changes are:

1. **Saved locally** to your SwiftData store
2. **Re-queued for sync** to services that support updates (QRZ, POTA, Club Log, eQSL)

**Note:** Some services don't support updating previously uploaded QSOs. Updates may only apply to future uploads.

## Deleting QSOs

Tap **Delete** from the detail view to remove a contact.

**Deletion behavior:**

- **Soft delete** -- QSOs are hidden, not permanently removed from the database
- **Hidden QSOs** don't appear in lists, stats, maps, or activations
- **Sync prevention** -- Hidden QSOs won't sync to cloud services
- **Reversible** -- View and restore hidden QSOs in **Settings -> Developer -> Hidden QSOs**

**Important:** Deletion does NOT remove QSOs from cloud services. Most services (QRZ, POTA, LoTW) don't support remote deletion via API.

## Sessions Tab

The Sessions tab (within Logs) provides a browsable history of all completed logging sessions, grouped by month.

### Session List

Each session row shows:

- **Date and time**
- **Activation type** (POTA, Rove, Hunter, General)
- **Park reference(s)** (for POTA activations)
- **QSO count**
- **QSO timeline** (horizontal bar showing contact timing and band changes)
- **Conditions badges** (solar and weather indicators)
- **Equipment badges** (radio, antenna, key/mic)
- **Recording indicator** (microphone icon if WebSDR recording exists)
- **Upload status** (for POTA sessions: pending, completed, failed)

### Session Grouping

Sessions are grouped by month in reverse chronological order (most recent first).

### Recording Navigation

Sessions with WebSDR recordings show a microphone icon. Tap the session to:

- Navigate to the **Recording Player** (full-screen with transport controls)
- View the **QSO list** synced to recording timestamps
- **Share clips** (select range, export M4A)

See [WebSDR Recording](/reference/websdr/) for details.

### Import ADIF into Session

Long-press any session to reveal the **Import ADIF** option. This lets you import an ADIF file directly into an existing session, merging the contacts with the session's existing QSOs.

**Validation warnings:** If the imported ADIF contains QSOs with a different callsign or park reference than the session, Carrier Wave displays a warning before proceeding. You can choose to continue or cancel the import.

This is useful when you have QSOs logged in another app during an activation and want to consolidate them into a single session.

### Session Detail

Tap any session to view:

- **Full equipment list**
- **Session photos** (with full-screen viewer)
- **Notes** (operator comments)
- **Persisted spots** (RBN and POTA spots captured during the session)
- **QSO list** (expandable rows with swipe-to-delete)
- **Edit button** (modify equipment, photos, notes)

For **POTA activations**, the detail view additionally shows:

- **Upload button** (submit to POTA)
- **Reject option** (mark QSOs as hidden, prevent upload)
- **Share card** (generate brag sheet with map and stats)
- **Export ADIF** (download activation log for offline use)
- **Activation statistics** (charts, distance histogram, rate analysis)

See [Service Sync Flow](/reference/sync-flow/) for POTA upload details.

## See Also

- [Home](/reference/dashboard/) - View aggregated stats and drill-down views
- [Service Sync Flow](/reference/sync-flow/) -- Understand sync behavior and status indicators
- [Logger](/reference/logger/) -- Log new contacts during activations
- [WebSDR Recording](/reference/websdr/) -- Remote SDR integration and playback
