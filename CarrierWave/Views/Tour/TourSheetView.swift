import CarrierWaveData
import SwiftUI

// MARK: - TourPage

struct TourPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
}

// MARK: - TourSheetView

struct TourSheetView: View {
    // MARK: Lifecycle

    init(pages: [TourPage], onComplete: @escaping () -> Void, onSkip: (() -> Void)? = nil) {
        self.pages = pages
        self.onComplete = onComplete
        self.onSkip = onSkip
    }

    // MARK: Internal

    let pages: [TourPage]
    let onComplete: () -> Void
    let onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    VStack(spacing: 16) {
                        Image(systemName: page.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                            .padding(.top, 24)

                        Text(page.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        Text(page.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? .none : .easeInOut, value: currentPage)

            // Page indicators
            if pages.count > 1 {
                HStack(spacing: 8) {
                    ForEach(0 ..< pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 16)
            }

            // Buttons
            HStack(spacing: 16) {
                if let onSkip, currentPage < pages.count - 1 {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button {
                        withAnimation(reduceMotion ? .none : .easeInOut) {
                            currentPage += 1
                        }
                    } label: {
                        Text("Next")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        onComplete()
                        dismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .landscapeAdaptiveDetents(portrait: [.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    // MARK: Private

    @State private var currentPage = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TourSheetView(
                pages: [
                    TourPage(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Welcome to Carrier Wave",
                        body: "Your amateur radio log aggregator."
                    ),
                    TourPage(
                        icon: "arrow.triangle.2.circlepath",
                        title: "One Log, Many Destinations",
                        body: "Import QSOs from any source and sync everywhere."
                    ),
                ],
                onComplete: {},
                onSkip: {}
            )
        }
}
