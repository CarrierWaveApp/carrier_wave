#!/usr/bin/env bash
# Performance audit for Carrier Wave
# Checks all Swift files for banned patterns that cause multi-second freezes.
#
# Usage:
#   ./scripts/performance-audit.sh              # Check all files
#   ./scripts/performance-audit.sh file1 file2  # Check specific files
#   STAGED=1 ./scripts/performance-audit.sh     # Check staged git content

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Collect files to check
if [ $# -gt 0 ]; then
    FILES="$*"
elif [ "${STAGED:-}" = "1" ]; then
    FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' | grep -v '^Tools/' || true)
else
    FILES=$(find swift/ios/CarrierWave swift/packages/CarrierWaveData -name '*.swift' -not -path '*/DerivedData/*' 2>/dev/null || true)
fi

if [ -z "$FILES" ]; then
    echo -e "${GREEN}No Swift files to audit${NC}"
    exit 0
fi

PERF_ERRORS=""

for FILE in $FILES; do
    if [ ! -f "$FILE" ]; then
        continue
    fi

    # Read file content (or staged content)
    if [ "${STAGED:-}" = "1" ]; then
        CONTENT=$(git show ":$FILE" 2>/dev/null) || continue
    else
        CONTENT=$(cat "$FILE")
    fi

    # Check 1: @Query for QSO or ServicePresence (BANNED)
    QUERY_HITS=$(echo "$CONTENT" | grep -n '@Query' | grep -iE 'QSO|ServicePresence' || true)
    if [ -n "$QUERY_HITS" ]; then
        while IFS= read -r line; do
            HIT_LINE_NUM=$(echo "$line" | cut -d: -f1)
            if echo "$line" | grep -q 'perf-audit-ignore'; then
                continue
            fi
            PREV_LINE_NUM=$((HIT_LINE_NUM - 1))
            if [ "$PREV_LINE_NUM" -ge 1 ]; then
                PREV_LINE=$(echo "$CONTENT" | sed -n "${PREV_LINE_NUM}p")
                if echo "$PREV_LINE" | grep -q 'perf-audit-ignore'; then
                    continue
                fi
            fi
            PERF_ERRORS="${PERF_ERRORS}\n  ${FILE}:${HIT_LINE_NUM}\n    -> @Query is BANNED for QSO/ServicePresence. Use @State + FetchDescriptor in .task"
        done <<< "$QUERY_HITS"
    fi

    # Check 2: FetchDescriptor<QSO|ServicePresence> without fetchLimit
    if echo "$CONTENT" | grep -qE 'FetchDescriptor<(QSO|ServicePresence)>'; then
        LINE_NUMS=$(echo "$CONTENT" | grep -nE 'FetchDescriptor<(QSO|ServicePresence)>' | cut -d: -f1)
        TOTAL_LINES=$(echo "$CONTENT" | wc -l)

        for LINE_NUM in $LINE_NUMS; do
            DECL_LINE=$(echo "$CONTENT" | sed -n "${LINE_NUM}p")
            if echo "$DECL_LINE" | grep -q 'perf-audit-ignore'; then
                continue
            fi
            PREV_NUM=$((LINE_NUM - 1))
            if [ "$PREV_NUM" -ge 1 ]; then
                PREV=$(echo "$CONTENT" | sed -n "${PREV_NUM}p")
                if echo "$PREV" | grep -q 'perf-audit-ignore'; then
                    continue
                fi
            fi

            # Skip if used with fetchCount (no objects loaded)
            SCAN_END=$((LINE_NUM + 10))
            if [ "$SCAN_END" -gt "$TOTAL_LINES" ]; then
                SCAN_END=$TOTAL_LINES
            fi
            USES_FETCH_COUNT=false
            CUR=$((LINE_NUM + 1))
            while [ "$CUR" -le "$SCAN_END" ]; do
                FC_LINE=$(echo "$CONTENT" | sed -n "${CUR}p")
                if echo "$FC_LINE" | grep -qE '^\s{0,4}(func |class |struct |enum |actor |protocol |^\})'; then
                    break
                fi
                if echo "$FC_LINE" | grep -q 'fetchCount'; then
                    USES_FETCH_COUNT=true
                    break
                fi
                CUR=$((CUR + 1))
            done
            if [ "$USES_FETCH_COUNT" = true ]; then
                continue
            fi

            FOUND_LIMIT=false
            CUR=$((LINE_NUM + 1))
            while [ "$CUR" -le "$SCAN_END" ]; do
                SCAN_LINE=$(echo "$CONTENT" | sed -n "${CUR}p")
                if echo "$SCAN_LINE" | grep -qE '^\s{0,4}(func |class |struct |enum |actor |protocol |^\})'; then
                    break
                fi
                if echo "$SCAN_LINE" | grep -q 'fetchLimit'; then
                    FOUND_LIMIT=true
                    break
                fi
                CUR=$((CUR + 1))
            done
            if echo "$DECL_LINE" | grep -q 'fetchLimit'; then
                FOUND_LIMIT=true
            fi
            if [ "$FOUND_LIMIT" = false ]; then
                TRIMMED=$(echo "$DECL_LINE" | sed 's/^[[:space:]]*//')
                PERF_ERRORS="${PERF_ERRORS}\n  ${FILE}:${LINE_NUM}: ${TRIMMED}\n    -> FetchDescriptor for QSO/ServicePresence MUST set fetchLimit"
            fi
        done
    fi
done

if [ -n "$PERF_ERRORS" ]; then
    echo -e "${RED}Performance audit failed:${NC}"
    echo -e "$PERF_ERRORS"
    echo ""
    echo "See docs/PERFORMANCE.md for details"
    exit 1
fi

echo -e "${GREEN}Performance audit passed${NC}"
exit 0
