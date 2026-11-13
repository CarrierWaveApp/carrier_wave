#!/usr/bin/env bash
# Build CwFfi.xcframework — the Apple-platform consumable artifact of cw-ffi.
#
# Slices: ios-arm64 (device), ios-arm64_x86_64-simulator (universal),
#         macos-arm64_x86_64 (universal).
# Each slice carries the UniFFI-generated C header + module.modulemap; the
# accompanying Swift glue is in target/generated/swift/cw_ffi.swift.
#
# Why staticlib not cdylib: iOS apps can't ship arbitrary dylibs, and the
# vendored OpenSSL link only resolves as a static library on Apple targets.
#
# Outputs:
#   target/xcframework/CwFfi.xcframework
#   target/generated/swift/cw_ffi.swift     (used by the Swift consumer)
set -euo pipefail
cd "$(dirname "$0")/.."

TARGETS=(
    aarch64-apple-ios
    aarch64-apple-ios-sim
    x86_64-apple-ios
    aarch64-apple-darwin
    x86_64-apple-darwin
)

for t in "${TARGETS[@]}"; do
    if ! rustup target list --installed | grep -qx "$t"; then
        echo "→ installing rustup target $t"
        rustup target add "$t"
    fi
done

# Bindings + bindgen (provides the .swift, .h, .modulemap in target/generated/swift)
./scripts/generate-swift-bindings.sh

echo "→ building staticlib for each Apple target"
for t in "${TARGETS[@]}"; do
    cargo rustc -p cw-ffi --lib --target "$t" --release --crate-type staticlib
done

XC=target/xcframework
BUILD="$XC/build"
rm -rf "$XC"
mkdir -p "$BUILD/macos" "$BUILD/sim" "$BUILD/headers"

echo "→ lipo'ing macOS arm64 + x86_64"
lipo -create \
    target/aarch64-apple-darwin/release/libcw_ffi.a \
    target/x86_64-apple-darwin/release/libcw_ffi.a \
    -output "$BUILD/macos/libcw_ffi.a"

# Both arm64-sim and x86_64-sim are the same XCFramework variant (ios-simulator),
# so -create-xcframework rejects them as separate -library args; they must be one
# fat lib. This is what lets an Intel/x86_64 CI runner link the simulator slice.
echo "→ lipo'ing iOS simulator arm64 + x86_64"
lipo -create \
    target/aarch64-apple-ios-sim/release/libcw_ffi.a \
    target/x86_64-apple-ios/release/libcw_ffi.a \
    -output "$BUILD/sim/libcw_ffi.a"

# Headers dir: each XCFramework slice gets a copy. UniFFI emits the modulemap
# as `cw_ffiFFI.modulemap`, but `xcodebuild -create-xcframework` expects it
# named `module.modulemap` inside the per-slice Headers/ dir.
cp target/generated/swift/cw_ffiFFI.h "$BUILD/headers/"
cp target/generated/swift/cw_ffiFFI.modulemap "$BUILD/headers/module.modulemap"

echo "→ assembling XCFramework"
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libcw_ffi.a \
    -headers "$BUILD/headers" \
    -library "$BUILD/sim/libcw_ffi.a" \
    -headers "$BUILD/headers" \
    -library "$BUILD/macos/libcw_ffi.a" \
    -headers "$BUILD/headers" \
    -output "$XC/CwFfi.xcframework"

# Stage artifacts into the consuming SPM package so `swift build` resolves
# without manual intervention. Both destinations are gitignored.
CWC="$(cd ../../swift/packages/CarrierWaveCore && pwd)"
rm -rf "$CWC/Vendored/CwFfi.xcframework"
mkdir -p "$CWC/Vendored"
cp -R "$XC/CwFfi.xcframework" "$CWC/Vendored/"

mkdir -p "$CWC/Sources/CarrierWaveCwFfi"
cp target/generated/swift/cw_ffi.swift "$CWC/Sources/CarrierWaveCwFfi/CwFfi+Generated.swift"

echo ""
echo "✓ CwFfi.xcframework → $XC/CwFfi.xcframework"
echo "✓                   → $CWC/Vendored/CwFfi.xcframework (staged for SPM)"
echo "✓ Swift bindings    → target/generated/swift/cw_ffi.swift"
echo "✓                   → $CWC/Sources/CarrierWaveCwFfi/CwFfi+Generated.swift (staged)"
