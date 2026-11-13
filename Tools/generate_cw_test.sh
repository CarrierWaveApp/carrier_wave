#!/bin/bash

# Generate CW test audio files from text
# Usage: ./generate_cw_test.sh "TEXT TO ENCODE" [wpm] [frequency] [output_name] [noise_level]

set -e

# Check dependencies
check_deps() {
    local missing=()

    if ! command -v ebook2cw &> /dev/null; then
        missing+=("ebook2cw")
    fi

    if ! command -v ffmpeg &> /dev/null; then
        missing+=("ffmpeg")
    fi

    if ! command -v sox &> /dev/null; then
        missing+=("sox")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        echo "ERROR: Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Install with Homebrew:"
        for dep in "${missing[@]}"; do
            echo "  brew install $dep"
        done
        exit 1
    fi
}

# Show usage
usage() {
    echo "Usage: $0 \"TEXT\" [wpm] [frequency] [output_name] [noise]"
    echo ""
    echo "Arguments:"
    echo "  TEXT        - Text to encode as CW (required)"
    echo "  wpm         - Words per minute (default: 20)"
    echo "  frequency   - Tone frequency in Hz (default: 700)"
    echo "  output_name - Output filename without extension (default: test_cw)"
    echo "  noise       - Noise level or type (default: none)"
    echo ""
    echo "Noise options:"
    echo "  none        - Clean signal (default)"
    echo "  light       - Light static (SNR ~20dB)"
    echo "  moderate    - Moderate noise (SNR ~10dB)"
    echo "  heavy       - Heavy noise (SNR ~6dB)"
    echo "  qrm         - Nearby interfering signal"
    echo "  qsb         - Fading/varying signal strength"
    echo "  realistic   - Combination: moderate noise + slight fading"
    echo "  0.0-1.0     - Custom white noise amplitude"
    echo ""
    echo "Examples:"
    echo "  $0 \"CQ CQ DE W1AW\""
    echo "  $0 \"CQ CQ DE W1AW\" 25 600"
    echo "  $0 \"CQ CQ DE W1AW\" 20 700 test_noisy moderate"
    echo "  $0 \"CQ CQ DE W1AW\" 20 700 test_qrm qrm"
    echo "  $0 \"CQ CQ DE W1AW\" 20 700 test_custom 0.15"
    echo ""
    echo "Output: Creates a 16-bit mono WAV file at 44100 Hz"
}

# Generate white noise wav file
generate_noise() {
    local duration=$1
    local amplitude=$2
    local output=$3

    sox -n -r 44100 -c 1 -b 16 "$output" synth "$duration" whitenoise vol "$amplitude"
}

# Generate a sine wave for QRM interference
generate_qrm() {
    local duration=$1
    local freq=$2
    local amplitude=$3
    local output=$4

    # Offset frequency by 50-200 Hz to simulate nearby station
    local offset_freq=$((freq + 150))
    sox -n -r 44100 -c 1 -b 16 "$output" synth "$duration" sine "$offset_freq" vol "$amplitude"
}

# Apply fading (QSB) effect
apply_fading() {
    local input=$1
    local output=$2
    local rate=${3:-0.3}  # Fade rate in Hz

    # Use tremolo effect for amplitude modulation (fading)
    sox "$input" "$output" tremolo "$rate" 40
}

# Mix two audio files
mix_audio() {
    local file1=$1
    local file2=$2
    local output=$3

    sox -m "$file1" "$file2" "$output"
}

# Main
check_deps

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

TEXT="$1"
WPM="${2:-20}"
FREQ="${3:-700}"
OUTPUT="${4:-test_cw}"
NOISE="${5:-none}"

# Create temp directory for intermediate files
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "Generating CW audio..."
echo "  Text: \"$TEXT\""
echo "  WPM: $WPM"
echo "  Frequency: $FREQ Hz"
echo "  Noise: $NOISE"
echo "  Output: ${OUTPUT}.wav"
echo ""

# Generate MP3 with ebook2cw
echo "$TEXT" | ebook2cw -w "$WPM" -f "$FREQ" -o "$TMPDIR/cw" > /dev/null 2>&1

# Convert to WAV (16-bit mono, 44100 Hz)
ffmpeg -y -i "$TMPDIR/cw0000.mp3" -ar 44100 -ac 1 -acodec pcm_s16le "$TMPDIR/clean.wav" -loglevel error

# Get duration of the audio
DURATION=$(sox "$TMPDIR/clean.wav" -n stat 2>&1 | grep "Length" | awk '{print $3}')

# Apply noise/effects based on setting
case "$NOISE" in
    none)
        cp "$TMPDIR/clean.wav" "${OUTPUT}.wav"
        ;;
    light)
        generate_noise "$DURATION" 0.05 "$TMPDIR/noise.wav"
        mix_audio "$TMPDIR/clean.wav" "$TMPDIR/noise.wav" "${OUTPUT}.wav"
        ;;
    moderate)
        generate_noise "$DURATION" 0.15 "$TMPDIR/noise.wav"
        mix_audio "$TMPDIR/clean.wav" "$TMPDIR/noise.wav" "${OUTPUT}.wav"
        ;;
    heavy)
        generate_noise "$DURATION" 0.3 "$TMPDIR/noise.wav"
        mix_audio "$TMPDIR/clean.wav" "$TMPDIR/noise.wav" "${OUTPUT}.wav"
        ;;
    qrm)
        # Interfering signal at nearby frequency
        generate_qrm "$DURATION" "$FREQ" 0.4 "$TMPDIR/qrm.wav"
        generate_noise "$DURATION" 0.08 "$TMPDIR/noise.wav"
        mix_audio "$TMPDIR/clean.wav" "$TMPDIR/qrm.wav" "$TMPDIR/with_qrm.wav"
        mix_audio "$TMPDIR/with_qrm.wav" "$TMPDIR/noise.wav" "${OUTPUT}.wav"
        ;;
    qsb)
        # Fading signal
        generate_noise "$DURATION" 0.05 "$TMPDIR/noise.wav"
        apply_fading "$TMPDIR/clean.wav" "$TMPDIR/faded.wav" 0.4
        mix_audio "$TMPDIR/faded.wav" "$TMPDIR/noise.wav" "${OUTPUT}.wav"
        ;;
    realistic)
        # Moderate noise + slight fading
        generate_noise "$DURATION" 0.12 "$TMPDIR/noise.wav"
        apply_fading "$TMPDIR/clean.wav" "$TMPDIR/faded.wav" 0.2
        mix_audio "$TMPDIR/faded.wav" "$TMPDIR/noise.wav" "${OUTPUT}.wav"
        ;;
    *)
        # Assume it's a custom noise amplitude (0.0-1.0)
        if [[ "$NOISE" =~ ^[0-9]*\.?[0-9]+$ ]]; then
            generate_noise "$DURATION" "$NOISE" "$TMPDIR/noise.wav"
            mix_audio "$TMPDIR/clean.wav" "$TMPDIR/noise.wav" "${OUTPUT}.wav"
        else
            echo "ERROR: Unknown noise type: $NOISE"
            usage
            exit 1
        fi
        ;;
esac

echo "Done! Created ${OUTPUT}.wav"
echo ""
echo "Test with:"
echo "  swift Tools/test_cw_decoder.swift ${OUTPUT}.wav $FREQ adaptive"
