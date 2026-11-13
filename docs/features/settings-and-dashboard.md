# Settings and Dashboard Architecture

This document describes the design philosophy and structure for the Settings pane and Dashboard service cards.

## Design Principles

### Consistency First

All sync sources follow the same UI patterns regardless of their underlying authentication mechanism. Users should have a predictable experience when configuring any service.

### NavigationLink Pattern

Every sync source in Settings uses a NavigationLink to a dedicated settings view. This provides:

- Consistent navigation behavior (swipe back, navigation title)
- Room for service-specific options and status information
- Clear separation between the settings list and individual service configuration

### Status Indicators

Connected services display their status consistently:

- **Green checkmark** (`checkmark.circle.fill`) - Service is connected and ready
- **Orange clock** (`clock`) - Service is pending (e.g., awaiting email confirmation)
- **Callsign display** - When available, show the user's callsign for the service

## Settings Pane Structure

### Sync Sources Section

Each sync source follows this pattern in `SettingsMainView`:

```swift
NavigationLink {
    ServiceSettingsView()
} label: {
    Label("Service Name", systemImage: "icon.name")
}
```

Individual settings views (`QRZSettingsView`, `LoFiSettingsView`, `HAMRSSettingsView`, `POTASettingsView`) handle:

1. **Not Configured State**
   - Brief description of the service
   - Setup form or connect button
   - Link to get credentials (if applicable)

2. **Configured/Connected State**
   - Status section with green checkmark and callsign
   - Logout/disconnect button (destructive style)

3. **Intermediate States** (when applicable)
   - Pending email confirmation (LoFi)
   - Subscription inactive errors (HAMRS)

### Authentication Patterns

While the UI is consistent, services use different authentication mechanisms:

| Service | Auth Method | Credentials |
|---------|-------------|-------------|
| QRZ | API Key | Single key from QRZ settings |
| POTA | OAuth (WebView) | User logs in via pota.app |
| LoFi | Email verification | Callsign + email, then confirm link |
| HAMRS | API Key | Single key from hamrs.app |
| iCloud | System | Automatic via iCloud container |

All credentials are stored in the iOS Keychain, never in SwiftData.

## Dashboard Service Cards

### Layout

Service cards are arranged in a 2-column grid:

```
┌─────────────┐ ┌─────────────┐
│  Ham2K LoFi │ │     QRZ     │
└─────────────┘ └─────────────┘
┌─────────────┐ ┌─────────────┐
│    POTA     │ │    HAMRS    │
└─────────────┘ └─────────────┘
┌─────────────┐
│   iCloud    │
└─────────────┘
```

### Card Structure

Each service card displays:

**Header Row:**
- Service name (left)
- Status indicator + callsign (right)
  - Green checkmark when connected
  - Orange "Pending" for intermediate states
  - "Not configured" text when not set up

**Body (when configured):**
- Sync count: "✓ X QSOs synced"
- Pending count (if service supports upload): "⏱ Y pending sync"
- Sync result message after individual sync

**Body (when not configured):**
- NavigationLink button to configure the service

**Debug Mode Additions:**
- Individual sync button per service
- Menu with service-specific actions (clear data, disconnect, etc.)

### Sync Status Overlay

During global sync, cards show an animated overlay indicating the current phase:

- **Blue** - Downloading from service
- **Green** - Uploading to service
- **Orange** - Processing/merging data

### Read-Only vs Read-Write Services

Some services only support downloading QSOs:

| Service | Download | Upload |
|---------|----------|--------|
| QRZ | ✓ | ✓ |
| POTA | ✓ | ✓ |
| LoFi | ✓ | ✗ (read-only) |
| HAMRS | ✓ | ✗ (read-only) |
| iCloud | ✓ (import) | ✗ |

Read-only services don't show "pending sync" counts since there's nothing to upload.

## Adding a New Sync Source

To add a new sync source:

1. **Create the client** (`Services/NewServiceClient.swift`)
   - Use `actor` for thread safety
   - Store credentials in Keychain via `KeychainHelper`
   - Implement `isConfigured` property
   - Add `configure()` and `clearCredentials()` methods

2. **Add to Types.swift**
   - Add case to `ServiceType` enum
   - Set `supportsUpload` appropriately
   - Add case to `ImportSource` enum

3. **Create settings view** (`Views/Settings/NewServiceSettingsView.swift`)
   - Follow the pattern of existing settings views
   - Include status section when configured
   - Include setup section when not configured
   - Add logout button

4. **Add to SettingsMainView**
   - Add NavigationLink in the Sync Sources section

5. **Add dashboard card** (`Views/Dashboard/DashboardView.swift`)
   - Add client instance
   - Add state variable for sync result
   - Add card to the grid layout
   - Add card computed property following existing patterns
   - Add sync and clear action methods

6. **Integrate with SyncService**
   - Add download logic to `downloadFromAllSources()`
   - Add upload logic to `uploadToAllDestinations()` (if applicable)
   - Add single-service sync method
