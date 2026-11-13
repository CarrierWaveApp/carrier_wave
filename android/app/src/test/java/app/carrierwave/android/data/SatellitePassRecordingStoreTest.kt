package app.carrierwave.android.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Port of the iOS `SatellitePassRecordingStoreTests`: sidecar round-trip,
 * the 45-minute freshness window for quick-log playback, and 7-day
 * retention pruning — all against an injected directory + clock.
 */
class SatellitePassRecordingStoreTest {

    @get:Rule
    val temp = TemporaryFolder()

    private val now = 1_789_900_000_000L

    private fun recording(
        id: String,
        noradId: Int = 25544,
        startedAt: Long = now - 600_000,
        endedAt: Long? = now - 300_000,
        marks: List<Double> = emptyList(),
    ) = SatellitePassRecording(
        id = id,
        noradId = noradId,
        satelliteName = "ISS",
        startedAtEpochMs = startedAt,
        endedAtEpochMs = endedAt,
        markOffsets = marks,
        audioFileName = "$id.m4a",
    )

    @Test
    fun saveAndLoadRoundTrips() {
        val dir = temp.newFolder()
        val original = recording("aaa", marks = listOf(12.5, 340.0))
        SatellitePassRecordingStore.save(original, dir)
        val loaded = SatellitePassRecordingStore.loadAll(dir)
        assertEquals(listOf(original), loaded)
    }

    @Test
    fun loadAllSortsNewestFirst() {
        val dir = temp.newFolder()
        SatellitePassRecordingStore.save(recording("old", startedAt = now - 2_000_000), dir)
        SatellitePassRecordingStore.save(recording("new", startedAt = now - 100_000), dir)
        assertEquals(
            listOf("new", "old"),
            SatellitePassRecordingStore.loadAll(dir).map { it.id },
        )
    }

    @Test
    fun latestReturnsFreshFinishedRecordingForTheBird() {
        val dir = temp.newFolder()
        SatellitePassRecordingStore.save(recording("fresh"), dir)
        val hit = SatellitePassRecordingStore.latest(25544, dir, nowMs = now)
        assertEquals("fresh", hit?.id)
    }

    @Test
    fun latestSkipsUnfinishedOtherBirdAndStale() {
        val dir = temp.newFolder()
        SatellitePassRecordingStore.save(recording("running", endedAt = null), dir)
        SatellitePassRecordingStore.save(recording("wrong-bird", noradId = 7530), dir)
        SatellitePassRecordingStore.save(
            recording("stale", endedAt = now - 46 * 60 * 1_000),
            dir,
        )
        assertNull(SatellitePassRecordingStore.latest(25544, dir, nowMs = now))
    }

    @Test
    fun pruneDeletesOnlyExpiredRecordings() {
        val dir = temp.newFolder()
        val expired = recording("expired", startedAt = now - 8L * 24 * 3_600 * 1_000)
        val kept = recording("kept")
        SatellitePassRecordingStore.save(expired, dir)
        SatellitePassRecordingStore.save(kept, dir)
        SatellitePassRecordingStore.audioFile(expired, dir).writeBytes(byteArrayOf(1))
        SatellitePassRecordingStore.audioFile(kept, dir).writeBytes(byteArrayOf(1))

        SatellitePassRecordingStore.prune(dir, nowMs = now)

        assertEquals(listOf("kept"), SatellitePassRecordingStore.loadAll(dir).map { it.id })
        assertFalse(SatellitePassRecordingStore.audioFile(expired, dir).exists())
        assertTrue(SatellitePassRecordingStore.audioFile(kept, dir).exists())
    }

    @Test
    fun markEpochsAreStartPlusOffsets() {
        val rec = recording("marks", startedAt = 1_000_000L, marks = listOf(1.5, 60.0))
        assertEquals(listOf(1_001_500L, 1_060_000L), rec.markEpochsMs)
    }
}
