import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - OperatorsSheet

/// Shows all operators in a multi-op session with enriched callsign info
struct OperatorsSheet: View {
    let callsigns: [String]
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(callsigns, id: \.self) { callsign in
                        OperatorRow(callsign: callsign)
                    }
                }
                .padding()
            }
            .navigationTitle("Operators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}

// MARK: - OperatorRow

/// A single operator row that loads callsign info asynchronously
struct OperatorRow: View {
    // MARK: Internal

    let callsign: String

    var body: some View {
        Group {
            if let info = callsignInfo {
                LoggerCallsignCard(info: info)
            } else {
                loadingPlaceholder
            }
        }
        .task { await lookupCallsign() }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var callsignInfo: CallsignInfo?

    private var loadingPlaceholder: some View {
        HStack {
            Text(callsign)
                .font(.headline.weight(.bold).monospaced())
            Spacer()
            ProgressView()
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func lookupCallsign() async {
        let service = CallsignLookupService(modelContext: modelContext)
        // Streamed lookup: cached row renders the sheet instantly, enriched
        // row replaces it once QRZ/HamDB resolves.
        var sawInfo = false
        for await result in service.lookupStream(callsign) {
            guard !Task.isCancelled else {
                return
            }
            if let info = result.info {
                callsignInfo = info
                sawInfo = true
            }
        }
        if !sawInfo {
            // Show basic info even if lookup failed entirely.
            callsignInfo = CallsignInfo(callsign: callsign, source: .qrz)
        }
    }
}
