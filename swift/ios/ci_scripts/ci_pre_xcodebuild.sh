#!/bin/bash
# Xcode Cloud pre-xcodebuild script
# - Bumps CFBundleVersion to $CI_BUILD_NUMBER so every TestFlight upload is unique
# - Runs performance audit before building/testing
# https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

set -euo pipefail

# -----------------------------------------------------------------------------
# Bump the iOS build number to Xcode Cloud's build number.
#
# Why: if we ship the committed build number verbatim every time, App Store
# Connect rejects duplicate build numbers and TestFlight silently keeps serving
# the prior binary, so testers never see new code. $CI_BUILD_NUMBER is
# monotonic per Xcode Cloud workflow, so it's a safe source of truth.
#
# Where: every iOS target's CURRENT_PROJECT_VERSION resolves to
# $(CARRIER_WAVE_IOS_BUILD_NUMBER), defined once in swift/Versions.xcconfig
# (CAR-158). Rewriting that one line covers the app, watch, widgets and test
# targets. agvtool would be tidier but the project isn't configured for Apple
# Generic Versioning (no VERSIONING_SYSTEM = "apple-generic").
# -----------------------------------------------------------------------------
if [ -n "${CI_BUILD_NUMBER:-}" ]; then
    XCCONFIG="$CI_PRIMARY_REPOSITORY_PATH/swift/Versions.xcconfig"
    echo "Setting CARRIER_WAVE_IOS_BUILD_NUMBER to $CI_BUILD_NUMBER in $XCCONFIG"
    # BSD sed (macOS) in-place with empty suffix
    sed -i '' -E "s/^(CARRIER_WAVE_IOS_BUILD_NUMBER *= *)[0-9]+/\1$CI_BUILD_NUMBER/" "$XCCONFIG"
    # Verify the rewrite actually took effect; if not, fail loudly rather than
    # shipping another duplicate-build-number upload.
    if grep -qE "^CARRIER_WAVE_IOS_BUILD_NUMBER *= *$CI_BUILD_NUMBER$" "$XCCONFIG"; then
        echo "Build number bump confirmed."
    else
        echo "ERROR: Failed to rewrite CARRIER_WAVE_IOS_BUILD_NUMBER in $XCCONFIG." >&2
        exit 1
    fi
else
    echo "CI_BUILD_NUMBER not set — skipping build number bump (not running in Xcode Cloud?)"
fi

echo "Running performance audit..."

# In Xcode Cloud, CI_PULL_REQUEST_SOURCE_BRANCH is set for PR workflows.
# Check changed files for PRs, all files for branch pushes.
if [ -n "${CI_PULL_REQUEST_TARGET_BRANCH:-}" ]; then
    echo "PR detected: auditing changed files only"
    git fetch origin "$CI_PULL_REQUEST_TARGET_BRANCH" --depth=50
    CHANGED=$(git diff --name-only --diff-filter=ACM "origin/$CI_PULL_REQUEST_TARGET_BRANCH"...HEAD | grep '\.swift$' | grep -v '^Tools/' || true)
    if [ -n "$CHANGED" ]; then
        bash "$CI_PRIMARY_REPOSITORY_PATH/scripts/performance-audit.sh" $CHANGED
    else
        echo "No Swift files changed"
    fi
else
    echo "Branch push: auditing all files"
    bash "$CI_PRIMARY_REPOSITORY_PATH/scripts/performance-audit.sh"
fi
