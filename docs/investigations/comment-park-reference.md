# [DONE] User reporting that we're not properly pulling park references from ADIF comments

**Resolved:** 2026-02-15 on `feature/comment-park` branch. See `docs/investigations/2026-02-15-comment-park-reference.md` for full investigation trace.

We should be pulling park references from comments already, but apparently we're not. Investigate the flow end-to-end, add some synthetic data if necessary, and then also ensure that we take the comment value and set it into the proper field for our park that POTA reads from (this should also be used when uploading to QRZ and others).
