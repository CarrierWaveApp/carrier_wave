package app.carrierwave.android.ui.common

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiDuplicateStatus

/**
 * Day-scoped duplicate badge — the 5-state [FfiDuplicateStatus] port of iOS
 * `CallsignDuplicateStatus`. A new band/mode reads green (a valid new QSO); a
 * same-band/mode dupe or a band-unknown prior contact reads amber. First
 * contact shows nothing. Shared by the Hunter, Logger, and Session command bars.
 */
@Composable
fun DupeBadge(status: FfiDuplicateStatus, modifier: Modifier = Modifier) {
    val amber = Color(0xFFFFB74D)
    val green = Color(0xFF66BB6A)
    val info: Pair<String, Color>? = when (status) {
        is FfiDuplicateStatus.FirstContact -> null
        is FfiDuplicateStatus.PreviouslyWorked -> "worked today" to amber
        is FfiDuplicateStatus.NewBand -> "new band" to green
        is FfiDuplicateStatus.NewMode -> "new mode" to green
        is FfiDuplicateStatus.DuplicateBand -> "dupe" to amber
    }
    if (info == null) return
    val (label, color) = info
    Surface(
        shape = RoundedCornerShape(6.dp),
        color = color.copy(alpha = 0.18f),
        border = BorderStroke(0.5.dp, color.copy(alpha = 0.6f)),
        modifier = modifier,
    ) {
        Row(
            Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.CheckCircle, contentDescription = null, modifier = Modifier.size(14.dp), tint = color)
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium,
                color = color,
            )
        }
    }
}
