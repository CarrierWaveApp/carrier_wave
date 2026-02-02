# Session export

**Status: DONE**

I'd like to add a button to POTA activations that can generate a nice map of QSOs, show the total time run, number of calls, and show SNR circles with arcs to the user's location. It should generate an image that can be shared.

## Implementation

- Added share swipe action (swipe right) on activation rows in POTA Uploads
- Share card shows: map with QSO locations and geodesic arcs, park info, stats (QSOs, duration, bands, modes), callsign
- Uses existing share card infrastructure for rendering to UIImage and presenting share sheet
