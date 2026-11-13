#!/bin/bash
# Xcode Cloud post-clone script
# Runs after repository is cloned, before building
# https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

set -euo pipefail

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../../.." && pwd)}"

echo "Installing Homebrew dependencies for Xcode Cloud..."

# Install SwiftLint for build-phase lint checks (if used)
brew install swiftlint

# -----------------------------------------------------------------------------
# Build CwFfi.xcframework from the Rust core.
#
# Why: CarrierWaveCore's `CwFfi` binaryTarget points at
# swift/packages/CarrierWaveCore/Vendored/CwFfi.xcframework, which is
# gitignored (363 MB, rebuilt from rust/cw-core sources). A fresh clone has no
# framework at all, so SPM resolution fails unless we build it here. Xcode
# Cloud runners don't ship Rust, so install rustup first (the build script
# adds its own Apple targets). This is the slow part of the CI build (five
# release targets including vendored OpenSSL); there is no cargo cache on
# Xcode Cloud, so it rebuilds from scratch every time.
# -----------------------------------------------------------------------------
if ! command -v cargo >/dev/null 2>&1; then
    echo "Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env"

echo "Building CwFfi.xcframework (rust/cw-core)..."
"$REPO_ROOT/rust/cw-core/scripts/build-xcframework.sh"

# The build restages CwFfi+Generated.swift. If it differs from the committed
# copy, the commit was made without regenerating the bindings — the build
# still uses a consistent pair (both just rebuilt from this commit's Rust
# source), but flag the drift so it gets committed properly.
if ! git -C "$REPO_ROOT" diff --quiet -- \
    swift/packages/CarrierWaveCore/Sources/CarrierWaveCwFfi/CwFfi+Generated.swift; then
    echo "warning: committed CwFfi+Generated.swift is stale relative to rust/cw-core" >&2
    echo "warning: run rust/cw-core/scripts/build-xcframework.sh locally and commit the result" >&2
fi
