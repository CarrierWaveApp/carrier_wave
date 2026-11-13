package app.carrierwave.android.ui.satellites

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kotlin.math.abs

/**
 * Bottom overlay of the sky dome (port of the iOS `SkyDomeFooter`): hover
 * metadata card, selected-satellite status with the polarization hint on
 * lock, or a hint when nothing is selected.
 */
@Composable
fun SkyDomeFooter(
    vm: SatelliteViewModel,
    hovered: SkySighting?,
    selected: SkySighting?,
    selectedNoradId: UInt?,
    isOnTarget: Boolean,
    elementTiltDeg: Double?,
    modifier: Modifier = Modifier,
) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = Color.Black.copy(alpha = 0.55f),
        modifier = modifier.widthIn(max = 360.dp),
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
        ) {
            when {
                hovered != null -> HoverCard(vm, hovered, selectedNoradId, isOnTarget, elementTiltDeg)
                selected != null -> SelectedStatus(vm, selected, selectedNoradId, isOnTarget, elementTiltDeg)
                else -> Text(
                    "Select a satellite on the chart to highlight it here",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.7f),
                )
            }
        }
    }
}

@Composable
private fun SelectedStatus(
    vm: SatelliteViewModel,
    selected: SkySighting,
    selectedNoradId: UInt?,
    isOnTarget: Boolean,
    elementTiltDeg: Double?,
) {
    if (selected.elDeg <= 0) {
        Text(
            "${selected.position.name} is below the horizon",
            style = MaterialTheme.typography.bodyMedium,
            color = Color.White.copy(alpha = 0.7f),
        )
        return
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            selected.position.name,
            style = MaterialTheme.typography.titleMedium,
            fontFamily = FontFamily.Monospace,
            color = if (isOnTarget) Color(0xFF4CAF50) else Color(0xFFFF9800),
        )
        Text(
            "AZ %.0f°  EL %.0f°".format(selected.azDeg, selected.elDeg),
            style = MaterialTheme.typography.bodyMedium,
            color = Color.White,
        )
    }
    if (isOnTarget) LockLine(vm, selectedNoradId, elementTiltDeg)
}

@Composable
private fun HoverCard(
    vm: SatelliteViewModel,
    hovered: SkySighting,
    selectedNoradId: UInt?,
    isOnTarget: Boolean,
    elementTiltDeg: Double?,
) {
    val isSelected = hovered.position.noradId == selectedNoradId
    val summary = vm.summary(hovered.position.noradId)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            hovered.position.name,
            style = MaterialTheme.typography.titleMedium,
            fontFamily = FontFamily.Monospace,
            color = if (isSelected) Color(0xFFFF9800) else Color.White,
            maxLines = 1,
        )
        Text(
            "NORAD ${hovered.position.noradId}",
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.6f),
        )
        summary?.polarization?.let { polarization ->
            Text(
                polarization.label,
                style = MaterialTheme.typography.labelSmall,
                color = Color(0xFF80DEEA),
            )
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            "AZ %.0f°".format(hovered.azDeg),
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.7f),
        )
        Text(
            "EL %.0f°".format(hovered.elDeg),
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.7f),
        )
        hovered.position.rangeKm?.let { range ->
            Text(
                "%.0f km".format(range),
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = 0.7f),
            )
        }
        Text(
            "alt ${hovered.position.altKm.toInt()} km",
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.7f),
        )
    }
    val transmitters = summary?.transmitters.orEmpty()
    for (transmitter in transmitters.take(3)) {
        val downlink = transmitter.downlinkLowHz?.let { "↓ %.3f".format(it / 1_000_000.0) }
        val uplink = transmitter.uplinkLowHz?.let { "↑ %.3f".format(it / 1_000_000.0) }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            TransmitterHeardDot(transmitter)
            Text(
                listOfNotNull(transmitter.mode, downlink, uplink).joinToString("  ") +
                    if (!transmitter.isActive) "  (inactive)" else "",
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = if (transmitter.isActive) 0.85f else 0.5f),
                maxLines = 1,
            )
        }
    }
    if (transmitters.size > 3) {
        Text(
            "+ ${transmitters.size - 3} more transmitters",
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.5f),
        )
    }
    if (isSelected && isOnTarget) LockLine(vm, selectedNoradId, elementTiltDeg)
}

@Composable
private fun LockLine(vm: SatelliteViewModel, selectedNoradId: UInt?, elementTiltDeg: Double?) {
    Text(
        "✓ On target",
        style = MaterialTheme.typography.bodyMedium,
        color = Color(0xFF4CAF50),
    )
    val polarization = selectedNoradId?.let { vm.summary(it)?.polarization }
    when {
        polarization != null && polarization.isCircular -> Text(
            polarization.pointingHint,
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.7f),
        )
        elementTiltDeg != null -> {
            val suffix = when {
                abs(elementTiltDeg) < 20 -> " (H)"
                abs(elementTiltDeg) > 70 -> " (V)"
                else -> ""
            }
            Text(
                "Polarization roll %.0f°%s — twist to peak, flip 90° if it fades"
                    .format(elementTiltDeg, suffix),
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = 0.7f),
            )
        }
    }
}
