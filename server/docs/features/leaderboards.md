# Leaderboards

## Overview

Each challenge has a leaderboard ranking participants by score. Leaderboards update on each progress report and can be queried with pagination.

## Ranking

Rankings use PostgreSQL window functions:

```sql
SELECT
    callsign,
    score,
    current_tier,
    RANK() OVER (ORDER BY score DESC, updated_at ASC) as rank
FROM progress
WHERE challenge_id = $1
ORDER BY rank
```

### Tiebreakers

When scores are equal, tiebreaker determines rank:

| Tiebreaker | SQL |
|------------|-----|
| `earliestCompletion` | `ORDER BY score DESC, updated_at ASC` |
| `mostRecent` | `ORDER BY score DESC, updated_at DESC` |
| `alphabetical` | `ORDER BY score DESC, callsign ASC` |

## Queries

### Standard Leaderboard

```
GET /v1/challenges/{id}/leaderboard?limit=100&offset=0
```

Returns top N participants.

### Around Me

```
GET /v1/challenges/{id}/leaderboard?around=W1ABC
```

Returns entries centered around the specified callsign (5 above, 5 below).

Implementation:

```sql
WITH ranked AS (
    SELECT *, RANK() OVER (ORDER BY score DESC) as rank
    FROM progress WHERE challenge_id = $1
)
SELECT * FROM ranked
WHERE rank BETWEEN
    (SELECT rank FROM ranked WHERE callsign = $2) - 5
    AND
    (SELECT rank FROM ranked WHERE callsign = $2) + 5
```

## Response Format

```json
{
  "leaderboard": [
    {
      "rank": 1,
      "callsign": "K1ABC",
      "score": 50,
      "currentTier": "tier-50",
      "progress": {
        "completedGoals": 50,
        "percentage": 100.0
      },
      "completedAt": "2025-01-10T00:00:00Z"
    }
  ],
  "total": 1234,
  "userPosition": {
    "rank": 23,
    "callsign": "W1ABC",
    "score": 47
  },
  "lastUpdated": "2025-01-15T19:00:00Z"
}
```

## Updates

Leaderboards update whenever progress is reported. The server:

1. Receives progress report
2. Updates `progress` table
3. Recalculates score
4. Returns new rank in response

Clients poll for leaderboard updates (no WebSocket push in v1).

### Polling Recommendations

| Context | Interval |
|---------|----------|
| Active viewing | 30 seconds |
| Background | 5 minutes |
| Inactive | Don't poll |

## Snapshots

When a time-bounded challenge ends, the leaderboard is frozen:

1. Query final standings
2. Store in `challenge_snapshots` table
3. Include statistics (average score, completion rate)

Snapshots are immutable and served via:

```
GET /v1/challenges/{id}/snapshot
```

### Snapshot Format

```json
{
  "challengeId": "uuid",
  "endedAt": "2025-01-31T23:59:59Z",
  "finalStandings": [
    { "rank": 1, "callsign": "K1ABC", "score": 127 }
  ],
  "totalParticipants": 50,
  "statistics": {
    "averageScore": 45.2,
    "medianScore": 42,
    "completionRate": 0.12,
    "topTierCount": 6
  }
}
```

## Performance

### Indexes

The `progress` table has a composite index for leaderboard queries:

```sql
CREATE INDEX idx_progress_leaderboard
ON progress(challenge_id, score DESC);
```

### Caching

Consider caching leaderboard results for high-traffic challenges:
- Cache key: `leaderboard:{challenge_id}:{limit}:{offset}`
- TTL: 10-30 seconds
- Invalidate on progress update

Not implemented in v1, but the architecture supports adding a Redis cache layer.

## Rate Limiting

Leaderboard endpoint: 60 requests/minute per IP.

This allows polling every second for a minute, which is more than sufficient for the recommended 30-second interval.
