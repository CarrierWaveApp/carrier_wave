package app.carrierwave.android.ui.parks

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Forest
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiMultiplierCandidate

/**
 * Rosette multiplier-finder sheet — Android analog of iOS `MultipliersSheet`.
 * Lists candidates returned by `ParkMapApi.findMultipliers` (already merged
 * one-record-per-location and sorted score-desc/title-asc by Rust); tapping a
 * row dismisses the sheet and recenters the map on it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MultipliersSheet(
    candidates: List<FfiMultiplierCandidate>,
    isFinding: Boolean,
    onSelect: (FfiMultiplierCandidate) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Text("Multipliers", style = MaterialTheme.typography.titleMedium)

            when {
                isFinding -> ScanningState()
                candidates.isEmpty() -> EmptyState()
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                        contentPadding = PaddingValues(bottom = 16.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        items(candidates) { candidate ->
                            MultiplierRow(candidate = candidate, onClick = { onSelect(candidate) })
                        }
                        item {
                            Text(
                                "Found by overlap of the layers in view. Zoom in for counties and SOTA zones.",
                                modifier = Modifier.padding(top = 8.dp),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ScanningState() {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator()
        Text(
            "Scanning overlaps…",
            modifier = Modifier.padding(top = 12.dp),
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

@Composable
private fun EmptyState() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            Icons.Filled.WorkspacePremium,
            contentDescription = null,
            modifier = Modifier.size(40.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text("No multipliers in view", style = MaterialTheme.typography.titleMedium)
        Text(
            "Turn on POTA, SOTA Zones, WWFF, or Counties and zoom in to flag 2-fers and county-line spots.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun MultiplierRow(candidate: FfiMultiplierCandidate, onClick: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(candidate.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
        Text(candidate.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            candidate.kinds.forEach { kind -> MultiplierBadge(kind = kind) }
        }
    }
}

@Composable
private fun MultiplierBadge(kind: String) {
    val tint = multiplierTint(kind)
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(tint.copy(alpha = 0.18f))
            .padding(horizontal = 8.dp, vertical = 3.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(multiplierIcon(kind), contentDescription = null, modifier = Modifier.size(14.dp), tint = tint)
        Text(kind, style = MaterialTheme.typography.labelSmall, color = tint)
    }
}

/** `MultiplierKind` raw values from the Rust side — `"POTA + SOTA"` |
 * `"POTA + WWFF"` | `"County line"`, iOS `MultiplierCandidate.swift` parity. */
private fun multiplierIcon(kind: String): ImageVector =
    when (kind) {
        "POTA + SOTA" -> Icons.Filled.Terrain
        "POTA + WWFF" -> Icons.Filled.Forest
        else -> Icons.Filled.Map
    }

private fun multiplierTint(kind: String): Color =
    when (kind) {
        "POTA + SOTA" -> Color(0xFF43A047)
        "POTA + WWFF" -> Color(0xFFD81B60)
        else -> Color(0xFF757575)
    }
