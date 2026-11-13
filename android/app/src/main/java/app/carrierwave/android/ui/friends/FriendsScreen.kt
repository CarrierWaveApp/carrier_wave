package app.carrierwave.android.ui.friends

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.ui.common.SectionHeader
import app.carrierwave.android.ui.common.formatDay
import uniffi.cw_ffi.FfiFeedItem
import uniffi.cw_ffi.FfiFriendship
import uniffi.cw_ffi.FfiUserSearchResult

/**
 * Friends — social graph + activity feed. Mirrors the iOS Friends (`activity`)
 * tab: add-by-search, incoming/outgoing requests, accepted friends, and the
 * friends activity feed. All backed by the shared Rust [FriendsApi].
 */
@Composable
fun FriendsScreen(vm: FriendsViewModel, modifier: Modifier = Modifier) {
    val state by vm.state.collectAsStateWithLifecycle()
    var query by remember { mutableStateOf("") }

    if (!state.signedIn) {
        Column(
            modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Sign in on the More tab to use Friends.", style = MaterialTheme.typography.bodyMedium)
        }
        return
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Button(onClick = vm::sync, enabled = !state.syncing) {
                    Text(if (state.syncing) "Syncing…" else "Refresh")
                }
                state.message?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        // ── Add a friend (search) ──
        item {
            OutlinedTextField(
                value = query,
                onValueChange = {
                    query = it
                    vm.search(it)
                },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Find by callsign…", fontFamily = FontFamily.Monospace) },
                leadingIcon = { Icon(Icons.Default.Search, null) },
                singleLine = true,
            )
        }
        items(state.searchResults, key = { "search-${it.userId}" }) { user ->
            SearchRow(user, onAdd = { vm.sendRequest(user.userId) })
        }

        // ── Incoming requests ──
        if (state.incoming.isNotEmpty()) {
            item { SectionHeader("Requests", "${state.incoming.size}") }
            items(state.incoming, key = { "in-${it.friendUserId}" }) { req ->
                RequestRow(
                    req,
                    onAccept = { req.requestId?.let(vm::acceptRequest) },
                    onDecline = { req.requestId?.let(vm::declineRequest) },
                )
            }
        }

        // ── Sent (outgoing) ──
        if (state.outgoing.isNotEmpty()) {
            item { SectionHeader("Sent", "${state.outgoing.size}") }
            items(state.outgoing, key = { "out-${it.friendUserId}" }) { req ->
                Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 6.dp)) {
                    Text(req.friendCallsign, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium)
                    Text("  · pending", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        // ── Friends ──
        item { SectionHeader("Friends", "${state.friends.size}") }
        if (state.friends.isEmpty()) {
            item {
                Text(
                    "No friends yet — search by callsign above to add one.",
                    modifier = Modifier.padding(4.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        items(state.friends, key = { "fr-${it.friendUserId}" }) { friend ->
            FriendRow(friend, onRemove = { friend.friendshipId?.let(vm::removeFriend) })
        }

        // ── Activity feed ──
        if (state.feed.isNotEmpty()) {
            item { SectionHeader("Recent Activity") }
            items(state.feed, key = { "feed-${it.id}" }) { FeedRow(it) }
        }
    }
}

@Composable
private fun SearchRow(user: FfiUserSearchResult, onAdd: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column {
            Text(user.callsign, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium)
            user.displayName?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        OutlinedButton(onClick = onAdd) { Text("Add") }
    }
}

@Composable
private fun RequestRow(req: FfiFriendship, onAccept: () -> Unit, onDecline: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(req.friendCallsign, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            TextButton(onClick = onDecline) { Text("Decline") }
            Button(onClick = onAccept) { Text("Accept") }
        }
    }
}

@Composable
private fun FriendRow(friend: FfiFriendship, onRemove: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(friend.friendCallsign, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium)
        TextButton(onClick = onRemove) { Text("Remove") }
    }
}

@Composable
private fun FeedRow(item: FfiFeedItem) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(item.callsign, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium)
            Text(item.activityType, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
        }
        Text(
            formatDay(item.timestamp),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
