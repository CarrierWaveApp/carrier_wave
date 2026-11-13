package app.carrierwave.android.ui.common

import androidx.compose.ui.graphics.Color

/**
 * Band → accent color, mirroring the iOS app's band palette so a 20m QSO reads
 * the same blue on both platforms. Falls back to a neutral gray for unknown or
 * missing bands.
 */
fun bandColor(band: String?): Color = when (band?.lowercase()?.trim()) {
    "160m" -> Color(0xFF9C6ADE) // purple
    "80m" -> Color(0xFF4CAF83) // green
    "60m" -> Color(0xFF66BB6A)
    "40m" -> Color(0xFFE5534B) // red
    "30m" -> Color(0xFFFF9800) // orange
    "20m" -> Color(0xFF4F8BFF) // blue
    "17m" -> Color(0xFF26C6DA) // cyan
    "15m" -> Color(0xFFFFCA28) // amber
    "12m" -> Color(0xFFAB47BC)
    "10m" -> Color(0xFFEC407A) // pink
    "6m" -> Color(0xFF00BFA5) // teal
    "4m" -> Color(0xFF7E57C2)
    "2m" -> Color(0xFF42A5F5)
    "70cm" -> Color(0xFF5C6BC0)
    else -> Color(0xFF8A8A8E)
}
