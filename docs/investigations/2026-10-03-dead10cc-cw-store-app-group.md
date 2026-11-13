# 0xdead10cc kills from cw-store in the App Group container (CAR-350)

## Symptom

TestFlight crash feedback, mostly "crashes when I switch apps". The App Store
Connect API (`/v1/apps/{id}/betaFeedbackCrashSubmissions`, then
`/v1/betaFeedbackCrashSubmissions/{id}/crashLog`) still had logs for 13 of 143
submissions (builds 17–23, Jul–Sep 2026). Older submissions, and the newest two
(builds 23 and 26), returned 404 for the log.

## Findings

- 12/13: `EXC_CRASH (SIGKILL)`, `Termination Reason: RUNNINGBOARD 0xdead10cc`.
  Every log has a thread inside cw-store SQLite (`sqlite3_step`, `unixSync`,
  `fcntl`) when the app is suspended.
- Writes: `OffMainStoreSeam.commitQSOsWithPresence`, `FieldStore.upsertQso`,
  `CwStoreReconciler.reconcileQSOs`, `SwiftDataStoreImporter.batchedImport`,
  `ClubsSyncService.syncClubs`.
- Reads: `SOTASummitsCache.ensureLoaded` (`fetch_sota_summits_page`) and
  `AsyncServicePresenceCounts` / `StatsComputationActor`
  (`service_presence_counts`). Reads take a SHARED lock, which is enough to
  trigger the kill.
- 1/13: an iPad `UIPopoverPresentationController` exception from Share Video,
  already fixed by `e370ab6c`.

## Root cause

`cw-store.db` was placed in the shared App Group container (design decision
2026-06-14, so widgets and the watch could share it). RunningBoard kills a
suspended app that holds a file lock in an App Group container. Wrapping call
sites in `BackgroundTaskAssertion` (5acf47d4, d3349a4f, 70987eff, ee1411eb)
covered only some write paths. Nothing outside the app ever opened cw-store:
the widget reads SwiftData, and the watch can't see the phone's App Group.

## Fix

`CwStoreLocation`: on iOS the store lives in
`Application Support/CwStore/`. On the first resolve in each process, every
`cw-store.*` file is moved out of the App Group, SQLite sidecars first. If the
first move fails, the old location is still whole and the app keeps using it
until the next launch. If a later move fails, resolve throws instead of
opening a split store, and the next launch finishes the move. macOS is
unchanged.

Verified on the simulator: a real encrypted store and its recovery sidecar
seeded into the App Group were moved on launch, and the store reopened with
no orphaned copy.
