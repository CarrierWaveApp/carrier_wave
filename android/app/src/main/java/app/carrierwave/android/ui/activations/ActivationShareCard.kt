package app.carrierwave.android.ui.activations

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.carrierwave.android.ui.share.ShareMapBox
import uniffi.cw_ffi.FfiRingLabel

/** Card-fixed pixel width for the activation share image. */
private const val CARD_WIDTH_DP = 368
private const val MAP_BOX_WIDTH_DP = CARD_WIDTH_DP - 32
private const val MAP_ASPECT_RATIO =
    ActivationShareRenderer.MAP_WIDTH.toFloat() / ActivationShareRenderer.MAP_HEIGHT.toFloat()

/** Brand gradient — same as the brag card (iOS `BragSheetTheme.cardBackground`). */
private val cardGradient = Brush.linearGradient(
    colors = listOf(
        Color(red = 0.16f, green = 0.10f, blue = 0.32f, alpha = 1f),
        Color(red = 0.28f, green = 0.14f, blue = 0.45f, alpha = 1f),
        Color(red = 0.16f, green = 0.10f, blue = 0.32f, alpha = 1f),
    ),
    start = Offset(0f, 0f),
    end = Offset.Infinite,
)

private val white70 = Color.White.copy(alpha = 0.7f)
private val white15 = Color.White.copy(alpha = 0.15f)

/**
 * Activation share card: brand header, reference (park ref + name), date, the
 * RST-colored share map, and a stats strip (QSO count + bands). Port of iOS
 * `ActivationShareCardForExport`'s header/reference/stats/map sections
 * (`swift/ios/CarrierWave/Views/POTAActivations/ActivationShareCardView.swift`),
 * fixed at [CARD_WIDTH_DP]dp wide with content-driven height. The map + azimuthal
 * ring overlay reuse the shared [ShareMapBox].
 */
@Composable
fun ActivationShareCard(
    park: String,
    parkName: String?,
    callsign: String,
    displayDate: String,
    qsoCount: Int,
    bands: List<String>,
    mapImage: ImageBitmap?,
    ringLabels: List<FfiRingLabel> = emptyList(),
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .width(CARD_WIDTH_DP.dp)
            .background(cardGradient),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(top = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("CARRIER WAVE", color = Color.White, fontWeight = FontWeight.Bold, letterSpacing = 2.sp, style = MaterialTheme.typography.labelLarge)
            Text("POTA Activation", color = white70, style = MaterialTheme.typography.labelSmall)
        }

        // Reference: park code + optional name + date.
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                park,
                color = Color.White,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.titleMedium,
            )
            parkName?.takeIf { it.isNotBlank() }?.let {
                Text(it, color = white70, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center)
            }
            Text(displayDate, color = white70, style = MaterialTheme.typography.labelSmall)
        }

        if (mapImage != null) {
            ShareMapBox(
                mapImage = mapImage,
                ringLabels = ringLabels,
                boxWidthDp = MAP_BOX_WIDTH_DP,
                aspectRatio = MAP_ASPECT_RATIO,
                modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 8.dp),
            )
        } else {
            // Placeholder when no QSO grids resolve — parity with iOS's empty-map card.
            Box(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp)
                    .height((MAP_BOX_WIDTH_DP / MAP_ASPECT_RATIO).dp)
                    .clip(RoundedCornerShape(12.dp)).background(white15),
                contentAlignment = Alignment.Center,
            ) {
                Text("No mapped contacts", color = white70, style = MaterialTheme.typography.bodySmall)
            }
        }

        // Stats strip: QSO count + bands.
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp)
                .clip(RoundedCornerShape(12.dp)).background(white15).padding(vertical = 12.dp, horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            ShareStat("$qsoCount", "QSOs", Modifier.weight(1f))
            ShareStat("${bands.size}", if (bands.size == 1) "Band" else "Bands", Modifier.weight(1f))
        }
        if (bands.isNotEmpty()) {
            Text(
                bands.joinToString(" · "),
                color = white70,
                fontFamily = FontFamily.Monospace,
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
                textAlign = TextAlign.Center,
            )
        }

        Text(
            callsign,
            color = Color.White,
            fontWeight = FontWeight.SemiBold,
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 24.dp),
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun ShareStat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = Color.White, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
        Text(label, color = white70, style = MaterialTheme.typography.labelSmall)
    }
}
