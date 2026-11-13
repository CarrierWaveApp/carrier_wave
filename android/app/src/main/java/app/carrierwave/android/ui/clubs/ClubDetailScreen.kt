package app.carrierwave.android.ui.clubs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiClub
import uniffi.cw_ffi.FfiClubActivityItem
import uniffi.cw_ffi.FfiClubMember
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

private enum class DetailTab(val label: String) { MEMBERS("Members"), ACTIVITY("Activity"), MAP("Map") }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClubDetailScreen(vm: ClubDetailViewModel, club: FfiClub, homeGrid: String, onBack: () -> Unit) {
    val state by vm.state.collectAsState()
    var tab by rememberSaveable { mutableStateOf(DetailTab.MEMBERS) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(club.name) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            TabRow(selectedTabIndex = tab.ordinal) {
                DetailTab.entries.forEach { entry ->
                    Tab(
                        selected = tab == entry,
                        onClick = {
                            tab = entry
                            if (entry == DetailTab.ACTIVITY && state.activity.isEmpty()) {
                                vm.loadMoreActivity(reset = true)
                            }
                        },
                        text = { Text(entry.label) },
                    )
                }
            }

            state.message?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(16.dp),
                )
            }

            when (tab) {
                DetailTab.MEMBERS -> MembersTab(state.members, vm.myCallsign, state.syncing, vm::setMyNumber)
                DetailTab.ACTIVITY -> ActivityTab(
                    state.activity,
                    state.hasMoreActivity,
                    state.loadingActivity,
                    onLoadMore = { vm.loadMoreActivity() },
                )
                DetailTab.MAP -> ClubMapView(state.members, homeGrid, state.refinedLocations, Modifier.fillMaxSize())
            }
        }
    }
}

@Composable
private fun MembersTab(
    members: List<FfiClubMember>,
    myCallsign: String,
    syncing: Boolean,
    onSetNumber: (String?) -> Unit,
) {
    if (members.isEmpty()) {
        CenteredHint(if (syncing) "Loading members…" else "No members cached yet.")
        return
    }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(members, key = { "${it.clubId}:${it.callsign}" }) { member ->
            if (member.callsign.equals(myCallsign, ignoreCase = true)) {
                OwnMemberRow(member, onSetNumber)
            } else {
                MemberRow(member)
            }
        }
    }
}

@Composable
private fun MemberRow(member: FfiClubMember) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(member.callsign, fontWeight = FontWeight.SemiBold)
                if (member.role == "admin") {
                    Text(
                        "  ADMIN",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            val sub = listOfNotNull(member.lastGrid, member.number?.let { "#$it" }).joinToString(" · ")
            if (sub.isNotEmpty()) {
                Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (member.isCarrierWaveUser) {
            Text("CW", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
private fun OwnMemberRow(member: FfiClubMember, onSetNumber: (String?) -> Unit) {
    var number by rememberSaveable(member.number) { mutableStateOf(member.number ?: "") }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("${member.callsign}  (you)", fontWeight = FontWeight.SemiBold)
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = number,
                onValueChange = { number = it },
                label = { Text("Member number") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            OutlinedButton(onClick = { onSetNumber(number) }, modifier = Modifier.padding(start = 8.dp)) {
                Text("Save")
            }
        }
    }
}

@Composable
private fun ActivityTab(
    items: List<FfiClubActivityItem>,
    hasMore: Boolean,
    loading: Boolean,
    onLoadMore: () -> Unit,
) {
    if (items.isEmpty() && !loading) {
        CenteredHint("No recent activity.")
        return
    }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(items, key = { it.id }) { item -> ActivityRow(item) }
        item {
            if (loading) {
                Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                }
            } else if (hasMore) {
                OutlinedButton(onClick = onLoadMore, modifier = Modifier.fillMaxWidth()) {
                    Text("Load more")
                }
            }
        }
    }
}

@Composable
private fun ActivityRow(item: FfiClubActivityItem) {
    Column {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(item.callsign, fontWeight = FontWeight.SemiBold)
            Text(
                formatDay(item.timestamp),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(
            item.activityType,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun CenteredHint(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private val dayFormat = SimpleDateFormat("MMM d, HH:mm", Locale.US).apply {
    timeZone = TimeZone.getTimeZone("UTC")
}

/** Format a unix-seconds timestamp as a short UTC day/time. */
private fun formatDay(unixSeconds: Long): String = dayFormat.format(Date(unixSeconds * 1000))
