#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <frequency_hz> [mode] [location]"
    echo ""
    echo "  frequency_hz  Center frequency in Hz (e.g., 14058500)"
    echo "  mode          Demodulation mode: cw, usb, lsb, am (default: cw)"
    echo "  location      Grid square (EM55) or lat,lon (35.4,-89.6)"
    echo "                Used to pick nearby SDRs with geographic diversity"
    exit 1
}

FREQUENCY="${1:?$(usage)}"
MODE="${2:-cw}"
LOCATION="${3:-EM55}"
BANDWIDTH=500
DURATION=60
TARGET_COUNT=45
# Per-ring targets: 15 each across close, medium, far
RING_CLOSE=15
RING_MED=15
RING_FAR=15
# Search pool: 3x target per ring for fallback candidates
SEARCH_COUNT=270

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="cargo run --quiet --manifest-path ${SCRIPT_DIR}/../sdr-cli/Cargo.toml --"

echo "Finding SDRs in 3 distance rings from ${LOCATION} (pool of ${SEARCH_COUNT})..."
ALL_SDRS=()
while IFS= read -r line; do
    [[ -n "$line" ]] && ALL_SDRS+=("$line")
done < <($CLI sdrs search \
    --location "$LOCATION" \
    --count "$SEARCH_COUNT" \
    --available-only)

if [ ${#ALL_SDRS[@]} -eq 0 ]; then
    echo "No available SDRs found, exiting."
    exit 1
fi

# Split into three distance rings (results are sorted by distance)
TOTAL=${#ALL_SDRS[@]}
THIRD=$(( (TOTAL + 2) / 3 ))

CLOSE_SDRS=("${ALL_SDRS[@]:0:$THIRD}")
MED_SDRS=("${ALL_SDRS[@]:$THIRD:$THIRD}")
FAR_SDRS=("${ALL_SDRS[@]:$((THIRD * 2))}")

echo "  Pool: ${TOTAL} SDRs → close ${#CLOSE_SDRS[@]}, medium ${#MED_SDRS[@]}, far ${#FAR_SDRS[@]}"
echo "  Targets: close ${RING_CLOSE}, medium ${RING_MED}, far ${RING_FAR} = ${TARGET_COUNT} total"

OUTDIR=~/tmp/recording-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUTDIR"

MODE_UP=$(echo "$MODE" | tr '[:lower:]' '[:upper:]')
echo
echo "Recording up to ${TARGET_COUNT} SDRs at $(echo "$FREQUENCY" | awk '{printf "%.3f MHz", $1/1e6}') ${MODE_UP} bw=${BANDWIDTH}Hz for ${DURATION}s"
echo "Output: $OUTDIR"
echo

# Capture a single reference time so all recordings are time-aligned
REFERENCE_TIME=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

# Start a recording on an SDR, appending to IDS/STARTED_SDRS on success.
# Returns 0 on success, 1 on failure.
try_start() {
    local sdr="$1"
    local output
    output=$($CLI recordings create \
        --frequency "$FREQUENCY" \
        --mode "$MODE" \
        --sdr "$sdr" \
        --bandwidth "$BANDWIDTH" \
        --reference-time "$REFERENCE_TIME" 2>&1) || true

    local id
    id=$(echo "$output" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin)['id'])
except Exception:
    sys.exit(1)
" 2>/dev/null) || return 1

    IDS+=("$id")
    STARTED_SDRS+=("$sdr")
    return 0
}

# Start recordings from each ring, using candidates as fallback
declare -a IDS
declare -a STARTED_SDRS

start_from_ring() {
    local ring_name="$1"
    local target="$2"
    shift 2
    local candidates=("$@")
    local started=0

    for sdr in "${candidates[@]}"; do
        if [ "$started" -ge "$target" ]; then
            break
        fi
        if try_start "$sdr"; then
            echo "  [${ring_name}] Started $sdr → ${IDS[$((${#IDS[@]}-1))]}"
            started=$((started + 1))
        else
            echo "  [${ring_name}] FAILED $sdr (trying next)"
        fi
    done
    echo "  ${ring_name}: ${started}/${target}"
}

echo
start_from_ring "close"  "$RING_CLOSE" "${CLOSE_SDRS[@]}"
start_from_ring "medium" "$RING_MED"   "${MED_SDRS[@]}"
start_from_ring "far"    "$RING_FAR"   "${FAR_SDRS[@]}"

echo
echo "${#IDS[@]}/${TARGET_COUNT} SDRs started across 3 rings"

if [ ${#IDS[@]} -eq 0 ]; then
    echo "No recordings started, exiting."
    exit 1
fi

echo
echo "Listening for ${DURATION}s..."
sleep "$DURATION"

# Stop all recordings
for id in "${IDS[@]}"; do
    $CLI recordings stop "$id"
    echo "Stopped $id"
done

echo
echo "Downloading segments..."

# Download audio + metadata for each recording
for i in "${!IDS[@]}"; do
    id="${IDS[$i]}"
    sdr="${STARTED_SDRS[$i]}"
    safe_sdr="${sdr//[^a-zA-Z0-9._-]/_}"

    # Get segment count
    segments=$($CLI recordings get "$id" \
        | python3 -c "import sys,json; print(len(json.load(sys.stdin)['segments']))")

    if [ "$segments" -gt 0 ] 2>/dev/null; then
        for seg in $(seq 0 $((segments - 1))); do
            outfile="$OUTDIR/${safe_sdr}_seg${seg}.wav"
            $CLI recordings audio "$id" "$seg" -o "$outfile" -m
            echo "  $outfile"
        done
    else
        echo "  (no segments for $sdr)"
    fi
done

echo
echo "Combining ${#IDS[@]} recordings..."
COMBINE_JSON=$($CLI recordings combine "${IDS[@]}")
COMBINED=$(echo "$COMBINE_JSON" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null) \
    || { echo "Combine failed"; echo "$COMBINE_JSON"; exit 0; }

INCLUDED=$(echo "$COMBINE_JSON" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{d[\"included_count\"]}/{d[\"source_count\"]}')" 2>/dev/null)
echo "Combined recording: $COMBINED ($INCLUDED sources used)"

# Show excluded recordings
echo "$COMBINE_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for ex in d.get('excluded', []):
    print(f'  excluded {ex[\"id\"]}: {ex[\"reason\"]}')
" 2>/dev/null

# Download combined segments
segments=$($CLI recordings get "$COMBINED" \
    | python3 -c "import sys,json; print(len(json.load(sys.stdin)['segments']))")
for seg in $(seq 0 $((segments - 1))); do
    outfile="$OUTDIR/combined_seg${seg}.wav"
    $CLI recordings audio "$COMBINED" "$seg" -o "$outfile" -m
    echo "  $outfile"
done

# Transcribe the combined recording (CW mode only)
if [ "$MODE" = "cw" ]; then
    echo
    echo "Transcribing combined recording..."
    TX_JSON=$($CLI recordings transcribe "$COMBINED" 2>&1) || true
    TX_TEXT=$(echo "$TX_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('text',''))" 2>/dev/null) \
        || TX_TEXT=""
    TX_WPM=$(echo "$TX_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); w=d.get('wpm_estimate'); print(f'{w:.0f}' if w else '?')" 2>/dev/null) \
        || TX_WPM="?"
    TX_CHARS=$(echo "$TX_JSON" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('char_count',0))" 2>/dev/null) \
        || TX_CHARS="0"

    if [ -n "$TX_TEXT" ]; then
        echo "  WPM: ${TX_WPM}  chars: ${TX_CHARS}"
        echo "  Text: ${TX_TEXT}"
        # Save transcription to file
        echo "$TX_TEXT" > "$OUTDIR/transcription.txt"
        echo "  Saved to $OUTDIR/transcription.txt"
    else
        echo "  (no text decoded)"
    fi
fi

echo
echo "Done. Files in $OUTDIR"
open "$OUTDIR"
open "$(dirname "$0")/scrubber.html"
