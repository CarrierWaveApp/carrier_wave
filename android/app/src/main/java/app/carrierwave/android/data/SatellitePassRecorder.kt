package app.carrierwave.android.data

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import app.carrierwave.android.CwApp
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID

/**
 * Records pass audio from the mic with tap-to-mark timestamps (mirror of
 * the iOS `SatellitePassRecorder`): voice-grade AAC mono keeps a 15-minute
 * pass around 3–4 MB; recordings prune after 7 days via
 * [SatellitePassRecordingStore]. Foreground-only by design.
 *
 * Callers must hold RECORD_AUDIO before [start] (the record button
 * requests it). Recording takes transient audio focus and stops the
 * TuneIn stream first — TuneIn takes no focus itself, so the two would
 * otherwise talk over each other.
 */
object SatellitePassRecorder {
    data class State(
        val isRecording: Boolean = false,
        val markCount: Int = 0,
        val startedAtEpochMs: Long? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private var recorder: MediaRecorder? = null
    private var current: SatellitePassRecording? = null
    private var directory: java.io.File? = null
    private var focusRequest: AudioFocusRequest? = null

    /** Start recording for the selected bird; false when the recorder
     * can't start (missing permission surfaces here as an exception from
     * MediaRecorder, caught and returned as false). */
    fun start(context: Context, noradId: Int, satelliteName: String): Boolean {
        if (_state.value.isRecording) return true
        val app = context.applicationContext as CwApp
        app.tuneIn.stop()

        val dir = SatellitePassRecordingStore.defaultDirectory(context.filesDir)
        SatellitePassRecordingStore.prune(dir)

        val id = UUID.randomUUID().toString().lowercase()
        val startedAt = System.currentTimeMillis()
        val recording = SatellitePassRecording(
            id = id,
            noradId = noradId,
            satelliteName = satelliteName,
            startedAtEpochMs = startedAt,
            audioFileName = "$id.m4a",
        )
        val mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        return try {
            requestFocus(context)
            mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder.setAudioChannels(1)
            mediaRecorder.setAudioSamplingRate(22_050)
            mediaRecorder.setAudioEncodingBitRate(32_000)
            mediaRecorder.setOutputFile(
                SatellitePassRecordingStore.audioFile(recording, dir).absolutePath,
            )
            mediaRecorder.prepare()
            mediaRecorder.start()
            recorder = mediaRecorder
            current = recording
            directory = dir
            _state.value = State(isRecording = true, markCount = 0, startedAtEpochMs = startedAt)
            true
        } catch (_: Exception) {
            mediaRecorder.release()
            abandonFocus(context)
            false
        }
    }

    /** One "I just worked someone" tap. */
    fun mark() {
        val recording = current ?: return
        val started = _state.value.startedAtEpochMs ?: return
        if (!_state.value.isRecording) return
        val offset = (System.currentTimeMillis() - started) / 1_000.0
        current = recording.copy(markOffsets = recording.markOffsets + offset)
        _state.value = _state.value.copy(markCount = recording.markOffsets.size + 1)
    }

    /** Stop and persist; returns the finished recording. */
    fun stop(context: Context): SatellitePassRecording? {
        if (!_state.value.isRecording) return null
        val recording = current ?: return null
        val dir = directory ?: return null
        runCatching {
            recorder?.stop()
        }
        recorder?.release()
        recorder = null
        abandonFocus(context)
        val finished = recording.copy(endedAtEpochMs = System.currentTimeMillis())
        SatellitePassRecordingStore.save(finished, dir)
        current = null
        directory = null
        _state.value = State()
        return finished
    }

    /** The fresh recording (ended < 45 min ago) to play back in the
     * post-LOS quick log; stops a still-running recording first. */
    fun recentRecording(context: Context, noradId: Int): SatellitePassRecording? {
        if (_state.value.isRecording && current?.noradId == noradId) return stop(context)
        val dir = SatellitePassRecordingStore.defaultDirectory(context.filesDir)
        return SatellitePassRecordingStore.latest(noradId, dir)
    }

    fun stopIfRecording(context: Context) {
        if (_state.value.isRecording) stop(context)
    }

    private fun requestFocus(context: Context) {
        val audioManager = context.getSystemService(AudioManager::class.java) ?: return
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .build()
        focusRequest = request
        audioManager.requestAudioFocus(request)
    }

    private fun abandonFocus(context: Context) {
        val request = focusRequest ?: return
        focusRequest = null
        context.getSystemService(AudioManager::class.java)?.abandonAudioFocusRequest(request)
    }
}
