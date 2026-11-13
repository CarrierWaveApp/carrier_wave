import CarrierWaveData
import SwiftUI

extension LogsListContentView {
    var toolbarMenu: some View {
        Menu {
            Button {
                isSelectMode.toggle()
                if !isSelectMode {
                    selectedQSOIDs.removeAll()
                }
            } label: {
                Label(
                    isSelectMode ? "Done Selecting" : "Select QSOs",
                    systemImage: isSelectMode
                        ? "checkmark.circle.fill"
                        : "checkmark.circle"
                )
            }

            Divider()

            Button {
                showFileImporter = true
            } label: {
                Label("Import ADIF File", systemImage: "square.and.arrow.down")
            }

            Button {
                showLogScanner = true
            } label: {
                Label("Scan Handwritten Log", systemImage: "doc.text.viewfinder")
            }

            Button {
                showQueryHelp = true
            } label: {
                Label("Search Help", systemImage: "questionmark.circle")
            }

            Divider()

            // Quick filters
            Menu("Quick Filters") {
                Button("Last 7 days") { queryText = "after:7d" }
                Button("Last 30 days") { queryText = "after:30d" }
                Button("This year") {
                    queryText = "date:\(Calendar.current.component(.year, from: Date()))"
                }

                Divider()

                Button("CW contacts") { queryText = "mode:CW" }
                Button("FT8 contacts") { queryText = "mode:FT8" }
                Button("SSB contacts") { queryText = "mode:SSB" }

                Divider()

                Button("POTA activations") { queryText = "park:K-*" }
                Button("LoTW confirmed") { queryText = "confirmed:lotw" }
                Button("Pending upload") { queryText = "pending:yes" }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    var leadingToolbarContent: some View {
        HStack(spacing: 8) {
            if hasActiveQuery {
                Text("\(snapshots.count) matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(isSelectMode ? "Done" : "Select") {
                isSelectMode.toggle()
                if !isSelectMode {
                    selectedQSOIDs.removeAll()
                }
            }
            .font(.caption)
        }
    }
}
