package app.carrierwave.android.ui.share

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import uniffi.cw_ffi.FfiRingLabel

/**
 * Shared map-image box for share cards (brag sheet + activation, both map port
 * Phase D). Renders [mapImage] scaled to fill the box width at the rendered
 * PNG's own aspect ratio (no letterbox), with the azimuthal ring-label overlay
 * drawn natively on top per the FFI contract. Extracted from the brag-sheet
 * card so the activation card reuses the exact same crop + overlay math.
 *
 * [boxWidthDp] is the box's laid-out width in dp (card width minus horizontal
 * padding); the height derives from it and [aspectRatio] (width / height of the
 * rendered PNG).
 */
@Composable
fun ShareMapBox(
    mapImage: ImageBitmap,
    ringLabels: List<FfiRingLabel>,
    boxWidthDp: Int,
    aspectRatio: Float,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height((boxWidthDp / aspectRatio).dp)
            .clip(RoundedCornerShape(12.dp)),
    ) {
        Image(
            bitmap = mapImage,
            contentDescription = null,
            contentScale = ContentScale.FillWidth,
            modifier = Modifier.fillMaxSize(),
        )
        if (ringLabels.isNotEmpty()) {
            RingLabelOverlay(
                ringLabels = ringLabels,
                nativeWidth = mapImage.width,
                nativeHeight = mapImage.height,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

/**
 * Draws [ringLabels] (in the map PNG's native pixel space, `nativeWidth` x
 * `nativeHeight`) over the map box. `ContentScale.FillWidth` scales the image so
 * its width exactly fills the box, uniformly scaling height too — the box's
 * fixed height then center-crops any excess.
 *
 * Per the FFI contract ([FfiRingLabel]): `x` is the label's horizontal center,
 * and the text is drawn entirely ABOVE `y` (the ring's top point). The baseline
 * is derived as `y·scale − paint.descent() − 1` so the glyphs' descenders (and a
 * hairline of clearance) sit just above `y`, matching iOS's exact placement.
 * ~7sp, white at 0.2 alpha.
 */
@Composable
private fun RingLabelOverlay(
    ringLabels: List<FfiRingLabel>,
    nativeWidth: Int,
    nativeHeight: Int,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val textSizePx = with(density) { 7.sp.toPx() }
    Canvas(modifier = modifier) {
        if (nativeWidth <= 0 || nativeHeight <= 0) return@Canvas
        val scale = size.width / nativeWidth
        val scaledHeight = nativeHeight * scale
        val yOffset = (size.height - scaledHeight) / 2f

        val paint = android.graphics.Paint().apply {
            isAntiAlias = true
            color = android.graphics.Color.argb(51, 255, 255, 255) // white, 0.2 alpha
            textSize = textSizePx
            textAlign = android.graphics.Paint.Align.CENTER
        }

        translate(left = 0f, top = yOffset) {
            drawContext.canvas.nativeCanvas.let { canvas ->
                ringLabels.forEach { label ->
                    val x = label.x * scale
                    val y = label.y * scale - paint.descent() - 1f
                    canvas.drawText(label.text, x, y, paint)
                }
            }
        }
    }
}
