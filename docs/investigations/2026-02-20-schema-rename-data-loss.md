# Investigation: SwiftData Schema Rename Data Loss

**Date:** 2026-02-20
**Status:** In Progress
**Outcome:** TBD

## Problem Statement

User reports data loss after Feb 13 following deployment of SwiftData model fixes (commit 76d285f). Sync is also stuck. The fixes renamed stored properties which SwiftData treats as "drop old column, add new column" during lightweight migration, orphaning data in the old columns.

## Breaking Renames (commit 76d285f)

| Model | Old Property | New Property | Type Change |
|-------|-------------|-------------|-------------|
| QSO | `importSource: ImportSource` | `importSourceRawValue: String` | Enum → raw value |
| QSO | `servicePresence: [ServicePresence]` | `servicePresenceRelation: [ServicePresence]?` | Relationship rename |
| ServicePresence | `serviceType: ServiceType` | `serviceTypeRawValue: String` | Enum → raw value |
| UploadDestination | `type: ServiceType` | `typeRawValue: String` | Enum → raw value |
| ChallengeSource | `challenges: [ChallengeDefinition]` | `challengesRelation: [ChallengeDefinition]?` | Relationship rename |
| ChallengeDefinition | `participations: [ChallengeParticipation]` | `participationsRelation: [ChallengeParticipation]?` | Relationship rename |

## Recovery Plan

### Phase 1: Fix schema names (prevent further damage)
- Use `@Attribute(originalName:)` for renamed attributes
- Rename relationship stored properties back to original names
- Keep `nonisolated` and optional type changes (those are safe)

### Phase 2: SQLite data recovery
- Old columns should still exist in SQLite (it doesn't drop columns)
- Write a one-time migration to copy data from orphaned columns to current ones
- Alternatively, if CloudKit has the data, let sync recover it

## Investigation Log

### Step 1: Identified breaking renames
All renames came from commit 76d285f. The prior fix commits (61ad84f, d53e0ae) made no model property changes.

### Step 2: Recovery approach
Using `@Attribute(originalName:)` will tell SwiftData the new property name maps to the old column, recovering the data without needing a manual SQLite migration.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `QSO.swift` | Core model | `importSource` → `importSourceRawValue`, `servicePresence` → `servicePresenceRelation` |
| `ServicePresence.swift` | Upload tracking | `serviceType` → `serviceTypeRawValue` |
| `UploadDestination.swift` | Sync config | `type` → `typeRawValue` |
| `ChallengeSource.swift` | Challenges | `challenges` → `challengesRelation` |
| `ChallengeDefinition.swift` | Challenges | `participations` → `participationsRelation` |
