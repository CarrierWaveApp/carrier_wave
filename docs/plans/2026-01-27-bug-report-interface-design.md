# Bug Report Interface Design

## Overview

Add a bug report interface that allows users to email bug reports with app context to jaysvana@gmail.com.

## Entry Points

1. **Settings button** - "Report a Bug" in the About section of Settings
2. **Shake gesture** - Shake device anywhere in the app to present the bug report sheet

## User Interface

A modal sheet containing:

1. **Category picker** - Segmented control or picker
   - Options: Sync Issue, UI Problem, Crash, Other
   - Default: Other

2. **Description field** - Multi-line text field
   - Placeholder: "Describe what happened..."

3. **Screenshot section**
   - "Attach Screenshot" button with options:
     - Take Screenshot (captures screen behind sheet)
     - Choose from Photos (PhotosPicker)
   - Preview thumbnail with remove option

4. **Info summary** - Collapsed "Report includes..." showing what's auto-collected

5. **Debug log preview** - Expandable section (only visible when debug mode enabled)

6. **Submit button** - "Send Report"

## Auto-Collected Information

Always collected and included in email:

| Field | Source |
|-------|--------|
| App version | Bundle.main MARKETING_VERSION |
| Build number | Bundle.main CURRENT_PROJECT_VERSION |
| iOS version | UIDevice.current.systemVersion |
| Device model | utsname/machine identifier mapped to friendly name |
| QRZ configured | QRZClient.hasApiKey() |
| POTA configured | POTAAuthService.isAuthenticated |
| LoFi configured | LoFiClient has credentials |
| LoTW configured | LoTWClient.hasCredentials() |
| HAMRS configured | HAMRSClient has credentials |
| iCloud status | ICloudMonitor state |
| Debug mode | AppStorage debugMode value |
| Sync debug logs | Last 50 lines or 24 hours of SyncDebugLog entries |

**Visibility:**
- Basic info always visible in collapsed summary
- Sync debug logs only shown in UI when debug mode is enabled
- All info always sent in report regardless of visibility

## Email Format

**To:** jaysvana@gmail.com

**Subject:** `[Carrier Wave Bug] {Category} - v{version}`

**Body:**
```
Bug Report - Carrier Wave

Category: {category}

Description:
{user description}

---
App Information:
- Version: {version} ({build})
- iOS: {ios version}
- Device: {device model}
- Debug Mode: {on/off}

Service Status:
- QRZ: {configured/not configured}
- POTA: {configured/not configured}
- LoFi: {configured/not configured}
- LoTW: {configured/not configured}
- HAMRS: {configured/not configured}
- iCloud: {status}

Recent Sync Log:
{last 50 lines of sync debug log}
```

**Attachment:** Screenshot (JPEG) if provided

## Fallback Behavior

When `MFMailComposeViewController.canSendMail()` returns false:

1. Copy formatted report text to clipboard
2. Show alert: "Report copied to clipboard! Please email it to jaysvana@gmail.com"
3. If screenshot attached, save to temp file with note about manual attachment

## File Structure

### New Files

| File | Purpose |
|------|---------|
| `CarrierWave/Views/Settings/BugReportView.swift` | Main bug report sheet UI |
| `CarrierWave/Services/BugReportService.swift` | Collects device/app info, formats report, handles mail/clipboard |

### Modified Files

| File | Change |
|------|--------|
| `SettingsView.swift` | Add "Report a Bug" NavigationLink in aboutSection |
| `ContentView.swift` | Add shake gesture detection |

## Implementation Notes

### Shake Gesture Detection

Use `NotificationCenter` to observe `UIDevice.deviceDidShakeNotification` or subclass UIWindow to detect motion events globally. Debounce to prevent double-triggers.

### Screenshot Capture

For "Take Screenshot":
- Capture the key window's root view at the moment the user taps "Report a Bug"
- Store temporarily until report is sent or dismissed

### Mail Composer

Use `MFMailComposeViewController` wrapped in `UIViewControllerRepresentable`. Handle delegate callbacks for sent/cancelled/failed states.

### Privacy

Footer note in the sheet: "Report includes recent sync activity which may contain callsigns."
