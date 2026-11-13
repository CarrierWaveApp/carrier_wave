package app.carrierwave.android.ui.share

import androidx.compose.ui.graphics.Color

/**
 * RST → signal-quality color, a verbatim port of the iOS `RSTColorHelper`
 * (`swift/ios/CarrierWave/Views/POTAActivations/ActivationMapComponents.swift`).
 * Used to tint the activation share-map pins by how well each QSO was heard:
 *
 * - Green: average RS >= 55 (excellent)
 * - Yellow: average RS >= 45 (good)
 * - Red:    average RS <  45 (weak)
 */
object RstColor {
    // Match iOS's systemGreen / systemYellow / systemRed on the share pins.
    private val Green = Color(0xFF34C759)
    private val Yellow = Color(0xFFFFCC00)
    private val Red = Color(0xFFFF3B30)

    /** Compose color from the average of sent/received RST. */
    fun color(rstSent: String?, rstReceived: String?): Color {
        val avg = averageRst(rstSent, rstReceived)
        return when {
            avg >= 55 -> Green
            avg >= 45 -> Yellow
            else -> Red
        }
    }

    /**
     * Parse an RST string and extract its numeric RS value.
     * "599" -> 59, "59" -> 59, "579" -> 57, "449" -> 44, "5" -> 50.
     */
    fun parseRst(rst: String?): Int? {
        if (rst.isNullOrEmpty()) return null
        val digits = rst.filter { it.isDigit() }
        if (digits.isEmpty()) return null
        // 3-digit RST (CW/digital): take the first two (RS); 2-digit RS (phone):
        // take both; single digit: scale to tens (iOS parity).
        return when {
            digits.length >= 2 -> digits.substring(0, 2).toIntOrNull()
            else -> digits.toIntOrNull()?.times(10)
        }
    }

    /**
     * Average of sent and received RS values; defaults to 55 when neither
     * parses (iOS parity — an unrated QSO reads as "good").
     */
    fun averageRst(sent: String?, received: String?): Int {
        val sentValue = parseRst(sent)
        val receivedValue = parseRst(received)
        return when {
            sentValue != null && receivedValue != null -> (sentValue + receivedValue) / 2
            sentValue != null -> sentValue
            receivedValue != null -> receivedValue
            else -> 55
        }
    }
}
