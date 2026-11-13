---
title: "Troubleshooting"
description: "Common issues, sync debugging, error telemetry, and data repair"
weight: 20
showToc: true
---

This section helps diagnose and resolve common issues with Carrier Wave.

## Sync Issues

### QSOs Not Uploading

**Symptoms:** QSOs show "pending" status, never sync.

**Check:**
1. Network connectivity - try other apps
2. Service authentication - re-sign in if needed
3. Sync logs for specific errors

**Common causes:**
- Expired credentials
- Service temporarily down
- Rate limiting (wait and retry)

### QSOs Not Downloading

**Symptoms:** Contacts logged elsewhere don't appear.

**Check:**
1. Service supports downloads (POTA is upload-only)
2. Time since last sync
3. Manual sync trigger (pull to refresh)

### Sync Conflicts

**Symptoms:** Duplicate QSOs, mismatched data.

**Resolution:**
1. Let sync complete fully
2. Manually delete duplicates if needed
3. The most recent data usually wins

## Sync Debugging Tools

Carrier Wave provides several tools for diagnosing sync issues:

### Sync Debug Log

Enable detailed sync logging at **Settings -> Advanced -> Sync Debugging**:

- **Request logs** - Full HTTP request and response payloads for each service
- **Response parsing** - How each response was interpreted
- **Error details** with stack traces and error codes
- **Performance timing** - Duration of each sync phase
- **Action Required** markers (purple) highlight issues needing your attention

### Sharing Sync Logs

From the sync debug screen:

1. Tap **Share Sync Log**
2. The log is compiled as a plain text file
3. Share via the iOS share sheet (email, Messages, save to Files)
4. **Sensitive data warning** - Logs may contain callsigns and service URLs; review before sharing publicly

### Per-Service Sync Reports

Each service generates a visual sync report (accessible from the Home service cards):

- **Funnel visualization** showing data flow: Fetched -> Validated -> Applied -> Uploaded
- **Phase status badges** (success, warning, error)
- **Record counts** at each stage
- **Reconciliation details** for POTA job matching

### Sync Timeline

The sync timeline shows a chronological view of all sync events:

- **Timestamps** for each sync operation
- **Service identifier** showing which service was involved
- **Outcome** (success, partial, error)
- **Duration** of each operation

## Upload Error Telemetry

Carrier Wave collects anonymized error data to help diagnose service-wide issues:

### What's Collected

- **Error category** (authentication, network, validation, server error)
- **Service and endpoint** identifier
- **Timestamp** and retry count
- **HTTP status code** (for network errors)

### What's NOT Collected

- QSO content or personal data
- Callsigns or operator information
- Credentials or authentication tokens

### Viewing Telemetry

View error telemetry in **Settings -> Advanced -> Upload Error Log**:

- Error counts by service and category
- Recent error timeline
- Error rate trends

### Disabling Telemetry

Toggle off **Upload Error Telemetry** in Settings -> Advanced. This stops all error data collection.

## Data Repair Services

Carrier Wave includes several automated and manual repair tools for maintaining data integrity.

### Automated Repairs (Run During Sync)

These repairs execute automatically as part of the sync process:

- **Callsign whitespace repair** - Normalizes callsign spacing and removes leading/trailing whitespace
- **QRZ isSubmitted state repair** - Corrects sync status flags that may have become inconsistent
- **Orphan repair** - Fixes dangling service presence records (e.g., a QSO marked as "present" on a service that has no record of it)
- **POTA presence repair** - Rebuilds park activation tracking from actual POTA job data

### One-Time Manual Repairs

Available in **Settings -> Advanced -> One-Time Repairs**:

| Repair | Description |
|--------|-------------|
| **WPM backfill** | Compute WPM for historical CW QSOs that are missing speed data |
| **Conditions backfill** | Fetch solar conditions for sessions that were logged without conditions data |
| **Park ref extraction** | Re-parse POTA park references from QSO notes and comments |
| **K-index repair** | Correct invalid K-index values (e.g., values outside 0-9 range) |
| **PHONE/SSB merge** | Consolidate legacy "PHONE" mode records to "SSB" |
| **Activity log QSO flagging** | Re-link QSOs to activity log items |

Each repair shows a progress indicator and result count when complete.

### Force Re-Download

When sync state is severely inconsistent, use Force Re-Download per service:

1. Go to **Dashboard**
2. Tap the service card
3. Tap **Force Re-Download**
4. Confirm

This downloads the complete dataset from the service and rebuilds local state. It does not delete local QSOs that aren't on the service.

## Authentication Issues

### "Invalid Credentials" Error

**For username/password services (QRZ, LoTW, eQSL):**
1. Verify credentials on the service's website
2. Check for special characters that might need escaping
3. Re-enter credentials in Carrier Wave

**For OAuth services (POTA, HAMRS):**
1. Tap "Sign Out"
2. Sign in again via the web flow
3. Complete the OAuth authorization

### "Session Expired"

OAuth tokens expire. When prompted:
1. Tap to re-authenticate
2. Complete the sign-in flow
3. Sync resumes automatically

## App Performance

### Slow Dashboard

**Cause:** Large QSO database, statistics computing.

**Mitigation:**
- Statistics compute in background
- Wait for progress indicator to complete
- Consider archiving very old QSOs

### Battery Drain

**Cause:** Frequent sync, GPS updates.

**Check:**
1. Reduce sync frequency in Settings
2. Disable location services when not needed
3. Background App Refresh settings

## Viewing Sync Logs

For detailed sync troubleshooting:

1. Go to **Settings > Advanced > Sync Debugging**
2. Enable verbose logging
3. Reproduce the issue
4. View logs showing:
   - API requests and responses
   - Error messages
   - Timing information

Logs can be exported for support.

## Submitting Bug Reports

When you encounter a bug:

1. Go to **Settings > Bug Report**
2. Describe the issue
3. Tap **Generate Report**

The report includes:
- Device model and iOS version
- App version
- Recent error logs
- Database statistics (no personal QSO data)

**Not included:** Your actual QSO data, credentials, or personal information.

Reports can be:
- Emailed to support
- Copied to clipboard
- Saved to Files

## Common Error Messages

| Error | Meaning | Resolution |
|-------|---------|------------|
| "Network unavailable" | No internet connection | Check WiFi/cellular |
| "Authentication failed" | Bad credentials | Re-enter password |
| "Rate limited" | Too many requests | Wait, then retry |
| "Server error" | Service-side issue | Try again later |
| "Invalid ADIF" | Malformed upload data | Check QSO fields |
| "Duplicate activation" | POTA already has this activation | Check date/park reference |
| "Maintenance window" | POTA servers offline | Wait until 0400 UTC |
| "Connection timeout" | WebSDR receiver unresponsive | Try a different receiver |

## Data Recovery

### Accidental Deletion

Deleted QSOs are soft-deleted (hidden) and can be recovered:

1. Go to **Settings -> Advanced -> Hidden QSOs**
2. Find the deleted QSO
3. Tap **Restore**

If permanently deleted:
- If synced to cloud services, data exists there
- iCloud backup may contain older data
- Re-download from LoFi or QRZ using Force Re-Download

### Database Corruption

Rare, but if the app won't open:
1. Try force-quitting and reopening
2. Restart device
3. Reinstall app (synced data re-downloads)
4. Restore from iCloud backup as last resort

## Getting Help

If troubleshooting doesn't resolve your issue:

1. Check for app updates
2. Search existing bug reports
3. Submit detailed bug report with logs
4. Contact support with report reference

## See Also

- [Settings & Services](/reference/settings/) - Service configuration
- [Service Sync Flow](/reference/sync-flow/) - How sync works
- [iCloud Sync](/reference/icloud/) - Device sync issues
