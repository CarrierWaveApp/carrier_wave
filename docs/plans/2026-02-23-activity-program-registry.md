# Activity Program Registry

## Overview

Replace the hardcoded `ActivationType` enum (casual/pota/sota) with a server-driven activity program registry. The activities-server becomes the authoritative source for what programs exist, what their capabilities are, and how the client should handle them.

This enables supporting WWFF, LOTA, IOTA, and other on-air programs without app updates.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Carrier Wave   │────▶│  Activities     │────▶│  PostgreSQL     │
│  iOS App        │     │  Server (Axum)  │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │
        ▼                       ▼
  ActivityProgram         programs table
  (local cache)           (authoritative)
```

### Key Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Registry location | activities-server | Already has auth, clients, infrastructure |
| Authority | Server is authoritative | Single source of truth, updates without app release |
| Local cache | UserDefaults JSON + bundled fallback | Works offline, fast startup |
| Capability model | Per-program capability set | Programs range from reference-only to full integration |
| Migration | Gradual — enum stays as bridge | No SwiftData migration needed (already stores strings) |

---

## Program Model

Each program describes an on-air activity that operators can activate for:

```swift
struct ActivityProgram: Codable, Identifiable, Sendable {
    let slug: String              // "pota", "wwff", "lota", "iota"
    let name: String              // "Parks on the Air"
    let shortName: String         // "POTA"
    let icon: String              // SF Symbol name: "tree", "mountain.2"
    let website: String?          // "https://pota.app"

    // Reference format
    let referenceLabel: String    // "Park Reference", "Summit Reference"
    let referenceFormat: String?  // Regex: "^[A-Za-z]{1,4}-\\d{1,6}$"
    let referenceExample: String? // "K-1234", "W4C/CM-001"
    let multiRefAllowed: Bool     // POTA n-fer: true, SOTA: false

    // Activation rules
    let activationThreshold: Int? // 10 for POTA, nil for casual
    let supportsRove: Bool        // true for POTA, false for most

    // ADIF mapping
    let adifFields: ADIFFieldMapping?

    // Capabilities
    let capabilities: Set<ProgramCapability>

    var id: String { slug }
}
```

### Capability Tiers

Programs declare what they support. Tiers are additive:

```swift
enum ProgramCapability: String, Codable, Sendable {
    // Tier 1: Reference logging (all programs)
    case referenceField     // Has a typed reference field (park, summit, lighthouse)

    // Tier 2: Upload
    case adifUpload         // Can upload ADIF to program's API

    // Tier 3: Spots
    case browseSpots        // Can view spots for this program
    case selfSpot           // Can post self-spots

    // Tier 4: Deep integration
    case hunter             // Has a hunter/chaser workflow
    case locationLookup     // Has reference → location API (park cache)
    case progressTracking   // Track activation progress (X/10)
}
```

### ADIF Field Mapping

How the program's reference maps to ADIF fields during export/upload:

```swift
struct ADIFFieldMapping: Codable, Sendable {
    let mySig: String?         // "POTA", "WWFF", "SOTA"
    let mySigInfo: String?     // Which field holds the ref value
    let sigField: String?      // "SIG", custom field name
    let sigInfoField: String?  // "SIG_INFO", custom field name
}
```

---

## Server API

### Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/v1/programs` | None | List all activity programs |
| `GET` | `/v1/programs/{slug}` | None | Get single program definition |

### Database Schema

```sql
CREATE TABLE programs (
    slug            TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    short_name      TEXT NOT NULL,
    icon            TEXT NOT NULL,
    website         TEXT,
    reference_label TEXT NOT NULL,
    reference_format TEXT,
    reference_example TEXT,
    multi_ref_allowed BOOLEAN NOT NULL DEFAULT false,
    activation_threshold INT,
    supports_rove   BOOLEAN NOT NULL DEFAULT false,
    capabilities    TEXT[] NOT NULL DEFAULT '{}',
    adif_my_sig     TEXT,
    adif_my_sig_info TEXT,
    adif_sig_field  TEXT,
    adif_sig_info_field TEXT,
    sort_order      INT NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed built-in programs
INSERT INTO programs (slug, name, short_name, icon, reference_label, reference_format,
    reference_example, multi_ref_allowed, activation_threshold, supports_rove,
    capabilities, adif_my_sig, sort_order) VALUES
('casual', 'Casual', 'Casual', 'radio', 'Reference', NULL, NULL,
    false, NULL, false, '{}', NULL, 0),
('pota', 'Parks on the Air', 'POTA', 'tree', 'Park Reference',
    '^[A-Za-z]{1,4}-\d{1,6}$', 'K-1234', true, 10, true,
    '{referenceField,adifUpload,browseSpots,selfSpot,hunter,locationLookup,progressTracking}',
    'POTA', 1),
('sota', 'Summits on the Air', 'SOTA', 'mountain.2', 'Summit Reference',
    '^[A-Z0-9]{1,4}/[A-Z]{2}-\d{3}$', 'W4C/CM-001', false, 4, false,
    '{referenceField,adifUpload}', 'SOTA', 2),
('wwff', 'World Wide Flora & Fauna', 'WWFF', 'leaf', 'WWFF Reference',
    '^[A-Z]{1,4}FF-\d{4}$', 'KFF-1234', true, 44, false,
    '{referenceField,adifUpload}', 'WWFF', 3),
('iota', 'Islands on the Air', 'IOTA', 'water.waves', 'IOTA Reference',
    '^[A-Z]{2}-\d{3}$', 'EU-005', false, NULL, false,
    '{referenceField}', 'IOTA', 4),
('lota', 'Lighthouses on the Air', 'LOTA', 'light.beacon.max', 'Lighthouse Reference',
    NULL, 'US0001', false, NULL, false,
    '{referenceField}', 'LOTA', 5);
```

### Response Format

```json
GET /v1/programs

{
  "data": {
    "programs": [
      {
        "slug": "pota",
        "name": "Parks on the Air",
        "shortName": "POTA",
        "icon": "tree",
        "website": "https://pota.app",
        "referenceLabel": "Park Reference",
        "referenceFormat": "^[A-Za-z]{1,4}-\\d{1,6}$",
        "referenceExample": "K-1234",
        "multiRefAllowed": true,
        "activationThreshold": 10,
        "supportsRove": true,
        "capabilities": ["referenceField", "adifUpload", "browseSpots", "selfSpot", "hunter", "locationLookup", "progressTracking"],
        "adifFields": {
          "mySig": "POTA",
          "mySigInfo": "ref"
        }
      }
    ],
    "version": 1
  }
}
```

The `version` field lets the client know when the registry has changed, enabling efficient cache invalidation with `If-None-Match` / ETags.

---

## iOS Client Implementation

### Phase 1: Model + API + Cache (this PR)

Add the client-side data model and API endpoint. No behavior changes yet.

**New files:**
- `CarrierWave/Models/ActivityProgram.swift` — `ActivityProgram`, `ProgramCapability`, `ADIFFieldMapping`
- `CarrierWave/Services/ActivitiesClient+Programs.swift` — `fetchPrograms()` endpoint
- `CarrierWave/Services/ActivityProgramStore.swift` — Local cache with bundled fallback

**Behavior:**
- On app launch, `ActivityProgramStore` loads from UserDefaults cache
- Periodically fetches fresh list from server (daily or on version change)
- Bundled JSON fallback for offline-first startup
- `ActivationType` enum remains as bridge — `ActivityProgram.slug` maps to `ActivationType.rawValue`

### Phase 2: UI driven by registry

- Session start sheet renders activation type picker from `ActivityProgramStore.programs`
- Reference field label/placeholder/validation driven by program config
- New programs appear automatically after server-side addition
- `ActivationType` enum becomes a thin wrapper or is removed entirely

### Phase 3: Abstract upload

- Generic ADIF upload service reads endpoint config from program definition
- `ServiceType` extended for new programs
- Upload UI generalized

### Phase 4: Abstract spots

- Generic spots browsing for programs with `browseSpots` capability
- Self-spotting for programs with `selfSpot` capability
- POTA-specific deep integration (rove, P2P, spot comments) stays hardcoded

---

## Bridge Strategy

`LoggingSession.activationTypeRawValue` already stores a `String`. The bridge is straightforward:

```swift
// Current: enum-based
var activationType: ActivationType {
    get { ActivationType(rawValue: activationTypeRawValue) ?? .casual }
}

// Future: program-based
var programSlug: String {
    get { activationTypeRawValue }
    set { activationTypeRawValue = newValue }
}

var program: ActivityProgram? {
    ActivityProgramStore.shared.program(for: programSlug)
}
```

No SwiftData migration is needed because the stored value is already the slug string.

---

## What Stays Hardcoded

POTA has ~40 files of deeply integrated behavior:
- Auto-spotting timers, QSY spot prompts
- Spot comments polling and attachment
- Rove mode (park stop transitions, QRT spots)
- Park cache and two-fer dedup
- Job tracking and upload reconciliation
- P2P discovery

These remain POTA-specific code paths keyed on `slug == "pota"`. The registry doesn't try to abstract them — it just provides the data model that makes adding simpler programs trivial.
