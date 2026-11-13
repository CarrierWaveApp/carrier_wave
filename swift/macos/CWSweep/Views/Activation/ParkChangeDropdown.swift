import CarrierWaveData
import Foundation
import SwiftData
import SwiftUI

// MARK: - ParkChangeDropdown

/// Popover for mid-session park changes during a rove.
/// Shows the current park summary, a search field for new parks,
/// and a list of parks visited this session.
struct ParkChangeDropdown: View {
    // MARK: Internal

    let session: LoggingSession
    var onParkChanged: (() -> Void)?

    @Environment(\.modelContext) var modelContext

    var body: some View {
        VStack(spacing: 0) {
            currentParkSection
            Divider()
            searchSection
            if !visitedStops.isEmpty {
                Divider()
                visitedParksSection
            }
        }
        .frame(width: 360)
    }

    // MARK: Private

    private static let qualifiedThreshold = 10

    @State private var selectedReference = ""

    private var visitedStops: [RoveStop] {
        session.mergedRoveStops
    }

    private var currentParkRef: String {
        session.parkReference ?? ""
    }

    private var currentStop: RoveStop? {
        session.currentRoveStop
    }

    private var currentQSOCount: Int {
        currentStop?.qsoCount ?? 0
    }

    private var isCurrentQualified: Bool {
        currentQSOCount >= Self.qualifiedThreshold
    }
}

// MARK: - Subviews

private extension ParkChangeDropdown {
    var currentParkSection: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(currentParkRef.isEmpty ? "No park set" : currentParkRef)
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }

            Spacer()

            qualifiedBadge(qsoCount: currentQSOCount, isQualified: isCurrentQualified)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.08))
    }

    var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Switch to park")
                .font(.caption)
                .foregroundStyle(.secondary)

            ParkSearchField(
                selectedReference: $selectedReference,
                onParkSelected: { ref, _, _ in
                    switchToPark(ref)
                }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    var visitedParksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This Session")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(visitedStops) { stop in
                visitedParkRow(stop)
            }

            Spacer(minLength: 4)
        }
    }

    func visitedParkRow(_ stop: RoveStop) -> some View {
        let isCurrent = stop.parkReference.uppercased() == currentParkRef.uppercased()
        let isQualified = stop.qsoCount >= Self.qualifiedThreshold

        return Button {
            if !isCurrent {
                switchToPark(stop.parkReference)
            }
        } label: {
            HStack(spacing: 8) {
                Text(stop.parkReference)
                    .font(.body.monospaced().weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? .green : .primary)
                    .lineLimit(1)

                Spacer()

                qualifiedBadge(qsoCount: stop.qsoCount, isQualified: isQualified)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .hoverHighlightIfEnabled(!isCurrent)
    }

    func qualifiedBadge(qsoCount: Int, isQualified: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: isQualified ? "checkmark" : "xmark")
                .font(.caption2.weight(.bold))
            Text("\(qsoCount)")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(isQualified ? .green : .red)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isQualified ? Color.green : Color.red).opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Actions

private extension ParkChangeDropdown {
    func switchToPark(_ newRef: String) {
        guard !newRef.isEmpty, newRef.uppercased() != currentParkRef.uppercased() else {
            return
        }

        // End the current rove stop
        var stops = session.roveStops
        for idx in stops.indices where stops[idx].endedAt == nil {
            stops[idx].endedAt = Date()
        }

        // Add a new rove stop for the new park
        let newStop = RoveStop(
            parkReference: newRef,
            startedAt: Date()
        )
        stops.append(newStop)

        // Write back
        session.roveStops = stops
        session.parkReference = newRef

        try? CwStoreSeams.save(modelContext, sessions: [session])
        selectedReference = ""
        onParkChanged?()
    }
}

// MARK: - HoverHighlightIfEnabledModifier

private struct HoverHighlightIfEnabledModifier: ViewModifier {
    // MARK: Lifecycle

    init(enabled: Bool) {
        self.enabled = enabled
    }

    // MARK: Internal

    func body(content: Content) -> some View {
        content
            .background(enabled && isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .onHover { hovered in
                if enabled {
                    isHovered = hovered
                }
            }
    }

    // MARK: Private

    @State private var isHovered = false

    private let enabled: Bool
}

private extension View {
    func hoverHighlightIfEnabled(_ enabled: Bool) -> some View {
        modifier(HoverHighlightIfEnabledModifier(enabled: enabled))
    }
}
