# Investigation: iCloud Database Sync Options for Carrier Wave

**Date:** 2026-02-20
**Status:** Research complete

## Context

Carrier Wave uses SwiftData with a local-only `ModelContainer` (18 models). Current iCloud usage is limited to:

- **iCloud Key-Value Store** — `SettingsSyncService` syncs ~50 user settings via `NSUbiquitousKeyValueStore`
- **iCloud Drive monitoring** — `ICloudMonitor` watches for `.adi`/`.adif` files dropped into the app's iCloud Drive container (import-only, not database sync)

The app currently has **no CloudKit references** (no `CKSyncEngine`, `CKDatabase`, or `CKContainer`). No `@Attribute(.unique)` constraints are used on any SwiftData model, which is favorable for CloudKit compatibility.

The goal is to evaluate options for syncing the SwiftData database across a user's devices.

---

## Option 1: SwiftData + CloudKit Automatic Sync

**What it is:** Add `cloudKitContainerIdentifier` to `ModelConfiguration` to enable built-in `NSPersistentCloudKitContainer` mirroring.

### Setup

```swift
let config = ModelConfiguration(
    schema: schema,
    cloudKitContainerIdentifier: "iCloud.com.example.carrierwave"
)
```

Plus: enable CloudKit capability in Xcode, create a CloudKit container, add iCloud entitlement.

### Pros

- Minimal code change — essentially one line in `ModelConfiguration`
- Apple-managed sync with push notifications, background refresh
- No custom sync logic needed

### Cons

- **No `@Attribute(.unique)` allowed** — we don't use this, so OK for now
- **All properties must be optional or have defaults** — need to audit all 18 models
- **All relationships must be optional** — need to audit
- **No `Deny` delete rules** — need to audit
- **Schema changes are add-only once deployed** — no renames, no deletes, no type changes. This is a permanent constraint that limits future flexibility
- **Data duplication is common** — without unique constraints, deduplication must be handled manually
- **Sync is opaque** — black box with limited debugging tools. `TN3164` helps but developers widely report frustration
- **Not real-time** — Apple throttles sync based on battery, network, etc.
- **Pre-existing data may not sync** — data created before enabling CloudKit may never sync (by design)
- **iOS 18 data loss reports** — account change events can wipe local data; some developers report data loss in production
- **Slow initial import** — new devices can take minutes to sync large datasets
- **Conflict resolution is server-wins** — no way to customize merge policy in SwiftData (Core Data offers `NSMergePolicy`, SwiftData does not)
- **Private database only** — no shared or public database support natively

### Migration effort: Low code, high risk

### Verdict: Not recommended

The opaque nature, data duplication issues, inflexible schema evolution, and reports of data loss make this unsuitable for an app where QSO data integrity is critical.

---

## Option 2: CKSyncEngine + SwiftData (Recommended)

**What it is:** Use SwiftData for local persistence (as today) with CloudKit sync disabled, and use `CKSyncEngine` (iOS 17+) to handle sync manually by converting between SwiftData models and `CKRecord`s.

### How it works

1. SwiftData remains local-only (no `cloudKitContainerIdentifier`)
2. A `SyncManager` actor conforms to `CKSyncEngineDelegate`
3. On local changes: convert model diffs to `CKRecord`s, hand to CKSyncEngine
4. On remote changes: receive `CKRecord`s in `handleEvent`, convert to SwiftData model writes
5. CKSyncEngine handles: push notifications, retry logic, state serialization, zone management, account changes, system condition monitoring

### Key delegate methods

- `handleEvent` — react to fetched changes, sent change results, errors, account changes
- `nextRecordZoneChangeBatch` — provide pending local changes to upload

### Pros

- **Full control over conflict resolution** — compare local vs. server `CKRecord` metadata, implement custom merge logic (e.g., last-writer-wins with field-level merge)
- **Unique constraints allowed locally** — since we manage the mapping, local SwiftData can use any features
- **Schema flexibility** — `CKRecord` is a loose dictionary; local schema can evolve independently
- **Apple-endorsed direction** — Apple uses CKSyncEngine internally (Freeform, NSUbiquitousKeyValueStore). It's what Apple recommends for apps that aren't using Core Data
- **Transparent** — full visibility into sync state, errors, and conflicts
- **Battle-tested** — Christian Selig (Apollo) calls it "one of the best APIs Apple has built"
- **Keep existing SwiftData models as-is** — no need to make everything optional or remove constraints

### Cons

- **Significant implementation effort** — need to build model-to-CKRecord mapping for all synced models
- **Deletion conflicts are fire-and-forget** — CKSyncEngine trusts deletes without conflict checking
- **CKRecord is Obj-C-era** — string-keyed dictionary, not type-safe
- **Need to store CKRecord metadata** — each synced model needs a `lastKnownRecordData: Data?` property for conflict detection
- **UI update challenges** — changes from sync actor may not automatically trigger SwiftUI updates; need careful `@ModelActor` + main context merge patterns

### Architecture sketch

```
┌─────────────────────────────────────────────────┐
│  SwiftData (local, no CloudKit)                 │
│  ModelContainer → ModelContext                   │
├─────────────────────────────────────────────────┤
│  CloudSyncManager (actor)                       │
│  ├── CKSyncEngineDelegate                       │
│  ├── Model → CKRecord mapping                   │
│  ├── CKRecord → Model mapping                   │
│  ├── Conflict resolution logic                  │
│  └── Change tracking (dirty flags or history)   │
├─────────────────────────────────────────────────┤
│  CKSyncEngine                                   │
│  ├── Handles push notifications                 │
│  ├── Manages zones and subscriptions            │
│  ├── Serializes sync state                      │
│  └── Monitors system conditions                 │
├─────────────────────────────────────────────────┤
│  CloudKit (iCloud private database)             │
└─────────────────────────────────────────────────┘
```

### Migration effort: Medium-high

Need to: add CloudKit entitlement, implement CKSyncEngineDelegate, build bidirectional model mapping, add `lastKnownRecordData` to synced models, handle initial sync/migration, test extensively.

### Key resources

- [WWDC23: Sync to iCloud with CKSyncEngine](https://developer.apple.com/videos/play/wwdc2023/10188/)
- [Apple sample project](https://github.com/apple/sample-cloudkit-sync-engine)
- [Superwall tutorial](https://superwall.com/blog/syncing-data-with-cloudkit-in-your-ios-app-using-cksyncengine-and-swift-and-swiftui/)
- [Yingjie Zhao: SwiftData + CKSyncEngine](https://yingjiezhao.com/en/articles/Implementing-iCloud-Sync-by-Combining-SwiftData-with-CKSyncEngine/)
- [Christian Selig: CKSyncEngine Q&A](https://christianselig.com/2026/01/cksyncengine/)

### Verdict: Recommended

Best balance of control, reliability, and alignment with Apple's direction. Keeps our SwiftData models intact and gives us full control over conflict resolution — critical for QSO data where duplicates and data loss are unacceptable.

---

## Option 3: CloudKit Direct (CKDatabase + CKOperation)

**What it is:** Use the low-level CloudKit API directly, managing records, subscriptions, change tokens, and retry logic yourself.

### Pros

- Maximum control over every aspect
- Can use public, private, and shared databases

### Cons

- **CKSyncEngine exists specifically to avoid this** — Apple explicitly recommends CKSyncEngine over raw CKDatabase for sync use cases
- Enormous implementation effort: push notifications, subscription management, change token tracking, retry logic, system condition monitoring, account changes — all manual
- Easy to get wrong, hard to debug

### Verdict: Not recommended

CKSyncEngine handles all the plumbing that makes direct CloudKit usage painful. There's no upside to going lower-level unless you need public/shared databases (we don't).

---

## Option 4: iCloud Document Sync (NSFileCoordinator)

**What it is:** Place the SQLite database file in the app's iCloud Documents container and use `NSFileCoordinator` for file-level sync.

### Pros

- Conceptually simple — just sync a file

### Cons

- **Apple deprecated this approach for Core Data in iOS 10** — it never worked reliably for databases
- SQLite databases are not designed for file-level sync — concurrent writes from multiple devices corrupt the database
- `NSFileCoordinator` coordinates file access but cannot merge database-level changes
- No conflict resolution at the record level
- This is the approach Apple explicitly moved away from

### Verdict: Not viable

File-level sync is fundamentally incompatible with database semantics. Apple deprecated this pattern for good reason.

---

## Option 5: Point-Free SQLiteData (Third-party)

**What it is:** Replace SwiftData entirely with [SQLiteData](https://github.com/pointfreeco/sqlite-data), a third-party library from Point-Free built on GRDB (SQLite) with built-in CloudKit sync via CKSyncEngine.

### Key features

- Value types (`struct` with `@Table`) instead of reference types (`class` with `@Model`)
- Type-safe, schema-safe SQL queries (invalid queries don't compile)
- Built-in CloudKit sync and iCloud sharing
- Foreign key support with cascading deletes
- Works outside SwiftUI (UIKit, `@Observable`)
- Large binary assets automatically become `CKAsset`s

### Pros

- CloudKit sync "just works" with a few lines of code
- Better query safety than SwiftData
- Active development, well-documented
- Foreign keys and cascading deletes (SwiftData's relationship handling has known issues)
- Supports iCloud sharing (SwiftData does not)

### Cons

- **Complete rewrite of data layer** — replace all 18 `@Model` classes with `@Table` structs
- **Replace all SwiftData queries** — different query API
- **Third-party dependency** — Point-Free is reputable but it's not Apple
- **v1.0 just released** — relatively new, production track record is limited
- **Migration path** — need to migrate existing user data from SwiftData to SQLite

### Verdict: Worth watching, not recommended now

Impressive library but the migration cost is prohibitive for an existing SwiftData app. If starting fresh or if SwiftData becomes untenable, this would be a strong choice. Keep an eye on maturity.

---

## Comparison Matrix

| Criterion | Auto CloudKit | CKSyncEngine | CloudKit Direct | iCloud Docs | SQLiteData |
|---|---|---|---|---|---|
| Code change | Minimal | Medium | Large | N/A | Rewrite |
| Conflict resolution | None (server wins) | Full control | Full control | None | Built-in |
| Schema flexibility | Very limited | Full | Full | N/A | Full |
| Unique constraints | Forbidden | Allowed locally | Allowed locally | N/A | Allowed |
| Reliability | Mixed reports | Good (Apple dogfoods) | Depends on impl | Poor for DBs | New |
| Debugging | Opaque | Transparent | Transparent | N/A | Transparent |
| Apple alignment | Supported | Recommended | Supported | Deprecated pattern | Third-party |
| Model changes needed | Extensive | Minimal | Minimal | N/A | Full rewrite |
| iCloud sharing | No | Possible | Yes | No | Yes |

---

## Recommendation

**CKSyncEngine + SwiftData** (Option 2) is the recommended approach:

1. It keeps our existing SwiftData models and local persistence intact
2. It gives full control over conflict resolution — essential for QSO data integrity
3. It's Apple's recommended path for custom persistence + CloudKit
4. Schema can evolve independently of CloudKit
5. Our minimum deployment target (iOS 17+) already supports CKSyncEngine

### What we'd need to decide

- **Which models to sync** — likely QSO and LoggingSession at minimum; possibly ServicePresence, equipment lists
- **Conflict resolution strategy** — last-writer-wins? Field-level merge? Timestamp-based?
- **Whether metadata pseudo-modes sync** — per existing rules, WEATHER/SOLAR/NOTE should NOT sync
- **Migration plan** — how to handle existing devices with local-only data when sync is first enabled
- **Interaction with existing service sync** — QRZ/POTA/LoFi upload tracking (SyncRecord/ServicePresence) needs thought about whether those sync across devices too

### Existing infrastructure we can leverage

- `SettingsSyncService` — already syncs settings via iCloud KVS, pattern can inform the CKSyncEngine delegate design
- `ICloudMonitor` — already has iCloud container access; the CloudKit container setup will be similar
- `SyncService` — existing upload sync service provides patterns for change tracking and status reporting
