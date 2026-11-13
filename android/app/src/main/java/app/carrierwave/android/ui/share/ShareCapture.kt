package app.carrierwave.android.ui.share

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer

/**
 * Composes [content] normally (this is the visible on-screen preview, not a
 * hidden copy) while continuously recording it into [layer] on every draw
 * pass, so [layer] always holds the last-drawn frame.
 *
 * Rasterizing must happen from a caller-triggered coroutine (e.g. a button
 * click), never from a `LaunchedEffect` fired on composition/recomposition —
 * `GraphicsLayer.toImageBitmap()` only rasterizes whatever was last
 * `record`ed and does **not** wait for or trigger a pending draw pass, so an
 * effect racing the first frame can capture a blank or stale bitmap. A click
 * can only happen after the composable has already drawn at least once, so
 * gating capture behind it structurally guarantees `record{}` already ran.
 * This mirrors the pattern in the official Compose graphics docs
 * (developer.android.com/develop/ui/compose/graphics/draw/modifiers).
 *
 * Extracted from the brag-sheet share flow (Task 9) so the activation share
 * card (Task 11) captures its on-screen card the same way.
 */
@Composable
fun RecordedLayer(layer: GraphicsLayer, content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .drawWithContent {
                layer.record { this@drawWithContent.drawContent() }
                drawLayer(layer)
            },
    ) {
        content()
    }
}

/** Rasterizes [this] layer's last-recorded frame to a [Bitmap]. Call only from a click/user-action coroutine — see [RecordedLayer]. */
suspend fun GraphicsLayer.captureToBitmap(): Bitmap = toImageBitmap().asAndroidBitmap()
