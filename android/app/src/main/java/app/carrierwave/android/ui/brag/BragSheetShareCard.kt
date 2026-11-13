package app.carrierwave.android.ui.brag

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.carrierwave.android.ui.share.ShareMapBox
import uniffi.cw_ffi.FfiBragPeriod
import uniffi.cw_ffi.FfiBragPeriodConfig
import uniffi.cw_ffi.FfiBragStatMeta
import uniffi.cw_ffi.FfiBragStatResult
import uniffi.cw_ffi.FfiBragStatType
import uniffi.cw_ffi.FfiBragStatValue
import uniffi.cw_ffi.FfiRingLabel

/** Card-fixed pixel width for the share image (matches the map render width). */
const val SHARE_CARD_WIDTH_DP = 368

/** Map box width: [SHARE_CARD_WIDTH_DP] minus 16.dp horizontal padding on each side. */
private const val MAP_BOX_WIDTH_DP = SHARE_CARD_WIDTH_DP - 32

/**
 * Aspect ratio (width / height) of the rendered map PNG
 * ([BragSheetShareRenderer.MAP_WIDTH] / [BragSheetShareRenderer.MAP_HEIGHT] =
 * 736/400). The map box is sized to this ratio so the image fills its rounded
 * rect exactly, with no letterbox slivers.
 */
private const val MAP_ASPECT_RATIO = BragSheetShareRenderer.MAP_WIDTH.toFloat() / BragSheetShareRenderer.MAP_HEIGHT.toFloat()

/**
 * Brand gradient for the share card background. Port of iOS
 * `BragSheetTheme.cardBackground`
 * (`swift/ios/CarrierWave/Views/Activity/BragSheetTheme.swift:14-24`).
 */
private val cardGradient = Brush.linearGradient(
    colors = listOf(
        Color(red = 0.16f, green = 0.10f, blue = 0.32f, alpha = 1f),
        Color(red = 0.28f, green = 0.14f, blue = 0.45f, alpha = 1f),
        Color(red = 0.16f, green = 0.10f, blue = 0.32f, alpha = 1f),
    ),
    start = Offset(0f, 0f),
    end = Offset.Infinite,
)

private val white80 = Color.White.copy(alpha = 0.8f)
private val white60 = Color.White.copy(alpha = 0.6f)
private val white10 = Color.White.copy(alpha = 0.1f)
private val heroBackground = Color(0xFF9C27B0).copy(alpha = 0.2f) // Color.purple.opacity(0.2)

private fun FfiBragStatResult.isShareable(): Boolean = value !is FfiBragStatValue.NoData

/**
 * Brag sheet share card: header, optional map, hero stats, remaining enabled
 * stats, footer. Port of iOS `BragSheetShareCardView`
 * (`swift/ios/CarrierWave/Views/BragSheet/BragSheetShareCardView.swift`),
 * fixed at [SHARE_CARD_WIDTH_DP]dp wide with content-driven height (the iOS
 * view hardcodes height via `cardHeight`; Compose sizes to content instead of
 * precomputing it).
 */
@Composable
fun BragSheetShareCard(
    callsign: String,
    period: FfiBragPeriod,
    config: FfiBragPeriodConfig,
    results: List<FfiBragStatResult>,
    catalog: Map<FfiBragStatType, FfiBragStatMeta>,
    mapImage: ImageBitmap?,
    ringLabels: List<FfiRingLabel> = emptyList(),
    modifier: Modifier = Modifier,
) {
    val resultsByStat = results.associateBy { it.statType }
    val heroSet = config.heroStats.toSet()
    val heroStats = config.heroStats.take(4).filter { resultsByStat[it]?.isShareable() == true }
    val gridStats = config.enabledStats.filter {
        it !in heroSet && resultsByStat[it]?.isShareable() == true
    }

    Column(
        modifier = modifier
            .width(SHARE_CARD_WIDTH_DP.dp)
            .background(cardGradient),
    ) {
        // Header
        Column(
            modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                "CARRIER WAVE",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                period.shareHeadline(),
                color = Color.White,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.padding(top = 4.dp),
            )
        }

        // Period label
        Text(
            period.shareSubtitle(),
            color = white80,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 2.dp, bottom = 12.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )

        // Map (+ azimuthal ring-label overlay, drawn natively per the FFI
        // contract: [FfiRingLabel.x] is the horizontal center, text renders
        // ABOVE [FfiRingLabel.y] (the ring's top point) — see share_render_api.rs.
        // Labels are in the map PNG's native pixel space
        // (BragSheetShareRenderer.MAP_WIDTH x MAP_HEIGHT); Canvas below scales
        // them to the box's actual drawn size, matching the Image's
        // ContentScale.FillWidth + fixed-height clip (crops top/bottom, so the
        // vertical scale/offset must match the crop exactly).
        if (mapImage != null) {
            ShareMapBox(
                mapImage = mapImage,
                ringLabels = ringLabels,
                boxWidthDp = MAP_BOX_WIDTH_DP,
                aspectRatio = MAP_ASPECT_RATIO,
                modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 8.dp),
            )
        }

        // Hero stats
        if (heroStats.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                    .background(heroBackground)
                    .padding(vertical = 12.dp, horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                heroStats.forEach { stat ->
                    val result = resultsByStat[stat]
                    val meta = catalog[stat]
                    Column(
                        modifier = Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            result?.formatted ?: "-",
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                            style = MaterialTheme.typography.titleMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            meta?.shortDisplayName.orEmpty(),
                            color = white80,
                            style = TextStyle(fontSize = 10.sp),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }

        // Grid stats
        if (gridStats.isNotEmpty()) {
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                modifier = Modifier
                    .fillMaxWidth()
                    .height((42 * ((gridStats.size + 1) / 2)).dp)
                    .padding(horizontal = 16.dp)
                    .padding(top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                items(gridStats) { stat -> GridStatCell(stat, resultsByStat[stat], catalog[stat]) }
            }
        }

        // Footer
        Text(
            callsign,
            color = Color.White,
            fontWeight = FontWeight.SemiBold,
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 16.dp, bottom = 24.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}

@Composable
private fun GridStatCell(stat: FfiBragStatType, result: FfiBragStatResult?, meta: FfiBragStatMeta?) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(6.dp))
            .background(white10)
            .padding(horizontal = 8.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            iconForKey(meta?.iconKey ?: "number"),
            contentDescription = null,
            tint = white60,
            modifier = Modifier.height(12.dp).width(12.dp),
        )
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                result?.formatted ?: "-",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                style = TextStyle(fontSize = 11.sp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                meta?.displayName.orEmpty(),
                color = white60,
                style = TextStyle(fontSize = 8.sp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
