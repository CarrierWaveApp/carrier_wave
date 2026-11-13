package app.carrierwave.android.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import app.carrierwave.android.CwApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.FfiCallsignEnrichment
import uniffi.cw_ffi.FfiQrzLookup
import uniffi.cw_ffi.callsignFlag
import uniffi.cw_ffi.maidenheadBearing
import uniffi.cw_ffi.maidenheadDistanceKm
import uniffi.cw_ffi.maidenheadIsValid

private const val MAX_CLUB_CHIPS = 3

/**
 * Callsign enrichment chips. DXCC entity (CTY.dat) and SKCC membership are
 * resolved locally and instantly from the shared core's cached datasets and are
 * always shown.
 *
 * When [includeQrz] is set (the live Logger / Hunter Log / Spots surfaces, never
 * historical QSO lists), the chip flow expands to feature-parity with the iOS
 * `LoggerCallsignCard`: country flag, operator name, QTH / state / grid /
 * license, CQ zone, continent, great-circle distance + bearing from the home
 * grid, club badges, the all-time "previously worked" count, and any
 * previous-callsign. QRZ fields require stored QRZ credentials; the rest are
 * local.
 *
 * Renders nothing until something resolves, so it's invisible before the
 * datasets download / when a callsign has no enrichment.
 */
@Composable
fun EnrichmentBadges(
    callsign: String,
    modifier: Modifier = Modifier,
    includeQrz: Boolean = false,
) {
    val app = LocalContext.current.applicationContext as CwApp

    val enrichment by produceState<FfiCallsignEnrichment?>(null, callsign) {
        value = withContext(Dispatchers.IO) {
            runCatching { app.enrichmentApi.lookup(callsign) }.getOrNull()
        }
    }
    // Merged QRZ + HamDB callbook (HamDB needs no credentials, so US calls still
    // resolve name/grid/QTH when QRZ is unconfigured).
    val qrz by produceState<FfiQrzLookup?>(null, callsign, includeQrz) {
        value = if (includeQrz) {
            withContext(Dispatchers.IO) {
                runCatching { app.qrzApi.lookupCallbook(callsign) }.getOrNull()
            }
        } else {
            null
        }
    }
    // All-time "previously worked" count — store query, only on live surfaces.
    val workedCount by produceState(0L, callsign, includeQrz) {
        value = if (includeQrz) {
            withContext(Dispatchers.IO) {
                runCatching { app.store.workedBeforeCount(callsign) }.getOrNull()
            } ?: 0L
        } else {
            0L
        }
    }

    val chips = buildEnrichmentChips(callsign, enrichment, qrz, workedCount, includeQrz)
    if (chips.isEmpty()) return

    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for (chip in chips) {
            EnrichChip(chip.text, chip.tone.bg(), chip.tone.fg(), mono = chip.mono)
        }
    }
}

/** Chip color category, resolved against the Material theme at render time. */
private enum class ChipTone { Dxcc, Detail, Skcc, Club, Member, Worked }

@Composable private fun ChipTone.bg(): Color = when (this) {
    ChipTone.Dxcc -> MaterialTheme.colorScheme.tertiaryContainer
    ChipTone.Detail -> MaterialTheme.colorScheme.surfaceVariant
    ChipTone.Skcc, ChipTone.Club -> MaterialTheme.colorScheme.secondaryContainer
    ChipTone.Member, ChipTone.Worked -> MaterialTheme.colorScheme.primaryContainer
}

@Composable private fun ChipTone.fg(): Color = when (this) {
    ChipTone.Dxcc -> MaterialTheme.colorScheme.onTertiaryContainer
    ChipTone.Detail -> MaterialTheme.colorScheme.onSurfaceVariant
    ChipTone.Skcc, ChipTone.Club -> MaterialTheme.colorScheme.onSecondaryContainer
    ChipTone.Member, ChipTone.Worked -> MaterialTheme.colorScheme.onPrimaryContainer
}

private data class Chip(val text: String, val tone: ChipTone, val mono: Boolean = false)

/**
 * Build the ordered chip list. DXCC + SKCC always show; everything else is gated
 * behind [includeQrz] so historical QSO rows stay lightweight and unchanged.
 */
@Composable
private fun buildEnrichmentChips(
    callsign: String,
    enrichment: FfiCallsignEnrichment?,
    qrz: FfiQrzLookup?,
    workedCount: Long,
    includeQrz: Boolean,
): List<Chip> {
    val flag = remember(callsign, includeQrz) {
        if (includeQrz) runCatching { callsignFlag(callsign) }.getOrNull() else null
    }
    val home = (LocalContext.current.applicationContext as CwApp).userHomeGrid
    val distance = remember(qrz?.grid, home) { gridDistanceBearing(home, qrz?.grid) }

    return buildList {
        if (includeQrz && flag != null) add(Chip(flag, ChipTone.Detail))
        enrichment?.dxccName?.let { add(Chip("🌍 $it", ChipTone.Dxcc)) }
        if (includeQrz) {
            qrz?.name?.let { add(Chip("👤 $it", ChipTone.Detail)) }
            qrz?.qth?.let { add(Chip(it, ChipTone.Detail)) }
            qrz?.state?.let { add(Chip(it, ChipTone.Detail)) }
            qrz?.grid?.let { add(Chip(it, ChipTone.Detail)) }
            qrz?.licenseClass?.let { add(Chip(it, ChipTone.Detail)) }
            enrichment?.cqZone?.let { add(Chip("CQ $it", ChipTone.Detail)) }
            enrichment?.continent?.let { add(Chip(it, ChipTone.Detail)) }
            distance?.let { add(Chip(it, ChipTone.Detail)) }
        }
        enrichment?.skccBadge?.let { add(Chip("SKCC $it", ChipTone.Skcc, mono = true)) }
        if (includeQrz) {
            enrichment?.clubs?.take(MAX_CLUB_CHIPS)?.forEach { add(Chip(it, ChipTone.Club)) }
            val extraClubs = (enrichment?.clubs?.size ?: 0) - MAX_CLUB_CHIPS
            if (extraClubs > 0) add(Chip("+$extraClubs", ChipTone.Club))
            // Server memberships (CWops, etc.) with their precomputed chip label.
            enrichment?.memberships?.forEach { add(Chip(it.chipLabel, ChipTone.Member)) }
            if (workedCount > 0) add(Chip("×$workedCount prev", ChipTone.Worked))
            qrz?.previousCallsign?.let { add(Chip("↔ $it", ChipTone.Detail)) }
        }
    }
}

/** "1,234 km · 045° ↗" from [home] to [theirGrid], or null. */
private fun gridDistanceBearing(home: String, theirGrid: String?): String? {
    if (theirGrid == null || !maidenheadIsValid(theirGrid) || !maidenheadIsValid(home)) return null
    val km = maidenheadDistanceKm(home, theirGrid) ?: return null
    val bearing = maidenheadBearing(home, theirGrid)
    return if (bearing != null) {
        "%,.0f km · %03.0f° %s".format(km, bearing, bearingArrow(bearing))
    } else {
        "%,.0f km".format(km)
    }
}

@Composable
private fun EnrichChip(text: String, bg: Color, fg: Color, mono: Boolean = false) {
    Surface(color = bg, contentColor = fg, shape = RoundedCornerShape(6.dp)) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default,
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}
