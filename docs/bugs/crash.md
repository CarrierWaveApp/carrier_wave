# New crash

**✅ DONE** - Fixed stale ModelContext crash in ChallengesView.evaluateNewQSOs()

Root cause: ChallengesSyncService cached a ModelContext that became stale after device sleep.
When .didSyncQSOs notification fired, the cached progressEngine used the stale context,
causing SwiftData fetch to crash with EXC_BREAKPOINT.

Fix: Create a fresh ChallengeProgressEngine with current modelContext in evaluateNewQSOs()
instead of using the cached syncService.progressEngine.

Details in ~/Downloads/testflight_feedback.zip.

> Hey Jay. The app crashed when I hit the refresh button in the top right on the dashboard. The iPad had been asleep for a while right before i opened the app hit that refresh button. -Justin KG5VNQ
