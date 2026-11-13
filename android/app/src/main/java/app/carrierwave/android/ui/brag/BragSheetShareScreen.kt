package app.carrierwave.android.ui.brag

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.carrierwave.android.ui.share.RecordedLayer
import app.carrierwave.android.ui.share.description
import app.carrierwave.android.ui.share.displayName
import uniffi.cw_ffi.FfiBragPeriod
import uniffi.cw_ffi.FfiBragPeriodConfig
import uniffi.cw_ffi.FfiBragStatMeta
import uniffi.cw_ffi.FfiBragStatResult
import uniffi.cw_ffi.FfiBragStatType

/**
 * Brag sheet share flow: style picker (6 Rust-rasterized [uniffi.cw_ffi.FfiShareMapStyle]s) +
 * live card preview + share. Mirrors iOS's brag-sheet share sheet, on the
 * shared Rust rasterizer instead of MapKit — see [BragSheetShareRenderer].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BragSheetShareScreen(
    vm: BragSheetShareViewModel,
    callsign: String,
    period: FfiBragPeriod,
    config: FfiBragPeriodConfig,
    results: List<FfiBragStatResult>,
    catalog: Map<FfiBragStatType, FfiBragStatMeta>,
    onBack: () -> Unit,
) {
    val state by vm.state.collectAsState()
    val context = LocalContext.current
    val cardLayer = rememberGraphicsLayer()

    LaunchedEffect(period) { vm.load(period) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Share Brag Sheet") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            state.error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }

            if (state.loading) {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                return@Column
            }

            StylePicker(
                available = state.availableStyles,
                selected = state.style,
                onSelect = vm::selectStyle,
            )

            // Card preview, continuously recorded into cardLayer on every draw
            // pass (see RecordedLayer) so the Share button below can rasterize
            // exactly what's on screen — no separate hidden copy.
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                RecordedLayer(cardLayer) {
                    BragSheetShareCard(
                        callsign = callsign,
                        period = period,
                        config = config,
                        results = results,
                        catalog = catalog,
                        mapImage = state.mapImage,
                        ringLabels = state.ringLabels,
                    )
                }
            }

            Button(
                onClick = { vm.share(context, cardLayer) },
                // Stats-only card (no clusters, no map) still shares — mirrors
                // iOS, which renders a nil-map card rather than blocking Share.
                enabled = !state.sharing && (state.noClusters || state.mapImage != null),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (state.sharing) {
                    CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                } else {
                    Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.padding(end = 8.dp))
                }
                Text(if (state.sharing) "Preparing…" else "Share")
            }
        }
    }
}

@Composable
private fun StylePicker(
    available: List<uniffi.cw_ffi.FfiShareMapStyle>,
    selected: uniffi.cw_ffi.FfiShareMapStyle,
    onSelect: (uniffi.cw_ffi.FfiShareMapStyle) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("Map Style", style = MaterialTheme.typography.titleSmall)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            available.forEach { style ->
                FilterChip(
                    selected = style == selected,
                    onClick = { onSelect(style) },
                    label = { Text(style.displayName()) },
                )
            }
        }
        Text(
            selected.description(),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
