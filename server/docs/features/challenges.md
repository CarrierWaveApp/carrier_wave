# Challenges

## Overview

Challenges track progress toward ham radio goals. Three types exist, each with different progress models.

## Challenge Types

### Collection

Track progress toward completing a defined set of items.

**Examples:**
- Worked All States (50 states)
- DXCC (100+ entities)
- Worked All Continents (6 continents)

**Progress model:** X of Y completed

**Configuration:**

```json
{
  "goals": {
    "type": "collection",
    "items": [
      { "id": "US-CA", "name": "California", "category": "state" },
      { "id": "US-NY", "name": "New York", "category": "state" }
    ]
  }
}
```

### Cumulative

Track progress toward a numeric goal.

**Examples:**
- POTA Hunter: 1000 park contacts
- QSO count milestones

**Progress model:** Current value / target

**Configuration:**

```json
{
  "goals": {
    "type": "cumulative",
    "targetValue": 1000,
    "unit": "contacts",
    "calculationRule": "count"
  }
}
```

### Time-Bounded

Challenges with defined start/end dates.

**Examples:**
- 13 Colonies (July 1-7)
- Club sprint: Most CW contacts this month

**Configuration:**

```json
{
  "timeConstraints": {
    "type": "calendar",
    "startDate": "2025-01-01T00:00:00Z",
    "endDate": "2025-01-31T23:59:59Z",
    "timezone": "UTC"
  }
}
```

Can also use relative timing (N days from join).

## Tiers

Any challenge type can have tiers representing milestones.

```json
{
  "tiers": [
    { "id": "tier-25", "name": "25 States", "threshold": 25, "order": 1 },
    { "id": "tier-50", "name": "WAS", "threshold": 50, "order": 2 }
  ]
}
```

Tiers have associated badges awarded when threshold is reached.

## Qualification Criteria

QSOs qualify based on configurable rules:

| Criterion | Description | Example |
|-----------|-------------|---------|
| `bands` | Restrict to bands | `["40m", "20m"]` or null for any |
| `modes` | Restrict to modes | `["CW"]` or null for any |
| `requiredFields` | Require QSO fields | Park reference, grid square |
| `dateRange` | QSO date window | January 1-31, 2025 |
| `matchRules` | How QSO fields map to goals | state → goal ID |

**Example criteria:**

```json
{
  "qualificationCriteria": {
    "bands": ["40m", "20m"],
    "modes": ["CW", "SSB"],
    "requiredFields": [
      { "field": "parkReference", "requirement": "present" }
    ],
    "dateRange": {
      "start": "2025-01-01T00:00:00Z",
      "end": "2025-12-31T23:59:59Z"
    },
    "matchRules": [
      {
        "qsoField": "state",
        "goalField": "id",
        "transformation": "uppercase"
      }
    ]
  }
}
```

### Match Rules

Match rules define how a QSO's fields map to challenge goals:

- `qsoField`: Field in QSO (state, dxccEntity, parkReference, grid, etc.)
- `goalField`: Field in goal item to match against (usually `id`)
- `transformation`: Optional transform (none, uppercase, lowercase)

## Historical QSOs

Challenges can allow or forbid historical QSOs (logged before joining):

```json
{
  "historicalQsosAllowed": true
}
```

When false, only QSOs logged after join date count.

## Scoring

### Methods

| Method | Description |
|--------|-------------|
| `percentage` | (completed / total) * 100 |
| `count` | Raw count of completed items or value |
| `points` | Weighted scoring based on rules |

### Configuration

```json
{
  "scoring": {
    "method": "count",
    "tiebreaker": "earliestCompletion",
    "displayFormat": "{value}/50 states"
  }
}
```

### Tiebreakers

When scores are equal:
- `earliestCompletion`: First to reach score wins
- `mostRecent`: Most recent progress wins
- `alphabetical`: Callsign alphabetical order

## Categories

| Category | Description |
|----------|-------------|
| `award` | Official awards (DXCC, WAS, WAC) |
| `event` | Special events (13 Colonies, Field Day) |
| `club` | Club-specific challenges |
| `personal` | Individual goals |
| `other` | Everything else |

## Lifecycle

1. **Active**: Accepting joins and progress
2. **Ended**: Time-bounded challenge past end date
3. **Inactive**: Disabled by admin

When a time-bounded challenge ends:
1. No new progress accepted
2. Snapshot created with final standings
3. Badges awarded based on final state

## Client Evaluation

The iOS app evaluates QSOs locally against challenge criteria, then reports summary progress to the server. The server:

1. Validates callsign owns the device token
2. Stores progress
3. Calculates score and rank
4. Awards badges if tier thresholds crossed
5. Returns updated rank and any new badges
