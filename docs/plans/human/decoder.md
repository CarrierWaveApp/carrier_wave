# Logging QSOs automatically from decoder

**STATUS: COMPLETED** - Implemented 2026-01-29

I'd like for us to add the ability to transcribe QSOs as heard by the decoder. This'll mean a few things:
1. ✅ QSOs are rarely zero-beated. The decoder will need to find the right center tone frequency for each part of the QSO. It should log what it finds.
2. ✅ I want to intelligently color parts of the QSO (if it hears UR 599/UR RST 599 it should show signal).
3. ✅ It should automatically lookup callsigns it hears as part of the QSO.
5. ✅ I want to render each side of the QSO in a chat transcript format.

## Implementation Notes

- Chat/Raw toggle in CW transcription view
- Turn detection uses frequency changes (>30 Hz delta) and prosigns (DE, K, KN, BK)
- Enhanced highlighting for grid squares, power levels, operator names
- Two-tier callsign lookup: Polo notes lists (local) → QRZ XML API (future)
- Messages attributed to stations with callsign headers
