# FT8 Sample Audio Files & Test Vectors

Downloaded 2026-02-25 for FT8 decoder development and testing.

## Audio Format (all files)

- **Format:** RIFF WAV, PCM 16-bit signed, mono
- **Sample rate:** 12,000 Hz
- **Duration:** 15.000 seconds (one FT8 transmission window)
- **Size:** ~352 KB each (360,000 audio bytes + 44-byte WAV header)

## WSJT-X Official Samples (SourceForge)

Source: https://sourceforge.net/projects/wsjt/files/samples/FT8/

| File | Date | Description |
|------|------|-------------|
| `170709_135615.wav` | 2017-07-09 | Early FT8 recording (pre-77-bit protocol era) |
| `181201_180245.wav` | 2018-12-01 | FT8 recording (77-bit protocol, post v2.0) |
| `210703_133430.wav` | 2021-07-03 | Recent FT8 recording |

These are the "official" sample files distributed by K1JT's team. No expected-output reference files are provided with these; they serve as real-world smoke tests.

## ft8_lib Test Vectors (GitHub: kgoba/ft8_lib)

Source: https://github.com/kgoba/ft8_lib/tree/master/test/wav

Each WAV has a companion `.txt` with expected decode results in WSJT-X ALL.TXT format:
```
HHMMSS  SNR  DT  FREQ  ~  MESSAGE
```

### Timestamped recordings (191111_*)
Real off-air recordings from 2019-11-11. These contain 15-22 decodable signals per slot -- good for testing decoder sensitivity.

| File | Expected decodes |
|------|-----------------|
| `191111_110615.wav` | 22 signals |
| `191111_110630.wav` | 15 signals |
| `191111_110645.wav` | 20 signals |

### WebSDR recordings (websdr_*)
Captured from WebSDR receivers. `websdr_test5.wav` has 27 expected decodes -- a dense band scenario useful for stress-testing.

### 20m_busy suite
38 consecutive 15-second slots from a busy 20m band. Each has 15-25+ signals. Only 3 downloaded here (test_01 through test_03); the full set of 38 is available at the GitHub URL above.

## Encoding Test Vectors (test.c)

`ft8_lib_test_vectors/test.c` contains message encoding/decoding round-trip test vectors:

| Message | Type | Notes |
|---------|------|-------|
| `CQ K7IHZ DM43` | Standard | Basic CQ with grid |
| `CQ EA8/G5LSI` | Non-standard call | Compound callsign |
| `EA8/G5LSI R2RFE RR73` | Standard | Hash-based compound call |
| `R2RFE/P EA8/G5LSI R+12` | Standard | Portable suffix + signal report |
| `TNX BOB 73 GL` | Free text | 13-char free text |
| `TNX BOB 73` | Standard | Ambiguous -- encodes as standard, not free text |
| `CQ YL/LB2JK KO16sw` | Non-standard call | Foreign prefix compound call |
| `CQ POTA YL/LB2JK KO16sw` | Non-standard call | Directed CQ with compound call |
| `CQ JA LB2JK JO59` | Standard | Directed CQ (region) |
| `CQ 123 LB2JK JO59` | Standard | Directed CQ (numeric) |

## Additional Resources (not downloaded)

- **Full 20m_busy suite:** 38 WAV+TXT pairs at `https://github.com/kgoba/ft8_lib/tree/master/test/wav/20m_busy`
- **More websdr tests:** 20 WebSDR recordings (1-20) at `https://github.com/kgoba/ft8_lib/tree/master/test/wav/`
- **WSJT-X FT4 samples:** https://sourceforge.net/projects/wsjt/files/samples/FT4/
- **WSJT-X FST4/FST4W samples:** https://sourceforge.net/projects/wsjt/files/samples/FST4+FST4W/
- **WSJT-X Q65 samples:** https://sourceforge.net/projects/wsjt/files/samples/Q65/
