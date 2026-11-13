#!/usr/bin/env bash
# check-versions.sh — verify every place a release version is written agrees.
#
# Source of truth for the Apple apps is swift/Versions.xcconfig (CAR-158):
#   CARRIER_WAVE_IOS_MARKETING_VERSION / CARRIER_WAVE_IOS_BUILD_NUMBER
#   CW_SWEEP_MARKETING_VERSION         / CW_SWEEP_BUILD_NUMBER
# Android is versioned independently in android/app/build.gradle.kts.
#
# For each platform this script requires strict equality between:
#   - the xcconfig (or build.gradle.kts) marketing version,
#   - the newest WhatsNewEntry.version for that platform in
#     swift/packages/CarrierWaveData/.../WhatsNewCatalog+*.swift, and
#   - the newest released CHANGELOG.md heading for that platform.
# It also fails if a MARKETING_VERSION / CURRENT_PROJECT_VERSION literal is
# hardcoded in the iOS pbxproj or the macOS project.yml (the xcconfig would be
# silently overridden), or if a value in the xcconfig is malformed.
#
# Why equality and not "CHANGELOG may be ahead": a release bump is one commit
# that edits the xcconfig, renames [Unreleased], and prepends the What's New
# entry. Between releases all three already agree, so any mismatch is drift.
#
# Usage: scripts/check-versions.sh   (exit 0 = consistent, 1 = drift)
# Runs from scripts/pre-commit.sh (when a version-bearing file is staged),
# scripts/release.sh, and .github/workflows/ci.yml.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

XCCONFIG="swift/Versions.xcconfig"
PBXPROJ="swift/ios/CarrierWave.xcodeproj/project.pbxproj"
PROJECT_YML="swift/macos/project.yml"
GRADLE="android/app/build.gradle.kts"
CHANGELOG="CHANGELOG.md"
CATALOG_DIR="swift/packages/CarrierWaveData/Sources/CarrierWaveData/Utilities"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=0
fail() {
    echo -e "${RED}FAIL${NC} $*" >&2
    FAILED=1
}
ok() {
    echo -e "${GREEN}ok${NC}   $*"
}

# ---------------------------------------------------------------------------
# Readers
# ---------------------------------------------------------------------------

# xcconfig_value NAME → value of `NAME = value` in swift/Versions.xcconfig
xcconfig_value() {
    sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]/]+).*/\1/p" "$XCCONFIG" | head -n1
}

# newest_whats_new_version PLATFORM (iOS|macOS) → version of the first entry in
# catalog order (Recent → Archive → ArchiveOlder → ArchiveOldest → ArchiveSweep, newest-first)
# whose `platforms` contains the platform. An entry with no `platforms:` line
# uses the WhatsNewEntry default of [.iOS, .macOS].
newest_whats_new_version() {
    local platform="$1"
    cat "$CATALOG_DIR/WhatsNewCatalog+Recent.swift" \
        "$CATALOG_DIR/WhatsNewCatalog+Archive.swift" \
        "$CATALOG_DIR/WhatsNewCatalog+ArchiveOlder.swift" \
        "$CATALOG_DIR/WhatsNewCatalog+ArchiveOldest.swift" \
        "$CATALOG_DIR/WhatsNewCatalog+ArchiveSweep.swift" \
    | awk -v want="$platform" '
        # A new entry starts at `WhatsNewEntry(`; flush the previous one.
        /WhatsNewEntry\(/ {
            if (version != "" && matches(platforms, want)) { print version; found = 1; exit }
            version = ""; platforms = ""
        }
        /^[[:space:]]*version: "/ {
            v = $0; sub(/^[[:space:]]*version: "/, "", v); sub(/".*$/, "", v); version = v
        }
        /^[[:space:]]*platforms: \[/ {
            p = $0; sub(/^[[:space:]]*platforms: \[/, "", p); sub(/\].*$/, "", p); platforms = p
        }
        END {
            if (!found && version != "" && matches(platforms, want)) print version
        }
        function matches(p, w) {
            if (p == "") return 1               # default platforms = both
            return index(p, "." w) > 0
        }
    '
}

# newest_changelog_version TRACK (ios|sweep|android) → x.y.z of the newest
# released heading on that track. Unreleased headings are skipped.
#   ios     : first `## [x.y.z]` before `# Android`
#   sweep   : first `## [CW Sweep x.y.z]` (or legacy `## CW Sweep [x.y.z]`)
#   android : first `## [x.y.z]` after `# Android`
newest_changelog_version() {
    case "$1" in
        ios)
            awk '/^# Android/ { exit }
                 /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ { gsub(/\[|\]/, "", $2); print $2; exit }' "$CHANGELOG"
            ;;
        sweep)
            awk '/^# Android/ { exit }
                 /^## \[CW Sweep [0-9]+\.[0-9]+\.[0-9]+\]/ { gsub(/\[|\]/, "", $4); print $4; exit }
                 /^## CW Sweep \[[0-9]+\.[0-9]+\.[0-9]+\]/ { gsub(/\[|\]/, "", $4); print $4; exit }' "$CHANGELOG"
            ;;
        android)
            awk '/^# Android/ { in_android = 1; next }
                 in_android && /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ { gsub(/\[|\]/, "", $2); print $2; exit }' "$CHANGELOG"
            ;;
    esac
}

gradle_value() {
    sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"[:space:]]+)\"?.*/\1/p" "$GRADLE" | head -n1
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

require_semver() { # name value
    if ! [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fail "$1 is '$2' — expected X.Y.Z"
        return 1
    fi
}
require_int() { # name value
    if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        fail "$1 is '$2' — expected an integer"
        return 1
    fi
}

compare() { # label expected-source expected actual-source actual
    if [[ "$3" == "$5" ]]; then
        ok "$1: $2 $3 == $4"
    else
        fail "$1: $2 is '$3' but $4 is '$5'"
    fi
}

for f in "$XCCONFIG" "$PBXPROJ" "$PROJECT_YML" "$GRADLE" "$CHANGELOG"; do
    [[ -f "$f" ]] || { fail "missing $f"; }
done
[[ $FAILED -eq 0 ]] || exit 1

echo "Checking versions against $XCCONFIG ..."

# --- iOS -------------------------------------------------------------------
IOS_VERSION="$(xcconfig_value CARRIER_WAVE_IOS_MARKETING_VERSION)"
IOS_BUILD="$(xcconfig_value CARRIER_WAVE_IOS_BUILD_NUMBER)"
require_semver CARRIER_WAVE_IOS_MARKETING_VERSION "$IOS_VERSION" || true
require_int CARRIER_WAVE_IOS_BUILD_NUMBER "$IOS_BUILD" || true

IOS_WHATS_NEW="$(newest_whats_new_version iOS)"
IOS_CHANGELOG="$(newest_changelog_version ios)"
compare "iOS marketing version" "xcconfig" "$IOS_VERSION" "newest iOS WhatsNewEntry" "$IOS_WHATS_NEW"
compare "iOS marketing version" "xcconfig" "$IOS_VERSION" "newest released CHANGELOG heading" "$IOS_CHANGELOG"

# --- macOS (CW Sweep) --------------------------------------------------------
SWEEP_VERSION="$(xcconfig_value CW_SWEEP_MARKETING_VERSION)"
SWEEP_BUILD="$(xcconfig_value CW_SWEEP_BUILD_NUMBER)"
require_semver CW_SWEEP_MARKETING_VERSION "$SWEEP_VERSION" || true
require_int CW_SWEEP_BUILD_NUMBER "$SWEEP_BUILD" || true

SWEEP_WHATS_NEW="$(newest_whats_new_version macOS)"
SWEEP_CHANGELOG="$(newest_changelog_version sweep)"
compare "CW Sweep marketing version" "xcconfig" "$SWEEP_VERSION" "newest macOS WhatsNewEntry" "$SWEEP_WHATS_NEW"
compare "CW Sweep marketing version" "xcconfig" "$SWEEP_VERSION" "newest released CHANGELOG heading" "$SWEEP_CHANGELOG"

# --- Android (independent line; still must not drift from its changelog) ----
ANDROID_VERSION="$(gradle_value versionName)"
ANDROID_CODE="$(gradle_value versionCode)"
require_semver versionName "$ANDROID_VERSION" || true
require_int versionCode "$ANDROID_CODE" || true
ANDROID_CHANGELOG="$(newest_changelog_version android)"
compare "Android versionName" "build.gradle.kts" "$ANDROID_VERSION" "newest released Android CHANGELOG heading" "$ANDROID_CHANGELOG"

# --- No hardcoded literals may shadow the xcconfig --------------------------
if grep -nE '^\s*(MARKETING_VERSION|CURRENT_PROJECT_VERSION) = [0-9"][0-9.]*;' "$PBXPROJ"; then
    fail "$PBXPROJ hardcodes a version literal; it must reference \$(CARRIER_WAVE_IOS_*) from $XCCONFIG"
else
    ok "iOS pbxproj has no hardcoded MARKETING_VERSION / CURRENT_PROJECT_VERSION"
fi
if ! grep -qE 'baseConfigurationReference = [0-9A-F]+ /\* Versions\.xcconfig \*/' "$PBXPROJ"; then
    fail "$PBXPROJ no longer references Versions.xcconfig as its base configuration"
fi
if grep -nE '^\s*(MARKETING_VERSION|CURRENT_PROJECT_VERSION):\s*"?[0-9][0-9.]*"?\s*$' "$PROJECT_YML"; then
    fail "$PROJECT_YML hardcodes a version literal; it must reference \$(CW_SWEEP_*) from $XCCONFIG"
else
    ok "macOS project.yml has no hardcoded MARKETING_VERSION / CURRENT_PROJECT_VERSION"
fi
if ! grep -qE '^\s*(Debug|Release):\s*\.\./Versions\.xcconfig' "$PROJECT_YML"; then
    fail "$PROJECT_YML does not include ../Versions.xcconfig via configFiles"
fi

if [[ $FAILED -ne 0 ]]; then
    echo -e "${RED}Version drift detected.${NC} Fix the values above so they agree (see docs/RELEASING.md)." >&2
    exit 1
fi
echo -e "${GREEN}All version locations agree.${NC}"
