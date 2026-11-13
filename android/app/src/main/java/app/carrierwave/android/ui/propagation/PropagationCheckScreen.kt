package app.carrierwave.android.ui.propagation

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

/**
 * Host composable for the propagation-check feature — switches between the
 * start sheet, live view, and results view off [PropagationCheckViewModel]'s
 * [PropagationCheckScreen] state. The Android analog of iOS
 * `PropagationCheckRootView`'s sheet/fullScreenCover choreography, collapsed
 * into one screen since Android drives this feature with `rememberSaveable`
 * overlays (see `MainActivity`) rather than a persisted list of past checks.
 */
@Composable
fun PropagationCheckHostScreen(
    onBack: () -> Unit,
    vm: PropagationCheckViewModel = viewModel(factory = PropagationCheckViewModel.factory()),
) {
    val ui by vm.ui.collectAsStateWithLifecycle()

    BackHandler {
        when (ui.screen) {
            PropagationCheckScreen.START -> onBack()
            PropagationCheckScreen.LIVE -> vm.stop(uniffi.cw_ffi.FfiPropagationStopReason.USER)
            PropagationCheckScreen.RESULTS -> vm.reset()
        }
    }

    when (ui.screen) {
        PropagationCheckScreen.START -> PropagationCheckStartScreen(
            defaultCallsign = ui.defaultCallsign,
            defaultGrid = ui.defaultGrid,
            onBack = onBack,
            onStart = vm::start,
        )
        PropagationCheckScreen.LIVE -> PropagationCheckLiveScreen(vm)
        PropagationCheckScreen.RESULTS -> {
            val results = ui.results
            if (results != null) {
                PropagationCheckResultsScreen(
                    results = results,
                    stopReason = ui.stopReason,
                    onDone = { vm.reset(); onBack() },
                )
            } else {
                // No finalized results (shouldn't happen — stop() always sets
                // one on success) — fall back to the start sheet.
                PropagationCheckStartScreen(
                    defaultCallsign = ui.defaultCallsign,
                    defaultGrid = ui.defaultGrid,
                    onBack = onBack,
                    onStart = vm::start,
                )
            }
        }
    }
}
