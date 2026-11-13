# CW Decoder Test Tools

Tools for testing the Goertzel-based CW decoder outside of the iOS app.

## Dependencies

Install with Homebrew:

```bash
brew install ebook2cw ffmpeg
```

## Generate Test Audio

Use `generate_cw_test.sh` to create WAV files with CW audio:

```bash
# Basic usage (20 WPM, 700 Hz)
./Tools/generate_cw_test.sh "CQ CQ DE W1AW"

# Custom WPM and frequency
./Tools/generate_cw_test.sh "CQ CQ DE W1AW" 25 600

# Custom output filename
./Tools/generate_cw_test.sh "HELLO WORLD" 15 700 hello_test
```

This creates a 16-bit mono WAV file at 44100 Hz.

## Run the Decoder

Use `test_cw_decoder.swift` to decode the audio:

```bash
# Adaptive WPM (auto-detects speed)
swift Tools/test_cw_decoder.swift test_cw.wav 700

# Explicit adaptive mode
swift Tools/test_cw_decoder.swift test_cw.wav 700 adaptive

# Fixed WPM (no adaptation)
swift Tools/test_cw_decoder.swift test_cw.wav 700 20
```

Arguments:
- `wav_file` - Path to WAV file (16-bit PCM)
- `tone_frequency` - CW tone frequency in Hz (default: 700)
- `wpm|adaptive` - WPM number for fixed timing, or "adaptive" for auto-detection

## Quick Test

Generate and decode in one go:

```bash
./Tools/generate_cw_test.sh "CQ CQ DE W1AW" 20 700 && \
swift Tools/test_cw_decoder.swift test_cw.wav 700 adaptive
```

## Test Cases

Some useful test cases:

```bash
# Slow CW (easier to decode)
./Tools/generate_cw_test.sh "TEST" 10 700 slow_test

# Fast CW (stress test)
./Tools/generate_cw_test.sh "TEST" 35 700 fast_test

# Different frequencies
./Tools/generate_cw_test.sh "TEST" 20 600 low_freq
./Tools/generate_cw_test.sh "TEST" 20 800 high_freq

# Callsigns and common exchanges
./Tools/generate_cw_test.sh "CQ CQ CQ DE W1AW W1AW K" 20 700
./Tools/generate_cw_test.sh "W1AW DE N0CALL 599 CA" 22 700
./Tools/generate_cw_test.sh "TU 73 DE W1AW SK" 20 700
```
