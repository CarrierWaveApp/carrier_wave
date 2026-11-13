package app.carrierwave.android.ui.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.AuthDeepLinkResult
import app.carrierwave.android.CwApp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import uniffi.cw_ffi.AuthApi
import uniffi.cw_ffi.FfiAuthOutcome

/**
 * Drives the OAuth login surface. All protocol logic (PKCE, polling, token
 * lifecycle) lives in the shared Rust [AuthApi]; this view model only sequences
 * the calls and exposes UI state.
 */
class AccountViewModel(private val app: CwApp) : ViewModel() {

    /** Read the auth client lazily so a server change (which rebuilds it) takes effect immediately. */
    private val auth: AuthApi get() = app.authApi

    data class State(
        val signedIn: Boolean = false,
        val accountId: String? = null,
        val pendingCallsign: String? = null,
        val serverUrl: String = "",
        val busy: Boolean = false,
        val message: String? = null,
    )

    private val _state = MutableStateFlow(snapshot())
    val state: StateFlow<State> = _state.asStateFlow()

    /** The in-flight start+poll coroutine, so [cancel] can actually stop it. */
    private var verifyJob: Job? = null

    init {
        // A magic link tapped elsewhere (App Link / custom scheme) completes in
        // CwApp; reflect its result here and stop any redundant in-flight poll.
        viewModelScope.launch {
            app.authDeepLink.collect { result ->
                verifyJob?.cancel()
                verifyJob = null
                _state.value = when (result) {
                    AuthDeepLinkResult.SignedIn -> snapshot(message = "Signed in.")
                    AuthDeepLinkResult.AttachedToAccount ->
                        snapshot(message = "Callsign added to your account.")
                    AuthDeepLinkResult.AcknowledgedRemotely ->
                        snapshot(message = "Link verified — finish on the device where you started.")
                    is AuthDeepLinkResult.Failed ->
                        snapshot(message = result.message ?: "Sign-in link failed.")
                }
            }
        }
    }

    /** Re-read the session/pending state from the secure store. */
    fun refresh() {
        _state.value = snapshot()
    }

    /** Point the app at a different activities server (clubs + OAuth). */
    fun updateServerUrl(url: String) {
        val ok = app.updateBaseUrl(url)
        _state.value = snapshot(
            message = if (ok) "Server set to ${app.baseUrl}" else "Couldn't use that server URL",
        )
    }

    private fun snapshot(busy: Boolean = false, message: String? = null) = State(
        signedIn = auth.hasSession(),
        accountId = auth.accountId(),
        pendingCallsign = auth.pendingCallsign(),
        serverUrl = app.baseUrl,
        busy = busy,
        message = message,
    )

    /** Request a magic link, then poll until it's clicked (or it times out). */
    fun sendMagicLink(callsign: String, email: String?) {
        val call = callsign.trim().uppercase()
        if (call.isEmpty()) {
            _state.update { it.copy(message = "Enter a callsign first.") }
            return
        }
        verifyJob?.cancel()
        verifyJob = viewModelScope.launch {
            _state.value = snapshot(busy = true, message = null)
            try {
                auth.startVerification(call, email?.trim()?.ifBlank { null })
                _state.value = snapshot(
                    busy = true,
                    message = "Check your email to finish signing in…",
                )
                poll()
            } catch (e: CancellationException) {
                throw e // Cooperative cancellation (user tapped Cancel) — not an error.
            } catch (e: Exception) {
                _state.value = snapshot(busy = false, message = e.message ?: "Couldn't start sign-in")
            }
        }
    }

    private suspend fun poll() {
        try {
            when (auth.pollForCompletion(POLL_TIMEOUT_SECS, POLL_INTERVAL_SECS)) {
                FfiAuthOutcome.SIGNED_IN -> {
                    _state.value = snapshot(message = "Signed in.")
                    app.autoSyncSocial()
                }
                FfiAuthOutcome.ATTACHED_TO_ACCOUNT -> {
                    _state.value = snapshot(message = "Callsign added to your account.")
                    app.autoSyncSocial()
                }
                FfiAuthOutcome.TIMED_OUT ->
                    _state.value = snapshot(message = "Timed out waiting for the link. Try again.")
            }
        } catch (e: CancellationException) {
            throw e // Let cancellation unwind cleanly instead of showing "Sign-in failed".
        } catch (e: Exception) {
            _state.value = snapshot(busy = false, message = e.message ?: "Sign-in failed")
        }
    }

    fun cancel() {
        verifyJob?.cancel()
        verifyJob = null
        auth.cancelPendingVerification()
        refresh()
    }

    fun signOut() {
        viewModelScope.launch {
            _state.update { it.copy(busy = true) }
            try {
                auth.logout()
            } catch (_: Exception) {
                // Local state is cleared regardless; a network failure is non-fatal.
            }
            _state.value = snapshot(message = "Signed out.")
        }
    }

    companion object {
        private const val POLL_TIMEOUT_SECS: UInt = 180u
        private const val POLL_INTERVAL_SECS: UInt = 3u

        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                AccountViewModel(app)
            }
        }
    }
}
