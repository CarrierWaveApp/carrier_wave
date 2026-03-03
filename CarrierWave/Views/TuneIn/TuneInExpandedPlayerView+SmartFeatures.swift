import SwiftUI

// MARK: - Smart Feature UI (QSY Alert, Receiver Suggestion, Follow)

extension TuneInExpandedPlayerView {
    // MARK: - QSY Alert Banner

    @ViewBuilder
    var qsyAlertBanner: some View {
        if let alert = manager.qsyAlert {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("\(alert.callsign) moved to a new frequency")
                        .font(.caption.weight(.medium))
                    Spacer()
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            FrequencyFormatter.format(alert.newFrequencyMHz)
                                + " MHz"
                        )
                        .font(.subheadline.weight(.semibold).monospaced())
                        Text(alert.newBand + " · " + alert.newMode)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Retune") {
                        Task {
                            await manager.acceptQSYRetune()
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)

                    Button("Dismiss") {
                        manager.dismissQSYAlert()
                    }
                    .font(.caption)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Receiver Suggestion Banner

    @ViewBuilder
    var receiverSuggestionBanner: some View {
        if let suggestion = manager.receiverSuggestion {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text("Better receiver available")
                        .font(.caption.weight(.medium))
                    Spacer()
                }

                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()

                    Button("Switch to \(suggestion.suggestedName)") {
                        switchReceiver(suggestion.suggestedReceiver)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Keep") {
                        manager.dismissReceiverSuggestion()
                    }
                    .font(.caption)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Follow Button

    func followButton(_ callsign: String) -> some View {
        Button {
            manager.toggleFollow(
                callsign,
                frequencyMHz: manager.spot?.frequencyMHz,
                mode: manager.spot?.mode
            )
        } label: {
            Image(
                systemName: manager.isFollowing(callsign)
                    ? "bell.fill" : "bell"
            )
            .font(.caption)
            .foregroundStyle(
                manager.isFollowing(callsign) ? .blue : .secondary
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Receiver Switch

    func switchReceiver(_ receiver: KiwiSDRReceiver) {
        manager.dismissReceiverSuggestion()
        showReceiverPicker = false
        Task {
            await manager.session.finalize()
            if let spot = manager.spot {
                await manager.session.start(
                    receiver: receiver,
                    frequencyMHz: spot.frequencyMHz,
                    mode: spot.mode,
                    loggingSessionId: UUID(),
                    modelContext: modelContext
                )
            }
        }
    }
}
