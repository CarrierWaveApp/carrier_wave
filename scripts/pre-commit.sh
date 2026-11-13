#!/usr/bin/env bash
# Pre-commit hook for FullDuplex
# Runs SwiftFormat (check), SwiftLint, and performance audit on staged Swift files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Version consistency (CAR-158): when any version-bearing file is staged, make
# sure swift/Versions.xcconfig, the What's New catalog, CHANGELOG.md and the
# project files still agree. Runs before the Swift-only early exit below because
# a version bump may not touch a .swift file at all.
VERSION_FILES=$(git diff --cached --name-only --diff-filter=ACM \
    | grep -E '^(swift/Versions\.xcconfig|CHANGELOG\.md|swift/macos/project\.yml|swift/ios/CarrierWave\.xcodeproj/project\.pbxproj|android/app/build\.gradle\.kts|swift/packages/CarrierWaveData/Sources/CarrierWaveData/Utilities/WhatsNewCatalog.*\.swift)$' || true)
if [ -n "$VERSION_FILES" ]; then
    echo -e "${YELLOW}Version-bearing files staged; checking version consistency...${NC}"
    if ! "$SCRIPT_DIR/check-versions.sh"; then
        echo -e "${RED}Pre-commit checks failed${NC}"
        exit 1
    fi
fi

# Get staged Swift files (excluding Tools/ which contains standalone scripts)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' | grep -v '^Tools/' || true)

if [ -z "$STAGED_FILES" ]; then
    echo -e "${GREEN}No Swift files staged, skipping lint/format checks${NC}"
    exit 0
fi

echo -e "${YELLOW}Checking staged Swift files...${NC}"

# Check if tools are available
SWIFTFORMAT_AVAILABLE=false
SWIFTLINT_AVAILABLE=false

if command -v swiftformat &> /dev/null; then
    SWIFTFORMAT_AVAILABLE=true
else
    echo -e "${YELLOW}Warning: swiftformat not found. Install with: brew install swiftformat${NC}"
fi

if command -v swiftlint &> /dev/null; then
    SWIFTLINT_AVAILABLE=true
else
    echo -e "${YELLOW}Warning: swiftlint not found. Install with: brew install swiftlint${NC}"
fi

FAILED=false

# Run SwiftFormat check
if [ "$SWIFTFORMAT_AVAILABLE" = true ]; then
    echo -e "${YELLOW}Running SwiftFormat check...${NC}"

    UNFORMATTED_FILES=""
    for FILE in $STAGED_FILES; do
        if [ -f "$FILE" ]; then
            if ! swiftformat --lint "$FILE" 2>/dev/null; then
                UNFORMATTED_FILES="$UNFORMATTED_FILES $FILE"
            fi
        fi
    done

    if [ -n "$UNFORMATTED_FILES" ]; then
        echo -e "${RED}The following files need formatting:${NC}"
        for FILE in $UNFORMATTED_FILES; do
            echo "  $FILE"
        done
        echo -e "${YELLOW}Run 'make format' to fix formatting${NC}"
        FAILED=true
    else
        echo -e "${GREEN}SwiftFormat check passed${NC}"
    fi
fi

# Run SwiftLint
if [ "$SWIFTLINT_AVAILABLE" = true ]; then
    echo -e "${YELLOW}Running SwiftLint...${NC}"

    LINT_ERRORS=false
    for FILE in $STAGED_FILES; do
        if [ -f "$FILE" ]; then
            if ! swiftlint lint --strict --quiet "$FILE" 2>/dev/null; then
                LINT_ERRORS=true
            fi
        fi
    done

    if [ "$LINT_ERRORS" = true ]; then
        echo -e "${RED}SwiftLint found issues. Run 'make lint' for details${NC}"
        FAILED=true
    else
        echo -e "${GREEN}SwiftLint check passed${NC}"
    fi
fi

# Run performance audit (delegates to shared script)
echo -e "${YELLOW}Running performance audit...${NC}"

if ! STAGED=1 "$SCRIPT_DIR/performance-audit.sh" $STAGED_FILES; then
    FAILED=true
fi

if [ "$FAILED" = true ]; then
    echo -e "${RED}Pre-commit checks failed${NC}"
    exit 1
fi

echo -e "${GREEN}All pre-commit checks passed${NC}"
exit 0
