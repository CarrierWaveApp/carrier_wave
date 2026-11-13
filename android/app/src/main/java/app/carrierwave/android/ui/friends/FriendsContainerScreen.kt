package app.carrierwave.android.ui.friends

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import app.carrierwave.android.ui.clubs.ClubsListScreen
import app.carrierwave.android.ui.clubs.ClubsViewModel
import uniffi.cw_ffi.FfiClub

private enum class FriendsTab(val label: String) {
    FRIENDS("Friends"),
    CLUBS("Clubs"),
}

/**
 * The Friends tab, mirroring iOS where the social graph, activity feed, and Clubs
 * live together. "Friends" is the new shared-Rust social surface; "Clubs" reuses
 * the existing club list. Opening a club is handled by the parent (overlay), so
 * [clubsVm] and [onOpenClub] are passed through.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FriendsContainerScreen(
    clubsVm: ClubsViewModel,
    onOpenClub: (FfiClub) -> Unit,
    modifier: Modifier = Modifier,
) {
    val friendsVm: FriendsViewModel = viewModel(factory = FriendsViewModel.factory())
    var sub by rememberSaveable { mutableStateOf(FriendsTab.FRIENDS) }

    Column(modifier.fillMaxSize()) {
        SecondaryTabRow(selectedTabIndex = sub.ordinal) {
            FriendsTab.entries.forEach { tab ->
                Tab(
                    selected = sub == tab,
                    onClick = { sub = tab },
                    text = { Text(tab.label, style = MaterialTheme.typography.labelLarge) },
                )
            }
        }
        Box(Modifier.fillMaxSize()) {
            when (sub) {
                FriendsTab.FRIENDS -> FriendsScreen(friendsVm)
                FriendsTab.CLUBS -> ClubsListScreen(clubsVm, onOpenClub = onOpenClub)
            }
        }
    }
}
