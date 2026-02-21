# Setup & Build Commands

> **Cloud/web environment (Claude Code app):** Xcode and `make` are not available. Skip all build/test/deploy commands below. Focus on code changes only — the user will build and test locally.

When running locally, NEVER run or build the app yourself. Prompt the user to do so.

```bash
# Build for simulator
make build

# Build for device
make build-device

# Run tests
make test

# List available devices
make devices

# Install app on device (requires build-device first)
make install

# Launch app on device
make launch

# Build, install, and launch on device
make deploy
```

## Required Xcode Configuration

### 1. iCloud Entitlements

In Xcode, select the CarrierWave target, go to "Signing & Capabilities", and add:

1. **iCloud** capability
   - Check "iCloud Documents"
   - Add container: `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`

2. **Background Modes** capability
   - Check "Background fetch"

### 2. Info.plist Entries (for ADIF file handling)

Add Document Types to support opening .adi and .adif files:

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>ADIF Log File</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Default</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.amateur-radio-log</string>
        </array>
    </dict>
</array>
```
