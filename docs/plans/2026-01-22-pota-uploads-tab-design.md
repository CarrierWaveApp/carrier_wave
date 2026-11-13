# POTA Uploads Tab Design

**Date:** 2026-01-22
**Status:** Approved

## Overview

Add a new tab for POTA upload logs that shows:
1. Local upload attempts from the app with full debug metadata
2. POTA job statuses fetched from the API
3. Unified timeline correlating local attempts with POTA jobs

## Data Model

### POTAUploadAttempt (SwiftData)

Persistent record of each upload attempt from the app.

```swift
@Model
class POTAUploadAttempt {
    var id: UUID
    var timestamp: Date              // When upload was initiated
    var parkReference: String        // e.g., "K-1234"
    var qsoCount: Int                // Number of QSOs in upload
    var callsign: String             // Operator callsign used
    var location: String             // e.g., "US-CA"

    // Request details
    var adifContent: String          // Full ADIF that was sent
    var requestHeaders: [String: String]  // Headers (minus auth token)
    var filename: String             // Generated filename

    // Response details
    var httpStatusCode: Int?         // nil if network error before response
    var responseBody: String?        // Raw response
    var errorMessage: String?        // Parsed error or network error
    var success: Bool

    // Timing
    var requestDurationMs: Int?      // How long the request took

    // Correlation
    var correlatedJobId: Int?        // Linked POTA job ID (if matched)
}
```

### POTAJob (In-memory struct)

Fetched from POTA API on demand, not persisted.

```swift
struct POTAJob: Identifiable {
    let jobId: Int
    let status: POTAJobStatus
    let submitted: Date
    let processed: Date?
    let reference: String
    let parkName: String?
    let location: String?
    let totalQsos: Int               // -1 if parse failed
    let insertedQsos: Int            // -1 if processing failed
    let callsignUsed: String?
    let userComment: String?
}

enum POTAJobStatus: Int {
    case pending = 0
    case processing = 1
    case completed = 2
    case failed = 3
    case duplicate = 7
    case error = -1
}
```

## Correlation Logic

Local attempts are correlated with POTA jobs by:
- **Park reference:** Must match exactly (case-insensitive)
- **Time window:** Job `submitted` time within 5 minutes of local `timestamp`

When correlation is found, store the `jobId` in `POTAUploadAttempt.correlatedJobId`.

## Unified Timeline

### Entry Types

```swift
enum POTALogEntry: Identifiable {
    case localAttempt(POTAUploadAttempt)
    case potaJob(POTAJob)
    case correlated(attempt: POTAUploadAttempt, job: POTAJob)
}
```

### Row Display (Collapsed)

| Type | Icon | Content |
|------|------|---------|
| Local attempt (unmatched) | 📤 | timestamp, park ref, "X QSOs", status (✓ sent / ✗ failed) |
| POTA job (unmatched) | ☁️ | timestamp, park ref, park name, status badge |
| Correlated | 🔗 | timestamp, park ref, "X QSOs → Y inserted", combined status |

### Row Display (Expanded)

- **Local attempts:** ADIF content, request/response details, timing, headers
- **POTA jobs:** Full job metadata, QSO counts breakdown
- **Correlated:** Both sections combined

### Sorting

Reverse chronological by timestamp (most recent first).

## Tab Integration

### New Tab

```swift
enum AppTab: Hashable {
    case dashboard
    case logs
    case potaUploads  // NEW
    case settings
}
```

- **Label:** "POTA Uploads"
- **Icon:** `arrow.up.doc`

### Refresh Behavior

- **On tab appear:** Auto-fetch `/user/jobs` from POTA API
- **Loading state:** Show indicator during fetch
- **Manual refresh:** Button in toolbar
- **Not authenticated:** Show message prompting to authenticate in Settings

### Error Handling

- **Network errors:** Inline error banner with retry button
- **Auth errors (401):** "Session expired, re-authenticate in Settings"
- **Cache:** Keep last successful jobs fetch so list isn't empty on error

## POTAClient Changes

### New Method

```swift
func fetchJobs() async throws -> [POTAJob]
```

Calls `GET /user/jobs` and parses response.

### Upload Instrumentation

Modify `uploadActivation` to:
1. Capture start time
2. Build request as usual
3. Capture headers (redact auth token)
4. Execute request, capture timing
5. Create `POTAUploadAttempt` record
6. Save to SwiftData
7. Return result

## Files to Create/Modify

### New Files
- `FullDuplex/Models/POTAUploadAttempt.swift` - SwiftData model
- `FullDuplex/Models/POTAJob.swift` - Job struct and status enum
- `FullDuplex/Views/POTAUploads/POTAUploadsView.swift` - Main tab view
- `FullDuplex/Views/POTAUploads/POTALogEntryRow.swift` - Timeline row component

### Modified Files
- `FullDuplex/ContentView.swift` - Add new tab
- `FullDuplex/FullDuplexApp.swift` - Register POTAUploadAttempt in model container
- `FullDuplex/Services/POTAClient.swift` - Add fetchJobs(), instrument uploads
