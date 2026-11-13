---
title: "Spot Monitoring"
description: "RBN spots, POTA spots, SOTA spots, WWFF spots, P2P opportunities, and propagation data"
weight: 8
showToc: true
---

The Spot Monitoring system helps you find stations to work, assess propagation, and monitor current band conditions through integration with the {{< term "RBN" >}}, {{< term "POTA" >}} spotting network, SOTA spots, WWFF spots, and solar/weather data sources.

## Accessing Spots

### Logger Tab Commands

From the {{< term "Logger" >}} tab, enter these commands in the callsign field to open dedicated spot panels:

- `RBN` - Show your own {{< term "RBN" >}} spots
- `RBN <callsign>` - Show spots for any callsign
- `POTA` - Open POTA spots panel
- `P2P` - Show Park-to-Park opportunities (during POTA activations only)
- `SOLAR` - Display solar conditions panel
- `WEATHER` - Show weather conditions

### iPad Persistent Sidebar

On iPad, a persistent spots sidebar appears alongside the Logger, with tabs for:

- **POTA** - Active park activators
- **RBN/My Spots** - {{< term "RBN" >}} detections
- **P2P** - Park-to-park opportunities (when activating)

### Activity Log Hunter View

The [Activity Log](/reference/activity-log/) includes a dedicated hunter spot list with filtering specific to reviewing worked stations.

## Spot Types

### RBN (Reverse Beacon Network)

The {{< term "RBN" >}} is a worldwide network of automated receiving stations that decode {{< term "CW" >}} and digital mode transmissions. Each spot includes:

- **Callsign** - Station heard
- **Frequency** - In kHz
- **Mode** - CW, FT8, FT4, etc.
- **SNR** - Signal-to-noise ratio in dB
- **Spotter location** - RBN receiver grid or location

**Data source:** Vail ReRBN API
**Time window:** Limited to spots from the last 10 minutes

Use `RBN` to monitor your own signal propagation, or `RBN <callsign>` to check if another station is being heard.

### POTA Spots

Active {{< term "POTA" >}} park activators reported by hunters. Each spot includes:

- **Callsign** - Activator's call
- **Park reference** - e.g., K-4566
- **Park name** - Full park name
- **Frequency** - Operating frequency
- **Mode** - SSB, CW, FT8, etc.
- **Time spotted** - When the spot was posted
- **Comments** - Optional hunter feedback (e.g., "QRT", "Loud signal")

**Data source:** POTA API

Use the `POTA` command to open the dedicated POTA spots panel with band and mode filtering.

### SOTA Spots

{{< term "SOTA" >}} (Summits on the Air) spots show activators operating from mountain summits:

- **Callsign** - Summit activator's call
- **Summit reference** - e.g., W7W/KG-001
- **Summit name** - Full summit name
- **Frequency and mode**
- **Points** - Summit point value (1-10 based on altitude)
- **Altitude** - Summit elevation

**Data source:** SOTAwatch API

SOTA spots integrate into the merged spot list alongside POTA and RBN data. The summit reference appears as a badge on the spot row.

**Tap a SOTA spot** to auto-fill the Logger with the activator's callsign, frequency, and notes (`<summit-ref> - <summit-name> - <N>pts`). In an active FT8 session, the tap routes to the FT8 call-station flow if a recent decode of that callsign exists.

### WWFF Spots

{{< term "WWFF" >}} (World Wide Flora & Fauna) spots show activators operating from nature reserves:

- **Callsign** - Activator's call
- **WWFF reference** - e.g., KFF-1234
- **Reserve name** - Full reserve name
- **Frequency and mode**
- **Progress** - QSO count toward the 44-QSO activation requirement (if reported)

**Data source:** WWFF spotting network

### DX Cluster Sources (Optional)

Four additional spot sources are available, all off by default. Enable them from the source toggles in the Hunt spot filter sheet:

- **DX Summit** - Human-posted DX spots from dxsummit.fi
- **DXHeat** - DX cluster spots from dxheat.com
- **DXWatch** - DX cluster spots from dxwatch.com
- **Telnet DX cluster** - Live spots from a DX cluster node of your choice. The node (host and port) is configured in **Settings → Features → Hunt & P2P**, with common presets available (W3LPL is the default).

### Merged Spots

The main spot list merges {{< term "POTA" >}}, {{< term "SOTA" >}}, {{< term "WWFF" >}}, {{< term "RBN" >}}, and any enabled DX cluster sources into a unified view sorted by band:

- **Human spots first** - POTA/SOTA/WWFF spots (manually posted by hunters) appear before RBN spots
- **Deduplication** - When the same callsign appears on the same band in multiple sources, spots are combined with the human-posted source as preferred
- **Band grouping** - Spots organized by band for easy scanning

This merged view gives you human-confirmed activity alongside automated detection (RBN) in one place.

### Park-to-Park (P2P)

When you're conducting a {{< term "POTA" >}} activation, the `P2P` command shows potential park-to-park opportunities by cross-referencing:

- **POTA spots** - Other active park activators
- **RBN data** - Signal detections from skimmers within 500km of your {{< term "grid square" >}}

Each P2P entry displays:

- **SNR** - Signal strength from nearby RBN receivers
- **Frequency** - Operating frequency
- **Park information** - Park reference and name
- **Age** - Time since spot posted

**Tap a P2P spot** to auto-fill the Logger with callsign, frequency, and park-to-park notes.

## Spot Contact Validator

The spot contact validator provides near-miss alerts when you log a QSO that closely matches (but doesn't exactly match) an active spot:

- **Frequency mismatch** - You logged a QSO near a spotted frequency but not exactly on it
- **Callsign similarity** - You logged a callsign similar to a spotted station (possible typo)
- **Time proximity** - A spot appeared shortly after you logged a QSO on the same band

When a near-miss is detected, a subtle alert appears suggesting you verify the contact details. This helps catch logging errors before they're uploaded to services.

## Spot Comments Display

Spot comments from hunters are displayed inline on spot rows:

- **Latest comment** visible directly on the spot row
- **Comment count badge** showing total comments
- **Tap to expand** to see all comments in chronological order
- **RBN comments** (automated) are collapsed separately from human comments

## Spot Visual Indicators

### Age Color Coding

Spots are color-coded by age to help you prioritize fresh activity:

- **Green** - Less than 2 minutes old (very fresh)
- **Blue** - 2-10 minutes old
- **Orange** - 10-30 minutes old
- **Gray** - Older than 30 minutes

### Badges

Spots may display badges indicating special conditions:

- **SELF** - The spotted activator matches your own callsign
- **DUPE** - You've already worked this station on the same band and date
- **TODAY** - Worked today on a different band
- **PREV** - Worked in a previous session
- **FRIEND** - Station is in your friends list
- **SKCC** - Station is an SKCC member (shows member number and award level)

### SKCC Enrichment

Spots from SKCC (Straight Key Century Club) members display an orange pill showing their member number and award level:

- **Centurion (C)** — Worked 100 members
- **Tribune (T)** — Worked all US states + provinces with SKCC members
- **Tribune ×N (TxN)** — Multiple Tribune endorsements
- **Senator (S)** — Highest SKCC award

The SKCC roster is downloaded once per day and cached locally. Both Carrier Wave (iOS) and CW Sweep (macOS) share this data.

These indicators help you avoid duplicate contacts and identify new {{< term "multiplier" >}} opportunities.

### Worked-Before Cache

Carrier Wave maintains an in-memory cache of recently worked callsigns to provide instant DUPE/TODAY/PREV badge rendering without database queries. The cache is rebuilt when the app launches and updated as you log QSOs.

## Filtering

The spot filtering system lets you narrow results by multiple criteria. Filters for **HUNT** (POTA/SOTA spots) and **P2P** (park-to-park) are **persistent** — your selections are saved in Settings and applied automatically each time you open the spot panel.

### Active Filter Indicators

When filters are active, the HUNT and P2P command icons appear **filled** instead of outlined, and a descriptive summary (e.g., "20m, CW, POTA only") appears below the command bar. This gives you instant visual confirmation that filtering is in effect.

### Source Filter

- **POTA** - Show only POTA spots
- **SOTA** - Show only SOTA spots
- **WWFF** - Show only WWFF spots
- **RBN** - Show only RBN spots
- **All** - Merged view (default)

### Activity Filter (HUNT)

Filter hunt spots by activity program:

- **POTA** - Show only POTA activators
- **SOTA** - Show only SOTA activators
- **All** - Show all activity types (default)

### Band Filter

Multi-select band filter supporting:

- All HF bands (160m through 10m)
- VHF/UHF bands (6m, 2m, 70cm)
- Select multiple bands to monitor several at once

### Mode Filter

Multi-select mode filter including:

- {{< term "CW" >}}
- {{< term "SSB" >}} (Phone)
- {{< term "FT8" >}}
- {{< term "FT4" >}}
- Other digital modes

### Club Filter (HUNT)

Filter hunt spots by club membership. Select one or more clubs to show only spots from members of those clubs. Requires club roster data to be loaded.

### Friends Filter (HUNT)

Toggle to show only spots from stations in your friends list.

### Age Filter

Set maximum spot age from 5 to 30 minutes. Default is 12 minutes or less. Older spots are hidden to focus on current activity.

### Proximity Filter

**"Heard Nearby" toggle** with configurable radius (100-2000 miles):

- Shows only stations detected by {{< term "RBN" >}} receivers within your specified distance
- Helps assess short-skip propagation and regional activity
- Distance calculated from your {{< term "grid square" >}} (set in Settings)

### Region-Based Aggregation

Spots can be aggregated by geographic region to reduce clutter on busy bands:

- **Region grouping** collapses multiple RBN spots from the same geographic area into a single row
- **Expand** to see individual spots within a region
- **Region labels** (NE, SE, MW, SW, NW for US; EU, AS, OC, AF, SA for international)

### Sort Order

- **Recent** - Newest spots first (default)
- **Frequency** - Low to high frequency

### Hide Already Worked

Toggle to suppress spots with DUPE, TODAY, or PREV badges.

### Active Filter Badges

The spot panel header displays active filter badges (e.g., "20m, CW, <12 min") for quick reference to your current filters.

## Spot Map

A mini-map at the top of the spot panel shows:

- **Spotter locations** - RBN receiver positions
- **Signal paths** - Arcs from spotter to target station
- **Signal strength indicators** - RBN spotter circles sized by {{< term "SNR" >}} (larger = stronger signal)
- **Geographic context** - Your location and spotted station location

Spotter positions are resolved via HamDB {{< term "grid square" >}} lookups.

## P2P Discovery via RBN

Beyond the `P2P` command, Carrier Wave passively discovers park-to-park opportunities using RBN data:

- **Background scanning** of RBN spots for callsigns matching active POTA activators
- **Cross-reference** with POTA spot data to confirm park-to-park eligibility
- **Toast notification** when a P2P opportunity is detected on your current band
- **Tap the toast** to auto-fill the Logger with the P2P contact details

This passive discovery ensures you don't miss P2P opportunities even when you're not actively checking the spot panel.

## Background Spot Monitoring

During active logging sessions, Carrier Wave automatically monitors spots in the background:

### Automatic Polling

- **Interval:** Every 45 seconds
- **Active during:** Any open logging session
- **POTA filtering:** POTA spots included only during POTA activations

### Compact Summary Banner

When spots are detected in the background, a compact banner appears showing:

- **Spot count** - Total new spots
- **Region breakdown** - Spot counts by region (NE, EU, NA, etc.)
- **Distance range** - Minimum to maximum distance in miles/km

**Tap the banner** to expand and see individual spots.

### Persisted Spots

{{< term "RBN" >}} and {{< term "POTA" >}} spots detected during your session are saved and displayed in an expandable **Recorded Spots** section in the session detail view.

The recorded spots use the same aggregation as the live Logger spot view:

- **Human spots first** -- POTA spots appear before RBN spots
- **Deduplication** -- Same callsign + band merged, with POTA as the preferred source
- **Band grouping** -- Spots organized by band
- **RBN region collapsing** -- Consecutive RBN spots grouped by region
- **Age color coding and badges** -- SELF, DUPE, TODAY, PREV indicators preserved from capture time

Tap the section header to expand or collapse the list. This provides a historical record of propagation during your activation -- review which receivers heard you, on which bands, and at what signal strength.

See [POTA Activation Detail -- Recorded Spots](/reference/pota/#recorded-spots) for full details.

## Solar & Weather Conditions

### Solar Conditions (SOLAR Command)

The solar panel displays:

- **K-index** - Geomagnetic activity (0-9, lower is better)
- **SFI (Solar Flux Index)** - 10.7cm solar flux (higher is better for HF)
- **A-index** - Daily geomagnetic activity (lower is better)
- **Band conditions** - Per-band propagation forecast (day/night) showing Good/Fair/Poor ratings

**Data source:** HamQSL.com and NOAA

### Weather Conditions (WEATHER Command)

Weather panel with NOAA data including:

- **Temperature, humidity, wind**
- **Outdoor advisory** - Weather suitability for outdoor operations
- **Antenna advisory** - Wind/ice warnings for antenna safety
- **Equipment advisory** - Temperature/humidity warnings for gear

### Conditions Recording

- Solar and weather conditions are automatically recorded at session start
- Optional hourly background polling fills conditions history (enable in Settings)
- Historical conditions help correlate QSO success with propagation

## Frequency Activity

The spot system monitors nearby frequency activity from {{< term "RBN" >}} data:

### QRM Assessment

- Detects activity within +/-2kHz of your frequency
- Shows how busy the frequency is
- Helps decide if it's worth calling on a crowded frequency

### Frequency Warning Banner

A unified warning banner appears when:

- License class prohibits operation on your current frequency
- Significant {{< term "QRM" >}} detected nearby

## Data Sources

| Data | Source |
|------|--------|
| RBN spots | Vail ReRBN API |
| POTA spots | POTA API |
| SOTA spots | SOTAwatch API |
| WWFF spots | WWFF spotting network |
| Solar data | NOAA / HamQSL |
| Spotter locations | HamDB.org |

## See Also

- [Logger](/reference/logger/) - Log contacts from spot data
- [POTA Activations](/reference/pota/) - POTA-specific activation features
- [Activity Programs](/reference/activations/) - SOTA, WWFF, and other programs
- [Smart Spot Needs](/reference/smart-needs/) - Need-based spot matching and alerts
- [Activity Log](/reference/activity-log/) - Review worked stations and hunter spots
- [WebSDR Integration](/reference/websdr/) - Remote receiver integration for propagation assessment
