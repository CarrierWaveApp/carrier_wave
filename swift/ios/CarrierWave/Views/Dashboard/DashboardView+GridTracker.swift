//
//  DashboardView+GridTracker.swift
//  CarrierWave
//
//  Grid tracker dashboard card with navigation to detail view.
//

import SwiftUI

extension DashboardView {
    var gridTrackerCard: some View {
        NavigationLink {
            GridTrackerDetailView()
        } label: {
            GridTrackerCard(dataGeneration: asyncStats.dataGeneration)
        }
        .buttonStyle(.plain)
    }
}
