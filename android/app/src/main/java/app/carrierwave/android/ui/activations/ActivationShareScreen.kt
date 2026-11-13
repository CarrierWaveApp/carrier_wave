package app.carrierwave.android.ui.activations

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.carrierwave.android.ui.share.RecordedLayer
import app.carrierwave.android.ui.share.description
import app.carrierwave.android.ui.share.displayName
import uniffi.cw_ffi.FfiShareMapStyle

/**
 * Activation share-card flow: map-style picker + live card preview + share.
 * Mirrors the brag-sheet share screen (Task 9), on the shared Rust rasterizer.
 * Reached from the activation detail screen's share action.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivationShareScreen(
    park: String,
    parkName: String?,
    callsign: String,
    utcDate: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    vm: ActivationShareViewModel = viewModel(factory = ActivationShareViewModel.factory()),
) {
    val state by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val cardLayer = rememberGraphicsLayer()

    LaunchedEffect(park, callsign, utcDate) { vm.load(park, callsign, utcDate) }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Share Activation") },
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

            StylePicker(available = state.availableStyles, selected = state.style, onSelect = vm::selectStyle)

            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                RecordedLayer(cardLayer) {
                    ActivationShareCard(
                        park = park,
                        parkName = parkName,
                        callsign = callsign,
                        displayDate = utcDate,
                        qsoCount = state.qsoCount,
                        bands = state.bands,
                        mapImage = state.mapImage,
                        ringLabels = state.ringLabels,
                    )
                }
            }

            Button(
                onClick = { vm.share(context, cardLayer) },
                // Card with an empty-map placeholder still shares — mirrors iOS.
                enabled = !state.sharing && (state.noMappableQsos || state.mapImage != null),
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
    available: List<FfiShareMapStyle>,
    selected: FfiShareMapStyle,
    onSelect: (FfiShareMapStyle) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("Map Style", style = MaterialTheme.typography.titleSmall)
        androidx.compose.foundation.layout.Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
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
        Text(selected.description(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
