package app.carrierwave.android.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.School
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import app.carrierwave.android.ui.AmtPractice
import app.carrierwave.android.ui.common.StatCell
import uniffi.cw_ffi.FfiAmtStats

/**
 * Another Morse Trainer settings — email-link sign-in (read-only `stats:read`),
 * the connected account and practice streak, refresh, and sign-out. There is no
 * password: the user types their AMT email, presses Confirm in the email, and
 * this screen finishes by polling (in Rust).
 */
@Composable
fun AmtSettingsScreen(onBack: () -> Unit, vm: AmtViewModel = viewModel(factory = AmtViewModel.factory())) {
    val state by vm.state.collectAsState()

    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.padding(start = 4.dp, end = 20.dp, top = 20.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
            }
            Text("Another Morse Trainer", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.School, contentDescription = null, tint = AmtPractice, modifier = Modifier.size(32.dp))
                Text(
                    "Show your Morse practice streak and practice days alongside your QSOs. " +
                        "Read-only — you can remove Carrier Wave from AMT at any time.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            when {
                state.signedIn -> Connected(state, onRefresh = vm::refreshStats, onSignOut = vm::signOut)
                state.busy || state.pendingEmail != null -> Waiting(state.pendingEmail, onCancel = vm::cancel)
                else -> SignInForm(onSend = vm::sendLink)
            }

            state.message?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (state.isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

@Composable
private fun SignInForm(onSend: (String) -> Unit) {
    var email by rememberSaveable { mutableStateOf("") }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Sign in", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("AMT account email") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = { onSend(email) },
                enabled = email.contains('@'),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Email me a sign-in link")
            }
            Text(
                "AMT emails you a link that works for 15 minutes. Open it and press Confirm; this screen " +
                    "finishes automatically. Carrier Wave never sees your password or email address.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Waiting(email: String?, onCancel: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                Spacer(Modifier.size(12.dp))
                Text("Check your email", style = MaterialTheme.typography.titleMedium)
            }
            Text(
                "Sent to ${email ?: "your AMT address"}. Opening the link alone does nothing — only the Confirm button signs you in.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    OutlinedButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) { Text("Cancel") }
}

@Composable
private fun Connected(state: AmtViewModel.State, onRefresh: () -> Unit, onSignOut: () -> Unit) {
    val stats: FfiAmtStats? = state.stats
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Connected", style = MaterialTheme.typography.titleMedium)
            state.account?.let { account ->
                Text(
                    listOfNotNull(account.callsign, account.displayName).ifEmpty { listOf(account.id) }.joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                val current = stats?.streak?.current ?: 0L
                StatCell(if (current > 0) "${current}d" else "—", "Streak", Modifier.weight(1f), accent = AmtPractice)
                StatCell("${stats?.streak?.longest ?: 0L}d", "Best", Modifier.weight(1f))
                StatCell(formatPractice(stats?.practiceSeconds ?: 0.0), "Practised", Modifier.weight(1f))
                StatCell("${stats?.sessions ?: 0L}", "Sessions", Modifier.weight(1f))
            }
            Text(
                "Stats refresh when you open Home. They stay at zero until your AMT apps start syncing. " +
                    "Practice days appear in the activity grid in purple.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedButton(onClick = onRefresh, enabled = !state.refreshing, modifier = Modifier.weight(1f)) {
            if (state.refreshing) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Spacer(Modifier.size(8.dp))
            }
            Text("Refresh now")
        }
        OutlinedButton(onClick = onSignOut, enabled = !state.busy, modifier = Modifier.weight(1f)) {
            Text("Sign out")
        }
    }
    Spacer(Modifier.height(4.dp))
}

/** "12 min" / "1 h 05 min" from practice seconds. */
private fun formatPractice(seconds: Double): String {
    val minutes = (seconds / 60.0).toLong()
    return when {
        minutes < 1 -> "0 min"
        minutes < 60 -> "$minutes min"
        minutes % 60 == 0L -> "${minutes / 60} h"
        else -> "${minutes / 60} h %02d min".format(minutes % 60)
    }
}
