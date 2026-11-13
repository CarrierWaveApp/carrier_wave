package app.carrierwave.android.ui.map

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Park
import androidx.compose.material.icons.filled.Radio
import androidx.compose.material.icons.filled.SettingsInputAntenna
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiQsoMapAnnotation

/**
 * Callout shown when a map marker is tapped. Mirrors iOS `QSOCalloutView`:
 * title (callsign for a single QSO, else grid + count), up to three sample
 * callsigns, park references, and — when present — weather/solar/WPM/gear.
 * Tapping anywhere dismisses it.
 */
@Composable
fun QsoCalloutCard(annotation: FfiQsoMapAnnotation, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth().clickable(onClick = onDismiss),
        shape = RoundedCornerShape(8.dp),
        tonalElevation = 4.dp,
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                text = if (annotation.qsoCount == 1L) {
                    annotation.callsigns.firstOrNull() ?: annotation.gridSquare
                } else {
                    "${annotation.gridSquare} (${annotation.qsoCount})"
                },
                style = MaterialTheme.typography.titleMedium,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
            )

            if (annotation.qsoCount != 1L) {
                Text(
                    text = "${annotation.qsoCount} QSO${if (annotation.qsoCount == 1L) "" else "s"}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (annotation.callsigns.isNotEmpty()) {
                val shown = annotation.callsigns.take(3)
                val extra = annotation.callsigns.size - shown.size
                val text = shown.joinToString(", ") + if (extra > 0) ", +$extra more" else ""
                Text(
                    text = text,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                )
            }

            annotation.parkReferences.sorted().forEach { park ->
                CalloutRow(Icons.Filled.Park, park, color = MaterialTheme.colorScheme.tertiary)
            }
            annotation.averageWpm?.let { CalloutRow(Icons.Filled.Speed, "$it WPM avg") }
            annotation.radio?.let { CalloutRow(Icons.Filled.Radio, it) }
            annotation.antenna?.let { CalloutRow(Icons.Filled.SettingsInputAntenna, it) }
            annotation.key?.let { CalloutRow(Icons.Filled.Keyboard, it) }
            annotation.mic?.let { CalloutRow(Icons.Filled.Mic, it) }
            annotation.weather?.takeIf { it.isNotEmpty() }?.let { CalloutRow(Icons.Filled.Cloud, it) }
            annotation.solarConditions?.takeIf { it.isNotEmpty() }?.let { CalloutRow(Icons.Filled.WbSunny, it) }
        }
    }
}

@Composable
private fun CalloutRow(
    icon: ImageVector,
    text: String,
    color: Color = MaterialTheme.colorScheme.onSurfaceVariant,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.padding(top = 1.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = color, maxLines = 1)
    }
}
