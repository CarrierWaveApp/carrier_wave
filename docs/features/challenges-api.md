# Challenges API Reference

## Overview

This document specifies the API for challenge distribution and participation. Both the official Carrier Wave challenge server and community servers should implement this API.

**Base URL**: `https://challenges.fullduplex.app/v1` (official) or custom (community)

**Content-Type**: `application/json`

**Authentication**: Bearer token for write operations, public read for challenge definitions

---

## Challenge Definition Schema

The core JSON schema for challenge definitions.

### Full Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["id", "version", "metadata", "type", "configuration"],
  "properties": {
    "id": {
      "type": "string",
      "format": "uuid",
      "description": "Unique identifier for this challenge"
    },
    "version": {
      "type": "integer",
      "minimum": 1,
      "description": "Schema version, increment on updates"
    },
    "metadata": { "$ref": "#/$defs/Metadata" },
    "type": {
      "type": "string",
      "enum": ["collection", "cumulative", "timeBounded"],
      "description": "Challenge type"
    },
    "configuration": { "$ref": "#/$defs/Configuration" },
    "inviteConfig": { "$ref": "#/$defs/InviteConfig" },
    "badges": {
      "type": "array",
      "items": { "$ref": "#/$defs/Badge" }
    },
    "hamalertConfig": { "$ref": "#/$defs/HamAlertConfig" }
  },
  "$defs": {
    "Metadata": {
      "type": "object",
      "required": ["name", "description", "author"],
      "properties": {
        "name": { "type": "string", "maxLength": 100 },
        "description": { "type": "string", "maxLength": 2000 },
        "author": { "type": "string" },
        "authorCallsign": { "type": "string" },
        "createdAt": { "type": "string", "format": "date-time" },
        "updatedAt": { "type": "string", "format": "date-time" },
        "tags": {
          "type": "array",
          "items": { "type": "string" }
        },
        "category": {
          "type": "string",
          "enum": ["award", "event", "club", "personal", "other"]
        }
      }
    },
    "Configuration": {
      "type": "object",
      "required": ["goals", "qualificationCriteria", "scoring"],
      "properties": {
        "goals": { "$ref": "#/$defs/Goals" },
        "tiers": {
          "type": "array",
          "items": { "$ref": "#/$defs/Tier" }
        },
        "qualificationCriteria": { "$ref": "#/$defs/Criteria" },
        "scoring": { "$ref": "#/$defs/ScoringConfig" },
        "timeConstraints": { "$ref": "#/$defs/TimeConstraints" },
        "historicalQSOsAllowed": {
          "type": "boolean",
          "default": true
        }
      }
    },
    "Goals": {
      "oneOf": [
        { "$ref": "#/$defs/CollectionGoals" },
        { "$ref": "#/$defs/CumulativeGoal" }
      ]
    },
    "CollectionGoals": {
      "type": "object",
      "required": ["type", "items"],
      "properties": {
        "type": { "const": "collection" },
        "items": {
          "type": "array",
          "items": { "$ref": "#/$defs/GoalItem" }
        },
        "totalRequired": {
          "type": "integer",
          "description": "If set, only this many items needed (e.g., 100 for DXCC)"
        }
      }
    },
    "GoalItem": {
      "type": "object",
      "required": ["id", "name"],
      "properties": {
        "id": { "type": "string" },
        "name": { "type": "string" },
        "category": { "type": "string" },
        "metadata": {
          "type": "object",
          "additionalProperties": { "type": "string" }
        }
      }
    },
    "CumulativeGoal": {
      "type": "object",
      "required": ["type", "targetValue", "unit"],
      "properties": {
        "type": { "const": "cumulative" },
        "targetValue": { "type": "integer", "minimum": 1 },
        "unit": { "type": "string" },
        "calculationRule": { "$ref": "#/$defs/CalculationRule" }
      }
    },
    "CalculationRule": {
      "type": "object",
      "required": ["method"],
      "properties": {
        "method": {
          "type": "string",
          "enum": ["count", "sum", "custom"]
        },
        "field": {
          "type": "string",
          "description": "QSO field to sum (for sum method)"
        },
        "customFormula": {
          "type": "string",
          "description": "Custom calculation expression (future)"
        }
      }
    },
    "Tier": {
      "type": "object",
      "required": ["id", "name", "threshold", "order"],
      "properties": {
        "id": { "type": "string" },
        "name": { "type": "string" },
        "threshold": { "type": "integer", "minimum": 1 },
        "badgeId": { "type": "string" },
        "order": { "type": "integer" }
      }
    },
    "Criteria": {
      "type": "object",
      "properties": {
        "bands": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Allowed bands (null = any)"
        },
        "modes": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Allowed modes (null = any)"
        },
        "requiredFields": {
          "type": "array",
          "items": { "$ref": "#/$defs/FieldRequirement" }
        },
        "dateRange": { "$ref": "#/$defs/DateRange" },
        "matchRules": {
          "type": "array",
          "items": { "$ref": "#/$defs/MatchRule" }
        }
      }
    },
    "FieldRequirement": {
      "type": "object",
      "required": ["field", "requirement"],
      "properties": {
        "field": { "type": "string" },
        "requirement": {
          "type": "string",
          "enum": ["exists", "notEmpty", "matches"]
        },
        "pattern": {
          "type": "string",
          "description": "Regex pattern for 'matches' requirement"
        }
      }
    },
    "DateRange": {
      "type": "object",
      "properties": {
        "start": { "type": "string", "format": "date-time" },
        "end": { "type": "string", "format": "date-time" }
      }
    },
    "MatchRule": {
      "type": "object",
      "required": ["qsoField", "goalField"],
      "properties": {
        "qsoField": {
          "type": "string",
          "description": "Path to QSO field (e.g., 'state', 'dxcc.entity', 'pota.parkReference')"
        },
        "goalField": {
          "type": "string",
          "description": "Goal item field to match against (typically 'id')"
        },
        "transformation": {
          "type": "string",
          "enum": ["none", "uppercase", "lowercase", "stripPrefix", "extractRegex"]
        },
        "transformationArg": {
          "type": "string",
          "description": "Argument for transformation (prefix to strip, regex group)"
        }
      }
    },
    "ScoringConfig": {
      "type": "object",
      "required": ["method"],
      "properties": {
        "method": {
          "type": "string",
          "enum": ["percentage", "count", "points", "weighted"]
        },
        "weights": {
          "type": "array",
          "items": { "$ref": "#/$defs/WeightRule" }
        },
        "tiebreaker": {
          "type": "string",
          "enum": ["earliestCompletion", "mostRecent", "alphabetical"]
        },
        "displayFormat": {
          "type": "string",
          "description": "Display template, e.g., '{value} entities'"
        }
      }
    },
    "WeightRule": {
      "type": "object",
      "required": ["condition", "points"],
      "properties": {
        "condition": {
          "type": "object",
          "description": "Condition for weight application"
        },
        "points": { "type": "integer" }
      }
    },
    "TimeConstraints": {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type": {
          "type": "string",
          "enum": ["calendar", "relative"]
        },
        "startDate": { "type": "string", "format": "date-time" },
        "endDate": { "type": "string", "format": "date-time" },
        "durationDays": {
          "type": "integer",
          "description": "For relative type: days from join"
        },
        "timezone": {
          "type": "string",
          "default": "UTC"
        }
      }
    },
    "InviteConfig": {
      "type": "object",
      "properties": {
        "enabled": { "type": "boolean", "default": false },
        "maxParticipants": {
          "type": "integer",
          "minimum": 1,
          "description": "null = unlimited"
        },
        "expiresAt": { "type": "string", "format": "date-time" },
        "requiresToken": { "type": "boolean", "default": false }
      }
    },
    "Badge": {
      "type": "object",
      "required": ["id", "name", "imageUrl"],
      "properties": {
        "id": { "type": "string" },
        "name": { "type": "string" },
        "description": { "type": "string" },
        "imageUrl": {
          "type": "string",
          "format": "uri"
        },
        "tierId": {
          "type": "string",
          "description": "Associated tier (null = completion badge)"
        }
      }
    },
    "HamAlertConfig": {
      "type": "object",
      "properties": {
        "supported": {
          "type": "boolean",
          "default": false
        },
        "alertType": {
          "type": "string",
          "enum": ["dxcc", "state", "park", "grid", "sota", "custom"]
        },
        "spotSources": {
          "type": "array",
          "items": {
            "type": "string",
            "enum": ["rbn", "cluster", "pota", "sota", "pskreporter"]
          }
        },
        "commentTemplate": {
          "type": "string",
          "description": "Template for alert comment, e.g., 'Carrier Wave WAS: Need {state}'"
        }
      }
    }
  }
}
```

---

## API Endpoints

### List Challenges

Retrieve available challenges from a source.

```
GET /challenges
```

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `category` | string | Filter by category (award, event, club, personal) |
| `type` | string | Filter by type (collection, cumulative, timeBounded) |
| `active` | boolean | Only show currently active challenges (default: true) |
| `limit` | integer | Max results (default: 50, max: 200) |
| `offset` | integer | Pagination offset |

**Response:**

```json
{
  "challenges": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "metadata": {
        "name": "Worked All States",
        "description": "Work all 50 US states",
        "author": "Carrier Wave Official",
        "category": "award"
      },
      "type": "collection",
      "participantCount": 1234,
      "timeConstraints": null
    }
  ],
  "total": 45,
  "limit": 50,
  "offset": 0
}
```

---

### Get Challenge Definition

Retrieve full challenge definition.

```
GET /challenges/{challengeId}
```

**Response:** Full challenge definition JSON (see schema above)

**Headers:**

| Header | Description |
|--------|-------------|
| `ETag` | Version hash for caching |
| `X-Challenge-Version` | Definition version number |

---

### Join Challenge

Join a challenge as a participant.

```
POST /challenges/{challengeId}/join
```

**Request:**

```json
{
  "callsign": "W1ABC",
  "inviteToken": "xyz789"
}
```

**Response:**

```json
{
  "participationId": "123e4567-e89b-12d3-a456-426614174000",
  "joinedAt": "2025-01-15T10:30:00Z",
  "status": "active",
  "historicalAllowed": true
}
```

**Errors:**

| Code | Description |
|------|-------------|
| 400 | Invalid request |
| 403 | Invite required or expired |
| 409 | Already joined |
| 429 | Max participants reached |

---

### Leave Challenge

Leave a challenge and remove participation data.

```
POST /challenges/{challengeId}/leave
```

**Request:**

```json
{
  "callsign": "W1ABC"
}
```

**Response:**

```json
{
  "success": true,
  "leftAt": "2025-01-20T15:00:00Z"
}
```

---

### Report Progress

Report progress update to challenge server.

```
POST /challenges/{challengeId}/progress
```

**Request:**

```json
{
  "callsign": "W1ABC",
  "progress": {
    "completedGoals": ["US-CA", "US-NY", "US-TX"],
    "currentValue": 47,
    "qualifyingQSOCount": 52,
    "lastQSODate": "2025-01-15T22:45:00Z"
  },
  "currentTier": "tier-40"
}
```

**Response:**

```json
{
  "accepted": true,
  "serverProgress": {
    "completedGoals": ["US-CA", "US-NY", "US-TX"],
    "currentValue": 47,
    "percentage": 94.0,
    "score": 47,
    "rank": 23
  },
  "newBadges": []
}
```

---

### Get Leaderboard

Retrieve challenge leaderboard.

```
GET /challenges/{challengeId}/leaderboard
```

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `limit` | integer | Max results (default: 100) |
| `offset` | integer | Pagination offset |
| `around` | string | Callsign to center results around |

**Response:**

```json
{
  "leaderboard": [
    {
      "rank": 1,
      "callsign": "K3ABC",
      "score": 50,
      "progress": 100.0,
      "currentTier": "complete",
      "completedAt": "2025-01-10T14:30:00Z"
    },
    {
      "rank": 2,
      "callsign": "W1XYZ",
      "score": 49,
      "progress": 98.0,
      "currentTier": "tier-40",
      "completedAt": null
    }
  ],
  "total": 1234,
  "userPosition": {
    "rank": 23,
    "callsign": "W1ABC",
    "score": 47,
    "progress": 94.0
  },
  "lastUpdated": "2025-01-15T23:00:00Z"
}
```

---

### Validate Invite Link

Validate an invite token before joining.

```
GET /invites/{token}
```

**Response:**

```json
{
  "valid": true,
  "challengeId": "550e8400-e29b-41d4-a716-446655440000",
  "challengeName": "Club Winter Sprint",
  "expiresAt": "2025-02-01T00:00:00Z",
  "participantCount": 45,
  "maxParticipants": 100,
  "spotsRemaining": 55
}
```

**Errors:**

| Code | Description |
|------|-------------|
| 404 | Invalid or expired token |
| 410 | Challenge ended |
| 429 | Max participants reached |

---

### Get Historical Snapshot

Retrieve frozen standings for ended time-limited challenge.

```
GET /challenges/{challengeId}/snapshot
```

**Response:**

```json
{
  "challengeId": "550e8400-e29b-41d4-a716-446655440000",
  "endedAt": "2025-01-07T23:59:59Z",
  "finalStandings": [
    {
      "rank": 1,
      "callsign": "K3ABC",
      "score": 13,
      "badges": ["thirteen-colonies-complete"]
    }
  ],
  "totalParticipants": 892,
  "statistics": {
    "averageScore": 8.3,
    "completionRate": 0.42
  }
}
```

---

## Versioning

### Challenge Definition Updates

When a challenge definition is updated:

1. Increment `version` field
2. Update `metadata.updatedAt`
3. Clients detect via `ETag` or `X-Challenge-Version` header
4. Clients re-fetch and re-evaluate progress

### API Versioning

- API version in URL path: `/v1/challenges`
- Breaking changes require new version (`/v2/challenges`)
- Deprecation notice via `Deprecation` header

---

## Rate Limits

| Endpoint | Limit |
|----------|-------|
| `GET /challenges` | 60/minute |
| `GET /challenges/{id}` | 120/minute |
| `POST /challenges/{id}/progress` | 30/minute |
| `GET /challenges/{id}/leaderboard` | 60/minute |

Rate limit headers:
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`

---

## Error Response Format

```json
{
  "error": {
    "code": "CHALLENGE_NOT_FOUND",
    "message": "The requested challenge does not exist",
    "details": {
      "challengeId": "invalid-id"
    }
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `CHALLENGE_NOT_FOUND` | 404 | Challenge does not exist |
| `ALREADY_JOINED` | 409 | User already participating |
| `INVITE_REQUIRED` | 403 | Challenge requires invite token |
| `INVITE_EXPIRED` | 403 | Invite token has expired |
| `MAX_PARTICIPANTS` | 429 | Challenge is full |
| `CHALLENGE_ENDED` | 410 | Time-limited challenge has ended |
| `RATE_LIMITED` | 429 | Too many requests |
| `INVALID_CALLSIGN` | 400 | Callsign format invalid |

---

## Example Challenge Definitions

### Worked All States

```json
{
  "id": "was-standard",
  "version": 1,
  "metadata": {
    "name": "Worked All States",
    "description": "Work all 50 US states on any band and mode",
    "author": "Carrier Wave Official",
    "category": "award",
    "tags": ["award", "usa", "states"]
  },
  "type": "collection",
  "configuration": {
    "goals": {
      "type": "collection",
      "items": [
        { "id": "AL", "name": "Alabama", "category": "Southeast" },
        { "id": "AK", "name": "Alaska", "category": "Pacific" },
        { "id": "AZ", "name": "Arizona", "category": "Southwest" }
      ]
    },
    "tiers": [
      { "id": "was-25", "name": "WAS 25", "threshold": 25, "order": 1 },
      { "id": "was-complete", "name": "WAS", "threshold": 50, "order": 2, "badgeId": "badge-was" }
    ],
    "qualificationCriteria": {
      "matchRules": [
        { "qsoField": "state", "goalField": "id" }
      ]
    },
    "scoring": {
      "method": "count",
      "displayFormat": "{value}/50 states"
    },
    "historicalQSOsAllowed": true
  },
  "badges": [
    {
      "id": "badge-was",
      "name": "Worked All States",
      "imageUrl": "https://challenges.fullduplex.app/badges/was.png"
    }
  ],
  "hamalertConfig": {
    "supported": true,
    "alertType": "state",
    "spotSources": ["rbn", "cluster"],
    "commentTemplate": "Carrier Wave WAS: Need {state}"
  }
}
```

### POTA Kilo Hunter

```json
{
  "id": "pota-kilo-hunter",
  "version": 1,
  "metadata": {
    "name": "POTA Kilo Hunter",
    "description": "Make 1000 park-to-park contacts as a hunter",
    "author": "Carrier Wave Official",
    "category": "award",
    "tags": ["pota", "hunter", "milestone"]
  },
  "type": "cumulative",
  "configuration": {
    "goals": {
      "type": "cumulative",
      "targetValue": 1000,
      "unit": "contacts",
      "calculationRule": {
        "method": "count"
      }
    },
    "tiers": [
      { "id": "hunter-100", "name": "100 Parks", "threshold": 100, "order": 1 },
      { "id": "hunter-500", "name": "500 Parks", "threshold": 500, "order": 2 },
      { "id": "hunter-kilo", "name": "Kilo Hunter", "threshold": 1000, "order": 3, "badgeId": "badge-kilo" }
    ],
    "qualificationCriteria": {
      "requiredFields": [
        { "field": "pota.parkReference", "requirement": "exists" }
      ]
    },
    "scoring": {
      "method": "count",
      "displayFormat": "{value}/1000 contacts"
    },
    "historicalQSOsAllowed": true
  },
  "badges": [
    {
      "id": "badge-kilo",
      "name": "POTA Kilo Hunter",
      "imageUrl": "https://challenges.fullduplex.app/badges/pota-kilo.png"
    }
  ],
  "hamalertConfig": {
    "supported": true,
    "alertType": "park",
    "spotSources": ["pota"],
    "commentTemplate": "Carrier Wave POTA Hunter"
  }
}
```

### Club Sprint (Time-Bounded)

```json
{
  "id": "winter-sprint-2025",
  "version": 1,
  "metadata": {
    "name": "Winter CW Sprint 2025",
    "description": "Club competition: Most CW contacts in January",
    "author": "Example Radio Club",
    "category": "club",
    "tags": ["contest", "cw", "club"]
  },
  "type": "cumulative",
  "configuration": {
    "goals": {
      "type": "cumulative",
      "targetValue": 999999,
      "unit": "QSOs",
      "calculationRule": { "method": "count" }
    },
    "qualificationCriteria": {
      "modes": ["CW"],
      "dateRange": {
        "start": "2025-01-01T00:00:00Z",
        "end": "2025-01-31T23:59:59Z"
      }
    },
    "scoring": {
      "method": "count",
      "tiebreaker": "earliestCompletion",
      "displayFormat": "{value} QSOs"
    },
    "timeConstraints": {
      "type": "calendar",
      "startDate": "2025-01-01T00:00:00Z",
      "endDate": "2025-01-31T23:59:59Z",
      "timezone": "UTC"
    },
    "historicalQSOsAllowed": false
  },
  "inviteConfig": {
    "enabled": true,
    "maxParticipants": 50,
    "expiresAt": "2025-01-31T23:59:59Z",
    "requiresToken": true
  },
  "badges": [
    {
      "id": "badge-sprint-1st",
      "name": "Sprint Champion",
      "imageUrl": "https://example-club.org/badges/sprint-1st.png"
    }
  ]
}
```

---

## Implementation Notes for Community Servers

1. **Minimum implementation**: `GET /challenges` and `GET /challenges/{id}` for read-only source
2. **Full implementation**: All endpoints for interactive participation
3. **CORS**: Enable CORS for app access
4. **HTTPS**: Required for production use
5. **Validation**: Validate challenge definitions against JSON schema before serving
