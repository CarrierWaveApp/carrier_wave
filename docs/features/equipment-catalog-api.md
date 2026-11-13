# Equipment Catalog API Spec

Server-side API for the shared equipment catalog used by the recommendation engine.

## Overview

The activities server hosts a community-maintained catalog of amateur radio equipment (radios, antennas, keys, microphones, accessories). The iOS app fetches and caches this catalog for:
- Structured equipment inventory (replacing string-based `EquipmentStorage`)
- Fuzzy matching user-entered gear names ("did you mean…")
- Recommendation engine scoring (band coverage, modes, portability)

## Endpoints

### `GET /api/equipment/catalog`

Returns the full equipment catalog. Cached aggressively on the client (24h TTL + ETag).

**Response:**

```json
{
  "version": 3,
  "updated_at": "2026-03-28T12:00:00Z",
  "entries": [
    {
      "id": "lnr-mtr-4b",
      "name": "Mountain Topper MTR-4B",
      "manufacturer": "LNR Precision",
      "category": "radio",
      "bands": ["40m", "30m", "20m", "15m"],
      "modes": ["CW"],
      "max_power_watts": 3,
      "portability": "pocket",
      "weight_grams": 340,
      "description": "4-band QRP CW transceiver",
      "aliases": ["mtr4b", "mtr-4b", "mountain topper 4b", "mtr 4bv2"],
      "image_url": "https://activities.example.com/equipment/lnr-mtr-4b.jpg"
    },
    {
      "id": "elecraft-kx2",
      "name": "KX2",
      "manufacturer": "Elecraft",
      "category": "radio",
      "bands": ["80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m"],
      "modes": ["CW", "SSB", "DIGITAL"],
      "max_power_watts": 10,
      "portability": "backpack",
      "weight_grams": 370,
      "description": "All-band QRP transceiver with ATU",
      "aliases": ["kx-2", "kx 2"],
      "image_url": null
    }
  ]
}
```

**Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique slug (lowercase, hyphenated) |
| `name` | string | yes | Display name |
| `manufacturer` | string | yes | Manufacturer name |
| `category` | enum | yes | `radio`, `antenna`, `key`, `microphone`, `accessory` |
| `bands` | [string] | no | Bands covered (e.g., `["40m", "20m"]`). Empty = all bands. |
| `modes` | [string] | no | Modes supported: `CW`, `SSB`, `AM`, `FM`, `FT8`, `FT4`, `DIGITAL`. Empty = inherits from radio. |
| `max_power_watts` | int | no | Max power output (radios only) |
| `portability` | enum | no | `pocket`, `backpack`, `portable`, `mobile`, `base`. Default: `portable`. |
| `weight_grams` | int | no | Weight in grams |
| `description` | string | no | Short description |
| `aliases` | [string] | no | Common misspellings and abbreviations for fuzzy matching |
| `image_url` | string | no | Product image URL |

### `GET /api/equipment/catalog?since={timestamp}`

Delta fetch — returns only entries added or updated since the given timestamp. Same response shape but `entries` only contains changed items.

### `GET /api/equipment/search?q={query}&category={category}`

Server-side fuzzy search for when the client doesn't have the full catalog cached.

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `q` | string | Search query (e.g., "mtr4b") |
| `category` | string | Optional category filter |
| `limit` | int | Max results (default 5, max 20) |

**Response:**

```json
{
  "results": [
    {
      "entry": { /* CatalogEntry */ },
      "confidence": 0.92,
      "matched_field": "alias"
    }
  ]
}
```

## Client Integration

### iOS (`CarrierWaveData`)

The existing `CatalogEntry` model maps directly to the API response. Decoding uses `convertFromSnakeCase`.

**Cache strategy:**
- Full catalog fetched on first launch and stored in app container
- Delta sync via `since` parameter on subsequent launches
- 24h TTL with ETag-based conditional requests
- Fallback to cached catalog when offline

**Fuzzy matching:**
- Primary: local `CatalogMatcher` against cached catalog (instant, offline)
- Fallback: server search endpoint when catalog is stale or query has no local match

### Migration

On first launch after update:
1. Fetch full catalog from server
2. Run `EquipmentMigration.migrate(catalog:container:)` to convert legacy string lists
3. Present unmatched items to user for manual resolution ("Did you mean…")
4. Mark migration complete

## Rust Server Implementation Notes

### Data Model

```rust
#[derive(Serialize, Deserialize)]
struct EquipmentEntry {
    id: String,           // primary key, slug format
    name: String,
    manufacturer: String,
    category: EquipmentCategory,
    bands: Vec<String>,
    modes: Vec<String>,
    max_power_watts: Option<i32>,
    portability: Portability,
    weight_grams: Option<i32>,
    description: Option<String>,
    aliases: Vec<String>,
    image_url: Option<String>,
    updated_at: DateTime<Utc>,
}
```

### Seed Data Priority

Start with equipment commonly used in POTA/portable operations:

**Radios:** Elecraft KX2/KX3/K4, Icom IC-705/IC-7300, Yaesu FT-891/FT-818/FT-991A, LNR MTR-3B/4B/5B, QRP Labs QMX/QDX, Xiegu G90/X6100, Lab599 TX-500

**Antennas:** EFHW (various), Spooltenna, Chameleon MPAS 2.0, Buddipole, Linked dipole, Sotabeams, PackTenna, Wolf River Coils, Super Antenna

**Keys:** CW Morse TP-III/TP-I, Begali, Vibroplex, N0SA, Palm paddles, American Morse Equipment

**Microphones:** Heil Sound (various), stock mics per radio model

### Search Implementation

Use trigram similarity (`pg_trgm`) for fuzzy matching:

```sql
SELECT *, similarity(name || ' ' || array_to_string(aliases, ' '), $1) as score
FROM equipment_catalog
WHERE similarity(name || ' ' || array_to_string(aliases, ' '), $1) > 0.3
ORDER BY score DESC
LIMIT $2;
```

## Future Considerations

- **User contributions:** Allow users to submit new equipment entries for review
- **Equipment reviews/ratings:** Community feedback on gear for different use cases
- **Compatibility data:** "This antenna works well with this radio" based on community usage
- **Discontinued tracking:** Mark items as discontinued but keep for existing owners
