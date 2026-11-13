#!/bin/bash
# Generate a simulated POTA QSO audio recording with pure sine wave tones
# Two stations: W6JSV (activator) at 600Hz, N9HO (hunter) at 650Hz

set -e

OUTPUT_DIR="${1:-/tmp/pota_qso}"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

SAMPLE_RATE=44100

# Morse timing based on WPM
# At standard timing: dit = 1.2/WPM seconds
calc_timing() {
    local wpm=$1
    # Use bc for floating point
    echo "scale=4; 1.2 / $wpm" | bc
}

# Morse code lookup function (bash 3 compatible)
get_morse() {
    case "$1" in
        A) echo ".-" ;; B) echo "-..." ;; C) echo "-.-." ;; D) echo "-.." ;; E) echo "." ;;
        F) echo "..-." ;; G) echo "--." ;; H) echo "...." ;; I) echo ".." ;; J) echo ".---" ;;
        K) echo "-.-" ;; L) echo ".-.." ;; M) echo "--" ;; N) echo "-." ;; O) echo "---" ;;
        P) echo ".--." ;; Q) echo "--.-" ;; R) echo ".-." ;; S) echo "..." ;; T) echo "-" ;;
        U) echo "..-" ;; V) echo "...-" ;; W) echo ".--" ;; X) echo "-..-" ;; Y) echo "-.--" ;;
        Z) echo "--.." ;;
        0) echo "-----" ;; 1) echo ".----" ;; 2) echo "..---" ;; 3) echo "...--" ;; 4) echo "....-" ;;
        5) echo "....." ;; 6) echo "-...." ;; 7) echo "--..." ;; 8) echo "---.." ;; 9) echo "----." ;;
        "?") echo "..--.." ;; "/") echo "-..-." ;;
        *) echo "" ;;
    esac
}

# Generate a single transmission as pure sine wave
# Args: text, wpm, frequency, output_file
generate_pure_cw() {
    local text="$1"
    local wpm="$2"
    local freq="$3"
    local output="$4"

    local dit_len=$(calc_timing "$wpm")
    local dah_len=$(echo "scale=4; $dit_len * 3" | bc)
    local element_gap=$dit_len
    local letter_gap=$(echo "scale=4; $dit_len * 3" | bc)
    local word_gap=$(echo "scale=4; $dit_len * 7" | bc)

    local segments=()
    local first_element=true

    # Process each character
    for ((i=0; i<${#text}; i++)); do
        local char="${text:$i:1}"
        char=$(echo "$char" | tr '[:lower:]' '[:upper:]')

        if [[ "$char" == " " ]]; then
            # Full word gap (7 dits) - letter gap is added before next letter, not after previous
            segments+=("silence:$word_gap")
            first_element=true
            continue
        fi

        local code=$(get_morse "$char")
        if [[ -z "$code" ]]; then
            continue
        fi

        # Add letter gap before this letter (except for first)
        if [[ "$first_element" != "true" ]]; then
            segments+=("silence:$letter_gap")
        fi
        first_element=false

        # Process each element in the morse code
        local first_in_letter=true
        for ((j=0; j<${#code}; j++)); do
            local element="${code:$j:1}"

            # Add element gap within letter
            if [[ "$first_in_letter" != "true" ]]; then
                segments+=("silence:$element_gap")
            fi
            first_in_letter=false

            if [[ "$element" == "." ]]; then
                segments+=("tone:$dit_len:$freq")
            else
                segments+=("tone:$dah_len:$freq")
            fi
        done
    done

    # Build sox command to generate audio
    local tmpdir=$(mktemp -d)
    local part_num=0
    local part_files=()

    for seg in "${segments[@]}"; do
        local type="${seg%%:*}"
        local rest="${seg#*:}"
        local part_file="$tmpdir/part_$(printf '%04d' $part_num).wav"

        if [[ "$type" == "silence" ]]; then
            local duration="$rest"
            sox -n -r $SAMPLE_RATE -c 1 "$part_file" trim 0.0 "$duration"
        else
            # tone:duration:freq
            local duration="${rest%%:*}"
            local tone_freq="${rest#*:}"
            # Generate pure sine with soft attack/release (5ms) to avoid clicks
            sox -n -r $SAMPLE_RATE -c 1 "$part_file" synth "$duration" sine "$tone_freq" \
                fade q 0.005 "$duration" 0.005
        fi

        part_files+=("$part_file")
        ((part_num++))
    done

    # Concatenate all parts
    if [[ ${#part_files[@]} -gt 0 ]]; then
        sox "${part_files[@]}" "$output"
    else
        # Empty - create short silence
        sox -n -r $SAMPLE_RATE -c 1 "$output" trim 0.0 0.1
    fi

    rm -rf "$tmpdir"
}

echo "Generating pure sine wave CW audio..."

# 1. CQ CQ POTA DE W6JSV K (W6JSV, 600Hz, 20wpm)
echo "  1/8: CQ CQ POTA DE W6JSV K"
generate_pure_cw "CQ CQ POTA DE W6JSV K" 20 600 "01_cq1.wav"

# 2. CQ CQ POTA DE W6JSV K (W6JSV, 600Hz, 20wpm)
echo "  2/8: CQ CQ POTA DE W6JSV K"
generate_pure_cw "CQ CQ POTA DE W6JSV K" 20 600 "02_cq2.wav"

# 3. N9HO (N9HO responds, 650Hz, 25wpm)
echo "  3/8: N9HO"
generate_pure_cw "N9HO" 25 650 "03_n9ho_call.wav"

# 4. N9? (W6JSV partial copy, 600Hz, 20wpm)
echo "  4/8: N9?"
generate_pure_cw "N9?" 20 600 "04_n9q.wav"

# 5. N9HO (N9HO repeats, 650Hz, 25wpm)
echo "  5/8: N9HO"
generate_pure_cw "N9HO" 25 650 "05_n9ho_repeat.wav"

# 6. N9HO TU ES GM UR 599 599 CA BK (W6JSV exchange, 600Hz, 20wpm)
echo "  6/8: N9HO TU ES GM UR 599 599 CA BK"
generate_pure_cw "N9HO TU ES GM UR 599 599 CA BK" 20 600 "06_w6jsv_exchange.wav"

# 7. BK RR TU UR 599 599 AL AL BK (N9HO exchange, 650Hz, 25wpm)
echo "  7/8: BK RR TU UR 599 599 AL AL BK"
generate_pure_cw "BK RR TU UR 599 599 AL AL BK" 25 650 "07_n9ho_exchange.wav"

# 8. BK RR FB TU ES 72 EE (W6JSV signoff, 600Hz, 20wpm)
echo "  8/8: BK RR FB TU ES 72 EE"
generate_pure_cw "BK RR FB TU ES 72 EE" 20 600 "08_signoff.wav"

echo "Creating silence gaps..."

# Create silence gaps
sox -n -r $SAMPLE_RATE -c 1 silence_1s.wav trim 0.0 1.0
sox -n -r $SAMPLE_RATE -c 1 silence_2s.wav trim 0.0 2.0

echo "Concatenating all files..."

# Build the final audio with appropriate gaps
sox \
    01_cq1.wav silence_2s.wav \
    02_cq2.wav silence_2s.wav \
    03_n9ho_call.wav silence_1s.wav \
    04_n9q.wav silence_1s.wav \
    05_n9ho_repeat.wav silence_1s.wav \
    06_w6jsv_exchange.wav silence_1s.wav \
    07_n9ho_exchange.wav silence_1s.wav \
    08_signoff.wav \
    pota_qso_raw.wav

echo "Adding background static..."

# Get duration of the raw audio
duration=$(sox pota_qso_raw.wav -n stat 2>&1 | grep "Length" | awk '{print $3}')

# Generate band noise (pink noise filtered to sound like HF static)
sox -n -r $SAMPLE_RATE -c 1 noise_raw.wav synth "$duration" pinknoise

# Filter noise to HF-like frequencies (300-3000Hz bandpass)
sox noise_raw.wav noise_filtered.wav sinc 300-3000

# Mix: CW at full volume, noise at -20dB (about 10% volume)
sox -m pota_qso_raw.wav -v 0.1 noise_filtered.wav pota_qso_mixed.wav

# Normalize the final mix
sox pota_qso_mixed.wav pota_qso_final.wav norm -1

# Convert to mp3 for easier sharing
ffmpeg -y -i pota_qso_final.wav -b:a 192k pota_qso_final.mp3 2>/dev/null

echo ""
echo "Done! Output files:"
echo "  WAV: $OUTPUT_DIR/pota_qso_final.wav"
echo "  MP3: $OUTPUT_DIR/pota_qso_final.mp3"
echo ""
echo "QSO Summary:"
echo "  W6JSV (activator) - 600Hz @ 20wpm"
echo "  N9HO (hunter) - 650Hz @ 25wpm"
