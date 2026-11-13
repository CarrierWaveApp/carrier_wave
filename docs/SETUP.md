# Setup & Build Commands

> **Cloud/web environment (Claude Code app):** Xcode and `make` are not available. Skip all build/test/deploy commands below. Focus on code changes only — the user will build and test locally.

When running locally, NEVER run or build the app yourself. Prompt the user to do so.

## First-time setup

### CwFfi.xcframework (Rust core, required before `swift build`)

`CarrierWaveCore` depends on a binary target backed by the Rust `cw-core`
workspace via UniFFI. The XCFramework is gitignored — build it once after
cloning (and any time the Rust core changes):

```bash
cd rust/cw-core
./scripts/build-xcframework.sh
```

This will:

1. Install missing rustup targets (`aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-apple-darwin`, `x86_64-apple-darwin`).
2. Generate Swift bindings from `cw-ffi` via library-mode `uniffi-bindgen`.
3. Cross-compile a `staticlib` for each Apple slice and lipo the macOS pair.
4. Assemble `target/xcframework/CwFfi.xcframework`.
5. Stage both artifacts into `swift/packages/CarrierWaveCore/{Vendored, Sources/CarrierWaveCwFfi}`.

First run is ~6 minutes (vendored OpenSSL is built four times); subsequent
runs only rebuild what changed. If `swift build` ever errors with "no such
file or directory: Vendored/CwFfi.xcframework", re-run the script.

## Standard build commands

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
