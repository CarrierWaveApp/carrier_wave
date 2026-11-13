package app.carrierwave.android.data

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * One recorded satellite pass: an audio file plus the "I just worked
 * someone" tap marks stored as offsets from the recording start (mirror of
 * the iOS `SatellitePassRecording`). Sidecar JSON lives next to the audio.
 */
data class SatellitePassRecording(
    val id: String = UUID.randomUUID().toString().lowercase(),
    val noradId: Int,
    /** Short OSCAR designator ("AO-91") at record time. */
    val satelliteName: String,
    val startedAtEpochMs: Long,
    val endedAtEpochMs: Long? = null,
    /** Seconds from start, one per mark tap, ascending. */
    val markOffsets: List<Double> = emptyList(),
    /** Basename of the audio file next to the sidecar JSON. */
    val audioFileName: String,
) {
    /** Absolute epoch-ms timestamps of the marks (pre-seed quick-log rows). */
    val markEpochsMs: List<Long>
        get() = markOffsets.map { startedAtEpochMs + (it * 1_000).toLong() }
}

/**
 * Sidecar-JSON persistence for pass recordings under filesDir (mirror of
 * the iOS `SatellitePassRecordingStore`). Pure file plumbing with an
 * injectable directory + clock so retention and lookup are JVM-testable;
 * the MediaRecorder lifecycle lives in [SatellitePassRecorder].
 */
object SatellitePassRecordingStore {
    /** Pass audio is a scratchpad for post-LOS logging, not an archive. */
    const val RETENTION_MS = 7L * 24 * 3_600 * 1_000

    /** A recording only pre-seeds a quick log while the pass is fresh. */
    const val RECENT_WINDOW_MS = 45L * 60 * 1_000

    fun defaultDirectory(filesDir: File): File =
        File(filesDir, "satellite_recordings").apply { mkdirs() }

    fun audioFile(recording: SatellitePassRecording, directory: File): File =
        File(directory, recording.audioFileName)

    fun save(recording: SatellitePassRecording, directory: File) {
        val json = JSONObject().apply {
            put("id", recording.id)
            put("noradId", recording.noradId)
            put("satelliteName", recording.satelliteName)
            put("startedAtEpochMs", recording.startedAtEpochMs)
            recording.endedAtEpochMs?.let { put("endedAtEpochMs", it) }
            put("markOffsets", JSONArray(recording.markOffsets))
            put("audioFileName", recording.audioFileName)
        }
        // Atomic-enough for a scratchpad: write sibling then rename.
        val target = sidecarFile(recording.id, directory)
        val temp = File(directory, "${recording.id}.json.tmp")
        temp.writeText(json.toString())
        temp.renameTo(target)
    }

    fun loadAll(directory: File): List<SatellitePassRecording> =
        (directory.listFiles() ?: emptyArray())
            .filter { it.extension == "json" }
            .mapNotNull { file -> runCatching { decode(file.readText()) }.getOrNull() }
            .sortedByDescending { it.startedAtEpochMs }

    /** The freshest finished recording for a bird, ended < 45 min ago —
     * the one the post-LOS quick log should play back. */
    fun latest(
        noradId: Int,
        directory: File,
        nowMs: Long = System.currentTimeMillis(),
    ): SatellitePassRecording? = loadAll(directory).firstOrNull { recording ->
        val ended = recording.endedAtEpochMs ?: return@firstOrNull false
        recording.noradId == noradId && nowMs - ended < RECENT_WINDOW_MS
    }

    /** Delete recordings (sidecar + audio) older than [RETENTION_MS]. */
    fun prune(directory: File, nowMs: Long = System.currentTimeMillis()) {
        for (recording in loadAll(directory)) {
            if (nowMs - recording.startedAtEpochMs > RETENTION_MS) {
                audioFile(recording, directory).delete()
                sidecarFile(recording.id, directory).delete()
            }
        }
    }

    private fun sidecarFile(id: String, directory: File) = File(directory, "$id.json")

    private fun decode(text: String): SatellitePassRecording {
        val json = JSONObject(text)
        val offsets = json.getJSONArray("markOffsets")
        return SatellitePassRecording(
            id = json.getString("id"),
            noradId = json.getInt("noradId"),
            satelliteName = json.getString("satelliteName"),
            startedAtEpochMs = json.getLong("startedAtEpochMs"),
            endedAtEpochMs =
                if (json.has("endedAtEpochMs")) json.getLong("endedAtEpochMs") else null,
            markOffsets = (0 until offsets.length()).map { offsets.getDouble(it) },
            audioFileName = json.getString("audioFileName"),
        )
    }
}
