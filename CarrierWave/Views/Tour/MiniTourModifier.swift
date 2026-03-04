import CarrierWaveData
import SwiftUI

// MARK: - MiniTourModifier

struct MiniTourModifier: ViewModifier {
    // MARK: Internal

    let tourId: TourState.MiniTourID
    let tourState: TourState
    let triggerOnAppear: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                if triggerOnAppear, tourState.shouldShowMiniTour(tourId) {
                    showTour = true
                }
            }
            .sheet(isPresented: $showTour) {
                TourSheetView(
                    pages: MiniTourContent.pages(for: tourId),
                    onComplete: {
                        tourState.markMiniTourSeen(tourId)
                    },
                    onSkip: {
                        tourState.markMiniTourSeen(tourId)
                    }
                )
            }
    }

    // MARK: Private

    @State private var showTour = false
}

extension View {
    func miniTour(
        _ tourId: TourState.MiniTourID,
        tourState: TourState,
        triggerOnAppear: Bool = true
    ) -> some View {
        modifier(MiniTourModifier(tourId: tourId, tourState: tourState, triggerOnAppear: triggerOnAppear))
    }
}
