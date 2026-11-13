# Challenges Feature - Technical Design

## Overview

This document describes the technical architecture for the Challenges feature, covering data models, sync integration, external service integrations, and the web configurator.

See [challenges-prd.md](challenges-prd.md) for product requirements.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Challenge Sources                           │
├─────────────────┬─────────────────────┬─────────────────────────────┤
│  Official API   │  Community Sources  │      Invite Links           │
│  (Carrier Wave)   │  (User-added URLs)  │  (Challenge-specific)       │
└────────┬────────┴──────────┬──────────┴──────────────┬──────────────┘
         │                   │                         │
         └───────────────────┴─────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       Carrier Wave iOS App                            │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │
│  │  Challenge  │  │  Progress   │  │ Leaderboard │                  │
│  │   Store     │  │   Engine    │  │    Cache    │                  │
│  └─────────────┘  └─────────────┘  └─────────────┘                  │
│         │                │                │                         │
│         └────────────────┴────────────────┘                         │
│                          │                                          │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    SwiftData Store                          │    │
│  │  (QSOs, Challenge Definitions, User Progress, Badges)       │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
┌─────────────────────────┐   ┌─────────────────────────┐
│    Challenge Server     │   │       HamAlert API      │
│  (Leaderboards, Sync)   │   │   (Spot Management)     │
└─────────────────────────┘   └─────────────────────────┘
```

---

## Data Models

### Challenge Definition

The canonical challenge definition fetched from sources. Stored locally for reference.

```
ChallengeDefinition
├── id: UUID
├── sourceURL: String                    // Origin source for updates
├── version: Int                         // For update detection
├── metadata
│   ├── name: String
│   ├── description: String
│   ├── author: String
│   ├── createdAt: Date
│   └── updatedAt: Date
├── type: ChallengeType                  // collection | cumulative | timeBounded
├── configuration
│   ├── goals: [Goal]                    // Target items or values
│   ├── tiers: [Tier]?                   // Optional progression tiers
│   ├── qualificationCriteria: Criteria
│   ├── scoring: ScoringConfig
│   ├── timeConstraints: TimeConstraints?
│   └── historicalQSOsAllowed: Bool
├── inviteConfig: InviteConfig?          // If invite-link challenge
│   ├── maxParticipants: Int?
│   ├── expiresAt: Date?
│   └── participantCount: Int            // Current count
├── badges: [Badge]                      // Completion/tier badges
└── hamalertConfig: HamAlertConfig?      // Alert generation rules
```

### Goal

```
Goal (for Collection challenges)
├── id: String                           // e.g., "US-CA" for California
├── name: String                         // e.g., "California"
├── category: String?                    // e.g., "West Coast" for grouping
└── metadata: [String: String]           // Flexible additional data

Goal (for Cumulative challenges)
├── targetValue: Int                     // e.g., 1000 contacts
├── unit: String                         // e.g., "contacts", "points"
└── calculationRule: CalculationRule     // How to count/sum
```

### Tier

```
Tier
├── id: String
├── name: String                         // e.g., "DXCC 200"
├── threshold: Int                       // Items or value to reach
├── badgeId: String?                     // Reference to badge
└── order: Int                           // Display/progression order
```

### Qualification Criteria

```
Criteria
├── bands: [Band]?                       // nil = any band
├── modes: [Mode]?                       // nil = any mode
├── requiredFields: [FieldRequirement]   // e.g., parkReference must exist
├── dateRange: DateRange?                // QSO must fall within
└── matchRules: [MatchRule]              // How QSO maps to goals
```

### Match Rule

Defines how a QSO field maps to challenge goals.

```
MatchRule
├── qsoField: String                     // e.g., "state", "dxccEntity", "parkReference"
├── goalField: String                    // e.g., "id"
├── transformation: Transformation?      // Optional transform (uppercase, prefix strip, etc.)
└── validationRegex: String?             // Optional format validation
```

### Scoring Configuration

```
ScoringConfig
├── method: ScoringMethod                // percentage | count | points | weighted
├── weights: [WeightRule]?               // For weighted scoring
├── tiebreaker: TiebreakerRule?          // e.g., earliest completion time
└── displayFormat: String                // e.g., "{value} entities", "{value}%"
```

### Time Constraints

```
TimeConstraints
├── type: TimeConstraintType             // calendar | relative
├── startDate: Date?                     // For calendar type
├── endDate: Date?                       // For calendar type
├── duration: Duration?                  // For relative type (from join date)
└── timezone: String                     // For consistent evaluation
```

### Badge

```
Badge
├── id: String
├── name: String
├── description: String
├── imageURL: String                     // Hosted badge image
├── tier: String?                        // Associated tier, nil for completion badge
└── awardCriteria: AwardCriteria         // When to award
```

### HamAlert Configuration

```
HamAlertConfig
├── enabled: Bool
├── alertType: AlertType                 // dxcc | state | park | grid | custom
├── spotSources: [String]                // e.g., ["rbn", "pota", "sota"]
├── alertTemplate: AlertTemplate         // How to construct alert
└── autoManage: Bool                     // Auto-create/delete alerts
```

---

## User Data Models (Local)

### Challenge Participation

```
ChallengeParticipation
├── id: UUID
├── challengeId: UUID                    // Reference to ChallengeDefinition
├── userId: String                       // User's callsign
├── joinedAt: Date
├── status: ParticipationStatus          // active | completed | left | expired
├── progress: ChallengeProgress
├── currentTier: String?                 // Highest achieved tier
├── completedAt: Date?
├── hamalertEnabled: Bool
└── syncStatus: SyncStatus               // For sync destination
```

### Challenge Progress

```
ChallengeProgress
├── completedGoals: [String]             // Goal IDs for collection
├── currentValue: Int                    // For cumulative
├── percentage: Double                   // Computed
├── score: Int                           // Based on scoring config
├── qualifyingQSOIds: [UUID]             // QSOs that contributed
└── lastUpdated: Date
```

### Leaderboard Entry (Cached)

```
LeaderboardEntry
├── rank: Int
├── callsign: String
├── score: Int
├── progress: Double                     // Percentage
├── currentTier: String?
├── completedAt: Date?                   // For tiebreaking
└── isCurrentUser: Bool
```

---

## Challenge Sources

### Source Management

Users can configure multiple challenge sources:

```
ChallengeSource
├── id: UUID
├── type: SourceType                     // official | community | invite
├── url: String
├── name: String
├── isEnabled: Bool
├── lastFetched: Date?
├── lastError: String?
└── trustLevel: TrustLevel               // For UI indicators
```

### Source Discovery Flow

1. **Official source**: Pre-configured, always available
2. **Community sources**: User adds URL via settings
3. **Invite links**: Deep link opens app, extracts challenge ID and source

### Invite Link Format

```
fullduplex://challenge/join?
  source=https://example.com/challenges&
  id=abc123&
  token=xyz789
```

- `source`: Challenge source base URL
- `id`: Challenge ID
- `token`: Optional auth token for private challenges

---

## Sync Integration

### Sync Destination Architecture

Challenges sync integrates as an optional sync destination alongside QRZ, POTA, LoFi.

```
ChallengesSyncService: SyncDestination
├── isEnabled: Bool
├── syncInterval: TimeInterval
├── sync(qsos: [QSO]) async throws
├── fetchLeaderboard(challengeId: UUID) async throws -> [LeaderboardEntry]
└── reportProgress(participation: ChallengeParticipation) async throws
```

### Sync Flow

1. **QSO Logged** → Progress Engine evaluates against active challenges
2. **Progress Updated** → Local participation record updated
3. **Sync Triggered** → Progress reported to challenge server
4. **Leaderboard Fetched** → Cache updated, UI refreshed

### Real-Time Updates

For leaderboard real-time updates:

- **Option A**: WebSocket connection to challenge server
- **Option B**: Polling with configurable interval (default: 30s during active view)
- **Recommendation**: Start with polling, add WebSocket for v2

---

## Progress Engine

### QSO Evaluation

When a QSO is logged or imported:

```
func evaluateQSO(_ qso: QSO, against challenges: [ChallengeParticipation]) {
    for participation in challenges where participation.status == .active {
        let definition = participation.challengeDefinition

        // Check qualification criteria
        guard qso.matches(criteria: definition.qualificationCriteria) else { continue }

        // Check time constraints
        guard qso.isWithin(timeConstraints: definition.timeConstraints) else { continue }

        // Check historical allowance
        if !definition.historicalQSOsAllowed && qso.date < participation.joinedAt {
            continue
        }

        // Apply match rules to determine goal progress
        let matchedGoals = definition.matchRules.evaluate(qso)

        // Update progress
        participation.progress.apply(matchedGoals, from: qso)

        // Check tier advancement
        participation.evaluateTierAdvancement()

        // Trigger notification if progress made
        if matchedGoals.isNotEmpty {
            notifyProgress(participation, newMatches: matchedGoals)
        }
    }
}
```

### Batch Evaluation

For historical QSO evaluation when joining a challenge:

```
func evaluateHistoricalQSOs(for participation: ChallengeParticipation) async {
    guard participation.challengeDefinition.historicalQSOsAllowed else { return }

    let relevantQSOs = fetchQSOs(matching: participation.challengeDefinition.qualificationCriteria)

    for qso in relevantQSOs {
        // Evaluate without notifications (batch mode)
        evaluateQSO(qso, against: [participation], notificationsEnabled: false)
    }

    // Single summary notification
    notifyHistoricalEvaluation(participation)
}
```

---

## HamAlert Integration

### Connection Setup

```
HamAlertService
├── authenticate(apiKey: String) async throws
├── createAlert(config: AlertConfig) async throws -> AlertId
├── deleteAlert(id: AlertId) async throws
├── listAlerts() async throws -> [Alert]
└── syncAlerts(for participation: ChallengeParticipation) async throws
```

### Alert Lifecycle

1. **User enables HamAlert for challenge** → Service calculates needed entities
2. **Needed entities determined** → Alerts created via HamAlert API
3. **QSO logged matching entity** → Alert deleted via API
4. **Challenge definition updates** → Alerts recalculated

### Alert Template

```
AlertTemplate
├── callsignPattern: String?             // e.g., "*" for any
├── entityFilter: EntityFilter           // Based on remaining goals
├── spotSources: [SpotSource]
├── bands: [Band]?
├── modes: [Mode]?
└── comment: String                      // e.g., "Carrier Wave: WAS - Need {state}"
```

---

## Configurator (Web Tool)

### Overview

Separate web application for creating and managing challenge definitions.

**Repository**: `fullduplex-challenge-configurator` (separate repo)

### Core Features

1. **Challenge Builder**
   - Visual editor for challenge definition
   - Goal list management (manual entry, CSV import, API fetch)
   - Tier configuration
   - Criteria builder (bands, modes, fields, dates)
   - Scoring configuration

2. **Badge Manager**
   - Image upload with format/size validation
   - Preview at different resolutions
   - Association with tiers

3. **Invite Link Generator**
   - Create invite links with optional expiration
   - Set participant limits
   - Track participant count
   - Revoke links

4. **Publishing**
   - Export challenge definition as JSON
   - Direct publish to self-hosted server
   - Validation before publish

### Configurator Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Web Configurator                         │
├─────────────────────────────────────────────────────────────┤
│  Challenge Builder  →  Validation  →  JSON Export/Publish   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Challenge Server                          │
│  (Can be official Carrier Wave server or self-hosted)         │
├─────────────────────────────────────────────────────────────┤
│  • Hosts challenge definitions                              │
│  • Tracks participation                                     │
│  • Maintains leaderboards                                   │
│  • Stores frozen snapshots for ended challenges             │
└─────────────────────────────────────────────────────────────┘
```

### Goal Import Sources

For collection challenges, goals can be imported from:

- **Manual entry**: Type each goal
- **CSV upload**: Bulk import
- **DXCC entities**: Fetch from official list
- **US States**: Pre-built list
- **POTA parks**: Fetch from POTA API
- **SOTA summits**: Fetch from SOTA API
- **Custom API**: User provides endpoint

---

## UI Components

### Challenges Tab

```
ChallengesView
├── ActiveChallengesSection
│   ├── ChallengeProgressCard (for each active)
│   │   ├── Progress bar/ring
│   │   ├── Current tier indicator
│   │   ├── Quick stats (X/Y completed)
│   │   └── Tap → ChallengeDetailView
│   └── "Browse Challenges" button
├── CompletedChallengesSection
│   └── CompletedChallengeCard (badge display)
└── HistoricalChallengesSection
    └── Archived time-limited challenges
```

### Challenge Detail View

```
ChallengeDetailView
├── Header (name, description, time remaining if applicable)
├── ProgressSection
│   ├── Visual progress (bar/ring/grid)
│   ├── Tier progress indicators
│   └── Stats (completed, remaining, score)
├── LeaderboardSection
│   ├── Top participants
│   ├── Current user position (highlighted)
│   └── "View Full Leaderboard" → LeaderboardView
├── DrilldownSection
│   ├── Completed items list
│   ├── Remaining items list
│   └── Filter/search
├── HamAlertSection (if configured)
│   ├── Enable/disable toggle
│   ├── Active alerts count
│   └── "Manage Alerts" → alert list
└── Actions
    ├── Leave Challenge
    └── Share (if invite-link enabled)
```

### Browse Challenges View

```
BrowseChallengesView
├── SourceSelector (Official, Community sources)
├── CategoryFilter (Awards, Events, Club, Personal)
├── ChallengeList
│   └── ChallengePreviewCard
│       ├── Name, description
│       ├── Type indicator
│       ├── Participant count
│       ├── Time remaining (if bounded)
│       └── "Join" button
└── "Add Community Source" button
```

### Notifications

In-app notifications for:

- Progress: "Worked Alaska! 3 states remaining for WAS"
- Tier advancement: "Achieved DXCC 200! 🎖️"
- Challenge completion: "Congratulations! WAS Complete!"
- Time warnings: "Club Sprint ends in 1 hour"
- Leaderboard changes: "You moved to #3 on the leaderboard!"

---

## API Endpoints

See [challenges-api.md](challenges-api.md) for full API specification.

### Summary

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/challenges` | GET | List available challenges |
| `/challenges/{id}` | GET | Get challenge definition |
| `/challenges/{id}/join` | POST | Join challenge |
| `/challenges/{id}/leave` | POST | Leave challenge |
| `/challenges/{id}/progress` | POST | Report progress |
| `/challenges/{id}/leaderboard` | GET | Get leaderboard |
| `/invites/{token}` | GET | Validate invite link |

---

## Security Considerations

1. **Source Trust**: Clear visual indicators for official vs community sources
2. **Invite Links**: Token-based validation, expiration enforcement
3. **Progress Validation**: Server may validate reported progress against QSO data (future)
4. **HamAlert**: API key stored in Keychain, never in SwiftData
5. **Rate Limiting**: Respect API rate limits for all external services

---

## Migration & Rollout

### Phase 1: Core Infrastructure
- Challenge definition model
- Source management
- Basic progress tracking
- Local-only evaluation

### Phase 2: Sync & Leaderboards
- Challenge sync destination
- Leaderboard fetching
- Real-time updates

### Phase 3: Social Features
- Invite links
- Participant tracking
- Frozen snapshots

### Phase 4: Integrations
- HamAlert integration
- In-app notifications

### Phase 5: Configurator
- Web tool development
- Publishing workflow
- Badge management

---

## Open Technical Questions

1. **WebSocket vs Polling**: For v1, polling is simpler. Worth investing in WebSocket for real-time?

2. **Progress validation**: Should server validate progress against uploaded QSO data, or trust client?

3. **Offline queue**: If connectivity is required, should we queue progress updates during brief disconnections?

4. **Badge caching**: Download and cache badge images, or load on demand?
