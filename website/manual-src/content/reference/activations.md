---
title: "Activity Programs"
description: "POTA, SOTA, WWFF, and Activator of the Americas support"
weight: 8
showToc: true
---

Carrier Wave supports multiple amateur radio activity programs beyond POTA. This page covers the program registry, cross-program features, and program-specific details for SOTA, WWFF, and Activator of the Americas (AoA).

For POTA-specific features (activation logging, upload workflow, rove mode), see the dedicated [POTA Activations](/reference/pota/) page.

## Program Registry

Carrier Wave maintains a registry of supported activity programs with standardized handling:

| Program | ADIF Field | Reference Format | Example |
|---------|-----------|-----------------|---------|
| POTA | `SIG_INFO` / `MY_SIG_INFO` | `XX-NNNN` | US-1234 |
| SOTA | `SOTA_REF` / `MY_SOTA_REF` | `AA/BB-NNN` | W7W/KG-001 |
| WWFF | `WWFF_REF` / `MY_WWFF_REF` | `XFF-NNNN` | KFF-1234 |
| AoA | `COMMENT` | Code exchange | AoA-2025-0042 |

### ADIF Field Mapping

Each program maps to specific ADIF fields for export and sync:

- **Your reference** (activator) uses the `MY_` prefixed field
- **Their reference** (hunter) uses the unprefixed field
- Programs with no dedicated ADIF field use `COMMENT` or `APP_` fields

### Cross-Reference Matching

When you log a QSO with a station spotted on multiple programs (e.g., a POTA park that overlaps a WWFF reserve), Carrier Wave:

- Detects the overlap from reference databases
- Prompts you to log both references
- Populates both ADIF fields in the exported record

## SOTA (Summits on the Air)

SOTA encourages portable operation from mountain summits. Carrier Wave provides summit lookup, session support, and spot integration.

### Summit Lookup

Search for SOTA summits by:

- **Reference** (e.g., W7W/KG-001)
- **Name** (e.g., "Tiger Mountain")
- **Nearby** - GPS-based proximity search

Each summit result shows:

- **Reference** and full name
- **Altitude** (in feet or meters based on your units preference)
- **Points** (1-10 based on altitude: 1 point below 500m, up to 10 points above 2000m)
- **Region** and association
- **Activation count** - How many times this summit has been activated
- **Your history** - Whether you've activated or worked this summit

### SOTA Session Setup

When starting a SOTA activation session:

1. Set **Activation Type** to SOTA in the session wizard
2. Search and select your summit reference
3. The summit reference, altitude, and points are recorded with the session

### SOTA-Specific Fields

QSOs logged during a SOTA session automatically include:

- `MY_SOTA_REF` - Your summit reference
- Altitude metadata for the session

When you work another SOTA activator (S2S — summit-to-summit), enter their summit reference in the inline **Summit** field that appears in the Logger expanded fields row during a SOTA session:

- `SOTA_REF` - Their summit reference

Dual POTA + SOTA sessions show both fields: Park appears beneath the primary row (auto-enriched from spot lookup) and Summit takes the primary placement next to Grid.

### Activation Threshold

A valid SOTA activation requires **4 QSOs** from the summit (compared to POTA's 10). The Logger session-header chip and the watch's activation progress ring both track to this 4-QSO threshold; dual POTA + SOTA sessions use the lower of the two program targets.

### Self-Spotting

Tap **SPOT** during a SOTA session to send a self-spot to SOTAwatch (`api2.sota.org.uk/api/spots`). Dual POTA + SOTA sessions fan out: every POTA park reference is spotted to the POTA network *and* the SOTA reference is spotted to SOTAwatch in one tap. **SPOT REPEAT** and post-QSY auto-spotting use the same dispatcher.

### Session Grid from Summit

A SOTA session's `MY_GRIDSQUARE` is pinned to the summit's surveyed coordinates rather than your phone's GPS. This is reliable even with a cold GPS fix at the trailhead or with the phone in a backpack at the summit. Honours your grid precision preference (4 / 6 / 8 character).

### Brag Sheet and ADIF Export

SOTA-only session details include both **Brag Sheet** (program-neutral activation share card showing the summit reference, name, callsign, QSO count, and date) and **Export ADIF** actions. ADIF exports include `MY_SOTA_REF` for SOTA sessions, both `MY_SOTA_REF` and `MY_POTA_REF` (with `MY_SIG`/`MY_SIG_INFO`) for dual sessions, and S2S/P2P tags from each QSO's own references.

### Spots Integration

SOTA spots from SOTAwatch appear in the merged spot list alongside POTA and RBN data. See [Spot Monitoring](/reference/spots/) for details.

## WWFF (World Wide Flora & Fauna)

WWFF promotes operation from nature reserves and protected areas worldwide.

### WWFF References

WWFF references follow the format `XFF-NNNN` where `X` is the country prefix:

- **KFF** - United States
- **VFF** - Canada
- **GFF** - England
- And so on for each DXCC entity

### 44-QSO Progress Tracking

WWFF requires **44 QSOs** for a valid activation (compared to POTA's 10). Carrier Wave tracks your progress:

- **Progress bar** in the session header showing QSOs toward 44
- **Milestone notifications** at 22 (halfway) and 44 (activation complete)
- **Warning** when ending a session with fewer than 44 QSOs

### Award Tiers

WWFF has a tiered award system. Carrier Wave tracks your progress:

| Award | Requirement |
|-------|-------------|
| **WWFF Hunter** | Work 44 unique WWFF references |
| **WWFF Activator** | Activate 44 unique WWFF references |
| **Sapphire** | Higher thresholds (varies by national program) |

### National Representatives

WWFF is organized by national programs, each with their own coordinator. Carrier Wave's reference database includes all national program references.

### WWFF Session Setup

1. Set **Activation Type** to WWFF in the session wizard
2. Search and select your WWFF reference
3. The reference is recorded with the session and exported in the `MY_WWFF_REF` ADIF field

## Activator of the Americas (AoA)

AoA is a program where participants exchange unique codes during contacts.

### Code Exchange

During an AoA QSO:

1. Both stations exchange their AoA code
2. Enter the received code in the AoA field
3. The code is saved with the QSO

### AoA Codes in Quick Entry

AoA codes can be entered in quick entry mode. The parser recognizes AoA code format and assigns it to the appropriate field.

### Session Support

When operating AoA, set the activation type appropriately. AoA references are stored in the QSO comment field and exported with ADIF.

## Multi-Program Operations

You can activate multiple programs simultaneously when your location qualifies:

- **POTA + WWFF** - Many POTA parks overlap WWFF reserves
- **POTA + SOTA** - Some summits are within POTA park boundaries
- **Triple activation** - Rare locations qualify for all three programs

Carrier Wave handles multi-program sessions by:

- Tracking references for each program independently
- Populating all relevant ADIF fields on each QSO
- Generating separate upload files for each program's requirements

## See Also

- [POTA Activations](/reference/pota/) - Detailed POTA features
- [Spot Monitoring](/reference/spots/) - SOTA and WWFF spots
- [Map View](/reference/map/) - Summit pins and park boundaries
- [Export & Sharing](/reference/export/) - ADIF export with program references
- [Logger](/reference/logger/) - Session start and QSO entry
