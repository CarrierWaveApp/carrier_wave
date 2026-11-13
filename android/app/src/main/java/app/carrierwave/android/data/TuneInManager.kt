package app.carrierwave.android.data

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import uniffi.cw_ffi.CwException
import uniffi.cw_ffi.FfiKiwiReceiver
import uniffi.cw_ffi.FfiTuneInSpot
import uniffi.cw_ffi.FfiTuneInStrategy
import uniffi.cw_ffi.SdrApi
import uniffi.cw_ffi.SdrAudioListener
import uniffi.cw_ffi.SdrConnection
import kotlin.math.roundToInt

enum class TuneInPhase { IDLE, CONNECTING, STREAMING }

data class TuneInState(
    val phase: TuneInPhase = TuneInPhase.IDLE,
    /** Spot waiting on the strategy picker (the dialog is up while non-null). */
    val pendingSpot: FfiTuneInSpot? = null,
    /** Spot currently being listened to. */
    val spot: FfiTuneInSpot? = null,
    /** Receiver the session is connected to. */
    val receiver: FfiKiwiReceiver? = null,
    val muted: Boolean = false,
    val error: String? = null,
)

/**
 * Tune-In playback controller — the Android counterpart of iOS
 * `TuneInManager`. Receiver selection, the KiwiSDR protocol, and PCM decode
 * all live in the shared Rust [SdrApi]; this class only picks a candidate,
 * owns the [AudioTrack], and publishes UI state.
 *
 * Deliberate v1 subset vs iOS (documented, not silently dropped): no
 * cellular-data warning, no CW transcription, no recording, no QSY /
 * receiver-quality monitors, and no auto-reconnect — a dropped connection
 * surfaces as an error instead.
 */
class TuneInManager(
    private val sdrApi: () -> SdrApi,
    private val myGrid: () -> String,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _state = MutableStateFlow(TuneInState())
    val state: StateFlow<TuneInState> = _state.asStateFlow()

    private var connectJob: Job? = null

    /**
     * Session generation — bumped (under [audioLock]) every teardown so a
     * stale Rust audio callback can never touch a newer session's track.
     */
    private var generation = 0
    private var connection: SdrConnection? = null
    private var track: AudioTrack? = null

    /** Frames that arrive before the handshake returns a sample rate. */
    private val pendingFrames = ArrayDeque<ShortArray>()
    private val audioLock = Any()

    /** Show the strategy picker for [spot]. */
    fun requestTuneIn(spot: FfiTuneInSpot) {
        _state.update { it.copy(pendingSpot = spot, error = null) }
    }

    fun dismissStrategyPicker() {
        _state.update { it.copy(pendingSpot = null) }
    }

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }

    /** Tune in to the pending spot with the chosen strategy. */
    fun tuneIn(strategy: FfiTuneInStrategy) {
        val spot = _state.value.pendingSpot ?: return
        stopInternal()
        val gen = synchronized(audioLock) { generation }
        _state.update {
            it.copy(
                phase = TuneInPhase.CONNECTING,
                pendingSpot = null,
                spot = spot,
                receiver = null,
                error = null,
            )
        }
        connectJob = scope.launch {
            val api = sdrApi()
            val candidates =
                api.selectCandidateReceivers(spot, strategy, myGrid().ifBlank { null })
            if (candidates.isEmpty()) {
                fail(gen, "No KiwiSDR receivers are available right now. Try again later.")
                return@launch
            }
            // Try each ranked candidate until one connects (iOS performTuneIn).
            for (candidate in candidates) {
                synchronized(audioLock) { if (gen != generation) return@launch }
                val conn = try {
                    api.connect(
                        host = candidate.host,
                        port = candidate.port,
                        frequencyKhz = spot.frequencyMhz * 1_000.0,
                        mode = spot.mode,
                        password = null,
                        listener = AudioSink(gen),
                    )
                } catch (_: CwException) {
                    continue
                }
                synchronized(audioLock) {
                    if (gen != generation) {
                        conn.disconnect()
                        return@launch
                    }
                    connection = conn
                    openTrack(conn.sampleRate().roundToInt())
                }
                _state.update { it.copy(phase = TuneInPhase.STREAMING, receiver = candidate) }
                return@launch
            }
            fail(gen, "Couldn't connect to any nearby receiver. Try again later.")
        }
    }

    fun toggleMute() {
        val muted = !_state.value.muted
        _state.update { it.copy(muted = muted) }
        synchronized(audioLock) { track?.setVolume(if (muted) 0f else 1f) }
    }

    /** Stop listening and tear the session down. */
    fun stop() {
        stopInternal()
        _state.update { TuneInState() }
    }

    /**
     * Tear the current session down. When [expectedGen] is given, only the
     * session it names is torn down — a stale caller (e.g. a disconnect
     * callback racing a fresh tune-in) becomes a no-op. Returns whether the
     * teardown ran.
     */
    private fun stopInternal(expectedGen: Int? = null): Boolean {
        val conn: SdrConnection?
        val oldTrack: AudioTrack?
        synchronized(audioLock) {
            if (expectedGen != null && expectedGen != generation) return false
            generation++
            conn = connection
            connection = null
            oldTrack = track
            track = null
            pendingFrames.clear()
        }
        connectJob?.cancel()
        connectJob = null
        conn?.disconnect()
        oldTrack?.let { t ->
            runCatching { t.stop() }
            t.release()
        }
        return true
    }

    private fun fail(gen: Int, message: String) {
        synchronized(audioLock) { if (gen != generation) return }
        _state.update {
            it.copy(phase = TuneInPhase.IDLE, spot = null, receiver = null, error = message)
        }
    }

    /** Must be called under [audioLock], after the handshake fixed the rate. */
    private fun openTrack(sampleRate: Int) {
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val newTrack = AudioTrack(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build(),
            AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build(),
            maxOf(minBuffer * 4, MIN_TRACK_BUFFER_BYTES),
            AudioTrack.MODE_STREAM,
            AudioManager.AUDIO_SESSION_ID_GENERATE,
        )
        newTrack.play()
        if (_state.value.muted) newTrack.setVolume(0f)
        track = newTrack
        while (pendingFrames.isNotEmpty()) {
            val frame = pendingFrames.removeFirst()
            newTrack.write(frame, 0, frame.size)
        }
    }

    /**
     * PCM sink for one connection. Frames can start arriving on a Rust
     * callback thread before `connect` returns the handle (and its sample
     * rate), so early frames buffer until [openTrack] drains them. The
     * blocking [AudioTrack.write] is the backpressure — the iOS ring buffer's
     * job.
     */
    private inner class AudioSink(private val gen: Int) : SdrAudioListener {
        override fun onAudioFrame(samples: List<Short>, sMeter: UShort) {
            val frame = samples.toShortArray()
            val out = synchronized(audioLock) {
                if (gen != generation) return
                track ?: run {
                    pendingFrames.addLast(frame)
                    while (pendingFrames.size > MAX_PENDING_FRAMES) pendingFrames.removeFirst()
                    return
                }
            }
            runCatching { out.write(frame, 0, frame.size) }
        }

        override fun onDisconnected(reason: String) {
            if (!stopInternal(expectedGen = gen)) return
            _state.update {
                it.copy(
                    phase = TuneInPhase.IDLE,
                    spot = null,
                    receiver = null,
                    error = "Lost the receiver: $reason",
                )
            }
        }
    }

    private companion object {
        /** Floor for the track buffer — a couple seconds at KiwiSDR's ~12 kHz. */
        const val MIN_TRACK_BUFFER_BYTES = 48 * 1024

        /** Cap pre-track buffering (~512 samples/frame ⇒ a few seconds). */
        const val MAX_PENDING_FRAMES = 64
    }
}
