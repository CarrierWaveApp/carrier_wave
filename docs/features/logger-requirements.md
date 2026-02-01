# Logger Requirements

This document defines the requirements for the logger feature. **Every change to the logger must be checked for compliance with these requirements.**

## 1. Interface Performance

**The logger interface must be performant and not busy.**

- The UI must remain responsive during all operations
- Avoid unnecessary animations, transitions, or visual noise
- Keep the interface clean and focused on the core logging workflow
- Background operations (lookups, syncs) must not block the UI
- Minimize re-renders and unnecessary state updates

### 1a. Instant QSO Logging

**QSO submission must be instant—users should never wait for metadata.**

- When the user taps "Log QSO", the QSO is saved immediately to SwiftData
- The form clears and is ready for the next contact within milliseconds
- All metadata enrichment happens in the background after the QSO is saved:
  - QRZ callsign lookups (name, grid, location, license class)
  - Polo notes lookup
  - Previous contact count calculation
  - POTA park-to-park detection (checking active spots)
- The QSO list should show progressive loading states for pending metadata
- If the user has pre-fetched callsign info (displayed in the callsign card), use it immediately
- Background enrichment only runs for fields not already populated at log time

## 2. Log Deletion Policy

**Logs must never be deleted—only hidden.**

- QSO records are never removed from the database
- Use a `hidden` flag or equivalent to mark logs as not visible
- Hidden logs remain available for data integrity and potential recovery

## 3. Hidden Log Display

**We never show hidden logs by default anywhere in the app.**

- All list views, statistics, and exports should exclude hidden logs by default
- No UI surfaces hidden logs unless explicitly requested (e.g., an admin/debug view)

## 4. Data Source Querying

**Data sources are always queried regardless of success of other queries.**

- When fetching callsign data from multiple sources (QRZ, HamDB, etc.), query all sources
- A failure in one source must not prevent querying other sources
- Aggregate results from all successful queries

## 5. Data Source Ordering

**Data sources should always be sorted the same for every QSO and display tooltip.**

- Maintain a consistent, deterministic order when displaying data source results
- The sort order must be identical across:
  - QSO detail views
  - Tooltips
  - Any other UI that shows data source information

## 6. Data Source Persistence

**Data source results should be saved to logger entries (all available data).**

- When a QSO is logged, persist all data retrieved from data sources
- Store the complete response from each source that returned data
- This ensures historical accuracy even if external sources change or become unavailable
- Saved data should include: name, location, grid, license class, notes, and any other available fields

## 7. POTA-Specific Rules

### 7a. Same Band/Date Duplicate Warning

**Repeat callsigns on the same band and UTC date should be warned of and not allowed.**

- When logging a QSO, check for existing QSOs with:
  - Same callsign
  - Same band
  - Same UTC date
- If a duplicate is found:
  - Display a warning to the user
  - Prevent the QSO from being saved

### 7b. Different Band Highlighting

**Callsigns on different bands but the same UTC date should be highlighted.**

- When logging a QSO, check for existing QSOs with:
  - Same callsign
  - Different band
  - Same UTC date
- If found, highlight this in the UI (informational, not blocking)
- This helps activators know they've already worked this station on another band

---

## Compliance Checklist

When modifying logger code, verify:

- [ ] UI remains responsive and uncluttered (requirement 1)
- [ ] QSO logging is instant with no blocking operations (requirement 1a)
- [ ] No code path deletes QSO records (requirement 2)
- [ ] Default queries exclude hidden logs (requirement 3)
- [ ] All data sources are queried independently (requirement 4)
- [ ] Data source display order is consistent (requirement 5)
- [ ] All data source results are persisted to QSO records (requirement 6)
- [ ] POTA duplicate detection warns and blocks same band/date (requirement 7a)
- [ ] POTA different-band same-date contacts are highlighted (requirement 7b)
