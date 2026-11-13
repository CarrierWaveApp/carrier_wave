# More sync/upload problems from roothog

## POTA uploads are marked as done but not actually uploaded

User is reporting that their activations are partially uploaded to POTA, but we're not going back and uploading the remaining QSOs. Instead, we seem to label the entire set of QSOs as uploaded incorrectly. Are we pulling the user's upload jobs and activations correctly to compare what's uploaded to what's available? We may need to pull the user's activation like this to compare: https://api.pota.app/user/logbook?activatorOnly=1&page=1&size=25&startDate=2026-02-14&endDate=2026-02-14&reference=US-0189

## Inconsistency between devices

We're properly syncing QSOs from our activity log to QRZ, but then devices pulling from QRZ aren't showing the correct QSOs (the secondary device is just showing the first QSO twice instead of the two correct QSOs).
