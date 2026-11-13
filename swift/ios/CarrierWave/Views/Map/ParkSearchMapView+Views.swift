import CoreLocation
import MapKit
import SwiftUI

// MARK: - SwipeDownToDismissCallout

/// Wraps a map callout with a grabber, padding, and a swipe-down-to-dismiss gesture.
/// The callout tracks the finger as it drags downward and dismisses past the threshold
/// (or with sufficient predicted end-velocity); otherwise it springs back into place.
private struct SwipeDownToDismissCallout: ViewModifier {
    // MARK: Internal

    @Binding var offset: CGFloat

    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .contentShape(Rectangle())
            content
        }
        .padding()
        .offset(y: max(0, offset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    offset = value.translation.height
                }
                .onEnded { value in
                    let shouldDismiss = value.translation.height > dismissThreshold
                        || value.predictedEndTranslation.height > predictedDismissThreshold
                    if shouldDismiss {
                        onDismiss()
                        offset = 0
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            offset = 0
                        }
                    }
                }
        )
    }

    // MARK: Private

    private let dismissThreshold: CGFloat = 80
    private let predictedDismissThreshold: CGFloat = 200
}

// MARK: - View Components

extension ParkSearchMapView {
    var overlayContent: some View {
        VStack {
            if isLoadingBoundaries {
                HStack {
                    Spacer()
                    Label("Loading boundaries…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(.top, 8)
            }

            if hasSearchResults {
                searchResultsList
                    .padding(.top, 4)
            }

            Spacer()

            selectionCallout
        }
        .animation(reduceMotion ? .none : .easeInOut, value: selection)
    }

    @ViewBuilder
    var selectionCallout: some View {
        switch selection {
        case let .park(park):
            ParkCalloutView(
                park: park,
                boundary: boundariesByRef[park.reference],
                onStartSession: { startSessionFromPark($0) }
            )
            .modifier(SwipeDownToDismissCallout(
                offset: $calloutDragOffset,
                onDismiss: { withAnimation { selection = nil } }
            ))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case let .summit(summit):
            SummitCalloutView(
                summit: summit,
                onStartSession: { startSessionFromSummit($0) }
            )
            .modifier(SwipeDownToDismissCallout(
                offset: $calloutDragOffset,
                onDismiss: { withAnimation { selection = nil } }
            ))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case let .trail(trail):
            TrailCalloutView(trail: trail)
                .modifier(SwipeDownToDismissCallout(
                    offset: $calloutDragOffset,
                    onDismiss: { withAnimation { selection = nil } }
                ))
                .transition(.move(edge: .bottom).combined(with: .opacity))
        case .none:
            EmptyView()
        }
    }

    var searchResultsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(searchResults.prefix(8), id: \.reference) { park in
                    Button {
                        zoomToPark(park)
                    } label: {
                        searchChip(
                            ref: park.reference,
                            name: park.name,
                            color: .green
                        )
                    }
                    .buttonStyle(.plain)
                }
                ForEach(summitSearchResults.prefix(8), id: \.code) { summit in
                    Button {
                        zoomToSummit(summit)
                    } label: {
                        searchChip(
                            ref: summit.code,
                            name: summit.name,
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    func searchChip(ref: String, name: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ref)
                .font(.caption.monospaced())
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(name)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
