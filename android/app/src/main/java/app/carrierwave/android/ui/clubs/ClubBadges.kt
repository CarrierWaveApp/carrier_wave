package app.carrierwave.android.ui.clubs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.carrierwave.android.CwApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Small club-affiliation chips for a callsign, resolved from the local store's
 * membership cache (the shared Rust `clubs_for_callsign` lookup). Renders nothing
 * until clubs have been synced, so it's invisible before sign-in.
 */
@Composable
fun ClubBadges(callsign: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val clubs by produceState(initialValue = emptyList<String>(), callsign) {
        value = withContext(Dispatchers.IO) {
            (context.applicationContext as CwApp).store.clubsForCallsign(callsign)
        }
    }

    if (clubs.isEmpty()) return
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        clubs.take(MAX_CHIPS).forEach { ClubChip(it) }
        if (clubs.size > MAX_CHIPS) {
            ClubChip("+${clubs.size - MAX_CHIPS}")
        }
    }
}

@Composable
private fun ClubChip(text: String) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
        shape = RoundedCornerShape(6.dp),
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
        )
    }
}

private const val MAX_CHIPS = 3
