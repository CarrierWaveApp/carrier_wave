import SwiftUI

/// Casual operating layout: QSO log table + logger + stats
struct CasualLayout: View {
    let radioManager: RadioManager

    var body: some View {
        VSplitView {
            // Top: QSO log table
            QSOLogTableView()
                .frame(minHeight: 200)

            // Bottom: Parsed entry + session info
            VStack(spacing: 0) {
                ParsedEntryView(radioManager: radioManager)
                    .padding()
            }
            .frame(minHeight: 100)
        }
    }
}
