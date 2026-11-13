package app.carrierwave.android.ui.satellites

import android.media.MediaPlayer
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.carrierwave.android.data.SatellitePassRecording
import app.carrierwave.android.data.SatellitePassRecordingStore
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

/**
 * Inline playback for a fresh pass recording in the quick log (mirror of
 * the iOS `SatellitePassPlaybackView`): play/pause + scrub slider + one
 * chip per tap mark that seeks to mark − 5 s, so the operator can re-copy
 * the exchange they tapped on.
 */
@Composable
fun SatellitePassPlaybackView(recording: SatellitePassRecording) {
    val context = LocalContext.current
    var playing by remember { mutableStateOf(false) }
    var positionMs by remember { mutableIntStateOf(0) }
    var durationMs by remember { mutableIntStateOf(0) }

    val player = remember(recording.id) {
        val audio = SatellitePassRecordingStore.audioFile(
            recording,
            SatellitePassRecordingStore.defaultDirectory(context.filesDir),
        )
        runCatching {
            MediaPlayer().apply {
                setDataSource(audio.absolutePath)
                prepare()
            }
        }.getOrNull()
    }

    DisposableEffect(recording.id) {
        onDispose { player?.release() }
    }

    if (player == null) {
        Text(
            "Recording audio unavailable",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        return
    }
    durationMs = player.duration

    LaunchedEffect(playing) {
        while (isActive && playing) {
            positionMs = player.currentPosition
            if (!player.isPlaying) playing = false
            delay(250)
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = {
                if (playing) {
                    player.pause()
                    playing = false
                } else {
                    player.start()
                    playing = true
                }
            }) {
                Icon(
                    if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = if (playing) "Pause" else "Play",
                )
            }
            Slider(
                value = positionMs.toFloat(),
                onValueChange = { value ->
                    positionMs = value.toInt()
                    player.seekTo(value.toInt())
                },
                valueRange = 0f..durationMs.coerceAtLeast(1).toFloat(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (recording.markOffsets.isNotEmpty()) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                for ((index, offset) in recording.markOffsets.withIndex()) {
                    AssistChip(
                        onClick = {
                            // Land 5 s before the tap — the mark comes after
                            // the exchange, the exchange is what to re-copy.
                            val target = ((offset - 5) * 1_000).toInt().coerceAtLeast(0)
                            player.seekTo(target)
                            positionMs = target
                            if (!playing) {
                                player.start()
                                playing = true
                            }
                        },
                        label = { Text("Mark ${index + 1}") },
                    )
                }
            }
        }
    }
}
