package app.carrierwave.android.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.carrierwave.android.ui.clubs.ClubBadges
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.maidenheadBearing
import uniffi.cw_ffi.maidenheadDistanceKm
import uniffi.cw_ffi.maidenheadIsValid

/**
 * Shared QSO card used by both the Logger and the Session detail. Carries the
 * band-accent left bar, monospace callsign, band/mode pills, grid distance, RST,
 * and a timestamp rendered either as a full date or session-relative time.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun QsoCard(
    qso: FfiQso,
    homeGrid: String,
    modifier: Modifier = Modifier,
    relativeTime: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val distanceText = remember(qso.theirGrid, homeGrid) { gridDistance(homeGrid, qso.theirGrid) }

    ElevatedCard(
        onClick = onClick ?: {},
        enabled = onClick != null,
        modifier = modifier.fillMaxWidth(),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
        colors = CardDefaults.elevatedCardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
            // Read-only call sites pass no onClick (enabled = false); keep them
            // looking identical to the tappable ones.
            disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            // Band accent bar
            Surface(
                color = bandColor(qso.band),
                modifier = Modifier.width(3.dp).height(74.dp),
            ) {}
            Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp).fillMaxWidth()) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(
                        text = qso.callsign,
                        style = MaterialTheme.typography.titleMedium,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        qso.band?.let { BandPill(it) }
                        qso.mode?.let { ModePill(it) }
                    }
                }
                ClubBadges(qso.callsign, modifier = Modifier.padding(top = 2.dp))
                EnrichmentBadges(qso.callsign, modifier = Modifier.padding(top = 2.dp))
                formatFreq(qso.freqKhz)?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
                val park = qso.theirPark ?: qso.park
                if (qso.theirGrid != null || distanceText != null || park != null) {
                    Row(
                        Modifier.padding(top = 2.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        qso.theirGrid?.let {
                            Text(
                                it,
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        distanceText?.let {
                            Text(
                                it,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.75f),
                            )
                        }
                        park?.let {
                            Text(
                                "🌲 $it",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.tertiary,
                            )
                        }
                    }
                }
                Row(
                    Modifier.fillMaxWidth().padding(top = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = rstText(qso),
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = if (relativeTime) formatTime(qso.qsoDate) else formatTimestamp(qso.qsoDate),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    )
                }
            }
        }
    }
}

private fun rstText(qso: FfiQso): String = buildString {
    qso.rstSent?.let { append(it) }
    if (qso.rstSent != null && qso.rstRcvd != null) append(" / ")
    qso.rstRcvd?.let { append(it) }
}

/** "1,234 km / 045° ↗" between two grids, or null when not computable. */
fun gridDistance(homeGrid: String, grid: String?): String? {
    if (grid == null || !maidenheadIsValid(grid) || !maidenheadIsValid(homeGrid)) return null
    val km = maidenheadDistanceKm(homeGrid, grid) ?: return null
    val brg = maidenheadBearing(homeGrid, grid) ?: return null
    return "%,.0f km / %03.0f° %s".format(km, brg, bearingArrow(brg))
}
