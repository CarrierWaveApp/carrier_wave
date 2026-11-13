package app.carrierwave.android.ui.satellites

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

/**
 * G1000-convention pointing instruments on the sky-dome theme (port of
 * the iOS `PointingCompassTape` / `PointingElevationScale`): white scales
 * on black, orange fly-to bug/diamond, hollow when pinned off-scale.
 */
private val FLY_TO = Color(0xFFFF9800)
private val SCALE_WHITE = Color.White.copy(alpha = 0.9f)

/** ±45° heading-tape window centered on the boresight azimuth. */
@Composable
fun PointingCompassTape(pointingAzDeg: Double, targetAzDeg: Double) {
    val textMeasurer = rememberTextMeasurer()
    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(92.dp),
    ) {
        drawCompassTicks(pointingAzDeg, textMeasurer)
        drawCompassBug(pointingAzDeg, targetAzDeg)
        drawLubber()
    }
}

private const val WINDOW_DEG = 45.0

private fun DrawScope.compassX(delta: Double): Float =
    (size.width / 2 + delta * (size.width / (2 * WINDOW_DEG))).toFloat()

private fun compassLabel(degrees: Double): String = when (degrees.roundToInt()) {
    0 -> "N"
    90 -> "E"
    180 -> "S"
    270 -> "W"
    else -> degrees.roundToInt().toString()
}

private fun DrawScope.drawCompassTicks(pointingAzDeg: Double, textMeasurer: TextMeasurer) {
    val baseY = size.height - 24.dp.toPx()
    drawLine(
        SCALE_WHITE,
        Offset(0f, baseY),
        Offset(size.width, baseY),
        strokeWidth = 2.dp.toPx(),
    )
    var degree = kotlin.math.ceil((pointingAzDeg - WINDOW_DEG) / 5) * 5
    while (degree <= pointingAzDeg + WINDOW_DEG) {
        val normalized = ((degree % 360.0) + 360.0) % 360.0
        val tickX = compassX(degree - pointingAzDeg)
        val isMajor = normalized % 30.0 == 0.0
        val isMedium = normalized % 10.0 == 0.0
        val height = (if (isMajor) 24 else if (isMedium) 16 else 9).dp.toPx()
        drawLine(
            SCALE_WHITE,
            Offset(tickX, baseY),
            Offset(tickX, baseY - height),
            strokeWidth = (if (isMajor) 3 else 2).dp.toPx(),
        )
        if (isMajor) {
            val layout = textMeasurer.measure(
                compassLabel(normalized),
                style = TextStyle(
                    color = Color.White,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                ),
            )
            drawText(
                layout,
                topLeft = Offset(
                    tickX - layout.size.width / 2f,
                    baseY - height - 14.dp.toPx() - layout.size.height / 2f,
                ),
            )
        }
        degree += 5
    }
}

private fun DrawScope.drawCompassBug(pointingAzDeg: Double, targetAzDeg: Double) {
    val baseY = size.height - 24.dp.toPx()
    val delta = PointingFrame.wrap180(targetAzDeg - pointingAzDeg)
    val clamped = delta.coerceIn(-WINDOW_DEG, WINDOW_DEG)
    val bugX = compassX(clamped)
    val bug = Path().apply {
        moveTo(bugX, baseY + 4.dp.toPx())
        lineTo(bugX - 12.dp.toPx(), baseY + 20.dp.toPx())
        lineTo(bugX + 12.dp.toPx(), baseY + 20.dp.toPx())
        close()
    }
    if (clamped == delta) {
        drawPath(bug, FLY_TO)
    } else {
        drawPath(bug, FLY_TO, style = Stroke(width = 3.dp.toPx()))
    }
}

private fun DrawScope.drawLubber() {
    val baseY = size.height - 24.dp.toPx()
    val midX = size.width / 2
    drawLine(
        Color.White,
        Offset(midX, baseY - 30.dp.toPx()),
        Offset(midX, baseY + 2.dp.toPx()),
        strokeWidth = 4.dp.toPx(),
    )
    val pointer = Path().apply {
        moveTo(midX, baseY - 2.dp.toPx())
        lineTo(midX - 8.dp.toPx(), baseY + 12.dp.toPx())
        lineTo(midX + 8.dp.toPx(), baseY + 12.dp.toPx())
        close()
    }
    drawPath(pointer, Color.White)
}

/** Glideslope-style vertical deviation scale: dots at ±10°/±20°, orange
 * diamond at the elevation error (above center = tilt up). */
@Composable
fun PointingElevationScale(elErrorDeg: Double) {
    Canvas(
        modifier = Modifier
            .width(44.dp)
            .heightIn(max = 300.dp)
            .height(300.dp),
    ) {
        drawElevationScale()
        drawElevationDiamond(elErrorDeg)
    }
}

private const val EL_WINDOW_DEG = 30.0

private fun DrawScope.elevationY(error: Double): Float =
    (size.height / 2 - error * (size.height / (2 * EL_WINDOW_DEG))).toFloat()

private fun DrawScope.drawElevationScale() {
    val midX = size.width / 2
    for (dotDeg in listOf(-20.0, -10.0, 10.0, 20.0)) {
        drawCircle(
            SCALE_WHITE,
            radius = 4.dp.toPx(),
            center = Offset(midX, elevationY(dotDeg)),
            style = Stroke(width = 2.dp.toPx()),
        )
    }
    drawLine(
        Color.White,
        Offset(midX - 14.dp.toPx(), size.height / 2),
        Offset(midX + 14.dp.toPx(), size.height / 2),
        strokeWidth = 4.dp.toPx(),
    )
}

private fun DrawScope.drawElevationDiamond(elErrorDeg: Double) {
    val midX = size.width / 2
    val clamped = elErrorDeg.coerceIn(-EL_WINDOW_DEG, EL_WINDOW_DEG)
    val midY = elevationY(clamped)
    val diamond = Path().apply {
        moveTo(midX, midY - 12.dp.toPx())
        lineTo(midX + 10.dp.toPx(), midY)
        lineTo(midX, midY + 12.dp.toPx())
        lineTo(midX - 10.dp.toPx(), midY)
        close()
    }
    if (clamped == elErrorDeg) {
        drawPath(diamond, FLY_TO)
    } else {
        drawPath(diamond, FLY_TO, style = Stroke(width = 3.dp.toPx()))
    }
}
