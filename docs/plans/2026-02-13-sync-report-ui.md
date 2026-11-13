# Plan: Sync Report UI for Downloaded QSO Changes

**Date:** 2026-02-13
**Status:** Proposed

## Summary

Add a user-facing "Sync Report" that shows what happened during each sync download, replacing the current plain-string results ("+5 QSOs") with structured per-service funnel data.

## Analysis: What Data is Available

Each service (QRZ, POTA, LoFi, LoTW, HAMRS) funnels downloaded QSOs through:

1. **Raw fetch** — Count per service (all services track this)
2. **Field validation** — Skipped count (LoFi/HAMRS only; others pass all records)
3. **Dedup grouping** — Same contact from multiple sources collapsed by `callsign|band|mode|2min-bucket`
4. **Merge/Create** — `created` (new QSOs) and `merged` (enriched existing) counts from `QSOProcessingActor`
5. **ServicePresence** — Per-service presence records created/updated
6. **Reconciliation** — POTA: confirmed/failed/stale/orphan/in-progress counts; QRZ: reset count on full sync

All counts are already computed during sync execution. `SyncDebugLog` captures them for developers but nothing is surfaced to users.

## Design: UI Proposal

### Entry Points

1. **Primary**: Redesigned "Last Sync" section in existing `ServiceDetailSheet` (accessed by tapping a service row on dashboard)
2. **Secondary**: Subtle tertiary text on `ServiceRow` in dashboard: `"+5 new, 12 enriched [3 min ago]"` — disappears after 1 hour

### Summary View (in ServiceDetailSheet "Last Sync" section)

```
[Timestamp: "3 minutes ago"]                    [Status Badge: green "OK"]

 [arrow.down.circle] 247    [plus.circle] 5    [arrow.merge] 12
   Downloaded                  New               Enriched
```

- 3-5 inline stat chips (Downloaded, New, Enriched; optionally Skipped/Uploaded)
- Status badge: green checkmark (OK), orange triangle (Attention), red X (Error)

### Detail View (DisclosureGroup expansion)

Vertical step timeline with left-side connector line + SF Symbol icons:

```
 [arrow.down.circle]  Downloaded from API              247
       |
 [filter]             After Validation                 244  (3 skipped)
       |
 [arrow.merge]        Processed          5 new, 12 enriched
       |
 [arrow.up.circle]    Uploaded                           8
```

### Service-Specific Reconciliation (below funnel)

- **POTA**: confirmed/failed/stale/orphan/in-progress counts with semantic colors
- **QRZ** (full sync only): reset count

### Warning/Error States

- Failed sync: red icon + error message, no funnel
- Skipped QSOs: orange banner with explanation + guidance
- POTA failed jobs: orange/red reconciliation rows + link to jobs view

## HIG Review: PASS (85/100)

### Strengths
- Progressive disclosure matches iOS Settings/Health/Wallet patterns
- Semantic colors used correctly throughout
- Typography follows design language precisely
- Status communication is clear and actionable

### Critical Fixes Required

1. **DisclosureGroup accessibility**: Add `.accessibilityHint("Double tap to show detailed sync steps")`
2. **Timeline step accessibility**: Wrap each step in `.accessibilityElement(children: .combine)` with structured labels ("Step 1: Downloaded 237 QSOs")
3. **Stat chip accessibility**: Combine number + label for VoiceOver
4. **Reduce Motion**: Add `@Environment(\.accessibilityReduceMotion)` for DisclosureGroup animation
5. **Sheet navigation**: Confirm ServiceDetailSheet wrapped in NavigationStack with dismiss button

### Recommendations

- Limit stat chips to 4 max; move "Skipped" to detail view
- Implement `ViewThatFits` with vertical fallback for large Dynamic Type
- Ensure "View Jobs" button has `.frame(minHeight: 44)` touch target

## Code Review: CONCERN (Sound concept, needs architectural alignment)

### Blockers (Must Fix)

1. **SyncService.swift at 500 lines** — Cannot add report logic here. Create `SyncService+Report.swift` extension.

2. **Thread safety** — `SyncReport` and all nested types MUST be `Sendable` structs (not classes). Report data crosses from `QSOProcessingActor` (background) to `@MainActor` SyncService.

3. **Reconciliation counts not returned** — `QSOProcessingActor.reconcilePOTAPresence()` currently performs updates as side effects without returning counts. Must modify to return a `ReconciliationResult` struct.

### High Priority

4. **Merge with existing models** — Don't create parallel state. Evolve existing `SyncResult` struct (already has `downloaded`, `uploaded`, `newQSOs`, `mergedQSOs`, `errors`) instead of building `SyncReport` from scratch. Add timestamp + reconciliation details.

5. **Per-service storage** — `lastSyncReport: SyncReport?` won't work for single-service syncs (user taps "Sync QRZ" then "Sync POTA" — second overwrites first). Use `lastSyncResults: [ServiceType: ServiceSyncReport]` instead.

6. **Remove duplicate state** — Delete `@State var qrzSyncResult: String?` etc from DashboardView. Derive all UI from `syncService.lastSyncResults[.qrz]`.

### Medium Priority

7. **Latency audit** — Report building should take <50ms with 10k QSO syncs
8. **Persistence policy** — In-memory only (lost on restart) may be acceptable since sync is cheap; document this decision
9. **Error handling** — Add `error: String?` to `ServiceSyncReport` for partial failures

## Proposed File Changes

### New Files (3)
| File | Purpose | Est. Lines |
|------|---------|------------|
| `CarrierWave/Services/SyncService+Report.swift` | Report building logic + model types | ~150 |
| `CarrierWave/Views/Dashboard/SyncReportViews.swift` | `SyncReportHeader`, `SyncFunnelSummaryRow`, `SyncStepRow` | ~200 |
| `CarrierWave/Views/Dashboard/SyncFunnelDetailView.swift` | `SyncFunnelDetailView`, reconciliation, warning banners | ~200 |

### Modified Files (6-7)
| File | Change |
|------|--------|
| `SyncService.swift` | Add `@Published var lastSyncResults: [ServiceType: ServiceSyncReport]` |
| `SyncService+Download.swift` | Capture download counts into report during downloads |
| `SyncService+Process.swift` | Capture created/merged counts into report |
| `QSOProcessingActor.swift` | Return reconciliation counts from `reconcilePOTAPresence()` |
| `ServiceDetailSheet.swift` | Replace "Last Sync" section with funnel summary + detail |
| `DashboardView+Services.swift` | Pass `ServiceSyncReport` to detail sheet, add tertiary info |
| `DashboardView.swift` | Remove per-service `*SyncResult: String?` state variables |

## Implementation Strategy

**Recommended**: Prototype with single-service sync first (QRZ only), validate performance and threading, then expand to all services.

1. Evolve `SyncResult` → add timestamp, reconciliation, per-service detail
2. Add `lastSyncResults: [ServiceType: ServiceSyncReport]` to SyncService
3. Modify reconciliation actors to return result structs
4. Build UI components (`SyncFunnelSummaryRow`, step timeline)
5. Wire into `ServiceDetailSheet` replacing string results
6. Test with large syncs (10k+ QSOs) for latency
