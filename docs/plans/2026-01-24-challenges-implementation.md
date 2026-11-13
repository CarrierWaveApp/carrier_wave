# Challenges Feature Implementation Plan

## Overview

Implement Phases 1 & 2 of the Challenges feature: core infrastructure with local progress tracking, plus sync and leaderboards with the existing challenge server.

## Scope

- Challenge data models and types
- Challenge source management (official + community)
- Progress tracking engine that evaluates QSOs
- Server sync for progress reporting and leaderboard fetching
- Full UI: Challenges tab, browse, detail, leaderboards
- Deep link handling for invite links
- Local notifications for progress events

## Data Models

### Codable Types (ChallengeTypes.swift)

```swift
enum ChallengeType: String, Codable { case collection, cumulative, timeBounded }
enum ParticipationStatus: String, Codable { case active, completed, left, expired }
enum SourceType: String, Codable { case official, community, invite }

struct Goal: Codable, Identifiable { ... }
struct Tier: Codable, Identifiable { ... }
struct QualificationCriteria: Codable { ... }
struct MatchRule: Codable { ... }
struct ScoringConfig: Codable { ... }
struct TimeConstraints: Codable { ... }
struct Badge: Codable, Identifiable { ... }
struct ChallengeProgress: Codable { ... }
struct LeaderboardEntry: Codable, Identifiable { ... }
```

### SwiftData Models

- `ChallengeSource` - Source URLs for fetching challenges
- `ChallengeDefinition` - Challenge specs with JSON-encoded configuration
- `ChallengeParticipation` - User enrollment with progress
- `LeaderboardCache` - Cached leaderboard per challenge

## Services

- `ChallengesClient` (actor) - API communication
- `ChallengeProgressEngine` (@MainActor) - QSO evaluation
- `ChallengesSyncService` - Sync destination integration

## Views

- `ChallengesView` - Main tab
- `ChallengeProgressCard` - Summary card
- `ChallengeDetailView` - Full details with drilldown
- `BrowseChallengesView` - Discover and join
- `LeaderboardView` - Full standings

## Implementation Steps

### Step 1: Data Models & Types
- [ ] Create `ChallengeTypes.swift` with all Codable structs
- [ ] Create `ChallengeSource.swift` SwiftData model
- [ ] Create `ChallengeDefinition.swift` SwiftData model
- [ ] Create `ChallengeParticipation.swift` SwiftData model
- [ ] Create `LeaderboardCache.swift` SwiftData model
- [ ] Register models in SwiftData schema

### Step 2: ChallengesClient
- [ ] Create `ChallengesClient.swift` actor
- [ ] Implement authentication with Keychain
- [ ] Implement `fetchChallenges(from:)`
- [ ] Implement `joinChallenge(id:token:)`
- [ ] Implement `leaveChallenge(id:)`
- [ ] Implement `reportProgress(participation:)`
- [ ] Implement `fetchLeaderboard(challengeId:)`
- [ ] Create `ChallengesError.swift` for error types

### Step 3: ChallengeProgressEngine
- [ ] Create `ChallengeProgressEngine.swift`
- [ ] Implement `evaluateQSO(_:against:)` method
- [ ] Implement match rule processing
- [ ] Implement qualification criteria checking
- [ ] Implement tier advancement detection
- [ ] Implement `evaluateHistoricalQSOs(for:)` for batch evaluation

### Step 4: ChallengesSyncService
- [ ] Create `ChallengesSyncService.swift`
- [ ] Implement progress reporting to server
- [ ] Implement leaderboard fetching with caching
- [ ] Integrate with existing SyncService

### Step 5: Core Views
- [ ] Create `ChallengesView.swift` main tab
- [ ] Create `ChallengeProgressCard.swift` component
- [ ] Create `ChallengeDetailView.swift` with drilldown
- [ ] Add `.challenges` case to `AppTab` enum
- [ ] Add Challenges tab to `ContentView`

### Step 6: Browse & Join Flow
- [ ] Create `BrowseChallengesView.swift`
- [ ] Create source management UI
- [ ] Implement join/leave actions
- [ ] Add Challenges section to `SettingsView`

### Step 7: Leaderboards
- [ ] Create `LeaderboardView.swift`
- [ ] Implement polling mechanism (30s interval)
- [ ] Implement cache refresh on poll

### Step 8: Deep Links & Notifications
- [ ] Handle `carrierwave://challenge/join` URL scheme
- [ ] Implement local notification triggers for progress
- [ ] Implement notification for tier advancement
- [ ] Implement notification for challenge completion

## API Endpoints (Reference)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/challenges` | GET | List available challenges |
| `/challenges/{id}` | GET | Get challenge definition |
| `/challenges/{id}/join` | POST | Join challenge |
| `/challenges/{id}/leave` | POST | Leave challenge |
| `/challenges/{id}/progress` | POST | Report progress |
| `/challenges/{id}/leaderboard` | GET | Get leaderboard |
| `/invites/{token}` | GET | Validate invite link |

## Testing Notes

- Use in-memory SwiftData containers (existing pattern)
- Mock `ChallengesClient` for view/engine tests
- Test progress engine with various QSO/criteria combinations

## Files to Create

```
CarrierWave/
├── Models/
│   ├── ChallengeTypes.swift
│   ├── ChallengeSource.swift
│   ├── ChallengeDefinition.swift
│   ├── ChallengeParticipation.swift
│   └── LeaderboardCache.swift
├── Services/
│   ├── ChallengesClient.swift
│   ├── ChallengesError.swift
│   ├── ChallengeProgressEngine.swift
│   └── ChallengesSyncService.swift
└── Views/
    └── Challenges/
        ├── ChallengesView.swift
        ├── ChallengeProgressCard.swift
        ├── ChallengeDetailView.swift
        ├── BrowseChallengesView.swift
        └── LeaderboardView.swift
```

## Files to Modify

- `ContentView.swift` - Add Challenges tab
- `SettingsView.swift` - Add Challenges settings section
- `SyncService.swift` - Integrate ChallengesSyncService
- SwiftData schema registration (likely in App file)
