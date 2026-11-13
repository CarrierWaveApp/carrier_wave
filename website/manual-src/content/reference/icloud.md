---
title: "iCloud Sync"
description: "Cross-device synchronization via iCloud"
weight: 7
showToc: true
---

iCloud Sync keeps your Carrier Wave data synchronized across all your Apple devices.

## What Syncs

### Synced via iCloud

- **QSO database** - All your logged contacts
- **App settings** - Preferences and configuration
- **Callsign notes** - Custom notes files
- **WebSDR favorites** - Saved receiver list
- **Equipment profiles** - Station configurations
- **Community data** - Friends, challenge progress

### Not Synced

- **Service credentials** - Stored in device Keychain (you'll need to sign in on each device)
- **Cached data** - Callsign lookups, temporary files
- **WebSDR recordings** - Audio files remain on the recording device (too large for CloudKit)
- **Session photos** - Stored locally (available via iCloud Drive backup mirror if enabled)

## Sync Engine

Carrier Wave offers two iCloud sync engines. You can switch between them at **Settings → iCloud → Sync Engine**.

### CKSyncEngine (Default)

Apple's built-in CKSyncEngine framework:

- **Automatic conflict detection** at the record level
- **Efficient delta sync** - only changed records are transferred
- **Background sync** - updates happen without user intervention
- **Offline queue** - changes accumulate while offline and sync when connectivity returns

### Journal Sync Engine

An alternative sync engine that batches changes into JSON journal entries and uses SQLite snapshots for initial device setup:

- **Snapshot bootstrap** - new devices download a single SQLite snapshot instead of syncing thousands of individual records, dramatically reducing first-sync time
- **Batched journals** - changes are grouped into journal entries (up to 100 operations per CloudKit record) for more efficient transfer
- **Automatic snapshots** - a fresh snapshot is uploaded every 6 hours so new devices always start from a recent state
- **Cross-device setting** - toggling the sync engine on one device propagates the change to all devices via iCloud Key-Value Store

The journal engine is ideal for users with large QSO databases (10,000+) where CKSyncEngine's per-record sync can be slow on initial setup.

### Synced Entities

The following data model entities are synced via CKSyncEngine:

| Entity | Sync Behavior |
|--------|---------------|
| **QSO records** | Full bidirectional sync with field-level merge |
| **Sessions** | Metadata synced; QSOs linked by session ID |
| **Equipment profiles** | Full sync |
| **App preferences** | Last-write-wins for scalar values |
| **Callsign notes sources** | URL and configuration synced; content fetched independently per device |
| **WebSDR favorites** | Full sync |
| **Community friends** | Friend list synced; server data re-fetched per device |
| **Challenge participation** | Enrollment synced; progress computed locally |

## Enabling iCloud Sync

1. Open **Settings**
2. Scroll to **iCloud**
3. Toggle **Enable iCloud Sync**

Requirements:
- Signed into iCloud on your device
- Carrier Wave enabled in iCloud settings

## How It Works

Carrier Wave uses CloudKit to sync data:

1. **Local changes** are pushed to iCloud
2. **Remote changes** are pulled when detected
3. **Merge** combines changes from multiple devices

Sync happens automatically in the background.

## Conflict Resolution Strategies

When the same record is modified on multiple devices, Carrier Wave applies different strategies depending on the data type:

### Field-Level Merge (QSOs)

For QSO records, conflicts are resolved at the field level rather than the whole-record level:

- Each field's modification timestamp is tracked independently
- The most recently modified value for each field wins
- This prevents a frequency correction on one device from overwriting a notes edit on another device

### Union Merge (Collections)

For collection-type data (park references, equipment lists, callsign notes sources):

- Items from both versions are combined (union)
- Duplicates are detected and removed
- No data is lost from either device

### Last-Write-Wins (LWW)

For scalar settings and preferences:

- The most recent modification timestamp determines the winner
- The losing value is discarded
- Appropriate for settings where only one value can be correct (theme, default tab, etc.)

## iCloud Drive Backup Mirroring

In addition to CKSyncEngine sync, Carrier Wave can mirror your data to iCloud Drive as a backup:

- **ADIF export** of your complete QSO log written periodically to iCloud Drive
- **Settings snapshot** in JSON format
- **Accessible from Finder/Files** for manual recovery or transfer to other software

Enable this in Settings -> Backup & Restore -> iCloud Drive Backup Mirroring.

This provides an additional safety net beyond CloudKit sync, as iCloud Drive files are visible and downloadable from any device.

## Multi-Device Scenarios

### Logging on iPhone, Viewing on iPad

1. Log QSOs on your iPhone in the field
2. Open Carrier Wave on your iPad at home
3. QSOs appear automatically (may take a few moments)

### Simultaneous Logging

If you log on two devices simultaneously:
- Both QSOs are kept (no data loss)
- Duplicates may occur if logging the same contact on both

## Troubleshooting

### Sync Not Working

1. Verify iCloud is enabled in iOS Settings
2. Check Carrier Wave is enabled in iCloud settings
3. Ensure network connectivity
4. Pull to refresh in the app

### Data Not Appearing

iCloud sync can take time, especially:
- First sync with large databases
- Poor network conditions
- iCloud service issues

Check Apple's System Status page for iCloud outages.

### Duplicate QSOs

If duplicates appear after sync:
1. Check if logged on multiple devices
2. Use Logs search to find duplicates
3. Delete extras manually

## Recovery Mode

If the SwiftData database fails to open at launch, Carrier Wave now enters **Recovery Mode** instead of silently resetting. The broken database file is preserved in place (and copied to `Library/EmergencyBackup/`), an in-memory fallback container is loaded so the app stays usable, and a full-screen recovery view shows:

- What happened — timestamp + error from `Library/ContainerInitFailure.json`
- The QSO count of the most recent backup snapshot
- Three explicit actions:
  - **Restore from this backup** — stages a `BackupService` restore and exits the app to apply on next launch
  - **Send diagnostics** — opens the diagnostic-bundle share sheet
  - **Reset to empty database** — typed-confirmation gate (type `RESET` to enable the destructive button)

You're locked into Recovery Mode across launches until one of the three actions is picked. Triggered by AC9M's data-loss incident.

## Clear All QSOs

The **Clear All QSOs** button in Settings deletes every {{< term "QSO" >}} from this device. As of 1.92.0, if iCloud QSO Sync is enabled, your logbook is **re-downloaded from iCloud immediately** after the wipe — the same way a fresh install of the app would restore it. The status bar shows "Restoring from iCloud..." while the snapshot comes back and full-journal replay finishes.

If you want a clean wipe with **no** restore (for example, before handing the device off, or to start fresh while keeping iCloud's copy for another device), disable iCloud QSO Sync first, then Clear All QSOs. Re-enabling sync afterward will pull the cloud copy back down at that point.

## Storage

iCloud data counts against your iCloud storage quota. A typical ham's log uses minimal space (a few MB for thousands of QSOs).

## Privacy

Your QSO data is stored in your private iCloud container:
- Only accessible by your Apple ID
- Encrypted in transit and at rest
- Not shared with Apple or third parties

## Disabling Sync

To stop syncing:

1. Open **Settings**
2. Toggle off **Enable iCloud Sync**

Data remains on each device but no longer synchronizes.

**Warning:** Disabling sync doesn't delete data from iCloud. To fully remove, delete the app data in iOS Settings > [Your Name] > iCloud > Manage Storage.

## See Also

- [Settings & Services](/reference/settings/) - Other configuration options
- [Service Sync Flow](/reference/sync-flow/) - Cloud service sync
- [Troubleshooting](/reference/troubleshooting/) - Common issues
